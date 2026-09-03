//
//  LiveCaptureState.swift
//  Seq
//
//  Captures Graph's live performance directly over MIDI, skipping the Save/Open file round
//  trip entirely - Norm: "is it still necessary to have the graph record and load it into Seq,
//  or can we go direct into Seq?" Listens on graphMidiOut's own virtual destination (see
//  SeqMidiOut.initMidiInput, GBGSound), named "Seq" so it shows up in Graph's own existing MIDI
//  Destination picker - no new UI needed on Graph's side at all. That picker already lists
//  whatever CoreMIDI sees regardless of transport, which is what makes "we are going to want to
//  connect the iPad to the Mac... over the network or over USB" free: a same-Mac virtual
//  connection, a USB-connected iPad, and a Network MIDI (RTP-MIDI) session all show up and
//  behave identically here - this file has no transport-specific code, and needs none.
//
//  Mirrors Glass Bead Game III/Data/RecordingState.swift closely (the same ActiveGesture/
//  insertRecordedNote/backfilled-rest pattern), just driven by incoming MIDI note-on/pitch-bend/
//  note-off instead of local touch begin/end plus a 300Hz settings poll - the sample rate at
//  which pitch-bend actually arrives here is whatever Graph's own touch-move rate is (Graph
//  sends a MIDI pitch-bend update on every settings.xFrequency/yFrequency/zFrequency change,
//  i.e. every touch-move frame, not throttled - see AppSettings/Sound.setXPitch in Graph). X/Y/Z
//  only, same as Graph's own recorder - drone has no live-touch pitch interaction to capture
//  there either.
//
//  Known limitation, inherited from GraphMidiChannel's own established precedent
//  (SequencerState.swift): assumes Graph is using its default MPE channel assignment (2/3/4 for
//  X/Y/Z) - not negotiated live between the two apps, so this won't line up if Graph's "Use
//  MPE" is off. The same limitation the existing Seq->Graph MIDI-out already accepts, not a new
//  gap this introduces.
//

import Foundation
import GBGCore
import GBGSound

final class LiveCaptureState: ObservableObject {
    @Published private(set) var isCapturing = false

    private(set) var xPart = Part(name: "x")
    private(set) var yPart = Part(name: "y")
    private(set) var zPart = Part(name: "z")

    private let midi: SeqMidiOut
    private let sampleRateProvider: () -> Double
    private var sampleRate: Double { max(1, sampleRateProvider()) }

    private var captureStart: Date?

    private enum CapturedVoice: CaseIterable {
        case x, y, z
    }

    /// One voice's in-progress gesture - nil when that voice isn't currently mid-note.
    /// referenceFrequency is fixed at note-on, using whatever pitch-bend value is already known
    /// for that channel at that instant (0/center if none has arrived yet) - Graph's own
    /// non-MPE send order puts the real starting bend before note-on, MPE's own order puts it
    /// just after, so this can't assume either ordering; see Sound.beginExternalDrive (Graph
    /// target) for the identical assumption already made for the same real-world scenario.
    private struct ActiveGesture {
        let referenceFrequency: Double
        let startSampleTime: Int
        var samples: [Double]
    }
    private var activeGestures: [CapturedVoice: ActiveGesture] = [:]

    // Where each voice's Part left off - see RecordingState's identical property for why this
    // exists (Part's own "always tile contiguously" invariant).
    private var cursors: [CapturedVoice: Int] = [.x: 0, .y: 0, .z: 0]

    init(midi: SeqMidiOut, sampleRateProvider: @escaping () -> Double) {
        self.midi = midi
        self.sampleRateProvider = sampleRateProvider
        midi.onEvent = { [weak self] event in self?.handle(event) }
    }

    var hasAnyNotes: Bool {
        [xPart, yPart, zPart].contains { $0.notes.contains { $0.amplitude > 0 } }
    }

