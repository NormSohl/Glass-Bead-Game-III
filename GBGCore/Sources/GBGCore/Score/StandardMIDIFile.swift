//
//  StandardMIDIFile.swift
//  GBGCore
//
//  A minimal Standard MIDI File (SMF) reader/writer - just enough of the format to round-trip
//  note-on/off, pitch bend, and meta events. Deliberately generic/app-agnostic (knows nothing
//  about Note/Part/Scale) - SeqMIDICodec.swift is the layer that maps our own score model onto
//  this. Swift has no built-in SMF support, and this format is simple/stable enough (unchanged
//  since the 1980s) that hand-rolling the handful of pieces we need is more appropriate than a
//  dependency.
//
//  Division is metrical (ticks-per-quarter-note + a tempo meta-event), not SMPTE-based - more
//  consistently supported across third-party tools, and our own source timing (sample counts)
//  doesn't correspond to a real-world frame rate anyway, so there's no fidelity reason to prefer
//  SMPTE division here.
//

import Foundation

/// One event's payload - deliberately only the small set SeqMIDICodec actually needs, not a
/// general-purpose MIDI message model.
public enum MIDIFileEventKind: Equatable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int)
    case pitchBend(channel: Int, value: Int) // 0...16383, centered at 8192 - matches PitchBendMath
    case meta(type: Int, data: [UInt8])
    case endOfTrack
}

public struct MIDIFileEvent: Equatable {
    /// Ticks since the *previous* event in this track (not an absolute time) - matches SMF's
    /// own delta-time convention directly, so writing/reading doesn't need a separate
    /// absolute-vs-relative conversion step.
    public let deltaTicks: Int
    public let kind: MIDIFileEventKind

    public init(deltaTicks: Int, kind: MIDIFileEventKind) {
        self.deltaTicks = deltaTicks
        self.kind = kind
    }
}

public struct MIDIFileTrack {
    public var events: [MIDIFileEvent]

    public init(events: [MIDIFileEvent]) {
        self.events = events
    }
}

public enum StandardMIDIFile {
    /// Manufacturer ID 0x7D is reserved by the MIDI spec for "Non-Commercial" / educational and
    /// experimental use - exactly this case, and it avoids any risk of colliding with a real
    /// hardware manufacturer's own Sequencer-Specific payloads. SeqMIDICodec's own sub-type byte
    /// (document metadata vs. per-note metadata) follows this.
    public static let nonCommercialManufacturerID: UInt8 = 0x7D

    private static let headerChunkType: [UInt8] = Array("MThd".utf8)
    private static let trackChunkType: [UInt8] = Array("MTrk".utf8)

    // MARK: - Writing

    /// Encodes one or more tracks into a complete SMF byte stream (format 1 if more than one
    /// track, format 0 otherwise - both single-tempo-track conventions, neither implies
    /// anything about our own track-per-voice layout).
    public static func write(tracks: [MIDIFileTrack], ticksPerQuarterNote: Int) -> Data {
        var data = Data()
        data.append(contentsOf: headerChunkType)
        data.append(contentsOf: bigEndianUInt32(6)) // header length is always 6
        let format: UInt16 = tracks.count > 1 ? 1 : 0
        data.append(contentsOf: bigEndianUInt16(format))
        data.append(contentsOf: bigEndianUInt16(UInt16(tracks.count)))
        data.append(contentsOf: bigEndianUInt16(UInt16(ticksPerQuarterNote)))

        for track in tracks {
            data.append(trackData(for: track))
        }
        return data
    }

