//
//  MouseSimulator.swift
//  demo_middleClickForMac
//
//  Created by Tal Klein on 11/08/2026.
//

import CoreGraphics
import Foundation

enum MouseSimulator {

    static let syntheticMiddleClickMarker: Int64 = 0x54484D4944444C45

    static func middleClick() {

        GestureState.shared.markSyntheticMiddleClick()

        guard let currentEvent = CGEvent(source: nil) else {
            return
        }

        let location = currentEvent.location

        guard
            let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: location,
                mouseButton: .center
            ),
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseUp,
                mouseCursorPosition: location,
                mouseButton: .center
            )
        else {
            return
        }

        down.setIntegerValueField(.eventSourceUserData, value: syntheticMiddleClickMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticMiddleClickMarker)

        GestureDiagnostics.log("[PhysicalClick] synthetic middle down")
        down.post(tap: .cghidEventTap)
        GestureDiagnostics.log("[PhysicalClick] synthetic middle up")
        up.post(tap: .cghidEventTap)
    }
}
