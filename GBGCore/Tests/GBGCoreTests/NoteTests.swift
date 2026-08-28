import XCTest
@testable import GBGCore

final class NoteTests: XCTestCase {

    func testPercentCompleteIsZeroAtStartAndOneAtEnd() {
        let note = Note(startTime: 100, endTime: 200, startFrequency: 220, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(note.percentComplete(at: 100), 0.0)
        XCTAssertEqual(note.percentComplete(at: 200), 1.0)
        XCTAssertEqual(note.percentComplete(at: 150), 0.5)
    }

    func testGetCurrentFrequencyUsesTheTransitionCurve() {
        let note = Note(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 440, amplitude: 1)
        note.transition = TransLinear()

        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.5), 330, accuracy: 1e-9)
    }

    func testGetCurrentAmplitudeUsesTheEnvelopeCurve() {
        let note = Note(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 0.8)
        note.envelope = EnvFlat()

        XCTAssertEqual(note.getCurrentAmplitude(percentComplete: 0.5), 0.8, accuracy: 1e-9)
    }
}
