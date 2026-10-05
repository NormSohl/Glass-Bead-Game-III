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
//  Writes directly into SequencerState's own xPart/yPart/zPart - the same Part instances
//  PianoRollView already renders and ScorePlayer already reads - rather than a separate staging
//  copy merged in afterward. Norm: "I want to see recording in Seq in real time, not after
//  stopping recording" - every incoming pitch-bend sample updates the in-progress note in place
//  (via the same insertRecordedNote path finalizing already used, just called continuously
//  instead of once at note-off), so the piano roll shows the gesture growing exactly as it's
//  played, not only once capture stops. SequencerState.toggleLiveCapture() stops playback before
//  arming capture - the same "stop first" guard loadDocument already has - so this and
//  ScorePlayer.advance() (audio-render-thread) never touch these Parts at the same time.
//
//  Mirrors Glass Bead Game III/Data/RecordingState.swift's own ActiveGesture/gesture-cursor
//  pattern, just driven by incoming MIDI note-on/pitch-bend/note-off instead of local touch
//  begin/end plus a 300Hz settings poll - the rate at which pitch-bend actually arrives here is
//  whatever Graph's own touch-move rate is (Graph sends a MIDI pitch-bend update on every
//  settings.xFrequency/yFrequency/zFrequency change, i.e. every touch-move frame, not throttled -
//  see AppSettings/Sound.setXPitch in Graph). X/Y/Z only, same as Graph's own recorder - drone
//  has no live-touch pitch interaction to capture there either.
//
//  Assumes Graph's default MPE channel assignment (2/3/4 for X/Y/Z), inherited from
//  GraphMidiChannel's own established precedent (SequencerState.swift) - not negotiated live
//  between the two apps, but safe: Graph is MPE-only now, with no non-MPE mode to fall out of
//  sync with (see GBGSound.Midi). The same assumption the existing Seq->Graph MIDI-out already
//  makes.
//

import Foundation
import GBGCore
import GBGSound

final class LiveCaptureState: ObservableObject {
    @Published private(set) var isCapturing = false

    private let xPart: Part
    private let yPart: Part
    private let zPart: Part

    private let midi: SeqMidiOut
    private let sampleRateProvider: () -> Double
    private var sampleRate: Double { max(1, sampleRateProvider()) }
    // Seq's Pitch Bend Range setting, read per event so a change applies immediately.
    private let pitchBendRangeProvider: () -> Int

    // Called after every mutation to xPart/yPart/zPart, so SequencerState can bump
    // scoreRevision and the piano roll redraws live - see this file's own header comment.
    var onUpdate: (() -> Void)?

    private var captureStart: Date?

    private enum CapturedVoice: CaseIterable {
        case x, y, z
    }

    /// One voice's in-progress gesture - nil when that voice isn't currently mid-note.
    /// referenceFrequency is fixed at note-on, using whatever pitch-bend value is already known
    /// for that channel at that instant (0/center if none has arrived yet) - Graph's own MPE
    /// send order puts note-on before the real starting bend, but this doesn't hard-assume that:
    /// real MIDI transports (Network MIDI especially) can still reorder or drop packets, so a
    /// pitch-bend-before-note-on arrival is defended against rather than assumed impossible; see
    /// Sound.beginExternalDrive (Graph target) for the identical assumption already made for the
    /// same real-world scenario.
    private struct ActiveGesture {
        let referenceFrequency: Double
        let startSampleTime: Int
        var samples: [Double]
    }
    private var activeGestures: [CapturedVoice: ActiveGesture] = [:]

    // Where each voice's Part left off - see RecordingState's identical property for why this
    // exists (Part's own "always tile contiguously" invariant).
    private var cursors: [CapturedVoice: Int] = [.x: 0, .y: 0, .z: 0]

    init(midi: SeqMidiOut, xPart: Part, yPart: Part, zPart: Part, sampleRateProvider: @escaping () -> Double, pitchBendRangeProvider: @escaping () -> Int) {
        self.pitchBendRangeProvider = pitchBendRangeProvider
        self.midi = midi
        self.xPart = xPart
        self.yPart = yPart
        self.zPart = zPart
        self.sampleRateProvider = sampleRateProvider
        midi.onEvent = { [weak self] event in self?.handle(event) }
    }

    func toggleCapturing() {
        isCapturing ? stop() : start()
    }