    private static func trackData(for track: MIDIFileTrack) -> Data {
        var body = Data()
        for event in track.events {
            body.append(variableLengthQuantity(event.deltaTicks))
            body.append(eventBytes(for: event.kind))
        }
        // Every track must end with an explicit End of Track meta-event, whether or not the
        // caller already included one - harmless to double up in the rare case they did,
        // since a reader just stops at the first one.
        if track.events.last?.kind != .endOfTrack {
            body.append(variableLengthQuantity(0))
            body.append(eventBytes(for: .endOfTrack))
        }

        var chunk = Data()
        chunk.append(contentsOf: trackChunkType)
        chunk.append(contentsOf: bigEndianUInt32(UInt32(body.count)))
        chunk.append(body)
        return chunk
    }

    private static func eventBytes(for kind: MIDIFileEventKind) -> Data {
        var bytes: [UInt8] = []
        switch kind {
        case .noteOn(let channel, let note, let velocity):
            bytes = [0x90 | UInt8(channel & 0x0F), UInt8(note & 0x7F), UInt8(velocity & 0x7F)]
        case .noteOff(let channel, let note):
            // Explicit Note Off (0x80), not a zero-velocity Note On - simpler to read back
            // unambiguously, and running-status compression (which would want them to share a
            // status byte) isn't something this writer does anyway.
            bytes = [0x80 | UInt8(channel & 0x0F), UInt8(note & 0x7F), 0x40]
        case .pitchBend(let channel, let value):
            let clamped = max(0, min(16383, value))
            bytes = [0xE0 | UInt8(channel & 0x0F), UInt8(clamped & 0x7F), UInt8((clamped >> 7) & 0x7F)]
        case .meta(let type, let payload):
            bytes = [0xFF, UInt8(type & 0xFF)]
            bytes.append(contentsOf: variableLengthQuantity(payload.count))
            bytes.append(contentsOf: payload)
            return Data(bytes)
        case .endOfTrack:
            bytes = [0xFF, 0x2F, 0x00]
        }
        return Data(bytes)
    }

    private static func variableLengthQuantity(_ value: Int) -> Data {
        precondition(value >= 0, "MIDI delta-times and lengths are never negative")
        var chunks: [UInt8] = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            chunks.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        return Data(chunks.reversed())
    }

