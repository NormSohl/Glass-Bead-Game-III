import XCTest
@testable import GBGCore

final class PitchBendMathTests: XCTestCase {
    func testCentsToPitchBendIsCenteredAtZeroCents() {
        XCTAssertEqual(PitchBendMath.centsToPitchBend(pitchBendRange: 12, cents: 0), 8192)
    }

    func testCentsToPitchBendClampsAtTopOfRange() {
        XCTAssertEqual(PitchBendMath.centsToPitchBend(pitchBendRange: 2, cents: 200), 16383)
        XCTAssertEqual(PitchBendMath.centsToPitchBend(pitchBendRange: 2, cents: 500), 16383) // beyond range still clamps
    }

    func testCentsToPitchBendClampsAtBottomOfRange() {
        XCTAssertEqual(PitchBendMath.centsToPitchBend(pitchBendRange: 2, cents: -200), 0)
        XCTAssertEqual(PitchBendMath.centsToPitchBend(pitchBendRange: 2, cents: -500), 0) // beyond range still clamps
    }

    func testFreqToPBAtReferenceFrequencyIsCentered() {
        XCTAssertEqual(PitchBendMath.freqToPB(frequency: 440, referenceFrequency: 440, pitchBendRange: 12), 8192)
    }

    func testFreqToPBOneOctaveUpClampsAtRangeTop() {
        // one octave = 1200 cents, well beyond a +/-2 semitone (200 cent) pitch bend range
        let result = PitchBendMath.freqToPB(frequency: 880, referenceFrequency: 440, pitchBendRange: 2)
        XCTAssertEqual(result, 16383)
    }

    func testFreqToPBHalfSemitoneUpWithinRangeIsAboveCenter() {
        // quarter tone sharp of reference, well within a 2-semitone bend range
        let quarterToneUp = 440 * pow(2, (50.0 / 100.0) / 12.0)
        let result = PitchBendMath.freqToPB(frequency: quarterToneUp, referenceFrequency: 440, pitchBendRange: 2)
        XCTAssertGreaterThan(result, 8192)
        XCTAssertLessThan(result, 16383)
    }

    func testPitchBendToCentsIsCenteredAtZero() {
        XCTAssertEqual(PitchBendMath.pitchBendToCents(pitchBendRange: 12, pitchBend: 8192), 0)
    }

    func testPitchBendToCentsIsInverseOfCentsToPitchBend() {
        // Round-tripping a within-range cents value through centsToPitchBend and back should
        // land within a fraction of a cent (14-bit quantization, not exact) of the original.
        let originalCents = 137.0
        let pb = PitchBendMath.centsToPitchBend(pitchBendRange: 12, cents: originalCents)
        let roundTripped = PitchBendMath.pitchBendToCents(pitchBendRange: 12, pitchBend: pb)
        XCTAssertEqual(roundTripped, originalCents, accuracy: 0.1)
    }

    func testPitchBendToCentsAtExtremesMatchesDeclaredRange() {
        XCTAssertEqual(PitchBendMath.pitchBendToCents(pitchBendRange: 24, pitchBend: 0), -2400)
        XCTAssertEqual(PitchBendMath.pitchBendToCents(pitchBendRange: 24, pitchBend: 16383), 2400, accuracy: 0.5)
    }

    func testFrequencyFromNoteAndPitchBendAtCenterMatchesStandard12TETNote() {
        // MIDI note 69 = A4 = 440Hz by definition, centered pitch bend applies no offset.
        let frequency = PitchBendMath.frequencyFromNoteAndPitchBend(note: 69, pitchBend: 8192, pitchBendRange: 24)
        XCTAssertEqual(frequency, 440, accuracy: 0.0001)
    }

    func testFrequencyFromNoteAndPitchBendAppliesBendOnTopOfTheNote() {
        // Middle C (note 60, 12-TET) bent up by exactly the freqToPB encoding of a pure 3/2
        // fifth above it should decode back to that same just-intonation frequency.
        let middleC = 440 * pow(2, Double(60 - 69) / 12.0)
        let justFifth = middleC * 1.5
        let pb = PitchBendMath.freqToPB(frequency: justFifth, referenceFrequency: middleC, pitchBendRange: 24)
        let decoded = PitchBendMath.frequencyFromNoteAndPitchBend(note: 60, pitchBend: pb, pitchBendRange: 24)
        XCTAssertEqual(decoded, justFifth, accuracy: 0.01)
    }
}
