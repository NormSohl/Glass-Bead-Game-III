//
//  SeqMIDICodec.swift
//  GBGCore
//
//  Maps SeqDocument (see SeqDocument.swift) onto StandardMIDIFile.swift's generic event model -
//  the format Graph's Live Recording exports, GBG III/Seq's own Save writes, and Seq's Open
//  reads, replacing the plain-JSON SeqDocument.Codable round-trip used before this. See the
//  scoping plan this was built from for why: a stock reader (any DAW) gets fully correct,
//  standard note-on/off + pitch-bend playback with nothing extra to understand; Seq itself
//  additionally reads two kinds of Sequencer-Specific Meta-Event (manufacturer ID 0x7D,
//  "Non-Commercial" - reserved by the MIDI spec for exactly this kind of private, non-hardware
//  use) that a stock reader safely, silently skips:
//   - one **document-level** block (limit/highestRatio/lowestRatio/root - everything needed to
//     reconstruct the exact Scale a performance was played in, which nothing communicated to
//     Seq before this)
//   - one **per-note** block (exact startFrequency/endFrequency, transitionKind/envelopeKind,
//     and the raw recordedPitchBend buffer when present) - the exact Doubles, not the
//     tick-and-cents-quantized standard pitch-bend stream, so Seq's own Save/Open round-trip
//     stays bit-for-bit lossless the way the old JSON format was, even though every note also
//     always gets a real, standard pitch-bend curve for stock playback (below).
//
//  Every note gets a standard pitch-bend curve either way: notes with a recorded buffer emit it
//  directly (re-expressed as root-anchored bend - see PitchBendMath.swift); notes without one
//  (freshly placed, or segmented into a Flat/Linear/Ease* shape) have that shape sampled at
//  bakedCurveSampleHz and baked into the same kind of pitch-bend stream, by reconstructing a
//  real Note and reusing its own getCurrentFrequency(percentComplete:) rather than a second copy
//  of that interpolation math. A stock player never has to know the difference - only Seq's own
//  re-edit path cares, via the metadata block above.
//

import Foundation

/// Everything needed to reconstruct the exact `Scale` a performance was played in, plus the
/// root frequency `Scale` itself doesn't store. Carried in the document-level meta-event.
public struct MIDIScaleDefinition: Equatable {
    public let limit: Int
    public let highestRatio: Double
    public let lowestRatio: Double
    public let rootFrequency: Double

    public init(limit: Int, highestRatio: Double, lowestRatio: Double, rootFrequency: Double) {
        self.limit = limit
        self.highestRatio = highestRatio
        self.lowestRatio = lowestRatio
        self.rootFrequency = rootFrequency
    }
}

public enum SeqMIDICodec {
    // MARK: - Format constants

    public enum Voice: CaseIterable, Hashable {
        case drone, x, y, z
    }

    /// The whole interval always lives in pitch bend, never in which note number is on - see
    /// PitchBendMath.swift and MIDI.swift's own live-output convention, which this mirrors
    /// deliberately (this format is meant to represent "the same stream, logged," not a
    /// different encoding of it). One fixed anchor note, same for every voice/channel - MIDI
    /// pitch bend is per-channel, so voices don't need distinct anchor notes to stay
    /// independent.
    private static let anchorNoteNumber = 60

    /// +-24 semitones (4 octaves) - matches Norm's own live pitch-bend-range convention
    /// (chosen to just cover the graph's whole practical span from one fixed anchor). Fixed
    /// per-file, independent of whatever Graph's own live MIDI pitch-bend-range setting
    /// currently is - that's a separate, live-external-gear concern, not a property of this
    /// storage format. A frequency further than this from the anchor clamps at the pitch-bend
    /// boundary in the *standard/portable* bend stream only - the exact Double frequency is
    /// never lost, since it's stored separately and exactly in the per-note metadata block.
    public static let pitchBendRangeSemitones = 24

    /// Rate to sample a parametric (non-recorded) transition's curve into a baked pitch-bend
    /// stream, so a stock player hears the actual Ease-In/Ease-Out/etc. shape instead of a flat
    /// jump. Well above what's perceptible for a smooth curve, far below the 300Hz a live
    /// recording itself samples at (recorded notes emit their real buffer directly instead).
    private static let bakedCurveSampleHz = 100.0