    private static func bigEndianUInt32(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func bigEndianUInt16(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    // MARK: - Reading

    public enum ReadError: Error {
        case notAStandardMIDIFile
        case truncated
        case unsupportedFormat(Int)
    }

    public struct ReadResult {
        public let tracks: [MIDIFileTrack]
        public let ticksPerQuarterNote: Int
    }

    public static func read(_ data: Data) throws -> ReadResult {
        var cursor = Cursor(data: data)
        guard try cursor.readChunkType() == "MThd" else { throw ReadError.notAStandardMIDIFile }
        let headerLength = try cursor.readUInt32()
        let headerEnd = cursor.position + Int(headerLength)
        let format = try cursor.readUInt16()
        guard format == 0 || format == 1 else { throw ReadError.unsupportedFormat(Int(format)) }
        let numTracks = try cursor.readUInt16()
        let division = try cursor.readUInt16()
        guard division & 0x8000 == 0 else {
            // SMPTE division - not produced by this writer, and not something any current
            // caller needs to read back, so treated as unsupported rather than silently
            // misinterpreted as metrical.
            throw ReadError.unsupportedFormat(Int(division))
        }
        cursor.position = headerEnd // tolerate a header longer than 6 bytes, per spec

        var tracks: [MIDIFileTrack] = []
        for _ in 0..<numTracks {
            tracks.append(try readTrack(&cursor))
        }
        return ReadResult(tracks: tracks, ticksPerQuarterNote: Int(division))
    }

    private static func readTrack(_ cursor: inout Cursor) throws -> MIDIFileTrack {
        guard try cursor.readChunkType() == "MTrk" else { throw ReadError.notAStandardMIDIFile }
        let length = try cursor.readUInt32()
        let trackEnd = cursor.position + Int(length)

        var events: [MIDIFileEvent] = []
        var runningStatus: UInt8? = nil // some writers (not ours) omit repeated status bytes
        while cursor.position < trackEnd {
            let deltaTicks = try cursor.readVariableLengthQuantity()
            let kind = try readEventKind(&cursor, runningStatus: &runningStatus)
            events.append(MIDIFileEvent(deltaTicks: deltaTicks, kind: kind))
            if kind == .endOfTrack { break }
        }
        cursor.position = trackEnd
        return MIDIFileTrack(events: events)
    }

    private static func readEventKind(_ cursor: inout Cursor, runningStatus: inout UInt8?) throws -> MIDIFileEventKind {
        var status = try cursor.peekByte()
        if status & 0x80 != 0 {
            cursor.position += 1
        } else {
            // No status byte present - reuse whatever channel-voice status came before
            // (running status), a real thing some other tools' exports rely on.
            guard let previous = runningStatus else { throw ReadError.truncated }
            status = previous
        }

        switch status {
        case 0xFF:
            let type = Int(try cursor.readByte())
            let length = try cursor.readVariableLengthQuantity()
            let payload = try cursor.readBytes(length)
            runningStatus = nil // meta/sysex events don't participate in running status
            if type == 0x2F { return .endOfTrack }
            return .meta(type: type, data: payload)
        case 0xF0, 0xF7:
            // Sysex - not one of our own event kinds, but still needs to be consumed
            // correctly so the cursor stays in sync with the rest of the track.
            let length = try cursor.readVariableLengthQuantity()
            _ = try cursor.readBytes(length)
            runningStatus = nil
            return .meta(type: -1, data: []) // caller-side code ignores this; see SeqMIDICodec
        default:
            runningStatus = status
            let highNibble = status & 0xF0
            let channel = Int(status & 0x0F)
            switch highNibble {
            case 0x80:
                let note = try cursor.readByte()
                _ = try cursor.readByte() // velocity, unused for note-off
                return .noteOff(channel: channel, note: Int(note))
            case 0x90:
                let note = try cursor.readByte()
                let velocity = try cursor.readByte()
                if velocity == 0 { return .noteOff(channel: channel, note: Int(note)) } // common convention
                return .noteOn(channel: channel, note: Int(note), velocity: Int(velocity))
            case 0xE0:
                let lsb = try cursor.readByte()
                let msb = try cursor.readByte()
                return .pitchBend(channel: channel, value: Int(lsb) | (Int(msb) << 7))
            case 0xA0, 0xB0, 0xD0:
                _ = try cursor.readByte()
                _ = try cursor.readByte()
                return .meta(type: -1, data: [])
            case 0xC0:
                _ = try cursor.readByte()
                return .meta(type: -1, data: [])
            default:
                throw ReadError.truncated
            }
        }
    }

    private struct Cursor {
        let data: Data
        var position: Int = 0

        init(data: Data) {
            self.data = data
        }

        mutating func readByte() throws -> UInt8 {
            guard position < data.count else { throw ReadError.truncated }
            defer { position += 1 }
            return data[data.startIndex + position]
        }

        func peekByte() throws -> UInt8 {
            guard position < data.count else { throw ReadError.truncated }
            return data[data.startIndex + position]
        }

        mutating func readBytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, position + count <= data.count else { throw ReadError.truncated }
            let range = (data.startIndex + position)..<(data.startIndex + position + count)
            defer { position += count }
            return Array(data[range])
        }

        mutating func readUInt16() throws -> UInt16 {
            let bytes = try readBytes(2)
            return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        }

        mutating func readUInt32() throws -> UInt32 {
            let bytes = try readBytes(4)
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        }

        mutating func readChunkType() throws -> String {
            let bytes = try readBytes(4)
            return String(decoding: bytes, as: UTF8.self)
        }

        mutating func readVariableLengthQuantity() throws -> Int {
            var value = 0
            for _ in 0..<4 { // a VLQ is never more than 4 bytes for any length we'd ever write
                let byte = try readByte()
                value = (value << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { return value }
            }
            throw ReadError.truncated
        }
    }
}
