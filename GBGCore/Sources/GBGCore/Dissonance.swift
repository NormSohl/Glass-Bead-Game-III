//
//  Dissonance.swift
//  GBGCore
//
//  Pure math for the roughness/dissonance field that will drive DissonanceView.
//  Not wired into any UI yet - this is the model, tested on its own before any
//  Canvas rendering touches it.
//
//  Design, as worked out with Norm:
//  - Harmonic count per tone is tied to the same `limit` used for scale/diamond
//    generation, so the roughness field scales with the same complexity knob as
//    everything else (Scale, Diamonds).
//  - Each tone is treated as an idealized harmonic series with a linear amplitude
//    falloff (1.0 at the fundamental down to 1/limit at the highest included
//    harmonic) - the default weighting as of this pass, chosen over the more
//    standard 1/n falloff because it visibly reveals more structure in the field
//    between the octaves (middle harmonics stay comparatively louder, so more
//    harmonic-pair combinations contribute). 1/n (harmonicWeight) is still
//    available and tested as an alternative.
//  - Roughness between two partials is a function of their beat rate (the
//    absolute difference between their frequencies): a Gaussian bell peaking at
//    33 Hz - Helmholtz's estimate (via Ellis's appendix to his translation of
//    Helmholtz's "On the Sensations of Tone") of the beat rate at which two
//    partials sound maximally rough, as a fixed rate rather than one scaled to
//    the critical bandwidth at a given register the way later models (Plomp-
//    Levelt, Sethares) do. Tapers to ~0 at unison and ~0 by roughly twice the
//    peak. Symmetric for now - real roughness curves are probably asymmetric
//    (e.g. easing differently once the beat rate itself lands on a harmonic
//    relationship), but that's a possible future refinement, not built here.
//  - Total roughness for a candidate (root, X, Y) triad sums pairwise roughness
//    across every harmonic-of-A x harmonic-of-B combination, for all three tone
//    pairs (root x X, root x Y, X x Y) - not just matching harmonic numbers.

import Foundation

enum Dissonance {
    /// A harmonic weighting scheme: given a 1-indexed harmonic number, returns its amplitude weight.
    typealias HarmonicWeighting = (Int) -> Double

    /// Amplitude weight of the nth harmonic (1-indexed) of an idealized tone: the standard
    /// 1/n falloff from this literature. Available as an alternative to the default below.
    static func harmonicWeight(_ harmonicNumber: Int) -> Double {
        1.0 / Double(harmonicNumber)
    }

    /// Default weighting: falls off in a straight line from 1.0 at the fundamental to
    /// 1/limit at the highest included harmonic, rather than 1/n's curved falloff. Chosen
    /// over 1/n because middle harmonics stay comparatively louder here, so more
    /// harmonic-pair combinations contribute meaningfully to the field - visibly reveals
    /// more structure between the octaves.
    static func linearHarmonicWeight(_ harmonicNumber: Int, limit: Int) -> Double {
        Double(limit - harmonicNumber + 1) / Double(limit)
    }

    /// Frequency of the nth harmonic (1-indexed) of a tone at `fundamental`.
    static func harmonicFrequency(fundamental: Double, harmonicNumber: Int) -> Double {
        fundamental * Double(harmonicNumber)
    }

    /// Helmholtz's estimate (via Ellis) of the beat rate, in Hz, at which two partials sound
    /// maximally rough. A fixed rate, not scaled to register/critical bandwidth.
    static let peakRoughnessBeatRate: Double = 33.0

    /// Width of the roughness curve's falloff on either side of the peak. Not from Helmholtz/Ellis -
    /// chosen so the curve is practically zero at unison and by roughly double the peak beat rate.
    static let roughnessCurveSigma: Double = 10.0

    /// Roughness contributed by two partials beating `beatRate` Hz apart, before amplitude weighting.
    /// A Gaussian bell peaking at `peakBeatRate`, so it's ~0 at 0 Hz and ~0 by roughly `2 * peakBeatRate`.
    static func roughness(beatRate: Double, peakBeatRate: Double = peakRoughnessBeatRate, sigma: Double = roughnessCurveSigma) -> Double {
        let distanceFromPeak = beatRate - peakBeatRate
        return exp(-(distanceFromPeak * distanceFromPeak) / (2 * sigma * sigma))
    }

    /// Roughness contributed by one pair of partials, weighted by both partials' harmonic amplitude.
    static func pairwiseRoughness(freqA: Double, weightA: Double, freqB: Double, weightB: Double) -> Double {
        let beatRate = abs(freqA - freqB)
        return roughness(beatRate: beatRate) * weightA * weightB
    }

