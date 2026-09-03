import XCTest
@testable import GBGCore

final class SeqMIDICodecTests: XCTestCase {

    // ticksPerSecond inside SeqMIDICodec is 10_000 - using that same rate for both encode's
    // sampleRate and decode's targetSampleRate makes sample<->tick conversion exact (no
    // rounding), so tests can assert exact startTime/endTime instead of using tolerances.
    private let sampleRate = 10_000.0

    private func makeScale(root: Double = 261.6255653005986) -> MIDIScaleDefinition {
        MIDIScaleDefinition(limit: 5, highestRatio: 2.0, lowestRatio: 1.0, rootFrequency: root)
    }

    // MARK: - Basic note round trip

    func testRoundTripsAParametricNoteExactly() throws {
        let xPart = Part(name: "x")
        xPart.insertNote(
            startTime: 0, endTime: 10_000, startFrequency: 440, endFrequency: 660, amplitude: 0.75,
            transition: TransEaseInEaseOut(), envelope: EnvHump())

        let original = SeqDocument(dronePart: Part(name: "drone"), xPart: xPart, yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: original, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertEqual(result.document.xPart.notes.count, 1)
        let note = result.document.xPart.notes[0]
        XCTAssertEqual(note.startTime, 0)
        XCTAssertEqual(note.endTime, 10_000)
        // The per-note metadata block carries the exact Doubles - not the tick/cents-quantized
        // standard bend stream - so this must be bit-exact, not just approximately right.
        XCTAssertEqual(note.startFrequency, 440)
        XCTAssertEqual(note.endFrequency, 660)
        XCTAssertEqual(note.amplitude, 0.75)
        XCTAssertEqual(note.transitionKind, .easeInEaseOut)
        XCTAssertEqual(note.envelopeKind, .hump)
    }

    func testRoundTripsARecordedPitchBendNoteExactly() throws {
        let xPart = Part(name: "x")
        let samples = [0.0, 25, 50, 25, 0]
        xPart.insertRecordedNote(startTime: 0, endTime: 5_000, startFrequency: 440, endFrequency: 440, amplitude: 1.0, recordedPitchBend: samples)

        let original = SeqDocument(dronePart: Part(name: "drone"), xPart: xPart, yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: original, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        let note = result.document.xPart.notes.first { $0.amplitude > 0 }
        XCTAssertEqual(note?.transitionKind, .recordedContour)
        XCTAssertEqual(note?.recordedPitchBend, samples)

        // Confirm the buffer actually reconstructs a working contour (matching how
        // PartDTO.apply builds a real Note from this same NoteDTO), not just a tagged kind.
        let reconstructed = Part(name: "check")
        result.document.xPart.apply(to: reconstructed)
        let playedNote = try XCTUnwrap(reconstructed.notes.first { $0.amplitude > 0 })
        XCTAssertEqual(playedNote.getCurrentFrequency(percentComplete: 0.5), 440 * pow(2, 50.0 / 1200), accuracy: 0.01)
    }

    // MARK: - Silence gaps

    func testPreservesASilenceGapBetweenTwoNotes() throws {
        let xPart = Part(name: "x")
        xPart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 440, endFrequency: 440, amplitude: 1)
        // [1000, 2000) is left as silence (a zero-amplitude Note) - Part's normal tiling
        // invariant, matching how a live deletion already represents a gap.
        xPart.insertNote(startTime: 1_000, endTime: 2_000, startFrequency: 440, endFrequency: 440, amplitude: 0)
        xPart.insertNote(startTime: 2_000, endTime: 3_000, startFrequency: 550, endFrequency: 550, amplitude: 1)

        let original = SeqDocument(dronePart: Part(name: "drone"), xPart: xPart, yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: original, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        let notes = result.document.xPart.notes
        XCTAssertEqual(notes.count, 3, "the middle silence must come back as an explicit note, not a gap")
        XCTAssertEqual(notes[0].startTime, 0)
        XCTAssertEqual(notes[0].endTime, 1_000)
        XCTAssertGreaterThan(notes[0].amplitude, 0)

        XCTAssertEqual(notes[1].startTime, 1_000)
        XCTAssertEqual(notes[1].endTime, 2_000)
        XCTAssertEqual(notes[1].amplitude, 0)

        XCTAssertEqual(notes[2].startTime, 2_000)
        XCTAssertEqual(notes[2].endTime, 3_000)
        XCTAssertGreaterThan(notes[2].amplitude, 0)

        // Contiguous tiling: no gap or overlap anywhere in the reconstructed Part.
        for i in 1..<notes.count {
            XCTAssertEqual(notes[i].startTime, notes[i - 1].endTime)
        }
    }

    func testALeadingSilenceGapBeforeTheFirstNoteIsBackfilled() throws {
        let xPart = Part(name: "x")
        xPart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 440, endFrequency: 440, amplitude: 0)
        xPart.insertNote(startTime: 1_000, endTime: 2_000, startFrequency: 440, endFrequency: 440, amplitude: 1)

        let original = SeqDocument(dronePart: Part(name: "drone"), xPart: xPart, yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: original, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertEqual(result.document.xPart.notes.count, 2)
        XCTAssertEqual(result.document.xPart.notes[0].startTime, 0)
        XCTAssertEqual(result.document.xPart.notes[0].amplitude, 0)
    }

    // MARK: - All four voices

    func testAllFourVoicesRoundTripIndependently() throws {
        let dronePart = Part(name: "drone")
        dronePart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 220, endFrequency: 220, amplitude: 0.5)
        let xPart = Part(name: "x")
        xPart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 440, endFrequency: 440, amplitude: 1)
        let yPart = Part(name: "y")
        yPart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 550, endFrequency: 550, amplitude: 1)
        let zPart = Part(name: "z")
        zPart.insertNote(startTime: 0, endTime: 1_000, startFrequency: 880, endFrequency: 880, amplitude: 1)

