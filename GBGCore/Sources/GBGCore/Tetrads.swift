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

public struct TetradElement {
    public let xElement: ScaleElement
    public let yElement: ScaleElement
    public let zElement: ScaleElement
    public let locationNormalized: CGPoint
    public let sizeNormalized: Double
    public let dissonanceCount: Int // 0...6: how many of the six pairs among {root,X,Y,Z} coincide
    // 0, 1, or 3: how many of the three pairs among just {X:Y, X:Z, Y:Z} coincide - excludes
    // every root-involving pair (root:X, root:Y, root:Z). Norm's coloring rule for the 3-tone
    // view deliberately drops the drone from consideration: 2 is not achievable (equality among
    // three elements is transitive - X=Y and X=Z forces Y=Z, so it's always 0, 1, or 3, same
    // structural reasoning as dissonanceCount's own 4/5 gap).
    public let movingToneUnisonCount: Int

    public init(x: ScaleElement, y: ScaleElement, z: ScaleElement, sizeNormalized: Double, dissonanceCount: Int, movingToneUnisonCount: Int, highestRatioNormalized: Double) {
        self.xElement = x
        self.yElement = y
        self.zElement = z
        self.sizeNormalized = sizeNormalized
        self.dissonanceCount = dissonanceCount
        self.movingToneUnisonCount = movingToneUnisonCount
        // same X/Y screen mapping Diamonds uses - Z is the depth axis, not part of on-screen location
        self.locationNormalized = CGPoint(x: x.valueNormalized / highestRatioNormalized, y: y.valueNormalized)
    }
}

public struct Tetrads {
    var tetradList: [TetradElement] = []
    var scale: Scale

    public init(scale: Scale) {
        self.scale = scale

        // Precomputed once by Scale itself (see its own scaleElementByRoundedValue comment) -
        // this used to rebuild the identical dictionary here too, redundant with Scale's own
        // copy even though this particular call site is only a one-time per-scale cost, not a
        // per-frame one; reusing it removes the duplicate logic for free while we're here.
        let scaleElementByRoundedValue = scale.scaleElementByRoundedValue

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

                    // Same three checks, but counted separately from the root-involving three -
                    // Norm's coloring rule for the 3-tone view: red when all three moving tones
                    // coincide, white when exactly two of the three do, yellow when none do,
                    // regardless of where the drone sits.
                    var movingToneUnisonCount = 0
                    if xy.dissonance == 1.0 { movingToneUnisonCount += 1 }
                    if xz.dissonance == 1.0 { movingToneUnisonCount += 1 }
                    if yz.dissonance == 1.0 { movingToneUnisonCount += 1 }

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
                        movingToneUnisonCount: movingToneUnisonCount,
                        highestRatioNormalized: scale.highestRatioNormalized
                    ))
                }
            }
        }
    }

    public static func rounded(_ value: Double) -> Double {
        round(value * 100000) / 100000
    }

    /// The subset of `scale` whose interval with `zValueNormalized` is itself a scale member -
    /// exactly the xz/yz membership test every TetradElement is already built from above, exposed
    /// standalone so the graph's background grid can be filtered down to just the degrees that
    /// could actually participate in a tetrad at this Z, instead of showing every scale degree
    /// regardless of Z. At zValueNormalized == 0 (root/unison) this always returns the full
    /// scale unfiltered - every element's interval with root is itself, trivially a scale member -
    /// matching the "identical to the unfiltered default at Z=unison" invariant TetradsTests
    /// already verifies for the tetrads themselves.
    public static func elementsPairing(withNormalizedValue zValueNormalized: Double, in scale: Scale) -> [ScaleElement] {
        // Used to rebuild this exact lookup from scratch on every single call - GraphView calls
        // this (both directly, and via visibleScaleElements) on every touch-move frame during a
        // Z-slider drag, so that rebuild was happening dozens of times a second for no reason:
        // the dictionary depends only on `scale`, which Scale itself now precomputes once (see
        // its own scaleElementByRoundedValue comment) and never changes except on an actual
        // limit/range rebuild. Confirmed live 2026-09-09 as the likely cause of hangs building
        // up over sustained rapid Z dragging.
        return scale.scale.filter { element in
            let diff = abs(element.valueNormalized - zValueNormalized)
            return scale.scaleElementByRoundedValue[rounded(diff)] != nil
        }
    }
}