    /// Ticks per (a fixed, declared) quarter note = ticks per second directly, since every file
    /// this writes also declares a fixed 60 BPM tempo meta-event (1 quarter note = 1 second) -
    /// keeps the tick<->seconds conversion trivial on both ends, and any third-party tool
    /// reading the file computes the identical wall-clock timing from the same two numbers.
    /// Sample-rate-independent by construction: encode() converts the source samples->seconds
    /// once (using whatever sample rate the *writer's* audio engine is using), decode() converts
    /// back into samples using whatever sample rate the *reader* wants - the file itself carries
    /// no sample-rate dependency at all, an improvement over the old format's implicit
    /// same-sample-rate assumption between recorder and player.
    private static let ticksPerSecond = 10_000
    private static let declaredMicrosecondsPerQuarterNote: UInt32 = 1_000_000 // 60 BPM

    /// Used only when decoding a file with no document-level metadata block (a plain
    /// third-party .mid, not one this codec wrote) and a note with no recorded-pitch-bend
    /// metadata either - i.e. there's no better anchor available to reconstruct real Hz from the
    /// standard note+bend stream. Middle C; an arbitrary but reasonable fallback.
    private static let fallbackRootFrequency = 261.6255653005986

    private static let channelForVoice: [Voice: Int] = [.drone: 0, .x: 1, .y: 2, .z: 3]

    private static let documentMetaSubtype: UInt8 = 0x01
    private static let noteMetaSubtype: UInt8 = 0x02

    // MARK: - Encoding

    /// `sampleRate` is whatever the encoding side's audio engine is actually using - only
    /// needed to convert the document's own sample-count timing into real seconds once, at
    /// write time. See ticksPerSecond's own comment on why the resulting file then carries no
    /// sample-rate dependency at all.
    public static func encode(document: SeqDocument, scale: MIDIScaleDefinition, sampleRate: Double) -> Data {
        var tracks: [MIDIFileTrack] = []

        // Track 0 carries the tempo declaration and the document-level scale/tempo-info meta
        // event, at tick 0, ahead of any voice's own track - the conventional place a reader
        // looks for file-wide metadata first.
        let metaTrack = MIDIFileTrack(events: [
            MIDIFileEvent(deltaTicks: 0, kind: .meta(type: 0x51, data: [
                UInt8((declaredMicrosecondsPerQuarterNote >> 16) & 0xFF),
                UInt8((declaredMicrosecondsPerQuarterNote >> 8) & 0xFF),
                UInt8(declaredMicrosecondsPerQuarterNote & 0xFF),
            ])),
            MIDIFileEvent(deltaTicks: 0, kind: .meta(type: 0x7F, data: metaEventPayload(subtype: documentMetaSubtype, body: encodeDocumentMetaBody(scale: scale, tempoInfo: document.tempoInfo)))),
        ])
        tracks.append(metaTrack)

        for voice in Voice.allCases {
            let part = partDTO(for: voice, in: document)
            tracks.append(encodeTrack(for: part, channel: channelForVoice[voice]!, rootFrequency: scale.rootFrequency, sampleRate: sampleRate))
        }

        return StandardMIDIFile.write(tracks: tracks, ticksPerQuarterNote: ticksPerSecond)
    }

    private static func partDTO(for voice: Voice, in document: SeqDocument) -> PartDTO {
        switch voice {
        case .drone: return document.dronePart
        case .x: return document.xPart
        case .y: return document.yPart
        case .z: return document.zPart
        }
    }

