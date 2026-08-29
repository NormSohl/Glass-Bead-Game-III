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
    // Only the Dissonance Field has anything worth seeing through a diamond - otherwise a
    // fully opaque fill reads better, so the transparency below only applies while it's on.
    let showDissonanceField: Bool

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

                    // diamond size - two successive 15% reductions from the original sizing,
                    // per Norm (the second one requested 2026-08-28, after the graph started
                    // rendering much larger following that session's window-sizing fix)
                    var diamondSize = (size.width / 35) * diamond.sizeNormalized * 0.85 * 0.85
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
                    // draw fill - semi-transparent (0.7) only while the Dissonance Field is on,
                    // so its own detail still shows through, especially the dense/interesting
                    // structure right around unison where diamonds cluster largest and most
                    // densely; fully opaque otherwise. Stroke always stays fully opaque so each
                    // diamond's outline still reads clearly either way.
                    context.fill(diamondPath, with: .color(color.opacity(showDissonanceField ? 0.7 : 1.0)))
                    // draw border
                    context.stroke(diamondPath, with: .color(.gray))
                }
            }
        }
    }
}
