//
//  TickView.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/24/24.
//

import SwiftUI

enum Alignment {
    case top
    case bottom
    case leading
    case trailing
}

// tick marks
struct Ticks: View {
    var border:Double
    var alignment: Alignment
    //var mcolor: Color = .white
    
    var body: some View {
        Canvas(){ context, size in
            var tickLocation = 0.0
            var startLocation = CGPoint(x:0.0,y:0.0)
            var endLocation = CGPoint(x:0.0,y:0.0)
            var textLocation = CGPoint(x:0.0,y:0.0)
            for tick in 0...12 {
                
                //deal with edges of view by nudging text and ticks into viewable area
                var nudge = 0.0
                if tick == 0 {nudge = 1.0}
                if tick == 12 {nudge = -1.0}
                switch alignment {
                    
                case .leading:
                    tickLocation = size.height - (((size.height) / 12) * Double(tick))
                    startLocation = CGPoint(x: border - 1.0, y: tickLocation-nudge)
                    endLocation = CGPoint(x: border - 10.0, y: tickLocation-nudge)
                    textLocation = CGPoint(x: endLocation.x-10, y: tickLocation-(nudge*8))
                    
                case .trailing:
                    tickLocation = size.height - (((size.height) / 12) * Double(tick))
                    startLocation = CGPoint(x: 1.0, y: tickLocation-nudge)
                    endLocation = CGPoint(x: 10.0, y: tickLocation-nudge)
                    textLocation = CGPoint(x: endLocation.x+10, y: endLocation.y-(nudge*8))

                case .top:
                    tickLocation = (size.width / 12) * Double(tick)
                    startLocation = CGPoint(x: tickLocation+nudge, y: border - 1.0)
                    endLocation = CGPoint(x: tickLocation+nudge, y: border - 10.0)
                    textLocation = CGPoint(x: endLocation.x+(nudge*8), y: endLocation.y - 10)

                case .bottom:
                    tickLocation = ((size.width) / 12) * Double(tick)
                    startLocation = CGPoint(x: tickLocation+nudge, y: 1.0)
                    endLocation = CGPoint(x: tickLocation+nudge, y: 10.0)
                    textLocation = CGPoint(x: endLocation.x+(nudge*8), y: endLocation.y + 10)
                }
                
                // draw tick
                var mcolor: Color = .white
                
                let whiteTicks: Set = [0,2,4,5,7,9,11,12] // C, D, E, F, G, A, B, C
                if whiteTicks.contains(tick) {
                    let _ = (mcolor = .white)
                } // let _ = is a hack to make compiler view with assignment, since it returns a value
                else {
                    let _ = (mcolor = .blue)
                }
                
                let _ = context.stroke(
                    Path { path in
                        path.move(to: startLocation)
                        path.addLine(to: endLocation)
                    },
                    with: .color(mcolor),
                    lineWidth: 2
                )
                
                //Draw Note Name
                let noteNames = ["C³","","D³","","E³","F³","","G³","","A³","","B³","C⁴"]
                let _ = context.draw(Text(noteNames[tick]),at: textLocation)
            }
        }
    }
}
