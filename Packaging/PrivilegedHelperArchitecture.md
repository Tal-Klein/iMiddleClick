# Privileged Multitouch Helper Architecture

Use `SMAppService.daemon(plistName:)` on macOS 13 and later. The helper executable and launchd plist must be embedded in the app bundle:

```text
demo_middleClickForMac.app/
  Contents/
    MacOS/demo_middleClickForMac
    Library/
      LaunchDaemons/
        com.talklein.middleclick.multitouch-helper.plist
        mt_touch_helper
```

The GUI app remains non-root. The helper runs as a launch daemon and is the only process that loads private `MultitouchSupport.framework`.

Recommended production IPC is XPC through the launch daemon `MachServices` entry:

```text
com.talklein.middleclick.multitouch-helper
```

The helper interface should expose only:

```text
startMonitoring()
stopMonitoring()
stream sanitized touch frames:
  deviceKind: trackpad | magicMouse | unknown
  contactCount
  timestamp
```

Gesture recognition, event-tap suppression, and synthetic middle-click generation remain in the GUI app.

Project setup still required in Xcode:

1. Add a command-line executable helper target for `mt_touch_helper.c`, signed with the same Team ID.
2. Copy the signed helper executable to `Contents/Library/LaunchDaemons/mt_touch_helper`.
3. Copy `com.talklein.middleclick.multitouch-helper.plist` to `Contents/Library/LaunchDaemons/`.
4. Register it from the app with:

```swift
let service = SMAppService.daemon(plistName: "com.talklein.middleclick.multitouch-helper.plist")
try service.register()
```

Notes:

- `SMAppService` is the modern API for bundled launch daemons.
- A launch daemon is required because `MTDeviceStart` succeeds as root and fails as a normal user.
- The app should not use setuid and should not run the GUI as root.
- Hardened Runtime can remain enabled.
- App Sandbox is likely not appropriate for this product because Authorization Services are not supported in sandboxed apps and private API/root-helper installation is not Mac App Store suitable. If sandbox remains enabled during the TCP prototype, Outgoing Connections must be enabled.
- Uninstall should call `unregister()` and remove any user settings. The registered daemon is managed by ServiceManagement/launchd.
