import XCTest
@testable import GBGCore

final class PartEditingTests: XCTestCase {

    /// Asserts the Part's notes tile [0, end) with no gaps or overlaps - the invariant
    /// ScorePlayer depends on, which every editing operation must preserve.
    private func assertTiles(_ part: Part, file: StaticString = #filePath, line: UInt = #line) {
        var cursor = 0
        for note in part.notes {
            XCTAssertEqual(note.startTime, cursor, "gap or overlap at \(cursor)", file: file, line: line)
            XCTAssertGreaterThan(note.endTime, note.startTime, file: file, line: line)
            cursor = note.endTime
        }
    }

    private func makePartWithTwoNotes() -> (Part, Note, Note) {
        let part = Part(name: "test")
        let a = part.placeNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440)
        let b = part.placeNote(startTime: 300, endTime: 400, startFrequency: 550, endFrequency: 660)
        return (part, a, b)
    }

    // MARK: - placeNote / retile

    func testPlaceNoteBackfillsLeadingRestAndUsesLinearProfile() {
        let part = Part(name: "test")
        let note = part.placeNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440)

        XCTAssertEqual(part.notes.count, 2)
        XCTAssertEqual(part.notes[0].amplitude, 0)
        XCTAssertTrue(part.notes[1] === note)
        XCTAssertEqual(note.transitionKind, .linear)
        assertTiles(part)
    }

    func testPlaceNoteNeverStoresFlat() {
        let part = Part(name: "test")
        let note = part.placeNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440, profile: .flat)
        XCTAssertEqual(note.transitionKind, .linear)
    }

    func testSoundingNotesExcludesRests() {
        let (part, a, b) = makePartWithTwoNotes()
        XCTAssertEqual(part.soundingNotes.count, 2)
        XCTAssertTrue(part.soundingNotes[0] === a)
        XCTAssertTrue(part.soundingNotes[1] === b)
        assertTiles(part)
    }

    // MARK: - setEdge

    func testDraggingEndAwayFromAdjacentNoteLeavesARestNotAGrownNeighbor() {
        let part = Part(name: "test")
        let a = part.placeNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440)
        let b = part.placeNote(startTime: 100, endTime: 200, startFrequency: 550, endFrequency: 550)

        part.setEdge(.end, of: a, to: 50)

        XCTAssertEqual(a.endTime, 50)
        XCTAssertEqual(b.startTime, 100, "independent notes: b must not follow a's edge")
        XCTAssertEqual(part.notes.count, 3)
        XCTAssertEqual(part.notes[1].amplitude, 0)
        assertTiles(part)
    }

    func testEndEdgeStopsAtNextSoundingNote() {
        let (part, a, b) = makePartWithTwoNotes()

        let applied = part.setEdge(.end, of: a, to: 350)

        XCTAssertEqual(applied, 300)
        XCTAssertEqual(a.endTime, 300)
        XCTAssertEqual(b.startTime, 300)
        assertTiles(part)
    }

    func testStartEdgeStopsAtPreviousSoundingNote() {
        let (part, a, b) = makePartWithTwoNotes()

        part.setEdge(.start, of: b, to: 50)

        XCTAssertEqual(b.startTime, 200)
        XCTAssertEqual(a.endTime, 200)
        assertTiles(part)
    }

    func testStartEdgeCanReachZeroAndRestDisappears() {
        let (part, a, _) = makePartWithTwoNotes()

        part.setEdge(.start, of: a, to: -20)

        XCTAssertEqual(a.startTime, 0)
        XCTAssertTrue(part.notes[0] === a)
        assertTiles(part)
    }

    func testEdgeRespectsMinimumLength() {
        let (part, a, _) = makePartWithTwoNotes()

        part.setEdge(.end, of: a, to: 90, minimumNoteLength: 20)

        XCTAssertEqual(a.endTime, 120)
        assertTiles(part)
    }

    func testLastNoteEndIsUnbounded() {
        let (part, _, b) = makePartWithTwoNotes()

        part.setEdge(.end, of: b, to: 10_000)

        XCTAssertEqual(b.endTime, 10_000)
        assertTiles(part)
    }

    func testSetEdgeIgnoresRestsAndForeignNotes() {
        let (part, _, _) = makePartWithTwoNotes()
        let rest = part.notes[0]
        XCTAssertNil(part.setEdge(.end, of: rest, to: 50))
        let other = Part(name: "other").placeNote(startTime: 0, endTime: 10, startFrequency: 1, endFrequency: 1)
        XCTAssertNil(part.setEdge(.end, of: other, to: 50))
    }

    // MARK: - moveNote

    func testMoveNoteKeepsLengthAndClampsBetweenNeighbors() {
        let (part, a, b) = makePartWithTwoNotes()

        part.moveNote(a, toStart: 260)
        XCTAssertEqual(a.startTime, 200)
        XCTAssertEqual(a.endTime, 300)

        part.moveNote(b, toStart: 1000)
        XCTAssertEqual(b.startTime, 1000)
        XCTAssertEqual(b.endTime, 1100)
        assertTiles(part)
    }

    func testMoveFirstNoteToZero() {
        let (part, a, _) = makePartWithTwoNotes()
        part.moveNote(a, toStart: -50)
        XCTAssertEqual(a.startTime, 0)
        XCTAssertEqual(a.endTime, 100)
        assertTiles(part)
    }

    // MARK: - removeNote

    func testRemoveNoteMergesSurroundingRests() {
        let (part, a, b) = makePartWithTwoNotes()

        part.removeNote(a)

        XCTAssertEqual(part.soundingNotes.count, 1)
        XCTAssertTrue(part.soundingNotes[0] === b)
        XCTAssertEqual(part.notes.count, 2)
        assertTiles(part)
    }

    func testRemoveLastNoteTrimsTrailingSilence() {
        let (part, _, b) = makePartWithTwoNotes()
        part.removeNote(b)
        XCTAssertEqual(part.getLengthInSamples(), 200)
    }

    // MARK: - normalizeFlatTransitions

    func testFlatNoteBecomesEqualPitchLinearWithSameSound() {
        let part = Part(name: "test")
        let note = part.insertNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 880, amplitude: 1)
        XCTAssertEqual(note.transitionKind, .flat)
        let before = note.getCurrentFrequency(percentComplete: 0.7)

        part.normalizeFlatTransitions()

        XCTAssertEqual(note.transitionKind, .linear)
        XCTAssertEqual(note.endFrequency, 440)
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.7), before)
    }

    func testNormalizeLeavesOtherProfilesAlone() {
        let part = Part(name: "test")
        let note = part.placeNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 880, profile: .easeIn)
        part.normalizeFlatTransitions()
        XCTAssertEqual(note.transitionKind, .easeIn)
        XCTAssertEqual(note.endFrequency, 880)
    }
}

