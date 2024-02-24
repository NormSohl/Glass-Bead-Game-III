//
//  DiamondView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/12/22.
//

import SwiftUI


struct DiamondView: View {
    var showDiamonds: Bool
    var diamonds: Diamonds
    var border: Double

    var body: some View {
        if showDiamonds {
            Canvas(){context, size in
                context.fill(
                // draw diamonds
                Path { path in
                    for element in diamonds.DiamondList {
                        
                        // scale and invert y
                        let y = size.height - ((size.height * element.yElement.valueNormalized))
                        
                        // scale x
                        let x = (size.width * element.xElement.valueNormalized)
                        
                        // diamond size
                        var size = (size.width / 35) * element.sizeNormalized
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
                },
                with: .color(.white)
                )}
        }
    }
}
