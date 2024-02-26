//
//  HitTestView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/14/22.
//

import SwiftUI

@available(macOS 13.0, *)
struct HitTestView: View {
    var scale:Scale
    var snap:Bool
    
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    @State private var isKeyDown = false
    @State private var isShiftPressed = false
    @State private var isDragWithoutShift = false
    @State private var isDragWithShift = false
    
    var body: some View {
        Canvas(){context, size in
            context.stroke(
            Path { path in
                // crosshair
                var graphPoint:CGPoint = .zero
                
                // graph is the size of the view less the left and right border
                let graphWidth = size.width
                let graphHeight = size.height
                
                //print("HoverLocation: \(hoverLocation)")
                // not interested if mouse is outside of x and y graph edges
                if hoverLocation.x < 0 || hoverLocation.x > graphWidth || hoverLocation.y < 0 || hoverLocation.y > graphWidth {
                    print ("out of bounds")
                    return
                }
                
                // hit test for x axis against hoverLocation.x
                for scaleElement in scale.scale {
                    let lowerBounds = (graphWidth * scaleElement.lowerBounds)
                    let upperBounds = (graphWidth * scaleElement.upperBounds)
                    let locationX = hoverLocation.x
                    
                    // if location is less than the start of the graph, break loop
                    if locationX >= lowerBounds && locationX <= upperBounds {
                        
                        if isShiftPressed {
                            // if shift is pressed, play the unsnapped pitch, else play snapped value
                            //2^(701.955001/1200) = 1.5 hz - this is an example in standard notation for a perfect fifth
                            let graphLocation = locationX
                            let graphRatio = graphLocation / graphWidth //0 to 1 value in linear measure, not log as is needed for frequency
                            let frequencyRatio = pow(2, graphRatio) //make it log. converts to correct 1 to 2 value for frequency ratio. Works!
                            let unsnappedPitch =  triad.getRootPitch() * frequencyRatio // apply the ratio to the root frequency to get an actual frequency
                            triad.setXPitch(frequency: unsnappedPitch) // set the x value of the triad in the audio synthesiser to this frequency
                        }
                        else{
                            // if shift is not pressed, set snapped pitch from scale
                            let f2 = (scaleElement.value) * triad.getRootPitch()
                            triad.setXPitch(frequency: f2)
                        }
                        //assign x to crosshair
                        graphPoint.x = (graphWidth * scaleElement.valueNormalized)
                    }
                }
                // hit test for y axis against hoverLocation.y
                for scaleElement in scale.scale {
                    let lowerBounds = graphHeight - (graphHeight * scaleElement.lowerBounds)
                    let upperBounds = graphHeight - (graphHeight * scaleElement.upperBounds)
                    let locationY = hoverLocation.y
                    
                    // print("HitTestView: locationY = \(locationY), upperBounds = \(upperBounds), lowerBounds = \(lowerBounds)")
                    
                    if locationY <= lowerBounds && locationY >= upperBounds {
                        
                        if isShiftPressed {
                            // if shift is pressed, play the unsnapped pitch, else play snapped value
                            
                            //2^(701.955001/1200) = 1.5 hz - this is an example in standard notation for a perfect fifth
                            let graphLocation = locationY
                            var graphRatio = graphLocation / graphHeight //0 to 1 value in linear measure, not log as is needed for frequency
                            graphRatio  = 1-graphRatio // invert because y axis is upside down
                            //let graphCents = 1200 * graphRatio //this is correct! Finally! Included here only for debug output
                            let frequencyRatio = pow(2, graphRatio) //make it log. converts to correct 1 to 2 value for frequency ratio. Works!
                            let unsnappedPitch =  triad.getRootPitch() * frequencyRatio // apply the ratio to the root frequency to get an actual frequency
                            triad.setYPitch(frequency: unsnappedPitch) // set the x value of the triad in the audio synthesiser to this frequency
                            
                            // spew for debugging
                            //print("graphWidth = \(graphWidth), locationX = \(locationX), border = \(border), graphLocationX = \(graphLocationX), graphRatio = \(graphRatio), graphCents = \(graphCents), frequencyRatio = \(frequencyRatio)")
                        }
                        
                        else{
                            
                            // assign y pitch to snapped value
                            let f3 = (scaleElement.value) * triad.getRootPitch()
                            triad.setYPitch(frequency: f3)
                            //print("Snapped Y pitch = \(f3)")
                        }
                        
                        //assign y to crosshair
                        graphPoint.y =  size.height - ((graphHeight * scaleElement.valueNormalized))
                        //print("graphPoint.y =", graphPoint.y)
                    }
                }
                
                // draw crosshair
                let x:Double = 8
                path.move (to: CGPoint(x: graphPoint.x, y: graphPoint.y + x))
                path.addLine(to: CGPoint(x: graphPoint.x, y: graphPoint.y - x))
                path.move (to: CGPoint(x: graphPoint.x-x, y: graphPoint.y))
                path.addLine(to: CGPoint(x: graphPoint.x+x, y: graphPoint.y))
            }, with: .color(.white),
            lineWidth: 3
            )}
        
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    isHovering = true
                    //print ("HitTestView: onContinousHover: Hover active phase \(hoverLocation)")
                case .ended:
                    isHovering = false
                    print ("Hover ended phase")
                }
            }
            .onHover(perform: {_ in
                print("HitTestView: onContinousHover: onHover")
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
                        //print("HitTestView: value.location = \(value.location)")
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
                            print("HitTestView: DragGesture: Drag started without shift")
                            isDragWithoutShift = true
                            if snap {isShiftPressed = false}
                            else {isShiftPressed = true}
                            audio.startAudio(amp: 1)
                        }
                        //print("HitTestView: value.location = \(value.location)")
                    }
                    .onEnded { _ in
                        hoverLocation = .zero
                        isDragWithoutShift = false
                        isShiftPressed = false
                        print("HitTestView: DragGesture: Drag ended without shift")
                        audio.stopAudio()
                    }
            )
#if os(iOS)
            .defersSystemGestures(on: .all)
#endif
        }
    }
    