final class PitchEntryTests: XCTestCase {
    private let root = 261.6255653005986
    private let scale = Scale(limit: 11, highestRatio: 3.0, lowestRatio: 0.5)

    func testSnapLandsOnNearestRatio() {
        let snapped = scale.snappedFrequency(root * 1.251, rootFrequency: root)
        XCTAssertEqual(snapped, root * 5 / 4, accuracy: 1e-9)
    }

    func testSnapBelowRoot() {
        let snapped = scale.snappedFrequency(root * 0.6668, rootFrequency: root)
        XCTAssertEqual(snapped, root * 2 / 3, accuracy: 1e-9)
    }

    func testParseRatio() {
        XCTAssertEqual(PitchText.parse("5/4", rootFrequency: root)!, root * 1.25, accuracy: 1e-9)
        XCTAssertEqual(PitchText.parse(" 3 / 2 ", rootFrequency: root)!, root * 1.5, accuracy: 1e-9)
    }

    func testParseHz() {
        XCTAssertEqual(PitchText.parse("440", rootFrequency: root), 440)
        XCTAssertEqual(PitchText.parse("440 Hz", rootFrequency: root), 440)
        XCTAssertEqual(PitchText.parse("261.5hz", rootFrequency: root), 261.5)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(PitchText.parse("", rootFrequency: root))
        XCTAssertNil(PitchText.parse("abc", rootFrequency: root))
        XCTAssertNil(PitchText.parse("0/4", rootFrequency: root))
        XCTAssertNil(PitchText.parse("5/", rootFrequency: root))
        XCTAssertNil(PitchText.parse("-3", rootFrequency: root))
    }

    func testFormatShowsReducedRatioOnScale() {
        XCTAssertEqual(PitchText.format(root * 5 / 4, rootFrequency: root, scale: scale), "5/4")
        XCTAssertEqual(PitchText.format(root, rootFrequency: root, scale: scale), "1/1")
        XCTAssertEqual(PitchText.format(root * 2 / 3, rootFrequency: root, scale: scale), "2/3")
    }

    func testFormatShowsHzOffScale() {
        XCTAssertEqual(PitchText.format(root * 1.2345, rootFrequency: root, scale: scale), String(format: "%.2f Hz", root * 1.2345))
    }

    func testFormatParseRoundTrip() {
        let text = PitchText.format(root * 7 / 4, rootFrequency: root, scale: scale)
        XCTAssertEqual(PitchText.parse(text, rootFrequency: root)!, root * 7 / 4, accuracy: 1e-9)
    }
}

final class PartSnapshotTests: XCTestCase {
    func testRestoreUndoesEditsAndKeepsNoteIdentity() {
        let part = Part(name: "test")
        let a = part.placeNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440)
        let snapshot = part.snapshot()

        part.setEdge(.end, of: a, to: 500)
        a.endFrequency = 880
        a.selectTransition(.easeIn)
        part.placeNote(startTime: 600, endTime: 700, startFrequency: 330, endFrequency: 330)

