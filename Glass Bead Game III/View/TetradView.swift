//
//  TetradView.swift
//  Glass Bead Game III
//
//  Renders the depth-slider feature's tetrad layers: the (at most two) Z layers bracketing the
//  current Z slider position, cross-faded by the weight from TetradLayers.bracketingLayers.
//  Gated by the Diamonds toggle - "Diamonds" means "all diamonds, on any plane," not just a
//  flat 2D view.
//
//  Color scheme, per Norm (2026-08-28, revised after adding the third moving tone): with three
//  moving tones in play, the drone/root is dropped from the color calculation entirely -
//  movingToneUnisonCount (0/1/3, see Tetrads.swift) drives it instead of the old six-pair
//  dissonanceCount. Red when all three moving tones coincide (X=Y=Z, regardless of root), white
//  when exactly two of the three do, yellow - gradient by size - when none do. (2 is
//  structurally impossible, same as the old scheme's 4/5 gap.)
//
//  A tetrad layer at weight 1.0 (Z sitting exactly on a scale value) reduces to the same
//  geometry a flat 2D diamond would have at that position - see GBGCore's
//  TetradsTests.testTetradsReduceToDiamondsWhenZIsAtUnison for the verified math.

import SwiftUI
import GBGCore

struct TetradView: View {
    let tetradLayers: TetradLayers
    let scale: Scale
    @ObservedObject var settings: AppSettings
    let showDiamonds: Bool

    var body: some View {
        if showDiamonds {
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
                        // Norm: size should stay put during a cross-fade, only opacity fades
                        // (see the fill/stroke calls below), so a fading-in tetrad reads as
                        // "becoming visible" rather than "growing."
                        var tetradSize = (size.width / 35) * tetrad.sizeNormalized * 0.85
                        if tetradSize < 4 { tetradSize = 4 }
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
                    // The center point (X = Y = root) always reads red, regardless of where Z
                    // currently sits - same fixed reference convention ZSliderView's own root
                    // marker already uses (always red there too, not tied to the current touch).
                    // Norm: without this, the one fixed landmark on the graph disappears the
                    // moment Z leaves unison, losing the visual "where's home" anchor - sized
                    // normally like any other diamond at the current Z layer, only the color is
                    // pinned.
                    let color: Color = (tetrad.xElement.value == 1.0 && tetrad.yElement.value == 1.0)
                        ? TetradView.unisonColor
                        : TetradView.color(
                            forMovingToneUnisonCount: tetrad.movingToneUnisonCount,
                            sizeNormalized: tetrad.sizeNormalized)

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

    // Shared with ZSliderView's own diamond-list coloring (its central/unison diamond, and its
    // dissonance==3.0 case, both use this same red - see that file's own comment).
    static let unisonColor = Color(red: 0.8, green: 0.3, blue: 0.3)

    // Same toning as unisonColor above - a dominant channel under 1.0 with the other two raised
    // (not 0), rather than a pure saturated primary - applied to blue instead of red. Used by
    // ContentView's toolbar active-state color, which used to clash with the yellow diamonds (a
    // pure .accentColor, which follows the user's own System Settings accent choice - orange on
    // Norm's Mac). GraphView's own border was briefly this same blue too, then white instead -
    // Norm: the blue read as too cold there specifically, plain blue was fine for the toolbar.
    static let uiAccentColor = Color(red: 0.3, green: 0.3, blue: 0.8)

    private static func color(forMovingToneUnisonCount movingToneUnisonCount: Int, sizeNormalized: Double) -> Color {
        switch movingToneUnisonCount {
        case 3: return unisonColor // X = Y = Z, drone excluded
        // Black, not white - Norm: white read as too loud for a tier that isn't the map's most
        // important point (that's red, above). Black risks blending into the Dissonance Field's
        // own zero-roughness black when that's on too, but the stroke below stays gray
        // regardless of fill, so the diamond's outline still reads even against a black field.
        case 1: return Color(red: 0.0, green: 0.0, blue: 0.0) // exactly two of the three coincide
        default: // 0: none of the three coincide - yellow, gradient by size
            var shade = sizeNormalized
            if shade > 0.6 { shade = 1.0 }
            if shade <= 0.6 { shade = shade * 1.5 }
            return Color(red: shade, green: shade, blue: 0.0)
        }
    }
}
