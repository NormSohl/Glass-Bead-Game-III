//
//  HitTestView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/14/22.
//

import SwiftUI

// Deliberately module-scope rather than @State on HitTestView: an earlier attempt to
// keep this as view state caused inconsistent behavior. Left as-is until that can be
// re-verified interactively (needs eyes on the running app, not just a clean build).
var height = 0.0

struct HitTestView: View {
    // manage debug trace in hitTest
    let hitTestTrace = false
    
    let scale: Scale
    @ObservedObject var settings: AppSettings
    
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

            // x: touch-driven, unless the sequencer is currently driving this axis (playback,
            // scrub, or a piano-roll handle drag on an X note) - see AppSettings.
            // sequencerDrivenVoices. When driven, the crosshair is drawn from whatever the
            // sequencer already wrote into settings.xFrequency instead of from hoverLocation,
            // and touching the graph has no effect on it (the DragGesture below skips the write
            // too) - the sequencer owns this axis's output until it's done with it.
            if settings.sequencerDrivenVoices.contains(.x) {
                let xNormalized = log2(settings.xFrequency / rootFrequency)
                crosshairPoint.x = scale.convertScaleValueToScreenUnits(normalizedValue: xNormalized, screenSize: size.width)
            } else {
                let xHit = pitchHitTest(scale: scale, screenLocation: hoverLocation.x, graphSize: size.width, rootFrequency: rootFrequency, snapped: snapped)
                sound.setXPitch(frequency: xHit.frequency)
                settings.xFrequency = xHit.frequency
                crosshairPoint.x = xHit.crosshair
            }

            // y: same pattern as x, above.
            let yCrosshair: Double
            if settings.sequencerDrivenVoices.contains(.y) {
                let yNormalized = log2(settings.yFrequency / rootFrequency)
                yCrosshair = scale.convertScaleValueToScreenUnits(normalizedValue: yNormalized, screenSize: size.height)
            } else {
                let yHit = pitchHitTest(scale: scale, screenLocation: hoverLocation.y, graphSize: size.height, rootFrequency: rootFrequency, snapped: snapped)
                sound.setYPitch(frequency: yHit.frequency)
                settings.yFrequency = yHit.frequency
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
                    isSound = true
                }
            }
            .onEnded { _ in
                //hoverLocation = .zero  // don't think this is needed.
                isDrag = false
                isShift = false
                sound.endGraphTouch(pedal: settings.pedal)
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
                        isSound = true
                    }
                    if hitTestTrace {print("HitTestView: DragGesture .onChanged called. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
                .onEnded { _ in
                    //hoverLocation = .zero  // this has been causing occasional bad values leaking into drag gestures. Don't think it is actually needed.
                    isDrag = false
                    isShift = false
                    // if pedal is true, sound keeps going until the pedal itself is released
                    sound.endGraphTouch(pedal: settings.pedal)
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
