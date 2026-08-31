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

    // MARK: - centsOffset: defaults to 0, doesn't perturb the five existing transitions

    func testCentsOffsetDefaultsToZeroForEveryExistingTransition() {
        let transitions: [Transition] = [TransFlat(), TransLinear(), TransEaseIn(), TransEaseOut(), TransEaseInEaseOut()]
        for transition in transitions {
            for t in stride(from: 0.0, through: 1.0, by: 0.25) {
                XCTAssertEqual(transition.centsOffset(percentComplete: t), 0)
            }
        }
    }

    func testExistingTransitionsFrequencyUnaffectedByCentsOffsetAddition() {
        // Note.getCurrentFrequency's new centsOffset term must be provably inert for every
        // transition that existed before this change - guards against a regression in the
        // shared formula, not just in centsOffset's own default.
        let part = Part(name: "test")
        let note = part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 440, amplitude: 1, transition: TransLinear())
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.5), 330, accuracy: 0.0001)
    }

    // MARK: - TransRecordedContour

    func testRecordedContourInterpolatesLinearlyBetweenSamples() {
        let transition = TransRecordedContour(samples: [0, 100, 0])
        XCTAssertEqual(transition.centsOffset(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(transition.centsOffset(percentComplete: 0.5), 100, accuracy: 0.0001)
        XCTAssertEqual(transition.centsOffset(percentComplete: 1.0), 0, accuracy: 0.0001)
        XCTAssertEqual(transition.centsOffset(percentComplete: 0.25), 50, accuracy: 0.0001)
    }

    func testRecordedContourWithNoSamplesIsInert() {
        let transition = TransRecordedContour(samples: [])
        XCTAssertEqual(transition.centsOffset(percentComplete: 0.5), 0)
    }

    func testRecordedContourGlidesLinearlyWhenStartAndEndDiffer() {
        // A deliberate portamento kept as one note (startFrequency != endFrequency) rather
        // than split - the contour's own `interpolate` must still produce a genuine glide, per
        // the "deviation from the normal path" design, not just when start == end.
        let part = Part(name: "test")
        let note = part.insertNote(
            startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 440, amplitude: 1,
            transition: TransRecordedContour(samples: [0, 0, 0]))
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.5), 330, accuracy: 0.0001)
    }

    func testRecordedContourAppliesDeviationOnTopOfAStaticPitch() {
        // The ordinary recorded-touch case: startFrequency == endFrequency, so the linear base
        // is a constant and the deviation is the whole recorded shape.
        let part = Part(name: "test")
        let note = part.insertNote(
            startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440, amplitude: 1,
            transition: TransRecordedContour(samples: [0, 1200, 0])) // dips a full octave up at the midpoint
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0), 440, accuracy: 0.0001)
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 0.5), 880, accuracy: 0.0001)
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 1.0), 440, accuracy: 0.0001)
    }

    // MARK: - Part.insertRecordedNote: the two-part coupling helper

    func testInsertRecordedNoteSetsBothTheActiveTransitionAndThePersistentBuffer() {
        let part = Part(name: "test")
        let samples = [0.0, 10, -10, 0]
        let note = part.insertRecordedNote(startTime: 0, endTime: 100, startFrequency: 440, endFrequency: 440, amplitude: 1, recordedPitchBend: samples)

        XCTAssertEqual(note.transitionKind, .recordedContour)
        XCTAssertEqual(note.recordedPitchBend, samples)
        XCTAssertEqual(note.getCurrentFrequency(percentComplete: 1.0 / 3.0), 440 * pow(2, 10.0 / 1200), accuracy: 0.01)
    }

    // MARK: - recordedPitchBend: independent of the active transition, survives persistence

    func testRecordedPitchBendSurvivesJSONRoundTripIndependentlyOfActiveTransitionKind() throws {
        let part = Part(name: "x")
        let note = part.insertNote(
            startTime: 0, endTime: 1000, startFrequency: 440, endFrequency: 440, amplitude: 1,
            transition: TransLinear()) // active transition is .linear, NOT .recordedContour
        note.recordedPitchBend = [0, 50, -50, 0] // but a recorded buffer is still attached

        let dronePart = Part(name: "drone")
        let yPart = Part(name: "y")
        let zPart = Part(name: "z")
        let original = SeqDocument(dronePart: dronePart, xPart: part, yPart: yPart, zPart: zPart)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqDocument.self, from: data)

        let loadedX = Part(name: "x")
        decoded.apply(toDronePart: Part(name: "drone"), xPart: loadedX, yPart: Part(name: "y"), zPart: Part(name: "z"))

        XCTAssertEqual(loadedX.notes.count, 1)
        XCTAssertEqual(loadedX.notes[0].transitionKind, .linear)
        XCTAssertEqual(loadedX.notes[0].recordedPitchBend, [0, 50, -50, 0])
    }

    func testRecordedContourNoteRoundTripsAndPlaysBackIdenticallyAfterReload() throws {
        let part = Part(name: "x")
        let samples = [0.0, 30, -30, 0]
        part.insertRecordedNote(
            startTime: 0, endTime: 1000, startFrequency: 440, endFrequency: 440, amplitude: 1,
            recordedPitchBend: samples)

        let original = SeqDocument(dronePart: Part(name: "drone"), xPart: part, yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqDocument.self, from: data)

        let loadedX = Part(name: "x")
        decoded.apply(toDronePart: Part(name: "drone"), xPart: loadedX, yPart: Part(name: "y"), zPart: Part(name: "z"))

        XCTAssertEqual(loadedX.notes.count, 1)
        XCTAssertEqual(loadedX.notes[0].transitionKind, .recordedContour)
        XCTAssertEqual(loadedX.notes[0].recordedPitchBend, [0, 30, -30, 0])
        // The reconstructed transition must actually be a working TransRecordedContour, not
        // just tagged as one - confirm playback reproduces the original curve.
        XCTAssertEqual(loadedX.notes[0].getCurrentFrequency(percentComplete: 1.0 / 3.0), 440 * pow(2, 30.0 / 1200), accuracy: 0.01)
    }
}
