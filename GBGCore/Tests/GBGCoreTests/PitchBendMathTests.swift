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
}
