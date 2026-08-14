//
//  GlobalTouchMonitor.swift
//  demo_middleClickForMac
//
//  Created by Tal Klein on 11/08/2026.
//

import Foundation
import Network
import ServiceManagement

final class GlobalTouchMonitor {

    private let helperService = MultitouchHelperService()
    private let client = MultitouchHelperClient()

    func start() {
        helperService.registerIfNeeded()
        client.start()
    }

    func stop() {
        client.stop()
    }
}

private final class MultitouchHelperService {

    private let service = SMAppService.daemon(plistName: "com.talklein.middleclick.multitouch-helper.plist")
    private let registrationVersionKey = "multitouchHelperRegistrationVersion"
    private let currentRegistrationVersion = 4

    func registerIfNeeded() {
        refreshStoredStatus()

        switch service.status {
        case .enabled:
            refreshRegistrationIfNeeded()
            print("Multitouch launch daemon is enabled")

        case .requiresApproval:
            UserDefaults.standard.set("Helper Requires Approval", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            print("Multitouch launch daemon requires approval in System Settings")
            SMAppService.openSystemSettingsLoginItems()

        case .notRegistered, .notFound:
            register()

        @unknown default:
            UserDefaults.standard.set("Helper Status Unknown", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            print("Unknown multitouch launch daemon status: \(service.status)")
        }
    }

    private func refreshRegistrationIfNeeded() {
        guard UserDefaults.standard.integer(forKey: registrationVersionKey) < currentRegistrationVersion else {
            return
        }

        do {
            try service.unregister()
            print("Unregistered old multitouch launch daemon registration")
        } catch {
            print("Could not unregister old multitouch launch daemon registration: \(error)")
        }

        register()
    }

    private func register() {
        do {
            try service.register()
            UserDefaults.standard.set(currentRegistrationVersion, forKey: registrationVersionKey)
            print("Registered multitouch launch daemon; status: \(service.status)")

            if service.status == .requiresApproval {
                UserDefaults.standard.set("Helper Requires Approval", forKey: MiddleClickSettings.Keys.helperServiceStatus)
                SMAppService.openSystemSettingsLoginItems()
            } else {
                refreshStoredStatus()
            }
        } catch {
            UserDefaults.standard.set("Helper Registration Failed", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            print("Could not register multitouch launch daemon: \(error)")
        }
    }

    private func refreshStoredStatus() {
        switch service.status {
        case .enabled:
            UserDefaults.standard.set("Helper Registered", forKey: MiddleClickSettings.Keys.helperServiceStatus)
        case .requiresApproval:
            UserDefaults.standard.set("Helper Requires Approval", forKey: MiddleClickSettings.Keys.helperServiceStatus)
        case .notRegistered:
            UserDefaults.standard.set("Helper Not Registered", forKey: MiddleClickSettings.Keys.helperServiceStatus)
        case .notFound:
            UserDefaults.standard.set("Helper Not Found", forKey: MiddleClickSettings.Keys.helperServiceStatus)
        @unknown default:
            UserDefaults.standard.set("Helper Status Unknown", forKey: MiddleClickSettings.Keys.helperServiceStatus)
        }
    }
}

private final class MultitouchHelperClient {

    private let queue = DispatchQueue(label: "MultitouchHelperClient")
    private let host = NWEndpoint.Host("127.0.0.1")
    private let port = NWEndpoint.Port(rawValue: 47654)!

    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var receiveBuffer = ""
    private var deviceStates: [String: DeviceTouchState] = [:]
    private var isStopped = false

    private struct DevicePoint {
        var x: Double
        var y: Double
    }

    private struct TouchContact {
        var identifier: Int
        var state: Int
        var position: DevicePoint
    }

    private struct DeviceTouchState {
        var kind: TouchDeviceKind = .unknown
        var deviceName = "unknown"
        var fingerCount = 0
        var previousFingerCount = 0
        var previousContacts: [Int: TouchContact] = [:]
        var candidate: TapCandidate?
        var lastUpdatedAt: TimeInterval = 0
    }

    private struct TapCandidate {
        var requiredFingerCount: Int
        var contactID: Int?
        var startTimestamp: TimeInterval
        var startPoint: DevicePoint
        var maxMovement: Double = 0
        var isOwnedByPhysicalClick = false
        var hasFinished = false
    }

    func start() {
        queue.async { [weak self] in
            guard let self, connection == nil else {
                return
            }

            isStopped = false
            connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            isStopped = true
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            connection?.cancel()
            connection = nil
            resetTouchState()
        }
    }

    private func connect() {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                self?.handleConnectionState(state)
            }
        }

        connection.start(queue: queue)
        receive(on: connection)

        print("Connecting to multitouch root helper on 127.0.0.1:\(port.rawValue)")
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            UserDefaults.standard.set(true, forKey: MiddleClickSettings.Keys.helperConnected)
            UserDefaults.standard.set("Helper Running", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            print("Connected to multitouch root helper")

        case .failed(let error):
            UserDefaults.standard.set(false, forKey: MiddleClickSettings.Keys.helperConnected)
            UserDefaults.standard.set("Helper Not Running", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            print("Multitouch helper connection failed: \(error)")
            connection?.cancel()
            connection = nil
            resetTouchState()
            scheduleReconnect()

        case .cancelled:
            UserDefaults.standard.set(false, forKey: MiddleClickSettings.Keys.helperConnected)
            UserDefaults.standard.set("Helper Not Running", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            connection = nil
            resetTouchState()

            if isStopped == false {
                scheduleReconnect()
            }

        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self else {
                return
            }

            queue.async {
                if let data, data.isEmpty == false, let chunk = String(data: data, encoding: .utf8) {
                    self.receiveBuffer += chunk
                    self.processBufferedLines()
                }

                if let error {
                    print("Multitouch helper receive failed: \(error)")
                    connection?.cancel()
                    return
                }

                if isComplete {
                    connection?.cancel()
                    return
                }

                if let connection {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func processBufferedLines() {
        while let newlineIndex = receiveBuffer.firstIndex(of: "\n") {
            let line = String(receiveBuffer[..<newlineIndex])
            receiveBuffer.removeSubrange(...newlineIndex)
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        if line.hasPrefix("deviceFingerCount=") {
            handleDeviceFingerCountLine(line)
            return
        }

        guard line.hasPrefix("fingerCount=") else {
            return
        }

        let valueText = line
            .dropFirst("fingerCount=".count)
            .prefix { $0.isNumber }

        guard let fingerCount = Int(valueText) else {
            print("Could not parse multitouch helper line: \(line)")
            return
        }

        _ = fingerCount
    }

    private func handleDeviceFingerCountLine(_ line: String) {
        guard
            let fingerCount = parseInt(after: "deviceFingerCount=", in: line),
            let kindText = parseToken(after: "kind=", in: line)
        else {
            print("Could not parse multitouch helper line: \(line)")
            return
        }

        let deviceName = parseQuotedString(after: "device=\"", in: line) ?? "Unknown Device"
        let kind = normalizedDeviceKind(kindText: kindText, deviceName: deviceName)
        let position = parsePosition(in: line)
        let timestamp = parseDouble(after: "timestamp=", in: line) ?? ProcessInfo.processInfo.systemUptime
        let frame = parseInt(after: "frame=", in: line)
        let contacts = parseTouches(in: line)

        GestureDiagnostics.log("[MT] device=\(kind.rawValue) frame=\(frame.map(String.init) ?? "-") fingers=\(fingerCount) timestamp=\(timestamp)")
        updateObservedDeviceStatus(kind: kind)
        setFingerCount(
            fingerCount,
            for: kind,
            deviceName: deviceName,
            position: position,
            timestamp: timestamp,
            contacts: contacts
        )
    }

    private func setFingerCount(
        _ fingerCount: Int,
        for kind: TouchDeviceKind,
        deviceName: String,
        position: DevicePoint?,
        timestamp: TimeInterval,
        contacts: [TouchContact]
    ) {
        DispatchQueue.main.async {
            let deviceID = "\(kind.rawValue):\(deviceName)"
            self.handleTouchFrame(
                fingerCount: fingerCount,
                kind: kind,
                deviceID: deviceID,
                deviceName: deviceName,
                position: position,
                timestamp: timestamp,
                contacts: contacts
            )
            self.updateActiveGestureState()
        }
    }

    private func handleTouchFrame(
        fingerCount: Int,
        kind: TouchDeviceKind,
        deviceID: String,
        deviceName: String,
        position: DevicePoint?,
        timestamp: TimeInterval,
        contacts: [TouchContact]
    ) {
        guard let requiredFingerCount = MiddleClickSettings.requiredFingerCount(for: kind) else {
            deviceStates[deviceID] = DeviceTouchState(kind: kind, deviceName: deviceName, fingerCount: fingerCount, lastUpdatedAt: ProcessInfo.processInfo.systemUptime)
            GestureState.shared.clearPhysicalClickClaim(for: deviceID)
            return
        }

        var state = deviceStates[deviceID, default: DeviceTouchState()]
        state.kind = kind
        state.deviceName = deviceName
        let contactMap = Dictionary(uniqueKeysWithValues: contacts.map { ($0.identifier, $0) })
        updateTapCandidate(
            state: &state,
            deviceID: deviceID,
            kind: kind,
            fingerCount: fingerCount,
            requiredFingerCount: requiredFingerCount,
            timestamp: timestamp,
            position: position,
            contacts: contactMap
        )

        state.previousFingerCount = state.fingerCount
        state.fingerCount = fingerCount
        state.previousContacts = contactMap
        state.lastUpdatedAt = ProcessInfo.processInfo.systemUptime
        deviceStates[deviceID] = state
    }

    private func updateActiveGestureState() {
        let now = ProcessInfo.processInfo.systemUptime
        let activeState = deviceStates
            .filter { _, state in
                guard let requiredFingerCount = MiddleClickSettings.requiredFingerCount(for: state.kind) else {
                    return false
                }

                return state.fingerCount == requiredFingerCount
                    && MiddleClickSettings.physicalClickEnabled(for: state.kind)
                    && now - state.lastUpdatedAt <= 0.6
            }
            .max { first, second in
                first.value.lastUpdatedAt < second.value.lastUpdatedAt
            }

        GestureState.shared.setActivePhysicalClickGesture(
            kind: activeState?.value.kind,
            deviceID: activeState?.key,
            startedAt: activeState?.value.lastUpdatedAt ?? now
        )
    }

    private func updateTapCandidate(
        state: inout DeviceTouchState,
        deviceID: String,
        kind: TouchDeviceKind,
        fingerCount: Int,
        requiredFingerCount: Int,
        timestamp: TimeInterval,
        position: DevicePoint?,
        contacts: [Int: TouchContact]
    ) {
        if GestureState.shared.hasPhysicalClickClaim(for: deviceID) {
            state.candidate?.isOwnedByPhysicalClick = true
        }

        if var candidate = state.candidate {
            if fingerCount > requiredFingerCount {
                GestureDiagnostics.log("[Gesture] rejected: finger-count transition")
                resetCandidate(&state, deviceID: deviceID)
                return
            }

            if fingerCount < requiredFingerCount {
                finishCandidate(
                    candidate,
                    state: &state,
                    deviceID: deviceID,
                    kind: kind,
                    timestamp: timestamp
                )
                return
            }

            updateMovement(for: &candidate, position: position, contacts: contacts)
            state.candidate = candidate
            return
        }

        guard state.fingerCount < requiredFingerCount, fingerCount == requiredFingerCount else {
            if fingerCount == 0 {
                GestureState.shared.clearPhysicalClickClaim(for: deviceID)
            }

            return
        }

        let newContactIDs = Set(contacts.keys).subtracting(state.previousContacts.keys)
        let candidateID = newContactIDs.count == 1 ? newContactIDs.first : nil
        let startPoint = candidateID.flatMap { contacts[$0]?.position } ?? position ?? centroid(of: contacts)

        guard let startPoint else {
            return
        }

        state.candidate = TapCandidate(
            requiredFingerCount: requiredFingerCount,
            contactID: candidateID,
            startTimestamp: timestamp,
            startPoint: startPoint
        )
        GestureDiagnostics.log("[Gesture] candidate started id=\(candidateID.map(String.init) ?? "centroid") device=\(kind.rawValue)")
    }

    private func updateMovement(
        for candidate: inout TapCandidate,
        position: DevicePoint?,
        contacts: [Int: TouchContact]
    ) {
        let currentPoint = candidate.contactID.flatMap { contacts[$0]?.position } ?? position ?? centroid(of: contacts)

        guard let currentPoint else {
            return
        }

        candidate.maxMovement = max(candidate.maxMovement, distance(from: candidate.startPoint, to: currentPoint))
    }

    private func finishCandidate(
        _ candidate: TapCandidate,
        state: inout DeviceTouchState,
        deviceID: String,
        kind: TouchDeviceKind,
        timestamp: TimeInterval
    ) {
        let duration = timestamp - candidate.startTimestamp
        let movement = candidate.maxMovement
        let timeSinceMiddleClick = GestureState.shared.timeSinceSyntheticMiddleClick()
        resetCandidate(&state, deviceID: deviceID)

        guard candidate.isOwnedByPhysicalClick == false else {
            GestureDiagnostics.log("[Gesture] rejected: owned by physical click")
            return
        }

        guard MiddleClickSettings.tapEnabled(for: kind) else {
            GestureDiagnostics.log("[Gesture] rejected: tap disabled")
            return
        }

        guard duration <= 0.35 else {
            GestureDiagnostics.log("[Gesture] rejected: duration \(duration)")
            return
        }

        guard movement <= 0.03 else {
            GestureDiagnostics.log("[Gesture] rejected: movement \(movement)")
            return
        }

        guard timeSinceMiddleClick > 0.2 else {
            GestureDiagnostics.log("[Gesture] rejected: debounce")
            return
        }

        GestureDiagnostics.log("[Gesture] duration=\(duration) movement=\(movement)")
        GestureDiagnostics.log("[Gesture] TAP ACCEPTED")
        MouseSimulator.middleClick()
    }

    private func resetCandidate(_ state: inout DeviceTouchState, deviceID: String) {
        state.candidate = nil
        GestureState.shared.clearPhysicalClickClaim(for: deviceID)
    }

    private func resetTouchState() {
        DispatchQueue.main.async {
            self.deviceStates.removeAll()
            UserDefaults.standard.set(false, forKey: MiddleClickSettings.Keys.helperConnected)
            UserDefaults.standard.set("Helper Not Running", forKey: MiddleClickSettings.Keys.helperServiceStatus)
            GestureState.shared.setActivePhysicalClickGesture(kind: nil, deviceID: nil, startedAt: 0)
        }
    }

    private func parseInt(after prefix: String, in line: String) -> Int? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let valueText = line[prefixRange.upperBound...].prefix { $0.isNumber }
        return Int(valueText)
    }

    private func parseDouble(after prefix: String, in line: String) -> Double? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let valueText = line[prefixRange.upperBound...].prefix {
            $0.isNumber || $0 == "." || $0 == "-"
        }

        return Double(valueText)
    }

    private func parsePosition(in line: String) -> DevicePoint? {
        guard
            let x = parseDouble(after: "x=", in: line),
            let y = parseDouble(after: "y=", in: line)
        else {
            return nil
        }

        return DevicePoint(x: x, y: y)
    }

    private func parseTouches(in line: String) -> [TouchContact] {
        guard let touchesText = parseToken(after: "touches=", in: line), touchesText.isEmpty == false else {
            return []
        }

        return touchesText
            .split(separator: ";")
            .compactMap { item -> TouchContact? in
                let fields = item.split(separator: ":")

                guard
                    fields.count == 4,
                    let identifier = Int(fields[0]),
                    let state = Int(fields[1]),
                    let x = Double(fields[2]),
                    let y = Double(fields[3])
                else {
                    return nil
                }

                return TouchContact(identifier: identifier, state: state, position: DevicePoint(x: x, y: y))
            }
    }

    private func parseToken(after prefix: String, in line: String) -> String? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let token = line[prefixRange.upperBound...].prefix { $0 != " " && $0 != "\n" }
        return token.isEmpty ? nil : String(token)
    }

    private func parseQuotedString(after prefix: String, in line: String) -> String? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let remainder = line[prefixRange.upperBound...]

        guard let endIndex = remainder.firstIndex(of: "\"") else {
            return nil
        }

        return String(remainder[..<endIndex])
    }

    private func normalizedDeviceKind(kindText: String, deviceName: String) -> TouchDeviceKind {
        let reportedKind = TouchDeviceKind(rawValue: kindText) ?? .unknown

        if reportedKind != .unknown {
            return reportedKind
        }

        let lowercaseName = deviceName.lowercased()

        if lowercaseName.contains("mouse") {
            return .magicMouse
        }

        if lowercaseName.contains("trackpad") {
            return .trackpad
        }

        return .unknown
    }

    private func updateObservedDeviceStatus(kind: TouchDeviceKind) {
        let currentText = UserDefaults.standard.string(forKey: MiddleClickSettings.Keys.touchDeviceStatus) ?? ""
        var devices = Set(
            currentText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false && $0 != "No multitouch devices seen yet" }
        )

        switch kind {
        case .trackpad:
            devices.insert("Trackpad")
        case .magicMouse:
            devices.insert("Magic Mouse")
        case .unknown:
            devices.insert("Unknown")
        }

        UserDefaults.standard.set(devices.sorted().joined(separator: ", "), forKey: MiddleClickSettings.Keys.touchDeviceStatus)
    }

    private func distance(from startPoint: DevicePoint?, to endPoint: DevicePoint?) -> Double {
        guard let startPoint, let endPoint else {
            return 0
        }

        let x = endPoint.x - startPoint.x
        let y = endPoint.y - startPoint.y
        return (x * x + y * y).squareRoot()
    }

    private func centroid(of contacts: [Int: TouchContact]) -> DevicePoint? {
        guard contacts.isEmpty == false else {
            return nil
        }

        let total = contacts.values.reduce(DevicePoint(x: 0, y: 0)) { partialResult, contact in
            DevicePoint(
                x: partialResult.x + contact.position.x,
                y: partialResult.y + contact.position.y
            )
        }

        let count = Double(contacts.count)
        return DevicePoint(x: total.x / count, y: total.y / count)
    }

    private func scheduleReconnect() {
        guard isStopped == false else {
            return
        }

        reconnectWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.connect()
        }

        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1, execute: workItem)
    }
}