    /// Drone is always empty here, matching RecordingState's own convention - a valid,
    /// gracefully-handled document, not an error.
    func exportDocument() -> SeqDocument {
        SeqDocument(dronePart: Part(name: "drone"), xPart: xPart, yPart: yPart, zPart: zPart)
    }

    func toggleCapturing() {
        isCapturing ? stop() : start()
    }

    private func start() {
        xPart = Part(name: "x")
        yPart = Part(name: "y")
        zPart = Part(name: "z")
        activeGestures = [:]
        cursors = [.x: 0, .y: 0, .z: 0]
        captureStart = Date()
        isCapturing = true
    }

    /// Immediately finalizes whatever's in progress, same as RecordingState.stopRecording -
    /// doesn't wait for a note-off that may never arrive (e.g. Graph quit mid-touch).
    private func stop() {
        for voice in CapturedVoice.allCases {
            finalizeGesture(voice)
        }
        isCapturing = false
        captureStart = nil
    }

    private func handle(_ event: Midi.MidiInputEvent) {
        guard isCapturing, let voice = LiveCaptureState.voice(forChannel: event.channel) else { return }
        switch event.kind {
        case .noteOn:
            // The incoming note number is ignored - Graph always sends its own fixed anchor
            // note (graphMidiFixedNote) and carries the real interval entirely in pitch-bend,
            // same convention this whole codebase already uses end to end.
            beginGesture(voice, frequency: frequency(forPitchBend: 8192))
        case .noteOff:
            finalizeGesture(voice)
        case .pitchBend(let value):
            appendSample(voice, frequency: frequency(forPitchBend: value))
        case .controlChange:
            break
        }
    }

    private func frequency(forPitchBend value: Int) -> Double {
        PitchBendMath.frequencyFromNoteAndPitchBend(note: graphMidiFixedNote, pitchBend: value, pitchBendRange: graphMidiPitchBendRange)
    }

    private static func voice(forChannel channel: Int) -> CapturedVoice? {
        switch channel {
        case GraphMidiChannel.x: return .x
        case GraphMidiChannel.y: return .y
        case GraphMidiChannel.z: return .z
        default: return nil // GraphMidiChannel.drone's channel, and anything else, isn't captured
        }
    }

    private func part(for voice: CapturedVoice) -> Part {
        switch voice {
        case .x: return xPart
        case .y: return yPart
        case .z: return zPart
        }
    }

    private func beginGesture(_ voice: CapturedVoice, frequency: Double) {
        guard activeGestures[voice] == nil else { return } // a gesture is already in progress
        let startTime = currentSampleTime()
        let cursor = cursors[voice] ?? 0
        if startTime > cursor {
            part(for: voice).insertNote(startTime: cursor, endTime: startTime, startFrequency: frequency, endFrequency: frequency, amplitude: 0)
        }
        activeGestures[voice] = ActiveGesture(referenceFrequency: frequency, startSampleTime: startTime, samples: [0])
    }

    private func appendSample(_ voice: CapturedVoice, frequency: Double) {
        guard var gesture = activeGestures[voice] else { return }
        let cents = 1200 * log2(frequency / gesture.referenceFrequency)
        gesture.samples.append(cents)
        activeGestures[voice] = gesture
    }

    private func finalizeGesture(_ voice: CapturedVoice) {
        guard let gesture = activeGestures[voice] else { return }
        activeGestures[voice] = nil
        let endTime = currentSampleTime()
        guard endTime > gesture.startSampleTime else { return } // degenerate (e.g. instant tap) - drop
        part(for: voice).insertRecordedNote(
            startTime: gesture.startSampleTime, endTime: endTime,
            startFrequency: gesture.referenceFrequency, endFrequency: gesture.referenceFrequency,
            amplitude: 1,
            recordedPitchBend: gesture.samples)
        cursors[voice] = endTime
    }

    private func currentSampleTime() -> Int {
        guard let captureStart else { return 0 }
        return Int(Date().timeIntervalSince(captureStart) * sampleRate)
    }
}
