//
//  DiamondView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/12/22.
//

import SwiftUI


struct DiamondView: View {
    var diamonds: Diamonds
    let settings: AppSettings

    var body: some View {
        if settings.showDiamonds {
            Canvas(){context, size in
                for element in diamonds.DiamondList {
                    print("showDiamond: element = \(element)")
                    
                    // scale and invert y
                    let y = size.height - (size.height * (element.yElement.valueNormalized)/diamonds.numberOfOctaves)
                    
                    // scale x
                    let x = (size.width * (element.xElement.valueNormalized / diamonds.numberOfOctaves))
                    
                    // diamond size
                    var diamondSize = (size.width / 35) * element.sizeNormalized
                    if diamondSize < 4 {diamondSize =  4}
                    
                    // diamond color
                    var diamondShade = element.sizeNormalized
                    if diamondShade > 0.6 {diamondShade = 1.0}
                    if diamondShade <= 0.6 {diamondShade = diamondShade * 1.5} // brighten the fifth
                    var color = Color(red: diamondShade, green: diamondShade, blue: 0.0)
                    if element.mydissonance == 1.0 {
                        color = Color(red: 0, green: 0, blue: 0)
                    }
                    
                    print("ShowDiamonds: element.dissonance \(element.mydissonance)")
                    
                    // draw fill
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
                        with: .color(color)
                    )
                    // draw border
                    context.stroke(
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