        part.restore(snapshot)

        XCTAssertEqual(part.soundingNotes.count, 1)
        XCTAssertTrue(part.soundingNotes[0] === a)
        XCTAssertEqual(a.endTime, 200)
        XCTAssertEqual(a.endFrequency, 440)
        XCTAssertEqual(a.transitionKind, .linear)
        XCTAssertEqual(part.notes.first?.startTime, 0)
        XCTAssertEqual(part.getLengthInSamples(), 200)
    }

    func testRestoreBringsBackDeletedNote() {
        let part = Part(name: "test")
        let a = part.placeNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440)
        let snapshot = part.snapshot()
        part.removeNote(a)
        XCTAssertTrue(part.soundingNotes.isEmpty)
        part.restore(snapshot)
        XCTAssertTrue(part.soundingNotes.first === a)
    }

    func testRestoreBringsBackRecordedBuffer() {
        let part = Part(name: "test")
        let a = part.insertRecordedNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440, amplitude: 1, recordedPitchBend: [0, 10, 20])
        let snapshot = part.snapshot()
        a.selectTransition(.linear)
        a.recordedPitchBend = nil
        part.restore(snapshot)
        XCTAssertEqual(a.recordedPitchBend, [0, 10, 20])
        XCTAssertEqual(a.transitionKind, .recordedContour)
    }
}

final class NoteLookupAndEndpointTests: XCTestCase {
    func testNoteAtUsesHalfOpenSpansAndLeavesCursorAlone() {
        let part = Part(name: "test")
        let a = part.placeNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440)
        let b = part.placeNote(startTime: 200, endTime: 300, startFrequency: 550, endFrequency: 550)
        part.currentNoteIndex = 2
        XCTAssertEqual(part.note(at: 0)?.amplitude, 0) // leading rest
        XCTAssertTrue(part.note(at: 100) === a)
        XCTAssertTrue(part.note(at: 199) === a)
        XCTAssertTrue(part.note(at: 200) === b)
        XCTAssertNil(part.note(at: 300))
        XCTAssertNil(Part(name: "empty").note(at: 0))
        XCTAssertEqual(part.currentNoteIndex, 2)
    }

    private func recordedNote() -> Note {
        // A raw capture: base at middle C, contour from +700 to +400 cents.
        let part = Part(name: "test")
        return part.insertRecordedNote(startTime: 0, endTime: 100, startFrequency: 261.63, endFrequency: 261.63, amplitude: 1, recordedPitchBend: [700, 500, 400])
    }

    func testEndpointsIncludeRecordedContour() {
        let note = recordedNote()
        XCTAssertEqual(note.endpointFrequency(.start), 261.63 * pow(2, 7.0 / 12), accuracy: 1e-6)
        XCTAssertEqual(note.endpointFrequency(.end), 261.63 * pow(2, 4.0 / 12), accuracy: 1e-6)
    }

    func testSetEndpointHitsTheSoundingPitch() {
        let note = recordedNote()
        note.setEndpointFrequency(.start, to: 440)
        note.setEndpointFrequency(.end, to: 330)
        XCTAssertEqual(note.endpointFrequency(.start), 440, accuracy: 1e-9)
        XCTAssertEqual(note.endpointFrequency(.end), 330, accuracy: 1e-9)

        let plain = Part(name: "p").placeNote(startTime: 0, endTime: 10, startFrequency: 440, endFrequency: 440, profile: .easeIn)
        plain.setEndpointFrequency(.end, to: 660)
        XCTAssertEqual(plain.endFrequency, 660)
        XCTAssertEqual(plain.endpointFrequency(.end), 660, accuracy: 1e-9)
    }

    func testSetEndpointOnLegacyFlatConvertsFirst() {
        let note = Part(name: "p").insertNote(startTime: 0, endTime: 10, startFrequency: 440, endFrequency: 999, amplitude: 1)
        note.setEndpointFrequency(.end, to: 550)
        XCTAssertEqual(note.transitionKind, .linear)
        XCTAssertEqual(note.startFrequency, 440)
        XCTAssertEqual(note.endpointFrequency(.end), 550, accuracy: 1e-9)
    }

    func testProfileSwitchKeepsEndpointsAndRoundTrips() {
        let note = recordedNote()
        let start = note.endpointFrequency(.start), end = note.endpointFrequency(.end)
        let middle = note.getCurrentFrequency(percentComplete: 0.5)

        note.selectProfile(.linear)
        XCTAssertEqual(note.endpointFrequency(.start), start, accuracy: 1e-9)
        XCTAssertEqual(note.endpointFrequency(.end), end, accuracy: 1e-9)

        note.selectProfile(.recordedContour)
        XCTAssertEqual(note.startFrequency, 261.63, accuracy: 1e-9)
        XCTAssertEqual(note.endFrequency, 261.63, accuracy: 1e-9)
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.5), middle, accuracy: 1e-9)
    }
}
