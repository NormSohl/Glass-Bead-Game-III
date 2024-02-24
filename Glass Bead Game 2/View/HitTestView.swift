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
    var border:Double
    var snap:Bool
    
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    @State private var isKeyDown = false
    @State private var isShiftPressed = false
    @State private var isDragWithoutShift = false
    @State private var isDragWithShift = false
    
    init(scaleIn: Scale, borderIn: Double, snapIn: Bool){
        scale = scaleIn
        border = borderIn
        snap = snapIn
    }
    
    var body: some View {
        Canvas(){context, size in
            context.stroke(
            Path { path in
                // crosshair
                var graphPoint:CGPoint = .zero
                
                // graph is the size of the view less the left and right border
                let graphWidth = size.width - border - border
                let graphHeight = size.height - border - border
                
                //print("HoverLocation: \(hoverLocation)")
                // not interested if mouse is outside of x and y graph edges
                if hoverLocation.x < border || hoverLocation.x > border + graphWidth || hoverLocation.y < border || hoverLocation.y > graphWidth + border + border {
                    //print ("out of bounds")
                    return
                }
                
                // hit test for x axis against hoverLocation.x
                for scaleElement in scale.scale {
                    let lowerBounds = (graphWidth * scaleElement.lowerBounds) + border
                    let upperBounds = (graphWidth * scaleElement.upperBounds) + border
                    let locationX = hoverLocation.x
                    
                    // if location is less than the start of the graph, break loop
                    if locationX >= lowerBounds && locationX <= upperBounds {
                        
                        if isShiftPressed {
                            // if shift is pressed, play the unsnapped pitch, else play snapped value
                            //2^(701.955001/1200) = 1.5 hz - this is an example in standard notation for a perfect fifth
                            let graphLocation = locationX - border
                            let graphRatio = graphLocation / graphWidth //0 to 1 value in linear measure, not log as is needed for frequency
                            //let graphCents = 1200 * graphRatio //this is correct! Finally! Included here only for debug output
                            let frequencyRatio = pow(2, graphRatio) //make it log. converts to correct 1 to 2 value for frequency ratio. Works!
                            let unsnappedPitch =  triad.getRootPitch() * frequencyRatio // apply the ratio to the root frequency to get an actual frequency
                            triad.setXPitch(frequency: unsnappedPitch) // set the x value of the triad in the audio synthesiser to this frequency
                            
                            // spew for debugging
                            //print("graphWidth = \(graphWidth), locationX = \(locationX), border = \(border), graphLocationX = \(graphLocationX), graphRatio = \(graphRatio), graphCents = \(graphCents), frequencyRatio = \(frequencyRatio)")
                        }
                        else{
                            // if shift is not pressed, set snapped pitch from scale
                            // assign x pitch
                            let f2 = (scaleElement.value) * triad.getRootPitch()
                            triad.setXPitch(frequency: f2)
                            //print("scaleElement.value = \(scaleElement.value), unsnappedRatioX = \(unsnappedRatioX), Snapped X pitch = \(f2), unsnapped X pitch = \(unsnappedPitch)")
                        }
                        //assign x to crosshair
                        graphPoint.x = (graphWidth * scaleElement.valueNormalized) + border
                        if graphPoint.x < border { graphPoint.x = border }
                    }
                }
                // hit test for y axis against hoverLocation.y
                for scaleElement in scale.scale {
                    let lowerBounds = graphHeight - (graphHeight * scaleElement.lowerBounds) + border
                    let upperBounds = graphHeight - (graphHeight * scaleElement.upperBounds) + border
                    let locationY = hoverLocation.y
                    
                    // print("HitTestView: locationY = \(locationY), upperBounds = \(upperBounds), lowerBounds = \(lowerBounds)")
                    
                    if locationY <= lowerBounds && locationY >= upperBounds {
                        
                        if isShiftPressed {
                            // if shift is pressed, play the unsnapped pitch, else play snapped value
                            
                            //2^(701.955001/1200) = 1.5 hz - this is an example in standard notation for a perfect fifth
                            let graphLocation = locationY - border
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
                        graphPoint.y =  size.height - ((graphHeight * scaleElement.valueNormalized) + border)
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
            //.onKeyPress(phases: .all) { press in
            //    //var key:String = ""
            //    //key += press.characters
            //    print("Hit test view KeyPress = \(press.characters)")
            //    return .handled
            //}
            
            // due to mouse down stopping hover behavior, use key to trigger sound. This allows hover to continue while turning on rendering of sound. Any key works.  It would be nice to block repeat of keydown
            /*
             .onAppear(perform: {
             NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
             isShiftPressed = NSEvent.modifierFlags.contains(.shift)
             if isKeyDown == false {
             isKeyDown = true
             
             HitTestView.audio.startAudio(amp: 0.1)
             print("keyDown Event. isKeyDown = ", isKeyDown)
             //print("startAudio amp = 0.5")
             }
             return nil
             }
             NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) {_ in
             if isKeyDown == true {
             isKeyDown = false
             print("keyUp Event. isKeyDown = ", isKeyDown)
             HitTestView.audio.stopAudio()
             }
             return nil
             }
             //NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) {_ in
             //    var location = NSEvent.mouseLocation
             //
             //    print("Mouse drag location = ", location)
             //    return nil
             //}
             
             //NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {_ in
             //    hoverLocation   = self.mouseLocation
             //    print("mouse: \(self.mouseLocation.x) \(self.mouseLocation.y)")
             //    return nil
             //}
             })*/
        }
        //func normalizeValue (minValue:Int, maxValue:Int, normalizeThis:CGFloat) ->CGFloat {
        //    return (normalizeThis - CGFloat (minValue)) / CGFloat (maxValue - minValue)
        
        //}
    }
    


