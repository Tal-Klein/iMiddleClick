#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define SERVER_PORT 47654
#define MAX_CLIENTS 8
#define MAX_DEVICES 16

typedef void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalizedPosition;
    float size;
    int field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef io_service_t (*MTDeviceGetServiceFn)(MTDeviceRef);
typedef void (*MTFrameCallbackFn)(MTDeviceRef, MTTouch[], int, double, int);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTFrameCallbackFn);
typedef int (*MTDeviceStartFn)(MTDeviceRef, int);
typedef int (*MTDeviceStopFn)(MTDeviceRef);

static int clientSockets[MAX_CLIENTS];
static int clientCount = 0;
static pthread_mutex_t clientMutex = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
    MTDeviceRef device;
    int lastFingerCount;
    int startStatus;
    char kind[32];
    char name[160];
} TrackedDevice;

static TrackedDevice trackedDevices[MAX_DEVICES];
static int trackedDeviceCount = 0;
static int lastTotalFingerCount = -1;
static pthread_mutex_t fingerMutex = PTHREAD_MUTEX_INITIALIZER;

static volatile sig_atomic_t isRunning = 1;

static void handleSignal(int signalNumber) {
    (void)signalNumber;
    isRunning = 0;
}

static void removeClientAtIndex(int index) {
    close(clientSockets[index]);

    for (int i = index; i < clientCount - 1; i++) {
        clientSockets[i] = clientSockets[i + 1];
    }

    clientCount--;
}

static void broadcastLine(const char *line) {
    pthread_mutex_lock(&clientMutex);

    for (int i = 0; i < clientCount;) {
        ssize_t sent = send(clientSockets[i], line, strlen(line), MSG_NOSIGNAL);

        if (sent < 0) {
            removeClientAtIndex(i);
            continue;
        }

        i++;
    }

    pthread_mutex_unlock(&clientMutex);
}

static void sendCurrentFingerCount(int clientSocket) {
    char line[256];

    pthread_mutex_lock(&fingerMutex);

    for (int i = 0; i < trackedDeviceCount; i++) {
        int fingerCount = trackedDevices[i].lastFingerCount < 0 ? 0 : trackedDevices[i].lastFingerCount;
        snprintf(line, sizeof(line), "deviceFingerCount=%d kind=%s device=\"%s\"\n", fingerCount, trackedDevices[i].kind, trackedDevices[i].name);
        send(clientSocket, line, strlen(line), MSG_NOSIGNAL);
    }

    pthread_mutex_unlock(&fingerMutex);

    snprintf(line, sizeof(line), "fingerCount=%d\n", lastTotalFingerCount < 0 ? 0 : lastTotalFingerCount);
    send(clientSocket, line, strlen(line), MSG_NOSIGNAL);
}

static void *serverThreadMain(void *context) {
    (void)context;

    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);

    if (serverSocket < 0) {
        perror("socket");
        return NULL;
    }

    int reuse = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(SERVER_PORT);

    if (bind(serverSocket, (struct sockaddr *)&address, sizeof(address)) != 0) {
        perror("bind");
        close(serverSocket);
        return NULL;
    }

    if (listen(serverSocket, 4) != 0) {
        perror("listen");
        close(serverSocket);
        return NULL;
    }

    printf("mt_touch_helper listening on 127.0.0.1:%d\n", SERVER_PORT);
    fflush(stdout);

    while (isRunning) {
        int clientSocket = accept(serverSocket, NULL, NULL);

        if (clientSocket < 0) {
            if (errno == EINTR) {
                continue;
            }

            perror("accept");
            break;
        }

        pthread_mutex_lock(&clientMutex);

        if (clientCount < MAX_CLIENTS) {
            clientSockets[clientCount++] = clientSocket;
            printf("client connected (%d active)\n", clientCount);
            sendCurrentFingerCount(clientSocket);
        } else {
            close(clientSocket);
        }

        pthread_mutex_unlock(&clientMutex);
        fflush(stdout);
    }

    close(serverSocket);
    return NULL;
}

static const char *copyServiceString(io_service_t service, CFStringRef key, char *buffer, size_t bufferSize) {
    if (service == IO_OBJECT_NULL) {
        snprintf(buffer, bufferSize, "unknown");
        return buffer;
    }

    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);

    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, buffer, bufferSize, kCFStringEncodingUTF8);
    } else {
        snprintf(buffer, bufferSize, "unknown");
    }

    if (value) {
        CFRelease(value);
    }

    return buffer;
}