    // MARK: - Source selection
    //
    // The named virtual destination ("Seq", set up alongside this in SequencerState.init) only
    // reaches same-Mac apps that can target it by name. A Network MIDI connection or a
    // USB-connected device shows up as a plain MIDI SOURCE instead - this is what actually lets
    // "connect the iPad to the Mac over the network or over USB" reach capture, since neither of
    // those has a "Seq"-named destination of its own to target. Both paths feed the same
    // handle(_:) above, so there's nothing else to wire up once a source is selected here.
    // Mirrors SequencerState.graphDestinationIndex's own didSet-applies-immediately pattern.
    var midiSources: [SeqMidiOut.MidiEndpointInfo] { midi.midiSources }

    @Published var selectedSourceIndex: Int = 0 {
        didSet { midi.setMidiSource(source: selectedSourceIndex) }
    }

    /// Re-scans for newly-available sources - a Network MIDI connection made after this app
    /// launched (or a cable plugged in) doesn't show up on its own. See
    /// SeqMidiOut.refreshMidiSources' own comment.
    func refreshSources() {
        midi.refreshMidiSources()
    }

    /// Clears x/y/z and starts fresh, matching Graph's own Record button - drone is left
    /// untouched (never captured, see this file's header comment), so anything already there
    /// (e.g. from a prior import) survives.
    private func start() {
        xPart.notes.removeAll()
        yPart.notes.removeAll()
        zPart.notes.removeAll()
        activeGestures = [:]
        cursors = [.x: 0, .y: 0, .z: 0]
        captureStart = Date()
        isCapturing = true
        onUpdate?()
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
        PitchBendMath.frequencyFromNoteAndPitchBend(note: graphMidiFixedNote, pitchBend: value, pitchBendRange: pitchBendRangeProvider())
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
        writeLiveNote(voice) // visible immediately, not only once the first pitch-bend sample arrives
        onUpdate?()
    }

    private func appendSample(_ voice: CapturedVoice, frequency: Double) {
        guard var gesture = activeGestures[voice] else { return }
        let cents = 1200 * log2(frequency / gesture.referenceFrequency)
        gesture.samples.append(cents)
        activeGestures[voice] = gesture
        writeLiveNote(voice)
        onUpdate?()
    }

    /// Writes (or overwrites) the in-progress gesture's note to reflect exactly what's been
    /// captured so far, ending at "now" - the same insertRecordedNote finalization path
    /// finalizeGesture uses below, just run on every sample instead of once at note-off. This
    /// is the entire mechanism behind seeing the note grow live: each call re-carves the same
    /// still-growing time span via Part's own insertNote/clearRange, exactly as if a person were
    /// repeatedly replacing a note with a slightly longer one.
    private func writeLiveNote(_ voice: CapturedVoice) {
        guard let gesture = activeGestures[voice] else { return }
        let endTime = max(currentSampleTime(), gesture.startSampleTime + 1)
        part(for: voice).insertRecordedNote(
            startTime: gesture.startSampleTime, endTime: endTime,
            startFrequency: gesture.referenceFrequency, endFrequency: gesture.referenceFrequency,
            amplitude: 1,
            recordedPitchBend: gesture.samples)
    }

    private func finalizeGesture(_ voice: CapturedVoice) {
        guard let gesture = activeGestures[voice] else { return }
        activeGestures[voice] = nil
        let endTime = currentSampleTime()
        guard endTime > gesture.startSampleTime else {
            // Degenerate (e.g. an instant tap) - writeLiveNote already left a 1-sample note
            // behind for this gesture; turn it back to silence rather than leaving a stray
            // audible blip, matching RecordingState's own "drop degenerate gestures" behavior.
            let placeholderEnd = gesture.startSampleTime + 1
            part(for: voice).insertNote(startTime: gesture.startSampleTime, endTime: placeholderEnd, startFrequency: gesture.referenceFrequency, endFrequency: gesture.referenceFrequency, amplitude: 0)
            cursors[voice] = placeholderEnd
            onUpdate?()
            return
        }
        part(for: voice).insertRecordedNote(
            startTime: gesture.startSampleTime, endTime: endTime,
            startFrequency: gesture.referenceFrequency, endFrequency: gesture.referenceFrequency,
            amplitude: 1,
            recordedPitchBend: gesture.samples)
        cursors[voice] = endTime
        onUpdate?()
    }

    private func currentSampleTime() -> Int {
        guard let captureStart else { return 0 }
        return Int(Date().timeIntervalSince(captureStart) * sampleRate)
    }
}
