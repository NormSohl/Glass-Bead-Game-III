//
//  TempoDetection.swift
//  GBGCore
//
//  Detects tempo from a live recording's onset times via autocorrelation - not an inter-onset-
//  interval histogram, which breaks down as soon as a performance skips a beat or syncopates
//  (a single missed/extra onset corrupts every interval that touches it, where autocorrelation
//  just sees one weaker vote for that lag among many). Deliberately confidence-gated: melismatic
//  or unmetered material correctly detecting *no* confident tempo (returning nil) is the
//  expected outcome for that material, not a failure of the detector.
//
//  Pure, no UI, no audio dependency - operates on onset sample-times the caller already
//  extracted (from Note boundaries after segmentation, or a dedicated onset detector - out of
//  scope here either way).
//

import Foundation

/// A detected tempo, or nil when no candidate cleared `tempoConfidenceThreshold` - the correct,
/// expected result for melismatic/unmetered material, not a failure mode.
public struct TempoInfo: Codable, Equatable {
    public let bpm: Double
    /// Sample-time (same domain as the onsets passed in) of the inferred downbeat - the first
    /// onset, on the working assumption that a performance starts on the beat. Metadata only;
    /// nothing here ever rewrites a Note's own startTime/endTime.
    public let downbeatOffset: Int
    /// 0...1 - see `tempoConfidenceThreshold` for the cutoff below which `detectTempo` returns
    /// nil instead of a low-confidence guess.
    public let confidence: Double

    public init(bpm: Double, downbeatOffset: Int, confidence: Double) {
        self.bpm = bpm
        self.downbeatOffset = downbeatOffset
        self.confidence = confidence
    }
}

// MARK: - Tunable constants
//
// Need real-recording tuning later, same as Segmentation.swift's own constants - these are
// reasonable defaults verified against synthetic ground truth, not final.

private let tempoMinBPM = 40.0
private let tempoMaxBPM = 240.0

/// Width of the coarse time bins the onset impulse train is built in, before autocorrelating.
private let onsetBinSeconds = 0.01

/// Below this, `detectTempo` returns nil rather than a low-confidence guess - deliberately: a
/// caller displaying a detected-tempo grid should never have to second-guess whether a returned
/// value is trustworthy.
private let tempoConfidenceThreshold = 0.5

/// How many standard deviations above the mean autocorrelation the peak needs to reach for
/// confidence 1.0 - a genuine periodic pulse train typically peaks well beyond this at its true
/// period (and its integer multiples/divisors), while a non-periodic onset pattern's
/// autocorrelation stays close to its own mean at every lag.
private let confidenceZScoreForFullConfidence = 6.0

/// Finds the tempo best explaining `onsetTimes` (in the same sample domain as `Note.startTime`)
/// via autocorrelation: the onsets are rasterized into a coarse impulse train, correlated
/// against time-shifted copies of itself across the lag range `tempoMinBPM`...`tempoMaxBPM`
/// covers, and the strongest, most prominent lag (if any clears `tempoConfidenceThreshold`)
/// becomes the result.
///
/// Returns nil for too few onsets to say anything meaningful, or when no lag's peak is
/// confidently distinguishable from the background correlation level - both expected outcomes
/// for sparse or unmetered material, not error conditions.
public func detectTempo(onsetTimes: [Int], sampleRate: Double) -> TempoInfo? {
    guard onsetTimes.count >= 4, sampleRate > 0 else { return nil }
    let sorted = onsetTimes.sorted()
    guard let first = sorted.first, let last = sorted.last, last > first else { return nil }

    let binSamples = onsetBinSeconds * sampleRate
    let numBins = max(1, Int((Double(last - first) / binSamples).rounded())) + 1
    var signal = [Double](repeating: 0, count: numBins)
    for onset in sorted {
        let bin = Int((Double(onset - first) / binSamples).rounded())
        if bin >= 0 && bin < numBins { signal[bin] += 1 }
    }

    let minLagBins = max(1, Int((60.0 / tempoMaxBPM / onsetBinSeconds).rounded()))
    let maxLagBins = min(numBins - 1, Int((60.0 / tempoMinBPM / onsetBinSeconds).rounded()))
    guard maxLagBins > minLagBins else { return nil }

    var correlations: [Double] = []
    correlations.reserveCapacity(maxLagBins - minLagBins + 1)
    for lag in minLagBins...maxLagBins {
        var sum = 0.0
        for i in 0..<(numBins - lag) {
            sum += signal[i] * signal[i + lag]
        }
        correlations.append(sum)
    }

    guard let maxCorrelation = correlations.max(),
          let peakOffset = correlations.firstIndex(of: maxCorrelation) else { return nil }
    let peakLagBins = minLagBins + peakOffset

    let mean = correlations.reduce(0, +) / Double(correlations.count)
    let variance = correlations.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(correlations.count)
    let stddev = variance.squareRoot()
    guard stddev > 0 else { return nil }

    let zScore = (maxCorrelation - mean) / stddev
    let confidence = min(1.0, max(0.0, zScore / confidenceZScoreForFullConfidence))
    guard confidence >= tempoConfidenceThreshold else { return nil }

    let periodSeconds = Double(peakLagBins) * onsetBinSeconds
    let bpm = 60.0 / periodSeconds

    return TempoInfo(bpm: bpm, downbeatOffset: first, confidence: confidence)
}
