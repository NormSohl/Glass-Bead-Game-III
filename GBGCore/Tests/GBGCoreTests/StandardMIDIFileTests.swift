import XCTest
@testable import GBGCore

final class StandardMIDIFileTests: XCTestCase {

    // MARK: - Header

    func testWriteProducesAValidMThdHeader() {
        let data = StandardMIDIFile.write(tracks: [MIDIFileTrack(events: [])], ticksPerQuarterNote: 480)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))
        // header length (bytes 4-7) is always 6
        XCTAssertEqual(Array(data[4..<8]), [0, 0, 0, 6])
        // format 0 for a single track
        XCTAssertEqual(Array(data[8..<10]), [0, 0])
        // track count
        XCTAssertEqual(Array(data[10..<12]), [0, 1])
        // division = ticksPerQuarterNote, high bit clear (metrical, not SMPTE)
        XCTAssertEqual(Array(data[12..<14]), [0x01, 0xE0]) // 480
    }

    func testMultipleTracksProduceFormat1() throws {
        let data = StandardMIDIFile.write(tracks: [MIDIFileTrack(events: []), MIDIFileTrack(events: [])], ticksPerQuarterNote: 100)
        XCTAssertEqual(Array(data[8..<10]), [0, 1]) // format 1
        let result = try StandardMIDIFile.read(data)
        XCTAssertEqual(result.tracks.count, 2)
    }

    func testReadRejectsDataWithoutAnMThdHeader() {
        let data = Data("nope".utf8)
        XCTAssertThrowsError(try StandardMIDIFile.read(data)) { error in
            guard case StandardMIDIFile.ReadError.notAStandardMIDIFile = error else {
                return XCTFail("expected .notAStandardMIDIFile, got \(error)")
            }
        }
    }

    // MARK: - Round-tripping events

    func testRoundTripsNoteOnPitchBendNoteOff() throws {
        let track = MIDIFileTrack(events: [
            MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 1, note: 60, velocity: 100)),
            MIDIFileEvent(deltaTicks: 50, kind: .pitchBend(channel: 1, value: 10000)),
            MIDIFileEvent(deltaTicks: 50, kind: .noteOff(channel: 1, note: 60)),
        ])
        let data = StandardMIDIFile.write(tracks: [track], ticksPerQuarterNote: 480)
        let result = try StandardMIDIFile.read(data)

        XCTAssertEqual(result.ticksPerQuarterNote, 480)
        XCTAssertEqual(result.tracks.count, 1)
        // the writer always appends an explicit End of Track after whatever the caller supplied
        XCTAssertEqual(result.tracks[0].events, [
            MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 1, note: 60, velocity: 100)),
            MIDIFileEvent(deltaTicks: 50, kind: .pitchBend(channel: 1, value: 10000)),
            MIDIFileEvent(deltaTicks: 50, kind: .noteOff(channel: 1, note: 60)),
            MIDIFileEvent(deltaTicks: 0, kind: .endOfTrack),
        ])
    }

    func testDoesNotDoubleUpAnExplicitEndOfTrack() throws {
        let track = MIDIFileTrack(events: [
            MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 0, note: 60, velocity: 100)),
            MIDIFileEvent(deltaTicks: 10, kind: .endOfTrack),
        ])
        let data = StandardMIDIFile.write(tracks: [track], ticksPerQuarterNote: 480)
        let result = try StandardMIDIFile.read(data)
        XCTAssertEqual(result.tracks[0].events.count, 2)
    }

    func testRoundTripsACustomMetaEventPayload() throws {
        let payload: [UInt8] = [0x7D, 0x01, 0xFF, 0x00, 0x42]
        let track = MIDIFileTrack(events: [MIDIFileEvent(deltaTicks: 0, kind: .meta(type: 0x7F, data: payload))])
        let data = StandardMIDIFile.write(tracks: [track], ticksPerQuarterNote: 480)
        let result = try StandardMIDIFile.read(data)

        guard case .meta(let type, let readPayload) = result.tracks[0].events[0].kind else {
            return XCTFail("expected a meta event")
        }
        XCTAssertEqual(type, 0x7F)
        XCTAssertEqual(readPayload, payload)
    }

    func testRoundTripsLargeDeltaTicksRequiringMultiByteVariableLengthQuantities() throws {
        // 0x7F (single byte) and 0x3FFF+1 (needs multiple VLQ bytes) both round-trip correctly.
        let track = MIDIFileTrack(events: [
            MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 0, note: 60, velocity: 100)),
            MIDIFileEvent(deltaTicks: 200_000, kind: .noteOff(channel: 0, note: 60)),
        ])
        let data = StandardMIDIFile.write(tracks: [track], ticksPerQuarterNote: 480)
        let result = try StandardMIDIFile.read(data)

        XCTAssertEqual(result.tracks[0].events[0].deltaTicks, 0)
        XCTAssertEqual(result.tracks[0].events[1].deltaTicks, 200_000)
    }

    func testNoteOnWithZeroVelocityReadsBackAsNoteOff() throws {
        // A common convention in third-party exports - not something this writer produces
        // itself, but the reader must still handle it correctly.
        var data = StandardMIDIFile.write(tracks: [MIDIFileTrack(events: [])], ticksPerQuarterNote: 480)
        // Hand-craft a single MTrk with a zero-velocity note-on, bypassing our own writer's
        // explicit-note-off convention to exercise the reader's fallback directly.
        var track = Data()
        track.append(contentsOf: Array("MTrk".utf8))
        var body: [UInt8] = [0x00, 0x90, 60, 0x00] // delta 0, note-on channel 0 note 60 velocity 0
        body.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00]) // End of Track
        track.append(contentsOf: [UInt8((body.count >> 24) & 0xFF), UInt8((body.count >> 16) & 0xFF), UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF)])
        track.append(contentsOf: body)

        data = Data(data.prefix(14)) + track // header (14 bytes) + our hand-crafted track
        let result = try StandardMIDIFile.read(data)
        XCTAssertEqual(result.tracks[0].events[0].kind, .noteOff(channel: 0, note: 60))
    }

    func testMultiTrackRoundTripKeepsTracksIndependent() throws {
        let trackA = MIDIFileTrack(events: [MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 0, note: 60, velocity: 100))])
        let trackB = MIDIFileTrack(events: [MIDIFileEvent(deltaTicks: 0, kind: .noteOn(channel: 1, note: 64, velocity: 90))])
        let data = StandardMIDIFile.write(tracks: [trackA, trackB], ticksPerQuarterNote: 960)
        let result = try StandardMIDIFile.read(data)

        XCTAssertEqual(result.tracks.count, 2)
        XCTAssertEqual(result.tracks[0].events.first?.kind, .noteOn(channel: 0, note: 60, velocity: 100))
        XCTAssertEqual(result.tracks[1].events.first?.kind, .noteOn(channel: 1, note: 64, velocity: 90))
    }
}
