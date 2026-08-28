import XCTest
@testable import GBGCore

final class PartTests: XCTestCase {

    private func makeSilentPart(length: Int) -> Part {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: length, startFrequency: 0, endFrequency: 0, amplitude: 0)
        return part
    }

    // MARK: - insertNote

    func testInsertNoteIntoEmptyPart() {
        let part = Part(name: "test")
        let note = part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(part.notes.count, 1)
        XCTAssertTrue(part.notes[0] === note)
        XCTAssertEqual(part.notes[0].startTime, 100)
        XCTAssertEqual(part.notes[0].endTime, 200)
    }

    func testInsertNoteSplitsAFullyContainingNote() {
        let part = makeSilentPart(length: 1000)

        part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(part.notes.count, 3)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 100)
        XCTAssertEqual(part.notes[0].amplitude, 0)

        XCTAssertEqual(part.notes[1].startTime, 100)
        XCTAssertEqual(part.notes[1].endTime, 200)
        XCTAssertEqual(part.notes[1].startFrequency, 440)

        XCTAssertEqual(part.notes[2].startTime, 200)
        XCTAssertEqual(part.notes[2].endTime, 1000)
        XCTAssertEqual(part.notes[2].amplitude, 0)
    }

    func testInsertNoteTrimsANoteStraddlingTheLeftEdge() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 200, startFrequency: 220, endFrequency: 220, amplitude: 1)

        part.insertNote(startTime: 150, endTime: 300, startFrequency: 440, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 150) // trimmed, own startTime/pitch untouched
        XCTAssertEqual(part.notes[1].startTime, 150)
        XCTAssertEqual(part.notes[1].endTime, 300)
    }

    func testInsertNoteTrimsANoteStraddlingTheRightEdge() {
        let part = Part(name: "test")
        part.insertNote(startTime: 200, endTime: 400, startFrequency: 220, endFrequency: 220, amplitude: 1)

        part.insertNote(startTime: 100, endTime: 300, startFrequency: 440, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 100)
        XCTAssertEqual(part.notes[0].endTime, 300)
        XCTAssertEqual(part.notes[1].startTime, 300) // trimmed, own endTime/pitch untouched
        XCTAssertEqual(part.notes[1].endTime, 400)
    }

    func testInsertNoteFullyReplacesANoteItContains() {
        let part = Part(name: "test")
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 220, endFrequency: 220, amplitude: 1)

        part.insertNote(startTime: 0, endTime: 300, startFrequency: 440, endFrequency: 440, amplitude: 1)

        XCTAssertEqual(part.notes.count, 1)
        XCTAssertEqual(part.notes[0].startFrequency, 440)
    }

    func testDeletingANoteLeavesASilenceBlockPreservingNeighborBoundaries() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)
        part.insertNote(startTime: 200, endTime: 300, startFrequency: 330, endFrequency: 330, amplitude: 1)

        // "delete" the middle note: overwrite its exact span with a silent note
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 0, endFrequency: 0, amplitude: 0)

        XCTAssertEqual(part.notes.count, 3)
        XCTAssertEqual(part.notes[0].endTime, 100) // left neighbor's own boundary untouched
        XCTAssertEqual(part.notes[1].amplitude, 0)
        XCTAssertEqual(part.notes[2].startTime, 200) // right neighbor's own boundary untouched
    }

    // MARK: - insertTime (ripple insert)

    func testInsertTimeShiftsNotesAtOrAfterThePointForward() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)

        part.insertTime(at: 100, duration: 50)

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 100) // before the insertion point - untouched
        XCTAssertEqual(part.notes[1].startTime, 150) // shifted forward
        XCTAssertEqual(part.notes[1].endTime, 250)
    }

    func testInsertTimeSplitsAStraddledNoteContinuousAtTheCut() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 440, amplitude: 1, transition: TransLinear())

        part.insertTime(at: 50, duration: 20)

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 50)
        XCTAssertEqual(part.notes[0].startFrequency, 220)
        XCTAssertEqual(part.notes[0].endFrequency, 330, accuracy: 1e-9) // halfway through 220->440

        XCTAssertEqual(part.notes[1].startTime, 70) // shifted by duration
        XCTAssertEqual(part.notes[1].endTime, 120)
        XCTAssertEqual(part.notes[1].startFrequency, 330, accuracy: 1e-9) // continuous at the cut
        XCTAssertEqual(part.notes[1].endFrequency, 440)
    }

    // MARK: - deleteTime (ripple delete)

    func testDeleteTimeClosesTheGapAndShiftsTheRemainderBack() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)
        part.insertNote(startTime: 200, endTime: 300, startFrequency: 330, endFrequency: 330, amplitude: 1)

        part.deleteTime(from: 100, duration: 100) // removes the whole middle note

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 100)
        XCTAssertEqual(part.notes[1].startTime, 100) // shifted back to close the gap
        XCTAssertEqual(part.notes[1].endTime, 200)
        XCTAssertEqual(part.notes[1].startFrequency, 330)
    }

    func testDeleteTimeSplitsAContainingNoteBeforeClosingTheGap() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 200, startFrequency: 220, endFrequency: 440, amplitude: 1, transition: TransLinear())

        part.deleteTime(from: 50, duration: 100) // removes [50,150) from inside the single note

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].startTime, 0)
        XCTAssertEqual(part.notes[0].endTime, 50)
        XCTAssertEqual(part.notes[0].endFrequency, 275, accuracy: 1e-9) // 25% through 220->440

        XCTAssertEqual(part.notes[1].startTime, 50) // shifted back from 150
        XCTAssertEqual(part.notes[1].endTime, 100) // shifted back from 200
        XCTAssertEqual(part.notes[1].startFrequency, 385, accuracy: 1e-9) // 75% through 220->440
    }

    // MARK: - length and playback traversal

    func testGetLengthInSamplesIsTheLastNotesEndTime() {
        let part = Part(name: "test")
        XCTAssertEqual(part.getLengthInSamples(), 0)

        part.insertNote(startTime: 0, endTime: 500, startFrequency: 220, endFrequency: 220, amplitude: 1)
        XCTAssertEqual(part.getLengthInSamples(), 500)
    }

    func testGetCurrentNoteAndGetNextNoteTraversal() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
        part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)

        let current = part.getCurrentNote(timeSlice: 50)
        XCTAssertEqual(current?.startFrequency, 220)

        let next = part.getNextNote()
        XCTAssertEqual(next?.startFrequency, 440)

        XCTAssertNil(part.getNextNote())
    }
}
