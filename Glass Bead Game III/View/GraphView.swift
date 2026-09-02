//
//  GraphView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI
import GBGCore

struct GraphView: View {
    let scale: Scale
    let diamonds:Diamonds
    let tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings
    @ObservedObject var recordingState: RecordingState

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
                    Graph(scale: scale, tetradLayers: tetradLayers, settings: settings)
                    // Tetrad Layers is the generalization Diamonds reduces to at Z=unison, not
                    // an independent thing to compare against it - so it takes over entirely
                    // (DiamondView doesn't draw at all) rather than the two overlapping, which
                    // showed as a smaller tetrad diamond nested inside a larger, unrelated,
                    // Z-independent 2D diamond at the same position. Diamonds itself (Norm)
                    // means "all diamonds, on any plane" though, so it's ANDed into TetradView's
                    // gate too rather than only ever disabling DiamondView.
                    DiamondView(diamonds: diamonds,
                                showDiamonds: settings.showDiamonds && !settings.showTetrads,
                                scale: scale,
                                showDissonanceField: settings.showDissonance)
                    TetradView(tetradLayers: tetradLayers,
                               scale: scale,
                               settings: settings,
                               showTetrads: settings.showTetrads && settings.showDiamonds)

                    HitTestView(scale:scale, settings: settings, recordingState: recordingState)
                }.border(.white)

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
    var tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings

    var body: some View {
        Canvas(){context, size in
            func drawLine(for interval: ScaleElement, weight: Double) {
                // Horizontal line
                var yIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                    normalizedValue: interval.valueNormalized,
                    screenSize: size.width)
                // y screen values are inverted
                yIntervalInScreenUnits = size.width - yIntervalInScreenUnits

                var path = Path()
                path.move(to: CGPoint(x: 0, y: yIntervalInScreenUnits))
                path.addLine(to: CGPoint(x: size.width, y: yIntervalInScreenUnits))

                // Vertical line
                let xIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                    normalizedValue: interval.valueNormalized,
                    screenSize: size.height)
                path.move(to: CGPoint(x: xIntervalInScreenUnits, y: 0))
                path.addLine(to: CGPoint(x: xIntervalInScreenUnits, y: size.height))

                context.stroke(path, with: .color(.gray.opacity(weight)))
            }

            // With the 3rd moving tone on, filter the grid down to just the scale degrees that
            // actually pair with the current Z (Tetrads.elementsPairing) instead of showing every
            // scale degree regardless of Z - matches the diamonds themselves thinning out at
            // off-root Z layers. At Z=unison this is always the full scale unfiltered (see
            // elementsPairing's own doc comment), so the default view is untouched either way.
            //
            // Weighted by the same bracketing-Z-keys TetradView's diamonds cross-fade between
            // (or the single nearest key when snapped), not just one hard-cutoff Z value - a
            // line valid at one bracketing key but not the other is drawn at that key's own
            // weight, so it fades in/out through a slide exactly like the diamonds do, rather
            // than snapping on/off abruptly. A line valid at both keys is drawn twice, once per
            // key's weight - alpha stacks, same as two overlapping diamonds would.
            if settings.showTetrads && settings.filterGraphLines {
                let zValueNormalized = Tetrads.rounded(log2(settings.zFrequency / settings.rootFrequency))
                let zKeys: [(key: Double, weight: Double)] = settings.snap
                    ? tetradLayers.nearestZKey(to: zValueNormalized).map { [(key: $0, weight: 1.0)] } ?? []
                    : tetradLayers.bracketingZKeys(around: zValueNormalized)

                for (key, weight) in zKeys {
                    for interval in Tetrads.elementsPairing(withNormalizedValue: key, in: scale) {
                        drawLine(for: interval, weight: weight)
                    }
                }
            } else {
                for interval in scale.scale {
                    drawLine(for: interval, weight: 1.0)
                }
            }
        }
    }
}
