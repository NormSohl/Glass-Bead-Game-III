//
//  TickView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/24/24.
//

import SwiftUI

// Named distinctly from SwiftUI's own Alignment type, which this file also uses
// implicitly via HStack/VStack elsewhere in the app - same name, different type,
// would otherwise be a trap for whichever Alignment is actually in scope.
enum TickAlignment {
    case top
    case bottom
    case leading
    case trailing
}

// tick marks
struct Ticks: View {
    let border:Double
    let alignment: TickAlignment
    let rangeBelow: Double
    let rangeAbove: Double

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

            // Label size tracks the actual space between ticks (the graph's rendered size
            // divided across the same numTicks used for layout above), not a fixed point size -
            // otherwise labels stay tiny on a large window and would overlap on a small one.
            // Capped so it doesn't balloon at extreme zoom; floored so it never disappears.
            let referenceSize = (alignment == .top || alignment == .bottom) ? size.width : size.height
            let tickSpacing = numTicks > 0 ? referenceSize / numTicks : 15
            let fontSize = min(18, max(8, tickSpacing * 0.55))

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
                
                let _ = context.draw(Text(noteNames[myTick]).font(.custom("SFPro", size: fontSize)).foregroundStyle(.white),at: textLocation)
            }
        }
    }
}