    private static func encodeTrack(for part: PartDTO, channel: Int, rootFrequency: Double, sampleRate: Double) -> MIDIFileTrack {
        var events: [MIDIFileEvent] = []
        var lastTick = 0

        func tick(forSample sample: Int) -> Int {
            let seconds = Double(sample) / max(1, sampleRate)
            return Int((seconds * Double(ticksPerSecond)).rounded())
        }

        func append(_ kind: MIDIFileEventKind, atTick tick: Int) {
            events.append(MIDIFileEvent(deltaTicks: max(0, tick - lastTick), kind: kind))
            lastTick = tick
        }

        for note in part.notes {
            guard note.amplitude > 0 else { continue } // silence/rests carry no MIDI events at all - see decode()'s matching gap-fill step
            let startTick = tick(forSample: note.startTime)
            let endTick = tick(forSample: note.endTime)

            append(.meta(type: 0x7F, data: metaEventPayload(subtype: noteMetaSubtype, body: encodeNoteMetaBody(note: note))), atTick: startTick)

            let velocity = max(1, min(127, Int((note.amplitude * 127).rounded())))
            append(.noteOn(channel: channel, note: anchorNoteNumber, velocity: velocity), atTick: startTick)

            for (offsetTick, frequency) in bendCurve(for: note, startTick: startTick, endTick: endTick) {
                append(.pitchBend(channel: channel, value: PitchBendMath.freqToPB(frequency: frequency, referenceFrequency: rootFrequency, pitchBendRange: pitchBendRangeSemitones)), atTick: offsetTick)
            }

            append(.noteOff(channel: channel, note: anchorNoteNumber), atTick: endTick)
        }
        return MIDIFileTrack(events: events)
    }

    /// The concrete pitch-bend samples for one note, in absolute frequency (converted to a
    /// pitch-bend value by the caller) - either the note's own recorded buffer (re-expressed
    /// against the note's own startFrequency, matching exactly how Note.getCurrentFrequency/
    /// TransRecordedContour already interpret these cents today - see this file's header
    /// comment on why root-anchoring only applies to the standard bend stream, not this
    /// interpretation) or, for a note with no recorded buffer, its parametric transition curve
    /// sampled at bakedCurveSampleHz.
    private static func bendCurve(for note: NoteDTO, startTick: Int, endTick: Int) -> [(tick: Int, frequency: Double)] {
        if let recorded = note.recordedPitchBend, !recorded.isEmpty {
            let duration = max(1, endTick - startTick)
            return recorded.enumerated().map { index, cents in
                let progress = Double(index) / Double(max(1, recorded.count - 1))
                let tick = startTick + Int((Double(duration) * progress).rounded())
                let actualFrequency = note.startFrequency * pow(2, cents / 1200)
                return (tick, actualFrequency)
            }
        }

        // No recorded buffer - reconstruct a real Note (reusing Note's own, already-correct
        // interpolation math, not a second copy of it) and sample its curve.
        let reconstructed = Note(startTime: note.startTime, endTime: note.endTime, startFrequency: note.startFrequency, endFrequency: note.endFrequency, amplitude: note.amplitude)
        reconstructed.transition = note.transitionKind.makeTransition()

        let durationSeconds = Double(max(0, endTick - startTick)) / Double(ticksPerSecond)
        let sampleCount = max(2, Int((durationSeconds * bakedCurveSampleHz).rounded()) + 1)
        return (0..<sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let tick = startTick + Int((Double(endTick - startTick) * progress).rounded())
            return (tick, reconstructed.getCurrentFrequency(percentComplete: progress))
        }
    }

    // MARK: - Custom meta-event payloads

    private static func metaEventPayload(subtype: UInt8, body: [UInt8]) -> [UInt8] {
        [StandardMIDIFile.nonCommercialManufacturerID, subtype] + body
    }

