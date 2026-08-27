import XCTest
@testable import GBGCore

final class NoteListTests: XCTestCase {
    func testListCoversMidiNotes12Through108() {
        let noteList = NoteList()
        // 12...108 inclusive is 97 notes
        XCTAssertEqual(noteList.list.count, 97)
        XCTAssertEqual(noteList.list.first?.noteMIDI, 12)
        XCTAssertEqual(noteList.list.last?.noteMIDI, 108)
    }

    func testMidiNote69IsConcertA440() {
        let noteList = NoteList()
        let a4 = noteList.list.first { $0.noteMIDI == 69 }
        XCTAssertNotNil(a4)
        XCTAssertEqual(a4?.noteFreq ?? 0, 440.0, accuracy: 0.0001)
        XCTAssertEqual(a4?.noteName, "A")
    }

    func testSearchListExactMatchReturnsSameNoteForLowAndHigh() {
        let noteList = NoteList()
        let result = noteList.searchList(frequency: 440.0)
        XCTAssertEqual(result.lowerNote.noteMIDI, result.higherNote.noteMIDI)
        XCTAssertEqual(result.lowerNote.noteMIDI, 69)
    }

    func testSearchListBetweenNotesReturnsAdjacentBounds() {
        let noteList = NoteList()
        // pick a frequency strictly between MIDI 69 (440 Hz) and MIDI 70
        let midiNote69Freq = 440.0
        let midiNote70Freq = pow(2, Double(70 - 69) / 12) * 440.0
        let between = (midiNote69Freq + midiNote70Freq) / 2

        let result = noteList.searchList(frequency: between)
        XCTAssertEqual(result.lowerNote.noteMIDI, 69)
        XCTAssertEqual(result.higherNote.noteMIDI, 70)
    }

    func testSearchListBelowRangeReturnsDefaultEntries() {
        let noteList = NoteList()
        let result = noteList.searchList(frequency: 1.0) // far below MIDI note 12
        XCTAssertEqual(result.lowerNote.noteMIDI, 0)
        XCTAssertEqual(result.higherNote.noteMIDI, 0)
    }

    func testSearchListAboveRangeReturnsDefaultEntries() {
        let noteList = NoteList()
        let result = noteList.searchList(frequency: 999_999.0) // far above MIDI note 108
        XCTAssertEqual(result.lowerNote.noteMIDI, 0)
        XCTAssertEqual(result.higherNote.noteMIDI, 0)
    }
}
