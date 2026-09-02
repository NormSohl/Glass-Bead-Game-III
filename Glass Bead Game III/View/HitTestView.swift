//
//  HitTestView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/14/22.
//

import SwiftUI
import GBGCore

// Deliberately module-scope rather than @State on HitTestView: an earlier attempt to
// keep this as view state caused inconsistent behavior. Left as-is until that can be
// re-verified interactively (needs eyes on the running app, not just a clean build).
var height = 0.0

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
    
    var body: some View {
        Canvas(){context, size in
            var crosshairPoint:CGPoint = .zero
            height = size.height

            if hitTestTrace {print("HitTestView: isHovering")}
            let rootFrequency = settings.rootFrequency
            let snapped = !isShift

            // x: touch-driven, unless the sequencer or incoming MIDI is currently driving this
            // axis (playback, scrub, a piano-roll handle drag on an X note, or an external MIDI
            // note-on - see AppSettings.sequencerDrivenVoices/externallyDrivenVoices and
            // Sound.handleIncomingMidi). When driven, the crosshair is drawn from whatever was
            // already written into settings.xFrequency instead of from hoverLocation, and
            // touching the graph has no effect on it (the DragGesture below skips the write
            // too) - whichever source is driving owns this axis's output until it's done.
            if settings.sequencerDrivenVoices.contains(.x) || settings.externallyDrivenVoices.contains(.x) {
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
            if settings.sequencerDrivenVoices.contains(.y) || settings.externallyDrivenVoices.contains(.y) {
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
                if isSound == false{
                    sound.beginGraphTouch(amp: 1)
                    recordingState.beginGraphTouch()
                    isSound = true
                }
            }
            .onEnded { _ in
                //hoverLocation = .zero  // don't think this is needed.
                isDrag = false
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
                    
                    // hack to duplicate the effect of shift-down with UI
                    if isShift == false{
                        if settings.snap {isShift = false}
                        else {isShift = true}
                    }
                    if isSound == false{
                        sound.beginGraphTouch(amp: 1)
                        recordingState.beginGraphTouch()
                        isSound = true
                    }
                    if hitTestTrace {print("HitTestView: DragGesture .onChanged called. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
                .onEnded { _ in
                    //hoverLocation = .zero  // this has been causing occasional bad values leaking into drag gestures. Don't think it is actually needed.
                    isDrag = false
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
    }
}