static int activeFingerCount(MTTouch touches[], int touchCount) {
    int activeCount = 0;

    for (int i = 0; i < touchCount; i++) {
        if (touches[i].state == 3 || touches[i].state == 4) {
            activeCount++;
        }
    }

    return activeCount;
}

static TrackedDevice *trackedDeviceForRef(MTDeviceRef device) {
    for (int i = 0; i < trackedDeviceCount; i++) {
        if (trackedDevices[i].device == device) {
            return &trackedDevices[i];
        }
    }

    return NULL;
}

static int totalFingerCount(void) {
    int total = 0;

    for (int i = 0; i < trackedDeviceCount; i++) {
        if (trackedDevices[i].lastFingerCount > 0) {
            total += trackedDevices[i].lastFingerCount;
        }
    }

    return total;
}

static void contactFrameCallback(MTDeviceRef device, MTTouch touches[], int touchCount, double timestamp, int frame) {
    (void)frame;

    int deviceFingerCount = activeFingerCount(touches, touchCount);
    char deviceLine[256];
    char totalLine[128];
    bool shouldBroadcastTotal = false;

    pthread_mutex_lock(&fingerMutex);

    TrackedDevice *trackedDevice = trackedDeviceForRef(device);

    if (!trackedDevice || trackedDevice->lastFingerCount == deviceFingerCount) {
        pthread_mutex_unlock(&fingerMutex);
        return;
    }

    trackedDevice->lastFingerCount = deviceFingerCount;
    int total = totalFingerCount();
    snprintf(deviceLine, sizeof(deviceLine), "deviceFingerCount=%d kind=%s device=\"%s\" timestamp=%f\n", deviceFingerCount, trackedDevice->kind, trackedDevice->name, timestamp);

    if (lastTotalFingerCount != total) {
        lastTotalFingerCount = total;
        snprintf(totalLine, sizeof(totalLine), "fingerCount=%d timestamp=%f\n", total, timestamp);
        shouldBroadcastTotal = true;
    }

    pthread_mutex_unlock(&fingerMutex);

    printf("%s", deviceLine);
    broadcastLine(deviceLine);

    if (shouldBroadcastTotal) {
        printf("%s", totalLine);
        broadcastLine(totalLine);
    }

    fflush(stdout);
}

static bool hasMousePreferences(io_service_t service) {
    if (service == IO_OBJECT_NULL) {
        return false;
    }

    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("MultitouchPreferences"), kCFAllocatorDefault, 0);

    if (!value || CFGetTypeID(value) != CFDictionaryGetTypeID()) {
        if (value) {
            CFRelease(value);
        }

        return false;
    }

    CFDictionaryRef preferences = (CFDictionaryRef)value;
    CFIndex count = CFDictionaryGetCount(preferences);
    const void **keys = calloc((size_t)count, sizeof(void *));
    bool foundMouseKey = false;

    if (keys) {
        CFDictionaryGetKeysAndValues(preferences, keys, NULL);

        for (CFIndex i = 0; i < count; i++) {
            if (CFGetTypeID(keys[i]) != CFStringGetTypeID()) {
                continue;
            }

            char key[128];

            if (CFStringGetCString((CFStringRef)keys[i], key, sizeof(key), kCFStringEncodingUTF8) && strstr(key, "Mouse")) {
                foundMouseKey = true;
                break;
            }
        }

        free(keys);
    }

    CFRelease(value);
    return foundMouseKey;
}

static void *loadSymbol(void *handle, const char *name) {
    void *symbol = dlsym(handle, name);

    if (!symbol) {
        fprintf(stderr, "missing required symbol: %s\n", name);
        exit(2);
    }

    return symbol;
}

