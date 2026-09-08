//
//  HitTestView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/14/22.
//

import SwiftUI
import GBGCore
#if os(macOS)
import AppKit
#endif

// Deliberately module-scope rather than @State on HitTestView: an earlier attempt to
// keep this as view state caused inconsistent behavior. Left as-is until that can be
// re-verified interactively (needs eyes on the running app, not just a clean build).
var height = 0.0

// Catches the window-activating click that AppKit otherwise swallows for focus alone: by
// default NSView.acceptsFirstMouse(for:) returns false, so when the window isn't key, the
// first click just brings it to front and is never delivered as a real mouseDown to the view
// underneath - a note placed with that first click was silently lost, requiring a second
// click. A local NSEvent monitor sidesteps that window-activation gate entirely (same
// technique already proven for scroll-wheel zoom in Seq/PianoRollView.swift - a local monitor
// sees matching events at the app level regardless of how the window's own view hierarchy
// would otherwise have handled them). Deliberately not conditioned on window.isKeyWindow -
// it's unclear whether that flag has already flipped true by the time a local monitor's
// handler runs, so this always calls the shared onFirstClick handler and relies on that
// handler's own isSound guard (mirroring the real DragGesture's own guard) to stay a no-op
// whenever a touch is already in progress - safe even if the real DragGesture also ends up
// firing normally for the same click, which is the common case once the window is key.
#if os(macOS)
private struct FirstClickCatcher: NSViewRepresentable {
    let onFirstClick: (CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FlippedNSView()
        context.coordinator.start(view: view, onFirstClick: onFirstClick)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onFirstClick = onFirstClick
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    // isFlipped = true so this view's own coordinate space is top-left origin, matching
    // SwiftUI's convention directly (plain NSViews are bottom-left origin by default) - the
    // caught location can then be treated exactly like a DragGesture's own value.location,
    // including the same height-flip HitTestView's other handlers already apply to it.
    final class FlippedNSView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator {
        var onFirstClick: ((CGPoint, Bool) -> Void)?
        private weak var view: NSView?
        private var monitor: Any?

        func start(view: NSView, onFirstClick: @escaping (CGPoint, Bool) -> Void) {
            self.view = view
            self.onFirstClick = onFirstClick
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let view = self.view else { return event }
                // addLocalMonitorForEvents fires for every left-mouse-down anywhere in the app,
                // not just this window - a click on the Settings popover (its own separate
                // NSWindow/NSPanel) or a menu was being misread as a click in the main window,
                // since view.convert(_:from:nil) blindly reinterprets event.locationInWindow as
                // if it belonged to `view`'s own window regardless of which window the event
                // actually came from - a coordinate collision that could land inside the graph's
                // bounds by coincidence and fire a note. Confirmed live 2026-09-07 ("menu clicks
                // also trigger graph notes"). Requiring the event's own window to match view's
                // window first is the fix - only a click truly in this window is worth converting
                // at all.
                guard event.window === view.window else { return event }
                let locationInView = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(locationInView) {
                    self.onFirstClick?(locationInView, event.modifierFlags.contains(.shift))
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif

struct HitTestView: View {
    // manage debug trace in hitTest
    let hitTestTrace = false
    
    let scale: Scale
    @ObservedObject var settings: AppSettings
    @ObservedObject var recordingState: RecordingState

    @State private var hoverLocation: CGPoint = .zero
    //@State private var isHovering = false
    @State private var isDrag = false
    @State private var isShift = false
    @State private var isSound = false
    // Tracks raw gesture lifecycle - true from a DragGesture's first onChanged to its onEnded,
    // always reset in onEnded regardless of pedal state. Deliberately separate from isSound,
    // which stays true across a pedal hand-off on purpose (see isSound's own onChange(of:
    // settings.pedal) comment) - that stickiness is exactly why isSound alone can't tell "a
    // brand-new touch just landed while pedal already held the previous note" apart from "this
    // is the same still-active touch". Used only to fire a re-strike (retriggerTouch) for the
    // former case, since beginGraphTouch's own onset detection won't retrigger a voice that
    // never went silent - confirmed live 2026-09-05 ("does fire on pen down... but does not
    // fire on pen down when pedal is on").
    @State private var isTouchDown = false
    
    var body: some View {
        Canvas(){context, size in
            var crosshairPoint:CGPoint = .zero
            height = size.height

            if hitTestTrace {print("HitTestView: isHovering")}
            let rootFrequency = settings.rootFrequency
            let snapped = !isShift

            // x: touch-driven, unless incoming MIDI (Seq, or any other controller) is currently
            // driving this axis - see AppSettings.externallyDrivenVoices and
            // Sound.handleIncomingMidi. When driven, the crosshair is drawn from whatever was
            // already written into settings.xFrequency instead of from hoverLocation, and
            // touching the graph has no effect on it (the DragGesture below skips the write
            // too) - whichever source is driving owns this axis's output until it's done.
            if settings.externallyDrivenVoices.contains(.x) {
                let xNormalized = log2(settings.xFrequency / rootFrequency)
                crosshairPoint.x = scale.convertScaleValueToScreenUnits(normalizedValue: xNormalized, screenSize: size.width)
            } else {
                let xHit = pitchHitTest(scale: scale, screenLocation: hoverLocation.x, graphSize: size.width, rootFrequency: rootFrequency, snapped: snapped)
                // xHit.frequency is a pure function of hoverLocation/rootFrequency/snapped, so
                // it's only actually different from settings.xFrequency when one of those truly
                // changed since the last render - guards against resending the exact same pitch
                // (to both the synth and, critically, any live MIDI destination) on every
                // unrelated view update this Canvas happens to re-run for, e.g. any other
                // settings change while a voice is already playing. Norm found this via a MIDI
                // capture: X/Y pitch bend kept re-arriving on a fixed stale value continuously
                // while nothing was actually being touched.
                //
                // The isDrag guard matters independently of that: this whole closure re-runs on
                // ANY settings change (e.g. Z-slider dragging, which is a totally separate touch
                // zone but shares this same AppSettings object), and hoverLocation keeps tracking
                // wherever the mouse cursor currently sits even when nothing's being touched (see
                // onContinuousHover below - that's deliberate, for the crosshair hover-preview).
                // Without this guard, X/Y's actual pitch would get silently overwritten by
                // whatever the mouse happens to be hovering over while dragging Z, since X/Y are
                // now audible during Z-only touches (Norm's own recent change) instead of muted
                // the way they used to be while graphTouchCount was 0 - crosshairPoint.x below
                // still uses the live hover position unconditionally, so the on-screen preview
                // keeps working exactly as before; only the audible/exported pitch is gated.
                if isDrag, xHit.frequency != settings.xFrequency {
                    sound.setXPitch(frequency: xHit.frequency)
                    settings.xFrequency = xHit.frequency
                }
                crosshairPoint.x = xHit.crosshair
            }

            // y: same pattern as x, above.
            let yCrosshair: Double
            if settings.externallyDrivenVoices.contains(.y) {
                let yNormalized = log2(settings.yFrequency / rootFrequency)
                yCrosshair = scale.convertScaleValueToScreenUnits(normalizedValue: yNormalized, screenSize: size.height)
            } else {
                let yHit = pitchHitTest(scale: scale, screenLocation: hoverLocation.y, graphSize: size.height, rootFrequency: rootFrequency, snapped: snapped)
                if isDrag, yHit.frequency != settings.yFrequency {
                    sound.setYPitch(frequency: yHit.frequency)
                    settings.yFrequency = yHit.frequency
                }
                yCrosshair = yHit.crosshair
            }

            // crosshair
            crosshairPoint.y = yCrosshair
            crosshairPoint.y = height - crosshairPoint.y
            
            // draw crosshair on graph
            context.stroke(
                Path { path in
                    let crossSize:Double = 8
                    path.move (to: CGPoint(x: crosshairPoint.x, y: crosshairPoint.y + crossSize))
                    path.addLine(to: CGPoint(x: crosshairPoint.x, y: crosshairPoint.y - crossSize))
                    path.move (to: CGPoint(x: crosshairPoint.x-crossSize, y: crosshairPoint.y))
                    path.addLine(to: CGPoint(x: crosshairPoint.x+crossSize, y: crosshairPoint.y))
                }, with: .color(.white),
                lineWidth: 3
            )
        }
        #if os(macOS)
        .background(FirstClickCatcher(onFirstClick: handleFirstClick))
        #endif
        // only needed for mouse input, so that crosshair is updated on hover
        .onContinuousHover { phase in
            if hitTestTrace {print("HitTestView: onContinuousHover")}
            switch phase {
            case .active(let location):
                hoverLocation = location
                hoverLocation.y = height - hoverLocation.y
            case .ended:
                if hitTestTrace {print("HitTestView: onContinuousHover .ended")}
            }
        }
        // not needed at all?
        .onHover(perform: {_ in
            if hitTestTrace {print("HitTestView: onHover")}
        }
    )
        
#if os(macOS)
        .gesture(
            // with shift pressed find a better solution for pen, since this is not implemented on iPad (yet?)
            // this is ONLY called when shift is pressed
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .modifiers(.shift)
            .onChanged { value in
                if hitTestTrace {print("HitTestView: DragGesture called with shift")}
                hoverLocation = value.location
                // invert y at the source
                hoverLocation.y = height - hoverLocation.y
                isDrag = true
                isShift = true
                if !isTouchDown {
                    isTouchDown = true
                    if isSound == false{
                        sound.beginGraphTouch(amp: 1)
                        recordingState.beginGraphTouch()
                        isSound = true
                    } else {
                        sound.retriggerTouch() // pedal already had it sounding - still a fresh strike
                    }
                }
            }
            .onEnded { _ in
                //hoverLocation = .zero  // don't think this is needed.
                isDrag = false
                isTouchDown = false
                // Resting state should reflect the Snapping toggle (matching the "hack" in the
                // plain gesture's onChanged below), not hardcode snapped=true - hardcoding this
                // to false used to make the crosshair visibly snap to the nearest diamond for a
                // frame right on release, even mid-Portamento with Snapping off, since the very
                // next hover-preview render would then compute a snapped hit-test. isDrag=false
                // (above) already freezes the actual audible pitch by that point (see the X/Y
                // write guards above), so this was a display-only glitch, not an audible one.
                isShift = !settings.snap
                sound.endGraphTouch(pedal: settings.pedal)
                recordingState.endGraphTouch()
                if !settings.pedal {
                    isSound = false
                }
            }
        )
#endif
        // for touch and pen
        // only called without shift pressed
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if hitTestTrace {print("HitTestView: DragGesture .onChanged called without shift")}
                    hoverLocation = value.location
                    hoverLocation.y = height - hoverLocation.y
                    isDrag = true
                    
                    // Mirrors settings.snap on every touch-move frame, not just once at the
                    // start of the drag (the original if isShift == false guard here only ever
                    // synced it the first time) - Norm found that releasing the new momentary-
                    // Portamento Shift key mid-drag correctly flipped settings.snap (and the
                    // toolbar icon) but the ongoing drag's own Portamento effect never let go,
                    // since nothing re-checked it again for the rest of that same touch. Now it
                    // tracks live, so a mid-drag Shift release (or press) takes effect
                    // immediately instead of only at the next touch's start.
                    isShift = !settings.snap
                    if !isTouchDown {
                        isTouchDown = true
                        if isSound == false{
                            sound.beginGraphTouch(amp: 1)
                            recordingState.beginGraphTouch()
                            isSound = true
                        } else {
                            sound.retriggerTouch() // pedal already had it sounding - still a fresh strike
                        }
                    }
                    if hitTestTrace {print("HitTestView: DragGesture .onChanged called. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
                .onEnded { _ in
                    //hoverLocation = .zero  // this has been causing occasional bad values leaking into drag gestures. Don't think it is actually needed.
                    isDrag = false
                    isTouchDown = false
                    // See the shift-modifier gesture's own onEnded, just above #endif, for why
                    // this reflects settings.snap rather than hardcoding false.
                    isShift = !settings.snap
                    // if pedal is true, sound keeps going until the pedal itself is released
                    sound.endGraphTouch(pedal: settings.pedal)
                    recordingState.endGraphTouch()
                    if !settings.pedal {
                        isSound = false
                    }
                    if hitTestTrace {print("HitTestView: DragGesture: .onEnded called. Drag ended without shift. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
        )
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
        // A touch's own onEnded only resets isSound to false when settings.pedal is already
        // false at that moment (see both gestures above) - deliberately, so a pedal-held touch
        // leaves isSound true and doesn't get double-triggered. But if the pedal is released
        // *afterward*, with no touch active, nothing was ever telling isSound to catch up -
        // it stayed stuck true, so the next real touch's onChanged saw isSound already true and
        // silently never called sound.beginGraphTouch() at all. Confirmed live: touching down
        // right after releasing a pedal that was sustaining a note produced no sound; the very
        // next touch (whose own onEnded finally reset isSound, since pedal was already false by
        // then) worked fine - the "only the first touch after pedal-off fails" signature this
        // fixes. Guarded by !isDrag so this can't fire mid-touch: releasePedal() itself already
        // no-ops while any touch is active (see Sound.releasePedal's own guard), so isSound
        // being true only because of a genuinely active touch is never what this needs to catch.
        .onChange(of: settings.pedal) {
            if !settings.pedal && !isDrag {
                isSound = false
            }
        }
    }

    // Mirrors exactly what a real DragGesture's onChanged does to start a touch (both the
    // shift-modifier and plain gestures above) - called from FirstClickCatcher for a click
    // that might otherwise have been swallowed for window focus alone. The isSound guard makes
    // this safe to call even when the real gesture also ends up firing normally for the same
    // click (the common case once the window is already key): whichever runs first wins, the
    // other just sees isSound already true and does nothing further.
    private func handleFirstClick(_ location: CGPoint, shiftHeld: Bool) {
        guard !isSound else { return }
        hoverLocation = location
        hoverLocation.y = height - hoverLocation.y
        isDrag = true
        if shiftHeld {
            isShift = true
        } else {
            // Same "hack to duplicate the effect of shift-down with UI" as the plain
            // DragGesture's own onChanged.
            isShift = !settings.snap
        }
        sound.beginGraphTouch(amp: 1)
        recordingState.beginGraphTouch()
        isSound = true
        isTouchDown = true // the real DragGesture's own onChanged, firing right after this for
                            // the same click, must see this already true - otherwise it would
                            // see isSound already true (just set above) and take the "pedal
                            // already had it sounding" retrigger branch for what's actually the
                            // same fresh touch this just started, firing a redundant retrigger.
    }
}
