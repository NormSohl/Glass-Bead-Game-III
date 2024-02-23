//
//  TickView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 4/19/23.
//

import SwiftUI

struct TickView: View {
    var geo:GeometryProxy
    var border:Double

    var body: some View {
        
        // graph is the size of the view less the left and right border
        let _ = print("TickView: geo \(geo.size)")
        let graphWidth = geo.size.width - border - border
        
        // draw white ticks
        let whiteTicks: Set = [0,2,4,5,7,9,11,12] // C, D, E, F, G, A, B, C
        Path { path in
            let size = (graphWidth) / 12
            for tick in 0...12 {
                if whiteTicks.contains(tick)
                {
                    // horizontal tick marks left
                    let tempHeight = graphWidth - (size * Double(tick))
                    path.move(to: CGPoint (x: 1, y: tempHeight + border))
                    path.addLine(to: CGPoint(x: 10, y: tempHeight + border))
                    
                    // horizontal tick marks right
                    path.move(to: CGPoint (x: geo.size.width - 10, y: tempHeight + border))
                    path.addLine(to: CGPoint(x:geo.size.width, y: tempHeight + border))
                    
                    //vertical tick marks top
                    let tempWidth = size * Double(tick)
                    path.move(to: CGPoint (x:tempWidth + border, y: 1))
                    path.addLine(to: CGPoint(x:tempWidth + border, y: 10))
                    
                    //vertical tick marks bottom
                    path.move(to: CGPoint (x:tempWidth + border, y: geo.size.height - 10))
                    path.addLine(to: CGPoint(x:tempWidth + border, y: geo.size.height))
                }
            }
        }
        .stroke(.white, lineWidth: 2)
        
        // draw black ticks
        Path { path in
            let size = (graphWidth) / 12
            for tick in 0...12 {
                if !whiteTicks.contains(tick)
                {
                    // horizontal tick marks left
                    let tempHeight = graphWidth - (size * Double(tick))
                    path.move(to: CGPoint (x: 1, y: tempHeight + border))
                    path.addLine(to: CGPoint(x: border-30, y: tempHeight + border))
                    
                    // horizontal tick marks right
                    path.move(to: CGPoint (x: geo.size.width - 10, y: tempHeight + border))
                    path.addLine(to: CGPoint(x: geo.size.width, y: tempHeight + border))
                    
                    //vertical tick marks bottom
                    let tempWidth = size * Double(tick)
                    path.move(to: CGPoint (x:tempWidth + border, y: 1))
                    path.addLine(to: CGPoint(x:tempWidth + border, y: border - 30))
                    
                    // vertical tick marks bottom
                    path.move(to: CGPoint (x:tempWidth + border, y: geo.size.height - 10))
                    path.addLine(to: CGPoint(x:tempWidth + border, y: geo.size.height))
                }
            }
        }
        .stroke(.black, lineWidth: 2)
    }
}
