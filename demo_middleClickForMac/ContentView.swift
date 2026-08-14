//
//  ContentView.swift
//  demo_middleClickForMac
//
//  Created by Tal Klein on 11/08/2026.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared

    @AppStorage(MiddleClickSettings.Keys.magicMouseEnabled) private var magicMouseEnabled = true
    @AppStorage(MiddleClickSettings.Keys.magicMouseFingerCount) private var magicMouseFingerCount = 2
    @AppStorage(MiddleClickSettings.Keys.magicMouseTapEnabled) private var magicMouseTapEnabled = true
    @AppStorage(MiddleClickSettings.Keys.magicMousePhysicalClickEnabled) private var magicMousePhysicalClickEnabled = true
    @AppStorage(MiddleClickSettings.Keys.helperConnected) private var helperConnected = false
    @AppStorage(MiddleClickSettings.Keys.helperServiceStatus) private var helperServiceStatus = "Helper Connecting"
    @AppStorage(MiddleClickSettings.Keys.touchDeviceStatus) private var touchDeviceStatus = "No multitouch devices seen yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "computermouse")
                    .imageScale(.large)

                Text("iMiddleClick")
                    .font(.headline)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Trackpad")

                StatusRow(title: "Enabled", isOn: true)
                Text("3 Finger Tap + Click")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Magic Mouse")

                Toggle("Enabled", isOn: $magicMouseEnabled)

                Picker("Fingers", selection: $magicMouseFingerCount) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                .disabled(magicMouseEnabled == false)

                Toggle("Tap", isOn: $magicMouseTapEnabled)
                    .disabled(magicMouseEnabled == false)

                Toggle("Physical Click", isOn: $magicMousePhysicalClickEnabled)
                    .disabled(magicMouseEnabled == false)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                Text(launchAtLogin.lastErrorText ?? launchAtLogin.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(helperConnected ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)

                Text(helperConnected ? "Helper Running" : helperServiceStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(touchDeviceStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Link("☕ Buy me a coffee", destination: URL(string: "https://ko-fi.com/kleinutilities")!)
                .font(.callout)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }
}

private struct StatusRow: View {
    let title: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.green : Color.secondary)

            Text(title)
                .font(.callout)

            Spacer()
        }
    }
}
