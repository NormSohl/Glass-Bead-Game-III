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

    /// Total roughness field value for a candidate (root, X, Y) triad: the sum of pairwise
    /// roughness across all three tone pairs (root x X, root x Y, X x Y).
    static func totalRoughness(rootFrequency: Double, xFrequency: Double, yFrequency: Double, limit: Int, weighting: HarmonicWeighting? = nil) -> Double {
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }
        let rootX = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: xFrequency, limit: limit, weighting: weighting)
        let rootY = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: yFrequency, limit: limit, weighting: weighting)
        let xY = roughnessBetweenTones(frequencyA: xFrequency, frequencyB: yFrequency, limit: limit, weighting: weighting)
        return rootX + rootY + xY
    }

    /// Builds a `resolution` x `resolution` grid of total roughness values covering the
    /// full X/Y range of `scale` (both axes span the same lowest-to-highest normalized
    /// range as the graph itself), for a fixed root frequency.
    ///
    /// Indexed [row][col]: row 0 is the lowest pitch (bottom of the graph), col 0 is the
    /// lowest pitch (left of the graph) - same orientation as the rest of the graph's
    /// coordinate space. Each cell is evaluated at its center point along that axis.
    static func roughnessGrid(scale: Scale, rootFrequency: Double, limit: Int, resolution: Int, weighting: HarmonicWeighting? = nil) -> [[Double]] {
        guard resolution > 0, limit > 0 else { return [] }
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }

        func frequency(atFraction fraction: Double) -> Double {
            let normalized = scale.lowestRatioNormalized + scale.rangeNormalized * fraction
            return rootFrequency * pow(2, normalized)
        }

        var grid = [[Double]](repeating: [Double](repeating: 0, count: resolution), count: resolution)
        for row in 0..<resolution {
            let yFraction = (Double(row) + 0.5) / Double(resolution)
            let yFrequency = frequency(atFraction: yFraction)
            for col in 0..<resolution {
                let xFraction = (Double(col) + 0.5) / Double(resolution)
                let xFrequency = frequency(atFraction: xFraction)
                grid[row][col] = totalRoughness(rootFrequency: rootFrequency, xFrequency: xFrequency, yFrequency: yFrequency, limit: limit, weighting: weighting)
            }
        }
        return grid
    }
}
