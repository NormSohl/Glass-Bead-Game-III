import XCTest
@testable import GBGCore

final class SeqDocumentTests: XCTestCase {

    // MARK: - TransitionKind/EnvelopeKind classification

    func testTransitionKindClassifiesEachConcreteSubclass() {
        XCTAssertEqual(TransitionKind.kind(of: TransFlat()), .flat)
        XCTAssertEqual(TransitionKind.kind(of: TransLinear()), .linear)
        XCTAssertEqual(TransitionKind.kind(of: TransEaseIn()), .easeIn)
        XCTAssertEqual(TransitionKind.kind(of: TransEaseOut()), .easeOut)
        XCTAssertEqual(TransitionKind.kind(of: TransEaseInEaseOut()), .easeInEaseOut)
    }

    func testTransitionKindMakeTransitionRoundTrips() {
        for kind in TransitionKind.allCases {
            XCTAssertEqual(TransitionKind.kind(of: kind.makeTransition()), kind)
        }
    }

    func testEnvelopeKindClassifiesEachConcreteSubclass() {
        XCTAssertEqual(EnvelopeKind.kind(of: EnvFlat()), .flat)
        XCTAssertEqual(EnvelopeKind.kind(of: EnvHump()), .hump)
    }

    func testEnvelopeKindMakeEnvelopeRoundTrips() {
        for kind in EnvelopeKind.allCases {
            XCTAssertEqual(EnvelopeKind.kind(of: kind.makeEnvelope()), kind)
        }
    }

    // MARK: - Note.transitionKind/envelopeKind

    func testNoteExposesItsTransitionAndEnvelopeKind() {
        let part = Part(name: "test")
        let note = part.insertNote(
            startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 440, amplitude: 1,
            transition: TransEaseInEaseOut(), envelope: EnvHump())

        XCTAssertEqual(note.transitionKind, .easeInEaseOut)
        XCTAssertEqual(note.envelopeKind, .hump)
    }

    // MARK: - SeqDocument round trip through JSON

    func testSeqDocumentRoundTripsThroughJSONPreservingAllNoteFields() throws {
        let dronePart = Part(name: "drone")
        dronePart.insertNote(startTime: 0, endTime: 1000, startFrequency: 220, endFrequency: 220, amplitude: 0.5, transition: TransFlat(), envelope: EnvFlat())

        let xPart = Part(name: "x")
        xPart.insertNote(startTime: 0, endTime: 500, startFrequency: 440, endFrequency: 660, amplitude: 1.0, transition: TransLinear(), envelope: EnvHump())
        xPart.insertNote(startTime: 500, endTime: 1000, startFrequency: 660, endFrequency: 330, amplitude: 0.8, transition: TransEaseIn(), envelope: EnvFlat())

        let yPart = Part(name: "y")
        yPart.insertNote(startTime: 0, endTime: 1000, startFrequency: 550, endFrequency: 550, amplitude: 0.7, transition: TransEaseOut(), envelope: EnvHump())

        let zPart = Part(name: "z")
        zPart.insertNote(startTime: 0, endTime: 1000, startFrequency: 880, endFrequency: 440, amplitude: 0.9, transition: TransEaseInEaseOut(), envelope: EnvFlat())

        let original = SeqDocument(dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqDocument.self, from: data)

        // Apply onto fresh Part instances (mirroring how Seq applies a loaded document onto its
        // own existing dronePart/xPart/yPart/zPart) rather than inspecting the DTO directly, so
        // this also exercises PartDTO.apply's insertNote-based rebuild.
        let loadedDrone = Part(name: "drone")
        let loadedX = Part(name: "x")
        let loadedY = Part(name: "y")
        let loadedZ = Part(name: "z")
        decoded.apply(toDronePart: loadedDrone, xPart: loadedX, yPart: loadedY, zPart: loadedZ)

        XCTAssertEqual(loadedDrone.notes.count, 1)
        XCTAssertEqual(loadedDrone.notes[0].startFrequency, 220)
        XCTAssertEqual(loadedDrone.notes[0].amplitude, 0.5)
        XCTAssertEqual(loadedDrone.notes[0].transitionKind, .flat)
        XCTAssertEqual(loadedDrone.notes[0].envelopeKind, .flat)

        XCTAssertEqual(loadedX.notes.count, 2)
        XCTAssertEqual(loadedX.notes[0].startTime, 0)
        XCTAssertEqual(loadedX.notes[0].endTime, 500)
        XCTAssertEqual(loadedX.notes[0].startFrequency, 440)
        XCTAssertEqual(loadedX.notes[0].endFrequency, 660)
        XCTAssertEqual(loadedX.notes[0].transitionKind, .linear)
        XCTAssertEqual(loadedX.notes[0].envelopeKind, .hump)
        XCTAssertEqual(loadedX.notes[1].startTime, 500)
        XCTAssertEqual(loadedX.notes[1].endTime, 1000)
        XCTAssertEqual(loadedX.notes[1].transitionKind, .easeIn)
        XCTAssertEqual(loadedX.notes[1].envelopeKind, .flat)

        XCTAssertEqual(loadedY.notes.count, 1)
        XCTAssertEqual(loadedY.notes[0].transitionKind, .easeOut)
        XCTAssertEqual(loadedY.notes[0].envelopeKind, .hump)

        XCTAssertEqual(loadedZ.notes.count, 1)
        XCTAssertEqual(loadedZ.notes[0].transitionKind, .easeInEaseOut)
        XCTAssertEqual(loadedZ.notes[0].amplitude, 0.9)
    }

    func testPartDTOApplyClearsWhateverThePartPreviouslyHeld() {
        let part = Part(name: "test")
        part.insertNote(startTime: 0, endTime: 100, startFrequency: 110, endFrequency: 110, amplitude: 1)
        XCTAssertEqual(part.notes.count, 1)

        let replacement = PartDTO(notes: [
            NoteDTO(startTime: 0, endTime: 50, startFrequency: 220, endFrequency: 220, amplitude: 1, transitionKind: .flat, envelopeKind: .flat)
        ])
        replacement.apply(to: part)

        XCTAssertEqual(part.notes.count, 1)
        XCTAssertEqual(part.notes[0].endTime, 50)
        XCTAssertEqual(part.notes[0].startFrequency, 220)
    }
}