    private static func encodeDocumentMetaBody(scale: MIDIScaleDefinition, tempoInfo: TempoInfo?) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(UInt8(clamping: scale.limit))
        bytes.append(contentsOf: doubleBytes(scale.highestRatio))
        bytes.append(contentsOf: doubleBytes(scale.lowestRatio))
        bytes.append(contentsOf: doubleBytes(scale.rootFrequency))
        if let tempoInfo {
            bytes.append(1)
            bytes.append(contentsOf: doubleBytes(tempoInfo.bpm))
            bytes.append(contentsOf: int32Bytes(Int32(clamping: tempoInfo.downbeatOffset)))
            bytes.append(contentsOf: doubleBytes(tempoInfo.confidence))
        } else {
            bytes.append(0)
        }
        return bytes
    }

    private static func encodeNoteMetaBody(note: NoteDTO) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(transitionKindByte(note.transitionKind))
        bytes.append(envelopeKindByte(note.envelopeKind))
        bytes.append(contentsOf: doubleBytes(note.startFrequency))
        bytes.append(contentsOf: doubleBytes(note.endFrequency))
        // The standard note-on velocity byte only carries amplitude at 1/127 granularity (fine
        // for generic playback loudness) - the exact Double lives here too, so Seq's own Save/
        // Open round-trip doesn't lose precision the old JSON format never lost.
        bytes.append(contentsOf: doubleBytes(note.amplitude))
        if let recorded = note.recordedPitchBend {
            bytes.append(1)
            bytes.append(contentsOf: int32Bytes(Int32(clamping: recorded.count)))
            for sample in recorded { bytes.append(contentsOf: doubleBytes(sample)) }
        } else {
            bytes.append(0)
        }
        return bytes
    }

    // MARK: - Decoding

    public struct DecodeError: Error, Equatable {
        public let message: String
    }

    public struct DecodeResult {
        public let document: SeqDocument
        /// nil only if the file has no document-level metadata block at all (e.g. a plain
        /// third-party .mid, not one this codec wrote) - callers that require a Scale should
        /// treat that as "unknown," not silently assume a default.
        public let scale: MIDIScaleDefinition?
    }

    private struct DecodedNoteMeta {
        let transitionKind: TransitionKind
        let envelopeKind: EnvelopeKind
        let startFrequency: Double
        let endFrequency: Double
        let amplitude: Double
        let recordedPitchBend: [Double]?
    }

    public static func decode(_ data: Data, targetSampleRate: Double) throws -> DecodeResult {
        let file: StandardMIDIFile.ReadResult
        do {
            file = try StandardMIDIFile.read(data)
        } catch {
            throw DecodeError(message: "Not a readable Standard MIDI File: \(error)")
        }
        guard file.ticksPerQuarterNote > 0 else {
            throw DecodeError(message: "File declares zero ticks per quarter note")
        }

        var scale: MIDIScaleDefinition?
        var tempoInfo: TempoInfo?
        var partsByChannel: [Int: Part] = [:]
        for (voice, channel) in channelForVoice {
            partsByChannel[channel] = Part(name: "\(voice)")
        }

        for track in file.tracks {
            var tick = 0
            var pendingNoteMeta: DecodedNoteMeta?
            var openNotes: [Int: (startTick: Int, velocity: Int, bends: [(tick: Int, cents: Double)])] = [:]

            for event in track.events {
                tick += event.deltaTicks
                switch event.kind {
                case .meta(let type, let payload):
                    guard type == 0x7F, payload.count >= 2, payload[0] == StandardMIDIFile.nonCommercialManufacturerID else { continue }
                    let subtype = payload[1]
                    let body = Array(payload.dropFirst(2))
                    if subtype == documentMetaSubtype {
                        (scale, tempoInfo) = try decodeDocumentMeta(body)
                    } else if subtype == noteMetaSubtype {
                        pendingNoteMeta = try decodeNoteMeta(body)
                    }
                case .noteOn(let channel, _, let velocity):
                    openNotes[channel] = (tick, velocity, [])
                case .pitchBend(let channel, let value):
                    guard var open = openNotes[channel] else { continue }
                    let cents = PitchBendMath.pitchBendToCents(pitchBendRange: pitchBendRangeSemitones, pitchBend: value)
                    open.bends.append((tick, cents))
                    openNotes[channel] = open
                case .noteOff(let channel, _):
                    guard let open = openNotes.removeValue(forKey: channel), let part = partsByChannel[channel] else { continue }
                    let meta = pendingNoteMeta
                    pendingNoteMeta = nil
                    insertDecodedNote(into: part, open: open, endTick: tick, meta: meta, rootFrequency: scale?.rootFrequency ?? fallbackRootFrequency, targetSampleRate: targetSampleRate)
                case .endOfTrack:
                    break
                }
            }
        }

        for (_, channel) in channelForVoice {
            if let part = partsByChannel[channel] {
                fillSilenceGaps(in: part, rootFrequency: scale?.rootFrequency ?? fallbackRootFrequency)
            }
        }

        let document = SeqDocument(
            dronePart: partsByChannel[channelForVoice[.drone]!] ?? Part(name: "drone"),
            xPart: partsByChannel[channelForVoice[.x]!] ?? Part(name: "x"),
            yPart: partsByChannel[channelForVoice[.y]!] ?? Part(name: "y"),
            zPart: partsByChannel[channelForVoice[.z]!] ?? Part(name: "z"),
            tempoInfo: tempoInfo)
        return DecodeResult(document: document, scale: scale)
    }

    private static func insertDecodedNote(into part: Part, open: (startTick: Int, velocity: Int, bends: [(tick: Int, cents: Double)]), endTick: Int, meta: DecodedNoteMeta?, rootFrequency: Double, targetSampleRate: Double) {
        func sample(forTick tick: Int) -> Int {
            let seconds = Double(tick) / Double(ticksPerSecond)
            return Int((seconds * targetSampleRate).rounded())
        }

        // The metadata block's exact Doubles are authoritative when present (round-trips
        // bit-for-bit, matching the old JSON format's own fidelity); only a file with no
        // per-note metadata at all (a third-party-authored .mid, not one this codec wrote) falls
        // back to reconstructing frequency from the quantized standard bend stream.
        let startFrequency = meta?.startFrequency ?? frequency(atTick: open.startTick, bends: open.bends, root: rootFrequency)
        let endFrequency = meta?.endFrequency ?? frequency(atTick: endTick, bends: open.bends, root: rootFrequency)
        let amplitude = meta?.amplitude ?? (Double(open.velocity) / 127.0)

        let note = part.insertNote(
            startTime: sample(forTick: open.startTick), endTime: sample(forTick: endTick),
            startFrequency: startFrequency, endFrequency: endFrequency,
            amplitude: amplitude,
            transition: (meta?.transitionKind ?? .flat).makeTransition(),
            envelope: (meta?.envelopeKind ?? .flat).makeEnvelope())

        if let recorded = meta?.recordedPitchBend {
            note.recordedPitchBend = recorded
            note.transition = TransRecordedContour(samples: recorded)
        }
    }

    private static func frequency(atTick tick: Int, bends: [(tick: Int, cents: Double)], root: Double) -> Double {
        // Nearest recorded bend sample at-or-before `tick`, falling back to the first sample
        // (or unison, if this note somehow carries no bend events at all).
        let cents = bends.last(where: { $0.tick <= tick })?.cents ?? bends.first?.cents ?? 0
        return root * pow(2, cents / 1200)
    }

    /// Backfills any timeline gap left by decode()'s own note loop (which never emits MIDI
    /// events for a zero-amplitude "silence" note - see encodeTrack's matching skip) with an
    /// explicit zero-amplitude Note, restoring Part's own contiguous-tiling invariant. Mirrors
    /// exactly how a live deletion already represents silence (insertNote with amplitude 0) -
    /// not a new concept, just applied once per decode instead of per edit.
    private static func fillSilenceGaps(in part: Part, rootFrequency: Double) {
        let sorted = part.notes.sorted { $0.startTime < $1.startTime }
        var cursor = 0
        for note in sorted {
            if note.startTime > cursor {
                part.insertNote(startTime: cursor, endTime: note.startTime, startFrequency: rootFrequency, endFrequency: rootFrequency, amplitude: 0)
            }
            cursor = max(cursor, note.endTime)
        }
    }

    private static func decodeDocumentMeta(_ body: [UInt8]) throws -> (MIDIScaleDefinition, TempoInfo?) {
        var cursor = 0
        func takeDouble() throws -> Double {
            guard cursor + 8 <= body.count else { throw DecodeError(message: "Truncated document metadata") }
            defer { cursor += 8 }
            return doubleFromBytes(Array(body[cursor..<(cursor + 8)]))
        }
        guard cursor < body.count else { throw DecodeError(message: "Empty document metadata") }
        let limit = Int(body[cursor]); cursor += 1
        let highestRatio = try takeDouble()
        let lowestRatio = try takeDouble()
        let rootFrequency = try takeDouble()
        guard cursor < body.count else { throw DecodeError(message: "Truncated document metadata") }
        let hasTempo = body[cursor] != 0; cursor += 1
        var tempoInfo: TempoInfo?
        if hasTempo {
            let bpm = try takeDouble()
            guard cursor + 4 <= body.count else { throw DecodeError(message: "Truncated tempo metadata") }
            let downbeatOffset = Int(int32FromBytes(Array(body[cursor..<(cursor + 4)]))); cursor += 4
            let confidence = try takeDouble()
            tempoInfo = TempoInfo(bpm: bpm, downbeatOffset: downbeatOffset, confidence: confidence)
        }
        return (MIDIScaleDefinition(limit: limit, highestRatio: highestRatio, lowestRatio: lowestRatio, rootFrequency: rootFrequency), tempoInfo)
    }

    private static func decodeNoteMeta(_ body: [UInt8]) throws -> DecodedNoteMeta {
        guard body.count >= 27 else { throw DecodeError(message: "Truncated note metadata") }
        let transitionKind = transitionKind(fromByte: body[0])
        let envelopeKind = envelopeKind(fromByte: body[1])
        let startFrequency = doubleFromBytes(Array(body[2..<10]))
        let endFrequency = doubleFromBytes(Array(body[10..<18]))
        let amplitude = doubleFromBytes(Array(body[18..<26]))
        let hasRecorded = body[26] != 0
        guard hasRecorded else {
            return DecodedNoteMeta(transitionKind: transitionKind, envelopeKind: envelopeKind, startFrequency: startFrequency, endFrequency: endFrequency, amplitude: amplitude, recordedPitchBend: nil)
        }
        guard body.count >= 31 else { throw DecodeError(message: "Truncated recorded-pitch-bend metadata") }
        let count = Int(int32FromBytes(Array(body[27..<31])))
        var cursor = 31
        var samples: [Double] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            guard cursor + 8 <= body.count else { throw DecodeError(message: "Truncated recorded-pitch-bend samples") }
            samples.append(doubleFromBytes(Array(body[cursor..<(cursor + 8)])))
            cursor += 8
        }
        return DecodedNoteMeta(transitionKind: transitionKind, envelopeKind: envelopeKind, startFrequency: startFrequency, endFrequency: endFrequency, amplitude: amplitude, recordedPitchBend: samples)
    }

    // MARK: - Small enum <-> byte mappings (stable across versions - never reorder)

    private static func transitionKindByte(_ kind: TransitionKind) -> UInt8 {
        switch kind {
        case .flat: return 0
        case .linear: return 1
        case .easeIn: return 2
        case .easeOut: return 3
        case .easeInEaseOut: return 4
        case .recordedContour: return 5
        }
    }

    private static func transitionKind(fromByte byte: UInt8) -> TransitionKind {
        switch byte {
        case 1: return .linear
        case 2: return .easeIn
        case 3: return .easeOut
        case 4: return .easeInEaseOut
        case 5: return .recordedContour
        default: return .flat
        }
    }

    private static func envelopeKindByte(_ kind: EnvelopeKind) -> UInt8 {
        switch kind {
        case .flat: return 0
        case .hump: return 1
        }
    }

    private static func envelopeKind(fromByte byte: UInt8) -> EnvelopeKind {
        byte == 1 ? .hump : .flat
    }

    // MARK: - Binary primitives

    private static func doubleBytes(_ value: Double) -> [UInt8] {
        let bits = value.bitPattern
        return (0..<8).map { UInt8((bits >> (8 * (7 - $0))) & 0xFF) }
    }

    private static func doubleFromBytes(_ bytes: [UInt8]) -> Double {
        var bits: UInt64 = 0
        for byte in bytes { bits = (bits << 8) | UInt64(byte) }
        return Double(bitPattern: bits)
    }

    private static func int32Bytes(_ value: Int32) -> [UInt8] {
        let bits = UInt32(bitPattern: value)
        return [UInt8((bits >> 24) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8(bits & 0xFF)]
    }

    private static func int32FromBytes(_ bytes: [UInt8]) -> Int32 {
        let bits = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        return Int32(bitPattern: bits)
    }
}
