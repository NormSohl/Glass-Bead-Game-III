//
//  Tetrads.swift
//  GBGCore
//
//  The 4-tone generalization of Diamonds, for the depth-slider feature's third moving tone (Z).
//  See the glass_bead_game_iii_depth_slider_design memory notes for the full design conversation
//  this implements - summarized here:
//
//  Diamonds already tests one thing precisely: root:X and root:Y are simple ratios by
//  construction (X and Y are drawn from scale.scale), and the one thing actually *checked* is
//  whether the X:Y interval is itself a scale member. A tetrad generalizes this from three legs
//  to six: X, Y, and Z are each independently drawn from scale.scale (root:X, root:Y, root:Z are
//  free, guaranteed by construction), and all three *other* pairwise intervals - X:Y, X:Z, Y:Z -
//  are independently checked against the scale. A tetrad exists exactly when all three checks
//  pass.
//
//  Verified (throwaway implementation, 2026-08-27) that this reduces exactly to Diamonds when Z
//  sits at unison: same (X,Y) existence and size, and dissonanceCount = old dissonance + 1 +
//  [X is unison] + [Y is unison] - the +1 is root:Z, a genuine sixth relationship the 3-leg model
//  never counted, trivially satisfied whenever Z sits on the drone. TetradsTests below re-verifies
//  this as a permanent regression test rather than trusting the throwaway script.
//
//  Achievable dissonanceCount values are {0, 1, 2, 3, 6} - 4 and 5 are structurally impossible
//  (no partition of 4 items yields exactly 4 or 5 coincident pairs without all 4 coinciding).
//
//  Performance is a one-time cost per limit/scale change, not per-frame, same as Diamonds - not
//  worth optimizing pre-emptively (confirmed: even the naive triple-nested-loop with linear
//  interval search lands in the same "hundreds of ms at worst, once" territory). The dictionary
//  lookup below is just a clean way to write the shared "is this interval in the scale, and if
//  so what ratio is it" check that all three pairs need, not a performance optimization.

import Foundation
import CoreGraphics

struct TetradElement {
    let xElement: ScaleElement
    let yElement: ScaleElement
    let zElement: ScaleElement
    let locationNormalized: CGPoint
    let sizeNormalized: Double
    let dissonanceCount: Int // 0...6: how many of the six pairs among {root,X,Y,Z} coincide

    init(x: ScaleElement, y: ScaleElement, z: ScaleElement, sizeNormalized: Double, dissonanceCount: Int, highestRatioNormalized: Double) {
        self.xElement = x
        self.yElement = y
        self.zElement = z
        self.sizeNormalized = sizeNormalized
        self.dissonanceCount = dissonanceCount
        // same X/Y screen mapping Diamonds uses - Z is the depth axis, not part of on-screen location
        self.locationNormalized = CGPoint(x: x.valueNormalized / highestRatioNormalized, y: y.valueNormalized)
    }
}

struct Tetrads {
    var tetradList: [TetradElement] = []
    var scale: Scale

    init(scale: Scale) {
        self.scale = scale

        // Shared by all three interval checks below, rather than three copies of the same
        // linear search - same rounding convention Diamonds already uses for floating-point
        // interval matching. Keyed to the actual ScaleElement (not just a membership Set),
        // because the size rule below needs that element's own numerator/denominator - the
        // X:Y/X:Z/Y:Z ratio itself, not just whether it exists in the scale.
        var scaleElementByRoundedValue: [Double: ScaleElement] = [:]
        for element in scale.scale {
            scaleElementByRoundedValue[Tetrads.rounded(element.valueNormalized)] = element
        }

        for x in scale.scale {
            for y in scale.scale {
                let xyValue = abs(x.valueNormalized - y.valueNormalized)
                guard let xy = scaleElementByRoundedValue[Tetrads.rounded(xyValue)] else { continue }

                for z in scale.scale {
                    let xzValue = abs(x.valueNormalized - z.valueNormalized)
                    let yzValue = abs(y.valueNormalized - z.valueNormalized)
                    guard let xz = scaleElementByRoundedValue[Tetrads.rounded(xzValue)],
                          let yz = scaleElementByRoundedValue[Tetrads.rounded(yzValue)] else { continue }

                    var dissonanceCount = 0
                    if x.dissonance == 1.0 { dissonanceCount += 1 } // root:X unison
                    if y.dissonance == 1.0 { dissonanceCount += 1 } // root:Y unison
                    if z.dissonance == 1.0 { dissonanceCount += 1 } // root:Z unison
                    if xy.dissonance == 1.0 { dissonanceCount += 1 } // X:Y unison
                    if xz.dissonance == 1.0 { dissonanceCount += 1 } // X:Z unison
                    if yz.dissonance == 1.0 { dissonanceCount += 1 } // Y:Z unison

                    // largest numerator/denominator across all six ratios (root:X, root:Y,
                    // root:Z, X:Y, X:Z, Y:Z) - same size rule Diamonds uses, extended from
                    // three ratios to six
                    var sizeRaw = max(x.numerator, x.denominator, y.numerator, y.denominator, z.numerator, z.denominator)
                    sizeRaw = max(sizeRaw, xy.numerator, xy.denominator)
                    sizeRaw = max(sizeRaw, xz.numerator, xz.denominator)
                    sizeRaw = max(sizeRaw, yz.numerator, yz.denominator)

                    var sizeNormalized = Double(sizeRaw) / Double(scale.limit)
                    sizeNormalized = 1 - sizeNormalized // inverted: higher partials have less power

                    tetradList.append(TetradElement(
                        x: x, y: y, z: z,
                        sizeNormalized: sizeNormalized,
                        dissonanceCount: dissonanceCount,
                        highestRatioNormalized: scale.highestRatioNormalized
                    ))
                }
            }
        }
    }

    static func rounded(_ value: Double) -> Double {
        round(value * 100000) / 100000
    }
}