static void addTrackedDevice(MTDeviceRef device, MTDeviceIsBuiltInFn isBuiltIn, MTDeviceGetServiceFn getService) {
    if (trackedDeviceCount >= MAX_DEVICES) {
        return;
    }

    io_service_t service = getService(device);
    char product[128];
    char transport[64];
    copyServiceString(service, CFSTR("Product"), product, sizeof(product));
    copyServiceString(service, CFSTR("Transport"), transport, sizeof(transport));
    bool builtIn = isBuiltIn(device);
    bool mousePreferences = hasMousePreferences(service);

    trackedDevices[trackedDeviceCount].device = device;
    trackedDevices[trackedDeviceCount].lastFingerCount = 0;
    trackedDevices[trackedDeviceCount].startStatus = -1;
    snprintf(
        trackedDevices[trackedDeviceCount].kind,
        sizeof(trackedDevices[trackedDeviceCount].kind),
        "%s",
        builtIn || strstr(product, "Trackpad") ? "trackpad" : mousePreferences || strstr(product, "Mouse") ? "magicMouse" : "unknown"
    );
    snprintf(
        trackedDevices[trackedDeviceCount].name,
        sizeof(trackedDevices[trackedDeviceCount].name),
        "%s%s%s",
        builtIn ? "built-in trackpad" : product,
        transport[0] ? " / " : "",
        transport
    );
    trackedDeviceCount++;
}

int main(int argc, char *argv[]) {
    bool trackAllDevices = argc > 1 && strcmp(argv[1], "--all-devices") == 0;

    signal(SIGINT, handleSignal);
    signal(SIGTERM, handleSignal);

    pthread_t serverThread;

    if (pthread_create(&serverThread, NULL, serverThreadMain, NULL) != 0) {
        perror("pthread_create");
        return 1;
    }

    void *handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);

    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }

    MTDeviceCreateListFn createList = (MTDeviceCreateListFn)loadSymbol(handle, "MTDeviceCreateList");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)loadSymbol(handle, "MTDeviceIsBuiltIn");
    MTDeviceGetServiceFn getService = (MTDeviceGetServiceFn)loadSymbol(handle, "MTDeviceGetService");
    MTRegisterContactFrameCallbackFn registerCallback = (MTRegisterContactFrameCallbackFn)loadSymbol(handle, "MTRegisterContactFrameCallback");
    MTDeviceStartFn start = (MTDeviceStartFn)loadSymbol(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)loadSymbol(handle, "MTDeviceStop");

    CFArrayRef devices = createList();

    if (!devices) {
        fprintf(stderr, "MTDeviceCreateList returned NULL\n");
        return 1;
    }

    CFIndex count = CFArrayGetCount(devices);
    printf("MTDeviceCreateList returned %ld device(s)\n", count);

    if (trackAllDevices) {
        printf("Tracking all multitouch devices\n");

        for (CFIndex i = 0; i < count; i++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
            addTrackedDevice(device, isBuiltIn, getService);
        }
    } else {
        for (CFIndex i = 0; i < count; i++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);

            if (!isBuiltIn(device)) {
                continue;
            }

            addTrackedDevice(device, isBuiltIn, getService);
            break;
        }

        if (trackedDeviceCount == 0 && count > 0) {
            printf("No built-in device found; falling back to first multitouch device\n");
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, 0);
            addTrackedDevice(device, isBuiltIn, getService);
        }
    }

    if (trackedDeviceCount == 0) {
        fprintf(stderr, "No multitouch device available\n");
        CFRelease(devices);
        return 1;
    }

    for (int i = 0; i < trackedDeviceCount; i++) {
        printf("Tracking device: \"%s\"\n", trackedDevices[i].name);
        registerCallback(trackedDevices[i].device, contactFrameCallback);

        trackedDevices[i].startStatus = start(trackedDevices[i].device, 0);
        printf("MTDeviceStart device=\"%s\" status=%d\n", trackedDevices[i].name, trackedDevices[i].startStatus);

        if (trackedDevices[i].startStatus != 0) {
            fprintf(stderr, "MTDeviceStart failed for \"%s\". Run this helper with sudo.\n", trackedDevices[i].name);
        }
    }

    fflush(stdout);

    while (isRunning) {
        sleep(1);
    }

    for (int i = 0; i < trackedDeviceCount; i++) {
        if (trackedDevices[i].startStatus == 0) {
            int stopStatus = stop(trackedDevices[i].device);
            printf("MTDeviceStop device=\"%s\" status=%d\n", trackedDevices[i].name, stopStatus);
        }
    }

    pthread_mutex_lock(&clientMutex);

    for (int i = 0; i < clientCount; i++) {
        close(clientSockets[i]);
    }

    clientCount = 0;
    pthread_mutex_unlock(&clientMutex);

    CFRelease(devices);
    dlclose(handle);

    return 0;
}
