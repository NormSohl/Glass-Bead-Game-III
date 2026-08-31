import XCTest
@testable import GBGCore

final class SegmentationTests: XCTestCase {

    let sampleRate = 44100.0

    // Builds a raw recorded note the way live capture would (via insertRecordedNote, the
    // required construction path - see Part.swift's own doc comment on why the two-step
    // version is a footgun), covering `seconds` of audio at `sampleRate`, with the given
    // evenly-spaced cents-offset samples.
    func makeRecordedNote(seconds: Double, samples: [Double], baseFrequency: Double = 440) -> Note {
        let part = Part(name: "test")
        let endTime = Int(seconds * sampleRate)
        return part.insertRecordedNote(
            startTime: 0, endTime: endTime,
            startFrequency: baseFrequency, endFrequency: baseFrequency,
            amplitude: 1, recordedPitchBend: samples)
    }

    // MARK: - Flat dwell: no glide anywhere -> exactly one output note

    func testFlatDwellProducesExactlyOneNote() {
        let samples = [Double](repeating: 0, count: 200) // 2 seconds, dead flat
        let note = makeRecordedNote(seconds: 2.0, samples: samples)

        let result = segmentPitch(note, sampleRate: sampleRate)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startTime, note.startTime)
        XCTAssertEqual(result[0].endTime, note.endTime)
        XCTAssertEqual(result[0].startFrequency, 440, accuracy: 0.01)
        XCTAssertEqual(result[0].endFrequency, 440, accuracy: 0.01)
    }

    // MARK: - dwell-glide-dwell-glide-dwell: a genuine three-note phrase

    func testThreePhraseDwellGlideDwellGlideDwellProducesThreeNotes() {
        // 3 seconds total, built at 100 samples/sec of contour density:
        //   0.0-0.8s dwell at 0c, 0.8-1.0s glide up 700c, 1.0-1.8s dwell at 700c,
        //   1.8-2.0s glide down to -500c, 2.0-3.0s dwell at -500c.
        // Glides move hundreds of cents in 0.2s - far beyond the 50c dwell-range threshold, so
        // dwell/glide/dwell/glide/dwell should all be unambiguous.
        var samples: [Double] = []
        let contourRate = 100.0 // samples per second
        func appendDwell(seconds: Double, cents: Double) {
            samples.append(contentsOf: [Double](repeating: cents, count: Int(seconds * contourRate)))
        }
        func appendGlide(seconds: Double, from: Double, to: Double) {
            let n = Int(seconds * contourRate)
            for i in 0..<n {
                let t = Double(i) / Double(n - 1)
                samples.append(from + (to - from) * t)
            }
        }
        appendDwell(seconds: 0.8, cents: 0)
        appendGlide(seconds: 0.2, from: 0, to: 700)
        appendDwell(seconds: 0.8, cents: 700)
        appendGlide(seconds: 0.2, from: 700, to: -500)
        appendDwell(seconds: 1.0, cents: -500)

        let note = makeRecordedNote(seconds: 3.0, samples: samples)
        let result = segmentPitch(note, sampleRate: sampleRate)

        XCTAssertEqual(result.count, 3)

        // Pieces tile the original note contiguously with no gaps or overlaps.
        XCTAssertEqual(result[0].startTime, note.startTime)
        XCTAssertEqual(result.last?.endTime, note.endTime)
        for i in 0..<(result.count - 1) {
            XCTAssertEqual(result[i].endTime, result[i + 1].startTime)
        }

        // Cut points fall within the ramp spans (0.8-1.0s and 1.8-2.0s), not off in a dwell.
        let cut1Seconds = Double(result[0].endTime) / sampleRate
        XCTAssertGreaterThanOrEqual(cut1Seconds, 0.8)
        XCTAssertLessThanOrEqual(cut1Seconds, 1.0)
        let cut2Seconds = Double(result[1].endTime) / sampleRate
        XCTAssertGreaterThanOrEqual(cut2Seconds, 1.8)
        XCTAssertLessThanOrEqual(cut2Seconds, 2.0)

        // Each piece is recentered on its own dwell - near-zero average recomputed cents.
        for piece in result {
            guard let pieceSamples = piece.recordedPitchBend, !pieceSamples.isEmpty else {
                XCTFail("expected a recorded buffer on every segmented piece")
                continue
            }
            let average = pieceSamples.reduce(0, +) / Double(pieceSamples.count)
            // Recentering targets the dwell region's own average, not the whole piece's - a
            // piece's samples still include a sliver of the adjoining glide out to the cut
            // point, which pulls its whole-piece average off zero. What matters is that it
            // stays small relative to the 500-700c swings between dwells, not exactly zero.
            XCTAssertEqual(average, 0, accuracy: 150)
        }

        // Recentered frequencies land near the three dwell levels: 0c, +700c, -500c from 440Hz.
        XCTAssertEqual(result[0].startFrequency, 440, accuracy: 5)
        XCTAssertEqual(result[1].startFrequency, 440 * pow(2, 700.0 / 1200), accuracy: 5)
        XCTAssertEqual(result[2].startFrequency, 440 * pow(2, -500.0 / 1200), accuracy: 5)
    }

    // MARK: - Vibrato that returns to its own starting pitch should stay one note

    func testVibratoStaysOneNote() {
        // 2 seconds at ~6Hz vibrato, +/-15c amplitude (30c total range - comfortably inside the
        // 50c dwell-range threshold). Fast local slope throughout, but the range-based dwell
        // criterion (not slope-based, precisely to handle this) should read the whole thing as
        // one sustained dwell rather than a string of tiny glides.
        let contourRate = 200.0 // samples per second - dense enough to resolve a 6Hz wobble
        let duration = 2.0
        let n = Int(duration * contourRate)
        var samples: [Double] = []
        for i in 0..<n {
            let t = Double(i) / contourRate
            samples.append(15.0 * sin(2 * Double.pi * 6.0 * t))
        }

        let note = makeRecordedNote(seconds: duration, samples: samples)
        let result = segmentPitch(note, sampleRate: sampleRate)

        XCTAssertEqual(result.count, 1, "a bounded vibrato should not be split into separate notes")
        XCTAssertEqual(result[0].startTime, note.startTime)
        XCTAssertEqual(result[0].endTime, note.endTime)
    }

    // MARK: - Too short to contain minDwellDurationSeconds anywhere -> exactly one note

    func testNoteTooShortForMinimumDwellProducesExactlyOneNote() {
        // 40ms total, well under the 100ms minimum dwell duration, sweeping a real 300c glide
        // across its whole span - no window, however placed, could plausibly read as "dwelling",
        // so this exercises the empty-dwell-regions fallback specifically (not just "it happens
        // to be flat").
        let contourRate = 200.0
        let duration = 0.04
        let n = max(3, Int(duration * contourRate))
        var samples: [Double] = []
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            samples.append(300.0 * t)
        }

        let note = makeRecordedNote(seconds: duration, samples: samples)
        let result = segmentPitch(note, sampleRate: sampleRate)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startTime, note.startTime)
        XCTAssertEqual(result[0].endTime, note.endTime)
    }

    // MARK: - Degenerate input: no recorded buffer at all -> unchanged single note

    func testNoteWithNoRecordedBufferPassesThroughUnchanged() {
        let part = Part(name: "test")
        let note = part.insertNote(startTime: 0, endTime: 1000, startFrequency: 440, endFrequency: 440, amplitude: 1)

        let result = segmentPitch(note, sampleRate: sampleRate)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0] === note)
    }
}

