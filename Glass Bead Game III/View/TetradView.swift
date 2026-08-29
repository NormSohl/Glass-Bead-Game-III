//
//  TetradView.swift
//  Glass Bead Game III
//
//  Renders the depth-slider feature's tetrad layers: the (at most two) Z layers bracketing the
//  current Z slider position, cross-faded by the weight from TetradLayers.bracketingLayers.
//  Opt-in via its own toggle, independent of the existing 2D Diamonds view, so the two can be
//  compared directly while this is still new/untested on device.
//
//  Color scheme settled in the depth-slider design notes: dissonanceCount 0 (all four pitches
//  distinct) is gray, 1/2/3 (some but not all coincide) is white, 6 (root=X=Y=Z) is red -
//  reusing DiamondView's existing gray/red RGB values for visual continuity with the 2D view.
//
//  Size/color/geometry otherwise mirror DiamondView exactly, so a tetrad layer at weight 1.0
//  (Z sitting exactly on a scale value) looks identical to the equivalent 2D diamond - matching
//  the verified reduction-to-2D behavior in TetradsTests.

import SwiftUI

struct TetradView: View {
    let tetradLayers: TetradLayers
    let scale: Scale
    @ObservedObject var settings: AppSettings
    let showTetrads: Bool

    var body: some View {
        if showTetrads {
            Canvas { context, size in
                let zRatio = settings.zFrequency / settings.rootFrequency
                // Rounded to the same precision TetradLayers groups its Z keys at
                // (Tetrads.rounded, 5 decimal places) - without this, an exactly-snapped Z
                // still lands a hair off from its true bracketing key after the
                // multiply/divide/log2 round-trip through settings.zFrequency, so
                // bracketingLayers would return two layers with weights like
                // 0.999999999999/0.000000000001 instead of a true 1.0/0.0 - technically
                // already invisible at that magnitude, but rounding first makes "snapped ->
                // exactly one layer" and "fade reaches exactly zero at the boundary" both
                // literally true instead of "true up to float noise."
                let zValueNormalized = Tetrads.rounded(log2(zRatio))

                // Snapped: exactly one layer, no blend - the Z-slider snaps to the full scale
                // (same grid X/Y use), but a tetrad only exists at the sparser subset of that
                // grid where all three cross-ratios also happen to be scale members, so a
                // snapped position is almost never itself a real Z layer. bracketingLayers'
                // continuous blend would then show two layers *permanently*, not just during a
                // transition - nearestLayer picks whichever real layer the snap is closest to
                // instead, matching "a snapped position shows exactly one layer." Unsnapped
                // (live, continuous motion) keeps the real two-layer crossfade - Norm: two
                // layers should only ever be visible *during* a fade, never at rest.
                let activeLayers: [(tetrads: [TetradElement], weight: Double)] = settings.snap
                    ? [tetradLayers.nearestLayer(atZNormalized: zValueNormalized)]
                    : tetradLayers.bracketingLayers(atZNormalized: zValueNormalized)

                // Collected across both bracketing layers and drawn smallest-last (on top),
                // not layer-order - Norm: "the smaller overprints the larger." Layer order
                // alone (below-Z first, above-Z second) doesn't guarantee that; size does.
                var toDraw: [(tetrad: TetradElement, weight: Double, size: Double)] = []
                for layer in activeLayers {
                    for tetrad in layer.tetrads {
                        // same base sizing as DiamondView, then faded by this layer's
                        // crossfade weight - applied after the floor so a fading-out layer
                        // still shrinks all the way to nothing rather than getting stuck at
                        // the floor size
                        var tetradSize = (size.width / 35) * tetrad.sizeNormalized * 0.85
                        if tetradSize < 4 { tetradSize = 4 }
                        tetradSize *= layer.weight
                        toDraw.append((tetrad, layer.weight, tetradSize))
                    }
                }
                toDraw.sort { $0.size > $1.size }

                for entry in toDraw {
                    let tetrad = entry.tetrad
                    // get screen location for Y
                    var yLocationInScreenUnits = scale.convertScaleValueToScreenUnits(
                        normalizedValue: tetrad.yElement.valueNormalized,
                        screenSize: size.height)
                    // invert because y screen values are upside down
                    yLocationInScreenUnits = size.height - yLocationInScreenUnits

                    // get screen location for X
                    let xLocationInScreenUnits = scale.convertScaleValueToScreenUnits(
                        normalizedValue: tetrad.xElement.valueNormalized,
                        screenSize: size.width)

                    let tetradSize = entry.size
                    let color = TetradView.color(forDissonanceCount: tetrad.dissonanceCount)

                    let tetradPath = Path { path in
                        path.move(to: CGPoint(x: xLocationInScreenUnits - tetradSize, y: yLocationInScreenUnits))
                        path.addLine(to: CGPoint(x: xLocationInScreenUnits, y: yLocationInScreenUnits + tetradSize))
                        path.addLine(to: CGPoint(x: xLocationInScreenUnits + tetradSize, y: yLocationInScreenUnits))
                        path.addLine(to: CGPoint(x: xLocationInScreenUnits, y: yLocationInScreenUnits - tetradSize))
                        path.closeSubpath()
                    }
                    context.fill(tetradPath, with: .color(color.opacity(entry.weight)))
                    context.stroke(tetradPath, with: .color(.gray.opacity(entry.weight)))
                }
            }
        }
    }

    private static func color(forDissonanceCount dissonanceCount: Int) -> Color {
        switch dissonanceCount {
        case 6: return Color(red: 0.8, green: 0.3, blue: 0.3) // root = X = Y = Z, the absolute center
        case 0: return Color(red: 0.75, green: 0.75, blue: 0.78) // all four pitches distinct
        default: return Color(red: 1.0, green: 1.0, blue: 1.0) // 1, 2, or 3: some but not all coincide
        }
    }
}
