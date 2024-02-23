//
//  DiamondView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/12/22.
//

import SwiftUI


struct DiamondView: View {
    //@ObservedObject var settings: AppSettings
    var showDiamonds: Bool
    var diamonds: Diamonds
    var geo: GeometryProxy
    var border: Double

    var body: some View {
        if showDiamonds {
            
            // graph is the size of the view less the left and right border
            let graphWidth = geo.size.width - border - border
            let graphHeight = geo.size.height - border - border
            
            // draw diamonds
            Path { path in
                for element in diamonds.DiamondList {
                    
                    // scale and invert y
                    let y = geo.size.height - ((graphHeight * element.yElement.valueNormalized) + border)
                    
                    // scale x
                    let x = (graphWidth * element.xElement.valueNormalized) + border
                    
                    // diamond size
                    var size = (geo.size.width / 35) * element.sizeNormalized
                    if size < 4 {size =  4}
                    
                    path.move(to: CGPoint (x:x-size, y:y))
                    // upper left line
                    path.addLine(to: CGPoint(x:x, y:y+size))
                    // upper right line
                    path.addLine(to: CGPoint(x:x+size, y:y))
                    // lower right line
                    path.addLine(to: CGPoint(x:x, y:y-size))
                    // lower left line
                    path.closeSubpath()
                }
            }
            .fill(.white)
        }
    }
}
