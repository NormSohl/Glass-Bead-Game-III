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
            let xHit = hittest(graphSize: size.width, location: hoverLocation.x, invert: false)
            triad.setXPitch(frequency: xHit.frequency)
            crosshairPoint.x = xHit.crosshair
                    
            // hit test y
            let yHit = hittest(graphSize: size.height, location: hoverLocation.y, invert: true)
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
                        startAudio()
                    }
                }
                .onEnded { _ in
                    hoverLocation = .zero
                    isDragWithShift = false
                    isShiftPressed = false
                    print("HitTestView: DragGesture: Drag ended with shift")
                    stopAudio()
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
                    startAudio()
                }
            }
            .onEnded { _ in
                hoverLocation = .zero
                isDragWithoutShift = false
                isShiftPressed = false
                //print("HitTestView: DragGesture: Drag ended without shift")
                stopAudio()
            }
        )
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
    
    func hittest(graphSize: Double, location: Double, invert: Bool)->(frequency: Double, crosshair: Double){
        
        // init return values
        var frequency: Double = 0.0
        var crosshair: Double = 0.0
        
        // hit test for hoverLocation
        var lowerBounds: Double = 0.0
        var upperBounds: Double = 0.0
        
        
        for scaleElement in scale.scale {
            //print("HitTestView: scale = \(scale.scale)")
            if invert == false {
                // process for x axis
                lowerBounds = (graphSize * scaleElement.lowerBounds)
                upperBounds = (graphSize * scaleElement.upperBounds)
                if location >= lowerBounds && location <= upperBounds {
                    
                    if isShiftPressed {
                        // if shift is pressed, play the unsnapped pitch, else play snapped value.
                        let graphRatio = location / graphSize //0 to 1 value in linear measure, not log as is needed for frequency
                        let frequencyRatio = pow(2, graphRatio) //make it log. converts to correct 1 to 2 value for frequency ratio. Works!
                        frequency =  triad.getRootPitch() * frequencyRatio // apply the ratio to the root frequency to get an actual frequency
                    }
                    else{
                        // if shift is not pressed, play snapped value from scale
                        frequency = (scaleElement.value) * triad.getRootPitch()
                    }
                    crosshair = (graphSize * scaleElement.valueNormalized)
               }
            }
            else {
                // process for y axis which is inverted
                lowerBounds = graphSize - (graphSize * scaleElement.lowerBounds)
                upperBounds = graphSize - (graphSize * scaleElement.upperBounds)
                // if location is less than the start of the graph, break loop
                if location <= lowerBounds && location >= upperBounds {
                    
                    if isShiftPressed {
                        // if shift is pressed, play the unsnapped pitch, else play snapped value.
                        let graphRatio = 1 - (location / graphSize) //0 to 1 value in linear measure, not log as is needed for frequency
                        let frequencyRatio = pow(2, graphRatio) //make it log. converts to correct 1 to 2 value for frequency ratio. Works!
                        frequency =  triad.getRootPitch() * frequencyRatio // apply the ratio to the root frequency to get an actual frequency
                    }
                    else{
                        // if shift is not pressed, play snapped value from scale
                        frequency = (scaleElement.value) * triad.getRootPitch()
                    }
                    crosshair =  graphSize - ((graphSize * scaleElement.valueNormalized))
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
}
    


