//
//  HitTestView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/14/22.
//

import SwiftUI

@available(macOS 13.0, *)
struct HitTestView: View {
    let scale: Scale
    let settings: AppSettings
    
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    @State private var isKeyDown = false
    @State private var isShiftPressed = false
    @State private var isDragWithoutShift = false
    @State private var isDragWithShift = false
    
    var body: some View {
        Canvas(){context, size in
            var crosshairPoint:CGPoint = .zero
            
            // hit test x
            let xHit = hittest(graphSize: size.width, screenLocation: hoverLocation.x, invert: false)
            triad.setXPitch(frequency: xHit.frequency)
            crosshairPoint.x = xHit.crosshair
            
            // hit test y
            let yHit = hittest(graphSize: size.height, screenLocation: hoverLocation.y, invert: true)
            triad.setYPitch(frequency: yHit.frequency)
            crosshairPoint.y = yHit.crosshair
            
            // draw crosshair on graph
            context.stroke(
                Path { path in
                    let x:Double = 8
                    path.move (to: CGPoint(x: crosshairPoint.x, y: crosshairPoint.y + x))
                    path.addLine(to: CGPoint(x: crosshairPoint.x, y: crosshairPoint.y - x))
                    path.move (to: CGPoint(x: crosshairPoint.x-x, y: crosshairPoint.y))
                    path.addLine(to: CGPoint(x: crosshairPoint.x+x, y: crosshairPoint.y))
                }, with: .color(.white),
                lineWidth: 3
            )
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
                isHovering = true
                //print ("HitTestView: onContinousHover: Hover active phase \(hoverLocation)")
            case .ended:
                isHovering = false
                //print ("Hover ended phase")
            }
        }
        .onHover(perform: {_ in
            //print("HitTestView: onContinousHover: onHover")
        })
        
#if os(macOS)
        .gesture(
            // with shift pressed find a better solution for pen, since this is not implemented on iPad (yet?)
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .modifiers(.shift)
                .onChanged { value in
                    hoverLocation = value.location
                    if isDragWithShift == false{
                        print("HitTestView: DragGesture: Drag started with shift")
                        isDragWithShift = true
                        isShiftPressed = true
                        audio.startAudio(amp: 1)
                    }
                }
                .onEnded { _ in
                    hoverLocation = .zero
                    isDragWithShift = false
                    isShiftPressed = false
                    print("HitTestView: DragGesture: Drag ended with shift")
                    audio.stopAudio()
                }
        )
#endif
        
        // for touch and pen
        // without shift pressed
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    hoverLocation = value.location
                    if isDragWithoutShift == false{
                        //print("HitTestView: DragGesture: Drag started without shift")
                        isDragWithoutShift = true
                        if settings.snap {isShiftPressed = false}
                        else {isShiftPressed = true}
                        audio.startAudio(amp: 1)
                    }
                }
                .onEnded { _ in
                    hoverLocation = .zero
                    isDragWithoutShift = false
                    isShiftPressed = false
                    //print("HitTestView: DragGesture: Drag ended without shift")
                    audio.stopAudio()
                }
        )
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
    
    func hittest(graphSize: Double, screenLocation: Double, invert: Bool)->(frequency: Double, crosshair: Double){
        
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
                screenSize: graphSize,
                invert: invert)
            
            upperBounds = scale.convertScaleValueToScreenUnits(
                normalizedValue: scaleElement.upperBounds,
                screenSize: graphSize,
                invert: invert)
            
            if invert == false {
                if screenLocation >= lowerBounds && screenLocation <= upperBounds {
                    print("HitTest: X axis")
                    let ret = hitTestCore(
                        invert: invert,
                        screenLocation: screenLocation,
                        graphSize: graphSize,
                        scaleElement: scaleElement)
                    frequency = ret.frequency
                    crosshair = ret.crosshair
                }
            }
            else {
                if screenLocation <= lowerBounds && screenLocation >= upperBounds {
                    print("HitTest: Y axis")
                    let ret = hitTestCore(
                        invert: true,
                        screenLocation: screenLocation,
                        graphSize: graphSize,
                        scaleElement: scaleElement)
                    frequency = ret.frequency
                    crosshair = ret.crosshair
                }
            }
        }
        return (frequency: frequency, crosshair: crosshair)
    }
    
    func startAudio (){
        triad.enableRootTone(enable: settings.playDrone)
        triad.enableXTone(enable: settings.playNoteX)
        triad.enableYTone(enable: settings.playNoteY)
        audio.startAudio(amp: 1)
    }
    
    func stopAudio (){
        audio.stopAudio()
    }
    
    func hitTestCore(
        invert: Bool,
        screenLocation: Double,
        graphSize: Double,
        scaleElement: ScaleElement
    )->(frequency: Double, crosshair: Double){
        
        // init return values
        var frequency: Double = 0.0
        var crosshair: Double = 0.0
        
        if isShiftPressed {
            // if shift is pressed, play the unsnapped pitch, else play snapped value.
            let screenRatio = screenLocation / graphSize //0 to 1 value in linear measure, not log as is needed for frequency
            // value is linear between 0 and rangeNormalized
            var value = scale.rangeNormalized * screenRatio
            
            if invert {  // invert. this is the y axis
                // invert value
                value =   1 - (value + scale.lowestRatioNormalized)
                // drop it by an octave - this is needed when there is an octave above and below. don't know why yet
                // not needed when the range is a fifth above and below. 
                //value = value - 1
            }
            else {  //don't invert this is the x axis
                value = value + scale.lowestRatioNormalized
            }
            
            // convert to frequency ratio
            let frequencyRatio = pow(2, value)
            frequency =  (triad.getRootPitch() * frequencyRatio) // apply the ratio to the root frequency to get an actual frequency
            // dont snap the crosshair
            crosshair = scale.convertScaleValueToScreenUnits(
                normalizedValue: value,
                screenSize: graphSize,
                invert: invert)
        }
        else{  // shift is not pressed, play snapped value from scale
            frequency = (triad.getRootPitch() * scaleElement.value)
            
            // snap the crosshair
            crosshair = scale.convertScaleValueToScreenUnits(
                normalizedValue: scaleElement.valueNormalized,
                screenSize: graphSize,
                invert: invert)
        }
        return (frequency, crosshair)
    }
}
