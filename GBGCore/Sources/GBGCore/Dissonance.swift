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
import Dispatch

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

    // MARK: - Fast (approximate) roughness, for roughnessGrid's rendering hot loop only

    // roughnessGrid below calls exp() tens of millions of times per full-resolution render -
    // measured (temporary XCTest `measure`, Release) at roughly 40% of that function's total
    // time. A lookup table trades a small, bounded amount of numerical precision for speed.
    // Deliberately NOT used by roughness/pairwiseRoughness/roughnessBetweenTones/totalRoughness
    // above, which stay exact - those have their own tests asserting 1e-7 precision, and are
    // the reference this fast path is verified against (see
    // testRoughnessFastStaysWithinPerceptualToleranceOfExact in DissonanceTests). The
    // justification for approximating at all: DissonanceView's own output collapses every
    // pixel to 256 (arguably ~128 perceptually distinct, per Norm) 8-bit levels via its tone
    // curve, so any error here well under that - this LUT's worst measured error is
    // orders of magnitude smaller - can never change a single rendered pixel.
    private static let roughnessLUTStep = 0.1
    // ~5.7 sigma past the peak - exp() there is already down around 1e-7, indistinguishable
    // from the 0 this returns beyond it.
    private static let roughnessLUTCutoff = 90.0
    private static let roughnessLUT: [Double] = {
        let count = Int((roughnessLUTCutoff / roughnessLUTStep).rounded(.up)) + 1
        return (0..<count).map { roughness(beatRate: Double($0) * roughnessLUTStep) }
    }()

    /// Linearly-interpolated lookup table stand-in for `roughness(beatRate:)`, used only by
    /// roughnessGrid's inner loop - see the section comment above for why this is safe.
    private static func roughnessFast(beatRate: Double) -> Double {
        guard beatRate < roughnessLUTCutoff else { return 0 }
        let position = beatRate / roughnessLUTStep
        let lowerIndex = Int(position)
        let fraction = position - Double(lowerIndex)
        let lower = roughnessLUT[lowerIndex]
        let upper = roughnessLUT[lowerIndex + 1]
        return lower + (upper - lower) * fraction
    }

    private static func pairwiseRoughnessFast(freqA: Double, weightA: Double, freqB: Double, weightB: Double) -> Double {
        roughnessFast(beatRate: abs(freqA - freqB)) * weightA * weightB
    }

    /// Total roughness between two tones' full harmonic series (`limit` harmonics each),
    /// summed over every harmonic-of-A x harmonic-of-B pair. Defaults to linear weighting
    /// (nil means "use linearHarmonicWeight for this limit"); a default parameter can't
    /// reference the `limit` parameter directly, so the fallback is resolved in the body.
    static func roughnessBetweenTones(frequencyA: Double, frequencyB: Double, limit: Int, weighting: HarmonicWeighting? = nil) -> Double {
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }
        // B's harmonic frequency/weight don't depend on harmonicA at all, but the loop below
        // used to recompute them fresh on every one of A's `limit` iterations anyway -
        // precomputed once here instead, same values, same summation order, just without the
        // redundant work.
        var freqB = [Double](repeating: 0, count: limit)
        var weightB = [Double](repeating: 0, count: limit)
        for h in 1...limit {
            freqB[h - 1] = harmonicFrequency(fundamental: frequencyB, harmonicNumber: h)
            weightB[h - 1] = weighting(h)
        }
        var total = 0.0
        for harmonicA in 1...limit {
            let freqA = harmonicFrequency(fundamental: frequencyA, harmonicNumber: harmonicA)
            let weightA = weighting(harmonicA)
            for i in 0..<limit {
                total += pairwiseRoughness(freqA: freqA, weightA: weightA, freqB: freqB[i], weightB: weightB[i])
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
    /// Uses the LUT-backed roughnessFast, not the exact roughness/roughnessBetweenTones this
    /// file's own tests hold to 1e-7 - see the "Fast (approximate) roughness" section above
    /// for why that's safe for a value that only ever ends up as one of 256 rendered pixel
    /// levels. testRoughnessGridStaysWithinPerceptualToleranceOfExactMath (DissonanceTests)
    /// is what actually guarantees the error stays small enough for that to hold.
    ///
    /// `isCancelled`, when given, is polled once per row-batch (see `rowBatchSize` below) -
    /// lets a caller running this off the main thread (see DissonanceView's background
    /// refinement passes) actually stop computing shortly after a caller-side cancellation
    /// happens, rather than finishing the whole grid and only discarding the result
    /// afterward. A cancelled call returns `[]`, the same empty-grid signal invalid inputs
    /// already use, so callers already checking for that don't need a second code path.
    static func roughnessGrid(scale: Scale, rootFrequency: Double, zFrequency: Double? = nil, limit: Int, resolution: Int, weighting: HarmonicWeighting? = nil, isCancelled: (() -> Bool)? = nil) -> [[Double]] {
        guard resolution > 0, limit > 0 else { return [] }
        let weighting = weighting ?? { linearHarmonicWeight($0, limit: limit) }

        func frequency(atFraction fraction: Double) -> Double {
            let normalized = scale.lowestRatioNormalized + scale.rangeNormalized * fraction
            return rootFrequency * pow(2, normalized)
        }

        // both axes share the same fraction-to-frequency mapping, so compute it once per index
        let frequencyAt = (0..<resolution).map { frequency(atFraction: (Double($0) + 0.5) / Double(resolution)) }

        // Harmonic amplitude weight depends only on the harmonic number (1...limit), never on
        // which tone it belongs to - one array shared by every harmonic series below, instead
        // of every one of them re-deriving it.
        let weightAt = (1...limit).map { weighting($0) }

        func harmonicFrequencies(fundamental: Double) -> [Double] {
            (1...limit).map { harmonicFrequency(fundamental: fundamental, harmonicNumber: $0) }
        }

        // Every axis position's own harmonic series, computed exactly once - O(resolution *
        // limit) total. Before this, an equivalent series was silently recomputed from scratch
        // by roughnessBetweenTones on every one of the O(resolution^2) grid-cell evaluations
        // that happened to touch a given axis position (as either its row or its column), which
        // was the single largest avoidable cost in the whole computation.
        let axisHarmonics = frequencyAt.map { harmonicFrequencies(fundamental: $0) }
        let rootHarmonics = harmonicFrequencies(fundamental: rootFrequency)
        let zHarmonics = zFrequency.map { harmonicFrequencies(fundamental: $0) }

        // Sum of pairwiseRoughnessFast across every harmonic-of-seriesA x harmonic-of-seriesB
        // pair - the shared core both the root/Z 1D tables and the main X-Y grid loop reduce
        // to, once their harmonic series are already sitting in an array rather than needing
        // deriving. Uses the LUT-backed fast path (see the section above), not the exact
        // pairwiseRoughness - this is the rendering hot loop the LUT exists for. Reads only
        // `weightAt` (immutable, computed above) and its own by-value arguments, so it's safe
        // to call from multiple rows in parallel below.
        func pairwiseSum(_ seriesA: [Double], _ seriesB: [Double]) -> Double {
            var total = 0.0
            for i in 0..<limit {
                let a = seriesA[i], weightA = weightAt[i]
                for j in 0..<limit {
                    total += pairwiseRoughnessFast(freqA: a, weightA: weightA, freqB: seriesB[j], weightB: weightAt[j])
                }
            }
            return total
        }

        // roughnessBetweenTones(root, ·) has only one free argument (root is always the fixed
        // frequency), so the root-X and root-Y terms are the same function evaluated at a
        // position, not two independent things to compute - one 1D table serves both, reused
        // as a lookup instead of recomputed inside the O(resolution^2) loop below. This does
        // NOT extend to the X-Y term: unlike root, X and Y both range freely across the axis,
        // and roughness depends on absolute frequency register, not just the interval between
        // two tones (the same reason a higher root frequency produces tighter banding) - so
        // X-Y genuinely needs its own computation per cell. Its own X<->Y symmetry is already
        // covered by the mirroring below.
        let rootTermAt = axisHarmonics.map { pairwiseSum(rootHarmonics, $0) }

        // Z is fixed for the whole field too (like root), so its X/Y terms are the same kind
        // of cheap 1D lookup as rootTermAt - the O(resolution^2) loop below only gains two
        // array reads and an addition per cell, not a second full pairwise computation.
        let zTermAt = zHarmonics.map { z in axisHarmonics.map { pairwiseSum(z, $0) } }
        let rootZ = zHarmonics.map { pairwiseSum(rootHarmonics, $0) } ?? 0

        // totalRoughness(root, X, Y[, Z]) is symmetric under swapping X and Y (every term
        // pairs X and Y with the same fixed frequencies - root and, when present, Z - so
        // swapping X and Y leaves the sum invariant), and both grid axes share the same
        // fraction mapping above - so grid[row][col] == grid[col][row] always. Only the
        // diagonal and one triangle need computing; the other triangle is a mirror, cutting
        // the cost roughly in half.
        //
        // Rows are otherwise independent - a row only ever writes its own row and the mirrored
        // column position in every other row, and no two different rows' writes ever land on
        // the same cell (each row "owns" a disjoint set of flat-buffer indices: its own row
        // band, plus one fixed column offset - its own row number - in every other row band).
        // So rows are computed in parallel batches across CPU cores via a flat, unsafe buffer
        // rather than one at a time into a plain [[Double]] (whose COW/uniqueness machinery
        // isn't documented as safe for concurrent same-array different-index writes the way a
        // raw buffer explicitly is). Batched - not one single resolution-wide
        // concurrentPerform - so isCancelled is still polled somewhat promptly rather than only
        // once for the entire grid: Norm, "interrupt the redraw the moment the drag message
        // comes in, don't wait." rowBatchSize is a plain tunable constant, not derived from
        // core count - small enough that a cancellation wastes at most one batch's already-
        // parallelized work, large enough that concurrentPerform's own per-call overhead stays
        // negligible next to the row math it's dispatching.
        let rowBatchSize = 32
        var flat = [Double](repeating: 0, count: resolution * resolution)
        var wasCancelled = false
        flat.withUnsafeMutableBufferPointer { buffer in
            var batchStart = 0
            while batchStart < resolution {
                if let isCancelled, isCancelled() { wasCancelled = true; return }
                let batchCount = min(rowBatchSize, resolution - batchStart)
                DispatchQueue.concurrentPerform(iterations: batchCount) { offset in
                    let row = batchStart + offset
                    let yHarmonics = axisHarmonics[row]
                    let rootY = rootTermAt[row]
                    for col in row..<resolution {
                        let xHarmonics = axisHarmonics[col]
                        let rootX = rootTermAt[col]
                        let xY = pairwiseSum(xHarmonics, yHarmonics)
                        var value = rootX + rootY + xY
                        if let zTermAt {
                            value += rootZ + zTermAt[col] + zTermAt[row]
                        }
                        buffer[row * resolution + col] = value
                        buffer[col * resolution + row] = value
                    }
                }
                batchStart += batchCount
            }
        }
        if wasCancelled { return [] }

        // Reshape the flat buffer back into the [[Double]] every existing caller already
        // expects - a plain, single-threaded copy, cheap next to the math that produced it.
        var grid = [[Double]]()
        grid.reserveCapacity(resolution)
        for row in 0..<resolution {
            grid.append(Array(flat[(row * resolution)..<((row + 1) * resolution)]))
        }
        return grid
    }
}
