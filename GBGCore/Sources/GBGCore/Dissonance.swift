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
//  - Each tone is treated as an idealized harmonic series with 1/n amplitude
//    falloff (the standard assumption in this literature - not universally true
//    of real instruments, but a defensible starting idealization).
//  - Roughness between two partials is a function of their beat rate (the
//    absolute difference between their frequencies): a Gaussian bell peaking at
//    an arbitrary "maximum roughness" beat rate, tapering to ~0 at unison and
//    ~0 by roughly twice the peak. Symmetric for now - real roughness curves are
//    probably asymmetric (e.g. easing differently once the beat rate itself
//    lands on a harmonic relationship), but that's a possible future refinement,
//    not built here.
//  - Total roughness for a candidate (root, X, Y) triad sums pairwise roughness
//    across every harmonic-of-A x harmonic-of-B combination, for all three tone
//    pairs (root x X, root x Y, X x Y) - not just matching harmonic numbers.

import Foundation

enum Dissonance {
    /// Amplitude weight of the nth harmonic (1-indexed) of an idealized tone: 1/n falloff.
    static func harmonicWeight(_ harmonicNumber: Int) -> Double {
        1.0 / Double(harmonicNumber)
    }

    /// Frequency of the nth harmonic (1-indexed) of a tone at `fundamental`.
    static func harmonicFrequency(fundamental: Double, harmonicNumber: Int) -> Double {
        fundamental * Double(harmonicNumber)
    }

    /// Roughness contributed by two partials beating `beatRate` Hz apart, before amplitude weighting.
    /// A Gaussian bell peaking at `peakBeatRate`, so it's ~0 at 0 Hz and ~0 by roughly `2 * peakBeatRate`.
    static func roughness(beatRate: Double, peakBeatRate: Double = 30.0, sigma: Double = 10.0) -> Double {
        let distanceFromPeak = beatRate - peakBeatRate
        return exp(-(distanceFromPeak * distanceFromPeak) / (2 * sigma * sigma))
    }

    /// Roughness contributed by one pair of partials, weighted by both partials' harmonic amplitude.
    static func pairwiseRoughness(freqA: Double, weightA: Double, freqB: Double, weightB: Double) -> Double {
        let beatRate = abs(freqA - freqB)
        return roughness(beatRate: beatRate) * weightA * weightB
    }

    /// Total roughness between two tones' full harmonic series (`limit` harmonics each),
    /// summed over every harmonic-of-A x harmonic-of-B pair.
    static func roughnessBetweenTones(frequencyA: Double, frequencyB: Double, limit: Int) -> Double {
        var total = 0.0
        for harmonicA in 1...limit {
            let freqA = harmonicFrequency(fundamental: frequencyA, harmonicNumber: harmonicA)
            let weightA = harmonicWeight(harmonicA)
            for harmonicB in 1...limit {
                let freqB = harmonicFrequency(fundamental: frequencyB, harmonicNumber: harmonicB)
                let weightB = harmonicWeight(harmonicB)
                total += pairwiseRoughness(freqA: freqA, weightA: weightA, freqB: freqB, weightB: weightB)
            }
        }
        return total
    }

    /// Total roughness field value for a candidate (root, X, Y) triad: the sum of pairwise
    /// roughness across all three tone pairs (root x X, root x Y, X x Y).
    static func totalRoughness(rootFrequency: Double, xFrequency: Double, yFrequency: Double, limit: Int) -> Double {
        let rootX = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: xFrequency, limit: limit)
        let rootY = roughnessBetweenTones(frequencyA: rootFrequency, frequencyB: yFrequency, limit: limit)
        let xY = roughnessBetweenTones(frequencyA: xFrequency, frequencyB: yFrequency, limit: limit)
        return rootX + rootY + xY
    }

    /// Builds a `resolution` x `resolution` grid of total roughness values covering the
    /// full X/Y range of `scale` (both axes span the same lowest-to-highest normalized
    /// range as the graph itself), for a fixed root frequency.
    ///
    /// Indexed [row][col]: row 0 is the lowest pitch (bottom of the graph), col 0 is the
    /// lowest pitch (left of the graph) - same orientation as the rest of the graph's
    /// coordinate space. Each cell is evaluated at its center point along that axis.
    static func roughnessGrid(scale: Scale, rootFrequency: Double, limit: Int, resolution: Int) -> [[Double]] {
        guard resolution > 0, limit > 0 else { return [] }

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
                grid[row][col] = totalRoughness(rootFrequency: rootFrequency, xFrequency: xFrequency, yFrequency: yFrequency, limit: limit)
            }
        }
        return grid
    }
}
