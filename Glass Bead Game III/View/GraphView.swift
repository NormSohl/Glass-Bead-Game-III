//
//  GraphView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI

struct GraphView: View {
    let scale: Scale
    let diamonds:Diamonds
    let tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings

    var body: some View {

        VStack(alignment: .leading, spacing:0){// group of all graph elements
            
            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Corner(border: settings.border)
                // top tick marks
                Ticks(border: settings.border, alignment: .top, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized)
                    .frame(height: settings.border)
                // top right corner
                Corner(border: settings.border)
            }
            
            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Ticks(border: settings.border, alignment: .leading, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized)
                    .frame(width: settings.border)
                ZStack(){
                    // dissonance field, drawn first so it sits behind the grid/diamonds
                    DissonanceView(scale: scale, settings: settings, showDissonance: settings.showDissonance)
                    // graph
                    Graph(scale: scale, settings: settings)
                    // Tetrad Layers is the generalization Diamonds reduces to at Z=unison, not
                    // an independent thing to compare against it - so it takes over entirely
                    // (Diamonds doesn't draw at all) rather than the two overlapping, which
                    // showed as a smaller tetrad diamond nested inside a larger, unrelated,
                    // Z-independent 2D diamond at the same position.
                    DiamondView(diamonds: diamonds,
                                showDiamonds: settings.showDiamonds && !settings.showTetrads,
                                scale: scale,
                                showDissonanceField: settings.showDissonance)
                    TetradView(tetradLayers: tetradLayers,
                               scale: scale,
                               settings: settings,
                               showTetrads: settings.showTetrads)

                    HitTestView(scale:scale, settings: settings)
                }.border(.orange)

                // right border
                Ticks(border: settings.border, alignment: .trailing, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized)
                    .frame(width: settings.border)
            }
            
            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Corner(border: settings.border)
                // bottom tick marks
                Ticks(border: settings.border, alignment: .bottom, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized)
                    .frame(height: settings.border)
                // bottom right corner
                Corner(border: settings.border)
            }
        }
    }
}

// filler for the corners of the border of the graph
struct Corner: View {
    var border:Double
    
    var body: some View {
        
        Rectangle()
            .fill(.clear)
            .frame(width:border, height: border)
    }
}

struct Graph: View {
    var scale: Scale
    @ObservedObject var settings: AppSettings

    var body: some View {
        Canvas(){context, size in
            // With the 3rd moving tone on, filter the grid down to just the scale degrees that
            // actually pair with the current Z (Tetrads.elementsPairing) instead of showing every
            // scale degree regardless of Z - matches the diamonds themselves thinning out at
            // off-root Z layers. At Z=unison this is always the full scale unfiltered (see
            // elementsPairing's own doc comment), so the default view is untouched either way.
            let intervals: [ScaleElement]
            if settings.showTetrads && settings.filterGraphLines {
                let zValueNormalized = Tetrads.rounded(log2(settings.zFrequency / settings.rootFrequency))
                intervals = Tetrads.elementsPairing(withNormalizedValue: zValueNormalized, in: scale)
            } else {
                intervals = scale.scale
            }
            context.stroke(
                Path { path in
                    for interval in intervals {

                        // Horizontal lines
                        var yIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                            normalizedValue: interval.valueNormalized,
                            screenSize:size.width)
                        // y screen values are inverted
                        yIntervalInScreenUnits = size.width - yIntervalInScreenUnits

                        // Draw
                        path.move(to: CGPoint (x: 0, y: yIntervalInScreenUnits))
                        path.addLine(to: CGPoint(x: size.width, y: yIntervalInScreenUnits))

                        // Vertical lines
                        let xIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                            normalizedValue: interval.valueNormalized,
                            screenSize:size.height)
                        // draw
                        path.move(to: CGPoint (x:xIntervalInScreenUnits, y:0))
                        path.addLine(to: CGPoint(x:xIntervalInScreenUnits, y: size.height))
                    }
                },
                with: .color(.gray)
            )
        }
    }
}
