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
            let whiteTicks: Set = [0,2,4,5,7,9,11,12] // C, D, E, F, G, A, B, C
            var mcolor: Color = .white
            for tick in 0...12 {
                if whiteTicks.contains(tick) {mcolor = .white}
                else {mcolor = .blue}
                context.stroke(
                    Path { path in
                        switch alignment {
                        case .leading:
                            let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                            path.move(to: CGPoint (x: 1, y: tickLocation))
                            path.addLine(to: CGPoint(x: 10, y: tickLocation))
                            
                        case .trailing:
                            let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                            path.move(to: CGPoint (x: border - 10, y: tickLocation))
                            path.addLine(to: CGPoint(x: border - 1, y: tickLocation))
                            
                        case .top:
                            let tickLocation = (size.width / 12) * Double(tick)
                            path.move(to: CGPoint (x: tickLocation, y: 1))
                            path.addLine(to: CGPoint(x: tickLocation, y:10))
                            
                        case .bottom:
                            let tickLocation = ((size.width) / 12) * Double(tick)
                            path.move(to: CGPoint (x: tickLocation, y: border - 1))
                            path.addLine(to: CGPoint(x: tickLocation, y: border - 10))
                        }
                    },
                    with: .color(mcolor),
                    lineWidth: 2
                )}
        }
    }
}