final class TempoDetectionTests: XCTestCase {

    let sampleRate = 44100.0

    // MARK: - A steady onset pattern should be detected confidently, with the right bpm

    func testSteadyOnsetPatternDetectsCorrectTempoWithHighConfidence() {
        // 120 BPM = one onset every 0.5s. 16 onsets = 8 seconds of steady quarter notes.
        let bpm = 120.0
        let periodSeconds = 60.0 / bpm
        let onsetCount = 16
        let onsets = (0..<onsetCount).map { Int(Double($0) * periodSeconds * sampleRate) }

        let result = detectTempo(onsetTimes: onsets, sampleRate: sampleRate)

        XCTAssertNotNil(result)
        guard let result else { return }
        XCTAssertEqual(result.bpm, bpm, accuracy: 2.0)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.5)
        XCTAssertEqual(result.downbeatOffset, onsets.first)
    }

    // MARK: - Arrhythmic onsets should not yield a confident tempo

    func testArrhythmicOnsetPatternReturnsNilOrLowConfidence() {
        // Deterministic (fixed-seed LCG), deliberately non-periodic gaps spanning 0.15-0.85s -
        // no common period explains this pattern, unlike the steady case above. A longer run
        // (40 onsets, vs. a handful) than the steady test needs, matching a real unmetered/
        // melismatic phrase and giving chance coincidences less room to fake a peak.
        var seed: UInt64 = 88172645463325252
        func nextUnit() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 1_000_000) / 1_000_000.0
        }
        var onsets: [Int] = [0]
        var t = 0.0
        for _ in 0..<40 {
            let gap = 0.15 + nextUnit() * 0.70
            t += gap
            onsets.append(Int(t * sampleRate))
        }

        let result = detectTempo(onsetTimes: onsets, sampleRate: sampleRate)

        if let result {
            XCTAssertLessThan(result.confidence, 0.5, "an arrhythmic pattern should not clear the confidence threshold")
        }
        // nil is the correct, expected outcome here - no further assertion needed if so.
    }

    // MARK: - Too few onsets to say anything meaningful

    func testTooFewOnsetsReturnsNil() {
        let result = detectTempo(onsetTimes: [0, 22050], sampleRate: sampleRate)
        XCTAssertNil(result)
    }
}