        let original = SeqDocument(dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)
        let data = SeqMIDICodec.encode(document: original, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertEqual(result.document.dronePart.notes.first?.startFrequency, 220)
        XCTAssertEqual(result.document.xPart.notes.first?.startFrequency, 440)
        XCTAssertEqual(result.document.yPart.notes.first?.startFrequency, 550)
        XCTAssertEqual(result.document.zPart.notes.first?.startFrequency, 880)
    }

    // MARK: - Document metadata: scale + tempo

    func testRoundTripsScaleMetadataExactly() throws {
        let scale = MIDIScaleDefinition(limit: 11, highestRatio: 2.5, lowestRatio: 0.9, rootFrequency: 330.125)
        let document = SeqDocument(dronePart: Part(name: "drone"), xPart: Part(name: "x"), yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: document, scale: scale, sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertEqual(result.scale, scale)
    }

    func testRoundTripsTempoInfoWhenPresent() throws {
        let tempoInfo = TempoInfo(bpm: 96.5, downbeatOffset: 4410, confidence: 0.82)
        let document = SeqDocument(dronePart: Part(name: "drone"), xPart: Part(name: "x"), yPart: Part(name: "y"), zPart: Part(name: "z"), tempoInfo: tempoInfo)
        let data = SeqMIDICodec.encode(document: document, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertEqual(result.document.tempoInfo, tempoInfo)
    }

    func testTempoInfoIsNilWhenTheDocumentNeverHadOne() throws {
        let document = SeqDocument(dronePart: Part(name: "drone"), xPart: Part(name: "x"), yPart: Part(name: "y"), zPart: Part(name: "z"))
        let data = SeqMIDICodec.encode(document: document, scale: makeScale(), sampleRate: sampleRate)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertNil(result.document.tempoInfo)
    }

    // MARK: - A plain third-party file with no custom metadata at all

    func testDecodingAFileWithNoCustomMetadataFallsBackToTheStandardBendStream() throws {
        // Hand-built via StandardMIDIFile directly (not SeqMIDICodec.encode) - simulates a .mid
        // authored by some other tool, carrying only the universal note-on/pitch-bend/note-off
        // events our own writer also emits, none of our Sequencer-Specific metadata.
        let track = MIDIFileTrack(events: [
            MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 1, note: 60, velocity: 127)),
            MIDIFileEvent(deltaTicks: 0, kind: .pitchBend(channel: 1, value: PitchBendMath.freqToPB(frequency: 440, referenceFrequency: 261.6255653005986, pitchBendRange: SeqMIDICodec.pitchBendRangeSemitones))),
            MIDIFileEvent(deltaTicks: 5_000, kind: .noteOff(channel: 1, note: 60)),
        ])
        let data = StandardMIDIFile.write(tracks: [track], ticksPerQuarterNote: 10_000)
        let result = try SeqMIDICodec.decode(data, targetSampleRate: sampleRate)

        XCTAssertNil(result.scale, "no scale metadata was present in this file")
        XCTAssertEqual(result.document.xPart.notes.count, 1)
        XCTAssertEqual(result.document.xPart.notes[0].startFrequency, 440, accuracy: 0.5)
    }
}
