//
//  Segmentation.swift
//  GBGCore
//
//  Splits a raw recorded note (one long TransRecordedContour note per touch-gesture, from live
//  capture) into a sequence of shorter, editable notes - each a held "dwell" with its own
//  recentered contour. Always produces dwell-only pieces for this pass (never keeps a glide as
//  one note with startFrequency != endFrequency, even though Note/TransRecordedContour's data
//  model supports that) - simpler, and the standalone-sequencer plan explicitly sanctions this
//  simplification for now, revisited once real recordings are in hand to tune against.
//
//  Pure, no UI, no Part/audio dependency beyond Note itself - see the plan's own step 2 for the
//  full design rationale.
//

import Foundation

// MARK: - Tunable constants
//
// These need real-recording tuning later (see the standalone-sequencer plan's "Deliberately
// out of scope" section) - the values below are reasonable defaults verified against synthetic
// ground truth, not final.

/// Light smoothing applied before analysis, purely to reduce single-sample capture noise - not
/// relied on to filter out vibrato (that's the dwell criterion's job, see below), so this can
/// stay narrow.
private let segmentationSmoothingWindowSeconds = 0.02

/// A window "dwells" if its pitch stays within this many cents of its own range (max - min) -
/// range-based rather than slope-based, deliberately: a vibrato has fast local slope but stays
/// within a bounded range, so a range check correctly reads it as dwelling (with wobble) while
/// a slope check would need careful width-tuning to avoid misreading it as a glide. Half a
/// semitone - roughly "probably does not go beyond half the space between the intervals," the
/// natural bound this feature's own design conversation landed on.
private let dwellRangeCentsThreshold = 50.0

/// Minimum duration (real time) for a stretch of dwelling to count as a genuine held note
/// rather than a passing moment inside a slide.
private let minDwellDurationSeconds = 0.1

/// Splits `note` (expected to carry a `recordedPitchBend` buffer, e.g. from live capture) into
/// dwell-only pieces. `sampleRate` is the audio sample rate `note.startTime`/`endTime` are
/// expressed in (the same value threaded through elsewhere in this codebase, e.g.
/// `ScorePlayer`/`SequencerState`) - needed to convert the time-based thresholds above into a
/// count of contour-array indices, independent of how densely the contour was actually sampled
/// during capture.
///
/// Returns `[note]` unchanged if there's nothing to segment (no buffer, degenerate duration) or
/// no dwell region is found anywhere long enough to count (a pure fast glide, or a note too
/// short to contain `minDwellDurationSeconds` at all) - never over-splits degenerate input.
public func segmentPitch(_ note: Note, sampleRate: Double) -> [Note] {
    guard let samples = note.recordedPitchBend, samples.count > 2 else { return [note] }
    let noteDurationSamples = note.endTime - note.startTime
    guard noteDurationSamples > 0, sampleRate > 0 else { return [note] }

    let noteDurationSeconds = Double(noteDurationSamples) / sampleRate
    let secondsPerIndex = noteDurationSeconds / Double(samples.count - 1)
    guard secondsPerIndex > 0 else { return [note] }

    let smoothingRadius = max(0, Int((segmentationSmoothingWindowSeconds / secondsPerIndex / 2).rounded()))
    let smoothed = movingAverageSmooth(samples, radiusIndices: smoothingRadius)
    let minDwellIndices = max(1, Int((minDwellDurationSeconds / secondsPerIndex).rounded()))

    func windowDwells(at i: Int) -> Bool {
        let end = min(i + minDwellIndices, smoothed.count)
        guard end - i >= 2 else { return false }
        let slice = smoothed[i..<end]
        return (slice.max()! - slice.min()!) <= dwellRangeCentsThreshold
    }

    var dwellFlags = [Bool](repeating: false, count: smoothed.count)
    for i in 0..<smoothed.count where windowDwells(at: i) {
        let end = min(i + minDwellIndices, smoothed.count)
        for j in i..<end { dwellFlags[j] = true }
    }

    var dwellRegions: [(start: Int, end: Int)] = [] // inclusive index ranges into `smoothed`
    var i = 0
    while i < dwellFlags.count {
        if dwellFlags[i] {
            var j = i
            while j < dwellFlags.count && dwellFlags[j] { j += 1 }
            dwellRegions.append((i, j - 1))
            i = j
        } else {
            i += 1
        }
    }

    guard !dwellRegions.isEmpty else { return [note] }

    func slope(_ a: Int, _ b: Int) -> Double {
        guard b > a else { return 0 }
        return (smoothed[b] - smoothed[a]) / (Double(b - a) * secondsPerIndex)
    }

    func steepestIndex(from: Int, to: Int) -> Int {
        guard to > from + 1 else { return (from + to) / 2 }
        var best = from
        var bestSlope = 0.0
        for k in from..<to {
            let s = abs(slope(k, k + 1))
            if s > bestSlope { bestSlope = s; best = k }
        }
        return best
    }

    var outputs: [Note] = []
    for (regionIndex, region) in dwellRegions.enumerated() {
        let pieceStartIndex = regionIndex == 0
            ? 0 // the first piece always starts at the note's own true start - no leading gap
            : steepestIndex(from: dwellRegions[regionIndex - 1].end, to: region.start)
        let pieceEndIndex = regionIndex == dwellRegions.count - 1
            ? smoothed.count - 1 // the last piece always ends at the note's own true end
            : steepestIndex(from: region.end, to: dwellRegions[regionIndex + 1].start)

        let pieceStartTime = note.startTime + Int((Double(pieceStartIndex) * secondsPerIndex * sampleRate).rounded())
        let pieceEndTime = note.startTime + Int((Double(pieceEndIndex) * secondsPerIndex * sampleRate).rounded())
        guard pieceEndTime > pieceStartTime else { continue }

        // Center pitch is the average over the dwell region itself, not the whole piece span
        // (which may include part of an adjoining glide on either side) - representative of
        // the held pitch, not dragged toward whatever's on either side of it.
        let dwellSlice = smoothed[region.start...region.end]
        let averageCents = dwellSlice.reduce(0, +) / Double(dwellSlice.count)
        let centerFrequency = note.startFrequency * pow(2, averageCents / 1200)

        // Recomputed relative to this piece's own new center - a constant subtraction, since
        // both the original samples and averageCents are already expressed in cents relative
        // to the same original reference frequency.
        let pieceSamples = (pieceStartIndex...pieceEndIndex).map { samples[min($0, samples.count - 1)] - averageCents }

        let pieceNote = Note(startTime: pieceStartTime, endTime: pieceEndTime, startFrequency: centerFrequency, endFrequency: centerFrequency, amplitude: note.amplitude)
        pieceNote.transition = TransRecordedContour(samples: pieceSamples)
        pieceNote.recordedPitchBend = pieceSamples
        pieceNote.envelope = note.envelope
        outputs.append(pieceNote)
    }

    // Safety net: reconstruction degenerating to nothing usable (shouldn't happen given the
    // guards above, but falling back to the original note beats returning silence).
    return outputs.isEmpty ? [note] : outputs
}

private func movingAverageSmooth(_ values: [Double], radiusIndices: Int) -> [Double] {
    guard radiusIndices > 0 else { return values }
    var result = [Double](repeating: 0, count: values.count)
    for i in 0..<values.count {
        let lo = max(0, i - radiusIndices)
        let hi = min(values.count - 1, i + radiusIndices)
        let slice = values[lo...hi]
        result[i] = slice.reduce(0, +) / Double(slice.count)
    }
    return result
}
