//
//  DiamondView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/12/22.
//

import SwiftUI


struct DiamondView: View {
    var diamonds: Diamonds
    let showDiamonds: Bool
    let scale: Scale

    var body: some View {
        if showDiamonds {
            Canvas(){context, size in
                for diamond in diamonds.diamondList {
                    
                    // get screen location for Y
                    var yLocationInScreenUnits = scale.convertScaleValueToScreenUnits(
                        normalizedValue: diamond.yElement.valueNormalized,
                        screenSize:size.height)
                    // invert because y screen values are upside down
                    yLocationInScreenUnits = size.height - yLocationInScreenUnits
                    
                    // get screen location for X
                    let xLocationInScreenUnits = scale.convertScaleValueToScreenUnits(
                        normalizedValue: diamond.xElement.valueNormalized,
                        screenSize:size.width)

                    // diamond size (15% smaller than the original sizing, per Norm)
                    var diamondSize = (size.width / 35) * diamond.sizeNormalized * 0.85
                    if diamondSize < 4 {diamondSize =  4}

                    // diamond color
                    var diamondShade = diamond.sizeNormalized
                    if diamondShade > 0.6 {diamondShade = 1.0}
                    if diamondShade <= 0.6 {diamondShade = diamondShade * 1.5} // brighten the fifth
                    var color = Color(red: diamondShade, green: diamondShade, blue: 0.0)
                    // was pure black - now that black is meaningful elsewhere (the dissonance
                    // field's zero-roughness color), a black diamond blended into the background
                    // instead of reading as a marker. Light gray stays visually distinct from
                    // both the yellow consonance scale and the red triple-dissonance diamond.
                    if diamond.mydissonance == 1.0 {color = Color(red: 0.75, green: 0.75, blue: 0.78)}
                    if diamond.mydissonance == 3.0 {color = Color(red: 0.8, green: 0.3, blue: 0.3)}
                    //if element.mydissonance == 2.0 {color = Color(red: 0.9, green: 0.3, blue: 0.3)}  // 2 never appears
                    //print("DiamondView: element.dissonance = \(element.mydissonance)")
                    
                    let diamondPath = Path { path in
                        path.move(to: CGPoint (x:xLocationInScreenUnits-diamondSize, y:yLocationInScreenUnits))
                        // upper left line
                        path.addLine(to: CGPoint(x:xLocationInScreenUnits, y:yLocationInScreenUnits+diamondSize))
                        // upper right line
                        path.addLine(to: CGPoint(x:xLocationInScreenUnits+diamondSize, y:yLocationInScreenUnits))
                        // lower right line
                        path.addLine(to: CGPoint(x:xLocationInScreenUnits, y:yLocationInScreenUnits-diamondSize))
                        // lower left line
                        path.closeSubpath()
                    }
                    // draw fill
                    context.fill(diamondPath, with: .color(color))
                    // draw border
                    context.stroke(diamondPath, with: .color(.gray))
                }
            }
        }
    }
}