    /// Total roughness between two tones' full harmonic series (`limit` harmonics each),
    /// summed over every harmonic-of-A x harmonic-of-B pair. Defaults to linear weighting
    /// (nil means "use linearHarmonicWeight for this limit"); a default parameter can't
    /// reference the `limit` parameter directly, so the fallback is resolved in the body.
    static func roughnessBetweenTones(frequencyA: Double, frequencyB: Double, limit: Int, weighting: HarmonicWeighting? = nil) -> Double {
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }
        var total = 0.0
        for harmonicA in 1...limit {
            let freqA = harmonicFrequency(fundamental: frequencyA, harmonicNumber: harmonicA)
            let weightA = weighting(harmonicA)
            for harmonicB in 1...limit {
                let freqB = harmonicFrequency(fundamental: frequencyB, harmonicNumber: harmonicB)
                let weightB = weighting(harmonicB)
                total += pairwiseRoughness(freqA: freqA, weightA: weightA, freqB: freqB, weightB: weightB)
            }
        }
        return total
    }

    /// Total roughness field value for a candidate (root, X, Y) triad, or (root, X, Y, Z)
    /// tetrad when `zFrequency` is given: the sum of pairwise roughness across every tone
    /// pair (root x X, root x Y, X x Y, and - with Z - root x Z, X x Z, Y x Z).
    static func totalRoughness(rootFrequency: Double, xFrequency: Double, yFrequency: Double, zFrequency: Double? = nil, limit: Int, weighting: HarmonicWeighting? = nil) -> Double {
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }
        let rootX = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: xFrequency, limit: limit, weighting: weighting)
        let rootY = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: yFrequency, limit: limit, weighting: weighting)
        let xY = roughnessBetweenTones(frequencyA: xFrequency, frequencyB: yFrequency, limit: limit, weighting: weighting)
        var total = rootX + rootY + xY
        if let zFrequency {
            let rootZ = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: zFrequency, limit: limit, weighting: weighting)
            let xZ = roughnessBetweenTones(frequencyA: xFrequency, frequencyB: zFrequency, limit: limit, weighting: weighting)
            let yZ = roughnessBetweenTones(frequencyA: yFrequency, frequencyB: zFrequency, limit: limit, weighting: weighting)
            total += rootZ + xZ + yZ
        }
        return total
    }

    /// Builds a `resolution` x `resolution` grid of total roughness values covering the
    /// full X/Y range of `scale` (both axes span the same lowest-to-highest normalized
    /// range as the graph itself), for a fixed root frequency and, when `zFrequency` is
    /// given, a fixed Z frequency too - the field then reflects the current (root, X, Y, Z)
    /// tetrad rather than just (root, X, Y), so it changes as Z moves.
    ///
    /// Indexed [row][col]: row 0 is the lowest pitch (bottom of the graph), col 0 is the
    /// lowest pitch (left of the graph) - same orientation as the rest of the graph's
    /// coordinate space. Each cell is evaluated at its center point along that axis.
    ///
    /// `isCancelled`, when given, is polled once per outer row (cheap relative to a row's own
    /// O(resolution) inner cost, but fine-grained enough that a cancellation mid-grid wastes at
    /// most one row's worth of work) - lets a caller running this off the main thread (see
    /// DissonanceView's background refinement passes) actually stop computing the moment a
    /// caller-side cancellation happens, rather than finishing the whole grid and only
    /// discarding the result afterward. A cancelled call returns `[]`, the same empty-grid
    /// signal invalid inputs already use, so callers already checking for that don't need a
    /// second code path.
    static func roughnessGrid(scale: Scale, rootFrequency: Double, zFrequency: Double? = nil, limit: Int, resolution: Int, weighting: HarmonicWeighting? = nil, isCancelled: (() -> Bool)? = nil) -> [[Double]] {
        guard resolution > 0, limit > 0 else { return [] }
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }

        func frequency(atFraction fraction: Double) -> Double {
            let normalized = scale.lowestRatioNormalized + scale.rangeNormalized * fraction
            return rootFrequency * pow(2, normalized)
        }

        // both axes share the same fraction-to-frequency mapping, so compute it once per index
        let frequencyAt = (0..<resolution).map { frequency(atFraction: (Double($0) + 0.5) / Double(resolution)) }

        // roughnessBetweenTones(root, ·) has only one free argument (root is always the fixed
        // frequency), so the root-X and root-Y terms are the same function evaluated at a
        // position, not two independent things to compute - one 1D table serves both, reused
        // as a lookup instead of recomputed inside the O(resolution^2) loop below. This does
        // NOT extend to the X-Y term: unlike root, X and Y both range freely across the axis,
        // and roughness depends on absolute frequency register, not just the interval between
        // two tones (the same reason a higher root frequency produces tighter banding) - so
        // X-Y genuinely needs its own computation per cell. Its own X<->Y symmetry is already
        // covered by the mirroring below.
        let rootTermAt = frequencyAt.map { roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: $0, limit: limit, weighting: weighting) }

        // Z is fixed for the whole field too (like root), so its X/Y terms are the same kind
        // of cheap 1D lookup as rootTermAt - the O(resolution^2) loop below only gains two
        // array reads and an addition per cell, not a second full pairwise computation.
        let zTermAt = zFrequency.map { z in frequencyAt.map { roughnessBetweenTones(frequencyA: z, frequencyB: $0, limit: limit, weighting: weighting) } }
        let rootZ = zFrequency.map { roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: $0, limit: limit, weighting: weighting) } ?? 0

        var grid = [[Double]](repeating: [Double](repeating: 0, count: resolution), count: resolution)
        // totalRoughness(root, X, Y[, Z]) is symmetric under swapping X and Y (every term
        // pairs X and Y with the same fixed frequencies - root and, when present, Z - so
        // swapping X and Y leaves the sum invariant), and both grid axes share the same
        // fraction mapping above - so grid[row][col] == grid[col][row] always. Only the
        // diagonal and one triangle need computing; the other triangle is a mirror, cutting
        // the cost roughly in half.
        for row in 0..<resolution {
            if let isCancelled, isCancelled() { return [] }
            let yFrequency = frequencyAt[row]
            let rootY = rootTermAt[row]
            for col in row..<resolution {
                let xFrequency = frequencyAt[col]
                let rootX = rootTermAt[col]
                let xY = roughnessBetweenTones(frequencyA: xFrequency, frequencyB: yFrequency, limit: limit, weighting: weighting)
                var value = rootX + rootY + xY
                if let zTermAt {
                    value += rootZ + zTermAt[col] + zTermAt[row]
                }
                grid[row][col] = value
                grid[col][row] = value
            }
        }
        return grid
    }
}
