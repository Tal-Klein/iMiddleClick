//
//  demo_middleClickForMacApp.swift
//  demo_middleClickForMac
//
//  Created by Tal Klein on 11/08/2026.
//

import AppKit
import SwiftUI

enum TouchDeviceKind: String {
    case trackpad
    case magicMouse
    case unknown

    var displayName: String {
        switch self {
        case .trackpad:
            return "Trackpad"
        case .magicMouse:
            return "Magic Mouse"
        case .unknown:
            return "Unknown Device"
        }
    }
}

enum MiddleClickSettings {
    enum Keys {
        static let magicMouseEnabled = "magicMouseEnabled"
        static let magicMouseFingerCount = "magicMouseFingerCount"
        static let magicMouseTapEnabled = "magicMouseTapEnabled"
        static let magicMousePhysicalClickEnabled = "magicMousePhysicalClickEnabled"
        static let helperConnected = "helperConnected"
        static let helperServiceStatus = "helperServiceStatus"
        static let touchDeviceStatus = "touchDeviceStatus"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.magicMouseEnabled: true,
            Keys.magicMouseFingerCount: 2,
            Keys.magicMouseTapEnabled: true,
            Keys.magicMousePhysicalClickEnabled: true,
            Keys.helperConnected: false,
            Keys.helperServiceStatus: "Helper Connecting",
            Keys.touchDeviceStatus: "No multitouch devices seen yet"
        ])
    }

    static func requiredFingerCount(for kind: TouchDeviceKind) -> Int? {
        switch kind {
        case .trackpad:
            return 3
        case .magicMouse:
            guard UserDefaults.standard.bool(forKey: Keys.magicMouseEnabled) else {
                return nil
            }

            let count = UserDefaults.standard.integer(forKey: Keys.magicMouseFingerCount)
            return count == 3 ? 3 : 2
        case .unknown:
            return nil
        }
    }

    static func tapEnabled(for kind: TouchDeviceKind) -> Bool {
        switch kind {
        case .trackpad:
            return true
        case .magicMouse:
            return UserDefaults.standard.bool(forKey: Keys.magicMouseEnabled)
                && UserDefaults.standard.bool(forKey: Keys.magicMouseTapEnabled)
        case .unknown:
            return false
        }
    }

    static func physicalClickEnabled(for kind: TouchDeviceKind) -> Bool {
        switch kind {
        case .trackpad:
            return true
        case .magicMouse:
            return UserDefaults.standard.bool(forKey: Keys.magicMouseEnabled)
                && UserDefaults.standard.bool(forKey: Keys.magicMousePhysicalClickEnabled)
        case .unknown:
            return false
        }
    }
}

@main
struct demo_middleClickForMacApp: App {
    private let interceptor = MouseEventInterceptor()
    private let touchMonitor = GlobalTouchMonitor()

    init() {
        MiddleClickSettings.registerDefaults()
        UserDefaults.standard.set(false, forKey: MiddleClickSettings.Keys.helperConnected)
        NSApplication.shared.setActivationPolicy(.accessory)
        LaunchAtLoginManager.shared.enableByDefaultIfNeeded()
        interceptor.start()
        touchMonitor.start()
    }

    var body: some Scene {
        MenuBarExtra("iMiddleClick", image: "StatusBarIcon") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            ContentView()
        }
    }
}

final class GestureState {
    static let shared = GestureState()

    private let lock = NSLock()
    private var activePhysicalClickDeviceKind: TouchDeviceKind?
    private var activePhysicalClickDeviceID: String?
    private var activePhysicalClickStartedAt: TimeInterval = 0
    private var suppressingPhysicalClick = false
    private var lastSyntheticMiddleClickTime: TimeInterval = 0
    private var physicalClickClaimedDeviceIDs: Set<String> = []

    private init() {}

    func setActivePhysicalClickGesture(kind: TouchDeviceKind?, deviceID: String?, startedAt: TimeInterval) {
        lock.lock()
        activePhysicalClickDeviceKind = kind
        activePhysicalClickDeviceID = deviceID
        activePhysicalClickStartedAt = startedAt

        if kind == nil {
            suppressingPhysicalClick = false
        }

        lock.unlock()
    }

    func claimActivePhysicalClickGesture() -> TouchDeviceKind? {
        lock.lock()
        defer { lock.unlock() }

        guard
            let activePhysicalClickDeviceKind,
            let activePhysicalClickDeviceID,
            suppressingPhysicalClick == false,
            MiddleClickSettings.physicalClickEnabled(for: activePhysicalClickDeviceKind),
            ProcessInfo.processInfo.systemUptime - activePhysicalClickStartedAt <= 0.5
        else {
            return nil
        }

        physicalClickClaimedDeviceIDs.insert(activePhysicalClickDeviceID)
        suppressingPhysicalClick = true
        return activePhysicalClickDeviceKind
    }

    func hasPhysicalClickClaim(for deviceID: String) -> Bool {
        lock.lock()
        let isClaimed = physicalClickClaimedDeviceIDs.contains(deviceID)
        lock.unlock()
        return isClaimed
    }

    func clearPhysicalClickClaim(for deviceID: String) {
        lock.lock()
        physicalClickClaimedDeviceIDs.remove(deviceID)
        lock.unlock()
    }

    func consumeSuppressingPhysicalClick() -> Bool {
        lock.lock()
        let shouldSuppress = suppressingPhysicalClick
        suppressingPhysicalClick = false
        lock.unlock()
        return shouldSuppress
    }

    func markSyntheticMiddleClick() {
        lock.lock()
        lastSyntheticMiddleClickTime = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    func timeSinceSyntheticMiddleClick() -> TimeInterval {
        lock.lock()
        let elapsed = ProcessInfo.processInfo.systemUptime - lastSyntheticMiddleClickTime
        lock.unlock()
        return elapsed
    }
}

enum GestureDiagnostics {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "gestureDiagnosticsEnabled")
    }

    static func log(_ message: String) {
        guard isEnabled else {
            return
        }

        print(message)
    }
}
