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
    let border:Double
    let alignment: Alignment
    let rangeBelow: Double
    let rangeAbove: Double
    //let Mysize: Double
    
    var body: some View {
        Canvas(){
            context, size in
            var tickLocation = 0.0
            var startLocation = CGPoint(x:0.0,y:0.0)
            var endLocation = CGPoint(x:0.0,y:0.0)
            var textLocation = CGPoint(x:0.0,y:0.0)
            
            // rangeBelow is negative, -1 to 0 for the octave, may be lower or higher. rangeAbove is positive, 0 to 1 for octave, may be lower or higher.
            let range = abs(rangeBelow) + rangeAbove
            let numTicks = 12 * range
            let centerTick = 12 * abs(rangeBelow)
            
            var MySize = size.width
            if size.height > MySize {MySize = size.height}
            
            for tick in 0...Int(numTicks){
                //deal with edges of view by nudging text and ticks into viewable area
                var nudge = 0.0
                if tick == 0 {nudge = 1.0}
                if tick == Int(numTicks) {nudge = -1.0}
                switch alignment {
                    
                case .leading:
                    tickLocation = size.height - (((size.height) / numTicks) * Double(tick))
                    startLocation = CGPoint(x: border - 1.0, y: tickLocation-nudge)
                    endLocation = CGPoint(x: border - 10.0, y: tickLocation-nudge)
                    textLocation = CGPoint(x: endLocation.x-10, y: tickLocation-(nudge*10))
                    
                case .trailing:
                    tickLocation = size.height - (((size.height) / numTicks) * Double(tick))
                    startLocation = CGPoint(x: 1.0, y: tickLocation-nudge)
                    endLocation = CGPoint(x: 10.0, y: tickLocation-nudge)
                    textLocation = CGPoint(x: endLocation.x+10, y: endLocation.y-(nudge*10))

                case .top:
                    tickLocation = (size.width / numTicks) * Double(tick)
                    startLocation = CGPoint(x: tickLocation+nudge, y: border - 1.0)
                    endLocation = CGPoint(x: tickLocation+nudge, y: border - 10.0)
                    textLocation = CGPoint(x: endLocation.x+(nudge*10), y: endLocation.y - 10)

                case .bottom:
                    tickLocation = ((size.width) / numTicks) * Double(tick)
                    startLocation = CGPoint(x: tickLocation+nudge, y: 1.0)
                    endLocation = CGPoint(x: tickLocation+nudge, y: 10.0)
                    textLocation = CGPoint(x: endLocation.x+(nudge*10), y: endLocation.y + 10)
                }
                
                // draw tick
                let mcolor: Color = .white
                //let whiteTicks: Set = [0,2,4,5,7,9,11,12] // C, D, E, F, G, A, B, C
                //if whiteTicks.contains(tick) {mcolor = .white} else {mcolor = .blue}
                context.stroke(
                    Path { path in
                        path.move(to: startLocation)
                        path.addLine(to: endLocation)
                    },
                    with: .color(mcolor),
                    lineWidth: 2
                )
                
                //Draw Note Name
                let noteNames = ["C","","D","","E","F","","G","","A","","B","C"]
                var myTick = tick - Int(centerTick)
                while myTick < 0 {myTick = myTick + 12}
                while myTick > 12 {myTick = myTick - 12}
                
                let _ = context.draw(Text(noteNames[myTick]).font(.custom("SFPro", size: 15)).foregroundStyle(.white),at: textLocation)
                //let _ = context.draw(Text("X").font(.custom("SFPro", size: 15)),at: textLocation)
                //let _ = context.draw(Text(noteNames[tick]).font(.custom("SFPro", size: 15)),at: textLocation)
            }
        }
    }
}
