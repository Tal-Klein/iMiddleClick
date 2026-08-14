//
//  LaunchAtLoginManager.swift
//  demo_middleClickForMac
//

import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Disabled"
    @Published private(set) var lastErrorText: String?

    private let service = SMAppService.mainApp
    private let defaultAppliedKey = "launchAtLoginDefaultApplied"

    private init() {
        refreshStatus()
    }

    func enableByDefaultIfNeeded() {
        guard UserDefaults.standard.bool(forKey: defaultAppliedKey) == false else {
            refreshStatus()
            return
        }

        switch service.status {
        case .enabled, .requiresApproval:
            UserDefaults.standard.set(true, forKey: defaultAppliedKey)
            refreshStatus()

        case .notRegistered, .notFound:
            do {
                try service.register()
                UserDefaults.standard.set(true, forKey: defaultAppliedKey)
                lastErrorText = nil
                print("Registered iMiddleClick to launch at login; status: \(service.status)")
            } catch {
                UserDefaults.standard.set(true, forKey: defaultAppliedKey)
                lastErrorText = "Unable to change setting"
                print("Could not register iMiddleClick to launch at login: \(error)")
            }

            refreshStatus()

        @unknown default:
            UserDefaults.standard.set(true, forKey: defaultAppliedKey)
            refreshStatus()
        }
    }

    func setEnabled(_ shouldEnable: Bool) {
        if shouldEnable {
            enable()
        } else {
            disable()
        }
    }

    func enable() {
        switch service.status {
        case .enabled, .requiresApproval:
            lastErrorText = nil
            refreshStatus()

        case .notRegistered, .notFound:
            do {
                try service.register()
                lastErrorText = nil
                print("Enabled launch at login; status: \(service.status)")
            } catch {
                lastErrorText = "Unable to change setting"
                print("Could not enable launch at login: \(error)")
            }

            refreshStatus()

        @unknown default:
            lastErrorText = "Unable to change setting"
            refreshStatus()
        }
    }

    func disable() {
        switch service.status {
        case .notRegistered:
            lastErrorText = nil
            refreshStatus()

        case .enabled, .requiresApproval, .notFound:
            do {
                try service.unregister()
                lastErrorText = nil
                print("Disabled launch at login; status: \(service.status)")
            } catch {
                lastErrorText = "Unable to change setting"
                print("Could not disable launch at login: \(error)")
            }

            refreshStatus()

        @unknown default:
            lastErrorText = "Unable to change setting"
            refreshStatus()
        }
    }

    func refreshStatus() {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusText = "Enabled"
        case .requiresApproval:
            isEnabled = true
            statusText = "Requires approval in System Settings"
        case .notRegistered:
            isEnabled = false
            statusText = "Disabled"
        case .notFound:
            isEnabled = false
            statusText = "Not available"
        @unknown default:
            isEnabled = false
            statusText = "Unknown status"
        }
    }
}
