//
//  MouseEventInterceptor.swift
//  demo_middleClickForMac
//
//  Created by Tal Klein on 11/08/2026.
//

import AppKit
import CoreGraphics

final class MouseEventInterceptor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {

        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, userInfo in

                return MouseEventInterceptor.handleEvent(
                    proxy: proxy,
                    type: type,
                    event: event
                )
            },
            userInfo: nil
        )

        guard let eventTap else {
            print("Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )

        guard let runLoopSource else {
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )

        CGEvent.tapEnable(
            tap: eventTap,
            enable: true
        )

    }
    
    private static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        if event.getIntegerValueField(.eventSourceUserData) == MouseSimulator.syntheticMiddleClickMarker {
            return Unmanaged.passUnretained(event)
        }

        let state = GestureState.shared

        switch type {

        case .leftMouseDown, .rightMouseDown:

            if let kind = state.claimActivePhysicalClickGesture() {
                GestureDiagnostics.log("[PhysicalClick] \(type == .leftMouseDown ? "leftDown" : "rightDown") intercepted device=\(kind.rawValue)")
                MouseSimulator.middleClick()

                return nil
            }

        case .leftMouseUp, .rightMouseUp:

            if state.consumeSuppressingPhysicalClick() {
                GestureDiagnostics.log("[PhysicalClick] original mouseUp suppressed")
                return nil
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
