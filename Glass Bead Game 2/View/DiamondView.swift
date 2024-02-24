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
                for element in diamonds.DiamondList {
                    
                    // scale and invert y
                    let y = size.height - ((size.height * element.yElement.valueNormalized))
                    
                    // scale x
                    let x = (size.width * element.xElement.valueNormalized)
                    
                    // diamond size
                    var diamondSize = (size.width / 35) * element.sizeNormalized
                    if diamondSize < 4 {diamondSize =  4}
                    context.fill(
                        Path { path in
                            path.move(to: CGPoint (x:x-diamondSize, y:y))
                            // upper left line
                            path.addLine(to: CGPoint(x:x, y:y+diamondSize))
                            // upper right line
                            path.addLine(to: CGPoint(x:x+diamondSize, y:y))
                            // lower right line
                            path.addLine(to: CGPoint(x:x, y:y-diamondSize))
                            // lower left line
                            path.closeSubpath()
                        },
                        with: .color(.gray)
                    )
                }
            }
            
        }
    }
}
