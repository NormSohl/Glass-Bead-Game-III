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
    let settings: AppSettings
    
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
            // hit test x
            let xHit = hitTest(graphSize: size.width, screenLocation: hoverLocation.x)
            sound.setXPitch(frequency: xHit.frequency)
            crosshairPoint.x = xHit.crosshair
            
            // hit test y
            let yHit = hitTest(graphSize: size.height, screenLocation: hoverLocation.y)
            sound.setYPitch(frequency: yHit.frequency)
            
            // crosshair
            crosshairPoint.y = yHit.crosshair
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
                    sound.startSound(amp: 1)
                    isSound = true
                }
            }
            .onEnded { _ in
                //hoverLocation = .zero  // don't think this is needed.
                isDrag = false
                isShift = false
                if !settings.pedal {
                    sound.stopSound()
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
                        sound.startSound(amp: 1)
                        isSound = true
                    }
                    if hitTestTrace {print("HitTestView: DragGesture .onChanged called. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
                .onEnded { _ in
                    //hoverLocation = .zero  // this has been causing occasional bad values leaking into drag gestures. Don't think it is actually needed.
                    isDrag = false
                    isShift = false
                    // if pedal is true, then use pointer out of graph to turn off sound
                    if !settings.pedal {
                        sound.stopSound()
                        isSound = false
                    }
                    if hitTestTrace {print("HitTestView: DragGesture: .onEnded called. Drag ended without shift. isDrag = \(isDrag), isShift = \(isShift), isSound = \(isSound)")}
                }
        )
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
    
    func hitTest(graphSize: Double, screenLocation: Double)->(frequency: Double, crosshair: Double){
        // init return values
        var frequency: Double = 0.0
        var crosshair: Double = 0.0
        
        // hit test for hoverLocation
        var lowerBounds: Double = 0.0
        var upperBounds: Double = 0.0
        
        for scaleElement in scale.scale {
            // process for x axis
            lowerBounds = scale.convertScaleValueToScreenUnits(
                normalizedValue: scaleElement.lowerBounds,
                screenSize: graphSize)
            
            upperBounds = scale.convertScaleValueToScreenUnits(
                normalizedValue: scaleElement.upperBounds,
                screenSize: graphSize)

            if screenLocation >= lowerBounds && screenLocation <= upperBounds {
                //print("HitTest: X axis")
                let ret = hitTestCore(
                    screenLocation: screenLocation,
                    graphSize: graphSize,
                    scaleElement: scaleElement)
                frequency = ret.frequency
                crosshair = ret.crosshair
                break;
            }
        }
        if hitTestTrace { print("HitTestView: hitTest called with return of: frequency: \(frequency), crosshair: \(crosshair)" )}
        return (frequency: frequency, crosshair: crosshair)
    }
    
    func hitTestCore(
        screenLocation: Double,
        graphSize: Double,
        scaleElement: ScaleElement
    )->(frequency: Double, crosshair: Double){
        
        // init return values
        var frequency: Double = 0.0
        var crosshair: Double = 0.0
        
        if isShift {
            // if shift is pressed, play the unsnapped pitch, else play snapped value.
            let screenRatio = screenLocation / graphSize //0 to 1 value in linear measure, not log as is needed for frequency
            // value is linear between 0 and rangeNormalized
            var value = scale.rangeNormalized * screenRatio
            // adjust tp be negitive if needed
            value = value + scale.lowestRatioNormalized
            
            // convert to frequency ratio
            let frequencyRatio = pow(2, value)
            frequency =  (sound.audio.triad.getTriadRootPitch() * frequencyRatio) // apply the ratio to the root frequency to get an actual frequency
            // dont snap the crosshair
            crosshair = scale.convertScaleValueToScreenUnits(
                normalizedValue: value,
                screenSize: graphSize)
        }
        else{  // shift is not pressed, play snapped value from scale
            frequency = (sound.audio.triad.getTriadRootPitch() * scaleElement.value)
            
            // snap the crosshair
            crosshair = scale.convertScaleValueToScreenUnits(
                normalizedValue: scaleElement.valueNormalized,
                screenSize: graphSize)
        }
        if hitTestTrace { print("HitTestView: hitTestCore called with return of: frequency: \(frequency), crosshair: \(crosshair)" )}
        return (frequency, crosshair)
    }
}
