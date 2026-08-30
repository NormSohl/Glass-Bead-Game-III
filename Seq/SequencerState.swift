//
//  SequencerState.swift
//  Seq
//
//  Owns the sequencer's document data (the four voices' Parts), transport/editing state
//  (playhead, play/scrub/drag state, pan/zoom), and Seq's two output drivers: the internal
//  synth (Step 2) and, as of Step 3b, a polled MIDI-out engine driving Graph over
//  SeqMidiOut. Ported from Graph's in-app sequencer and adapted: no AppSettings/Sound
//  coupling (Seq has no touch graph or crosshair to follow), no sequencerDrivenVoices (that
//  mechanism only makes sense when a local crosshair exists to drive - Graph's copy keeps it,
//  Seq's doesn't need it). Both output drivers can be on at once, same as Graph's own
//  "internal synth" + "MIDI" toggles.
//

import Foundation
import GBGCore
import GBGSound

// All four of the sequencer's Parts, including drone (unlike Graph's SequencerVoice, which is
// x/y/z only - the axes with a crosshair on the main graph). Seq has no crosshair at all, so
// there's no equivalent "graphAxis" mapping to carry over here.
enum PartVoice: Hashable, CaseIterable {
    case drone, x, y, z
}

// Graph's own established default MPE channel assignments (GBGSound.Midi's
// xMidiMPEChannel/yMidiMPEChannel/zMidiMPEChannel/rootMidiMPEChannel) - fixed here rather than
// negotiated live between the two apps, per the standalone-sequencer plan's documented
// limitation ("fixed to Graph's own established default channels"). If Graph's own MPE
// defaults ever change, this needs updating to match.
private enum GraphMidiChannel {
    static let x = 2
    static let y = 3
    static let z = 4
    static let drone = 5

    static func forVoice(_ voice: PartVoice) -> Int {
        switch voice {
        case .drone: return drone
        case .x: return x
        case .y: return y
        case .z: return z
        }
    }
}

// The fixed MIDI note number every send uses - matches Graph's own convention (its four voices
// each have a fixed note field; the real interval rides entirely on pitch-bend). Middle C.
private let graphMidiFixedNote = 60
// Middle C's own 12-TET frequency - the reference PitchBendMath.freqToPB encodes every send
// against, matching what Graph's own receive-side decode (PitchBendMath.
// frequencyFromNoteAndPitchBend, called with the same fixed note above) assumes.
private let graphMidiReferenceFrequency = 261.6255653005986
private let graphMidiPitchBendRange = 24 // matches Graph's own default pitchBendRangeMPE

// The name Graph's own Midi.initVirtualDestination() gives its virtual MIDI destination -
// used to auto-detect a likely Graph instance in the destination list rather than requiring
// manual selection every time.
private let graphVirtualDestinationName = "Glass Bead Game III"

final class SequencerState: ObservableObject {
    let dronePart = Part(name: "drone")
    let xPart = Part(name: "x")
    let yPart = Part(name: "y")
    let zPart = Part(name: "z")

    let sampleRate: Double
    let minimumNoteLengthSamples: Int
    private let settings: SeqSettings
    private let audio = Audio()
    private(set) var scorePlayer: ScorePlayer!

    // MARK: - Graph MIDI-out (Step 3b)

    private let graphMidiOut = SeqMidiOut()
    @Published var graphOutputEnabled: Bool = false
    @Published var graphDestinationIndex: Int = 0 {
        didSet { graphMidiOut.setMidiDestination(destination: graphDestinationIndex) }
    }
    // Set once at init if a destination named graphVirtualDestinationName is found - lets the
    // UI offer a one-tap "Graph detected, connect?" affordance instead of requiring manual
    // picker selection every time, without silently auto-connecting on its own.
    @Published private(set) var detectedGraphDestinationIndex: Int?
    var graphMidiDestinations: [SeqMidiOut.MidiEndpointInfo] { graphMidiOut.midiDestinations }

    // Tracks, per voice, which Note (if any) is currently sounding over the Graph MIDI
    // connection - a class reference, compared by identity, so a genuinely new Note (even one
    // with the same start/end/frequency values) is detected as "a new note started."
    private var graphMidiSoundingNote: [PartVoice: Note] = [:]

    /// One-tap connect for the auto-detect banner - sets the destination and enables output.
    func connectDetectedGraph() {
        guard let index = detectedGraphDestinationIndex else { return }
        graphDestinationIndex = index
        graphOutputEnabled = true
    }

    @Published var noteDurationSeconds: Double = 0.5
    var noteDurationSamples: Int { max(1, Int(noteDurationSeconds * sampleRate)) }

    @Published private(set) var playheadSample: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isScrubbing: Bool = false

    // The drone's current frequency while playing or scrubbing, for RootIndicatorView - drone
    // has no crosshair, so it isn't routed through anything x/y/z-shaped.
    @Published private(set) var drivenDroneFrequency: Double?
    @Published private(set) var drivenDroneAmplitude: Double?

    // Hand-rolled pan/zoom for the piano roll, matching Graph's own PianoRollView.
    @Published var offsetSamples: Int = 0
    @Published var pixelsPerSecond: Double = 120

    // Bumped after every mutation to Part/Note contents (a placed note, a handle drag) so
    // PianoRollView's Canvas redraws - Part/Note are plain classes with no Combine publishing.
    @Published var scoreRevision: Int = 0

    @Published var draggingHandle: DraggingHandle?

    // Which voice "Add Note" places into, and whether the next canvas tap places a note instead
    // of moving the playhead - see PianoRollView's tap handling.
    @Published var selectedVoice: PartVoice = .x
    @Published var isPlacingNote: Bool = false

    private var playheadTimer: Timer?

    init(settings: SeqSettings) {
        self.settings = settings
        self.sampleRate = audio.sampleRate
        self.minimumNoteLengthSamples = max(1, Int(0.02 * sampleRate))
        scorePlayer = ScorePlayer(
            triad: audio.triad,
            dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart,
            sampleRate: sampleRate)
        audio.scorePlayer = scorePlayer
        // No touch-based enable-gating exists in Seq - all four voices are simply always
        // enabled; whether anything is actually heard is governed entirely by whether a Part
        // has a nonzero-amplitude note at the current playhead.
        audio.triad.enableTriadRootTone(enable: true)
        audio.triad.enableTriadXTone(enable: true)
        audio.triad.enableTriadYTone(enable: true)
        audio.triad.enableTriadZTone(enable: true)

        graphMidiOut.initMidi()
        if let index = graphMidiOut.midiDestinations.firstIndex(where: { $0.name == graphVirtualDestinationName }) {
            detectedGraphDestinationIndex = index
        }
    }

    var hasAnyNotes: Bool {
        [dronePart, xPart, yPart, zPart].contains { $0.notes.contains { $0.amplitude > 0 } }
    }

    var scoreLengthSamples: Int {
        [dronePart, xPart, yPart, zPart].map { $0.getLengthInSamples() }.max() ?? 0
    }

    func part(for voice: PartVoice) -> Part {
        switch voice {
        case .drone: return dronePart
        case .x: return xPart
        case .y: return yPart
        case .z: return zPart
        }
    }

    // MARK: - Graph MIDI-out engine

    /// Looks up the current note for `voice` at `playheadSample` and drives graphMidiOut
    /// accordingly - fires note-on when a genuinely new Note starts (by reference identity),
    /// sends an updated pitch-bend on every call while the same note keeps sounding (this is
    /// what carries a Transition's glide/curve over MIDI, not just one flat pitch per note),
    /// and fires note-off once amplitude drops to 0 or no note is found. Shared by both
    /// pollPlayback (continuous, ~30Hz during real playback) and scrub (discrete, per drag
    /// update) - both need identical note-on/hold/off logic, just called at different
    /// cadences. No-ops entirely when graphOutputEnabled is false.
    private func updateGraphMidiOutput(voice: PartVoice, at sample: Int) {
        guard graphOutputEnabled else { return }
        let channel = GraphMidiChannel.forVoice(voice)
        let currentNote = part(for: voice).getCurrentNote(timeSlice: sample)
        let sounding = graphMidiSoundingNote[voice]

        guard let note = currentNote, note.amplitude > 0 else {
            if sounding != nil {
                graphMidiOut.noteOff(channel: channel, note: graphMidiFixedNote)
                graphMidiSoundingNote[voice] = nil
            }
            return
        }

        let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: sample))
        let pitchBendValue = PitchBendMath.freqToPB(frequency: frequency, referenceFrequency: graphMidiReferenceFrequency, pitchBendRange: graphMidiPitchBendRange)

        if sounding !== note {
            let velocity = min(127, max(1, Int(note.amplitude * 127)))
            graphMidiOut.noteOn(channel: channel, note: graphMidiFixedNote, velocity: velocity)
            graphMidiSoundingNote[voice] = note
        }
        graphMidiOut.pitchBend(channel: channel, value: pitchBendValue)
    }

    /// Flushes any voices still tracked as sounding over the Graph connection - called when a
    /// whole play/scrub session ends (not just per-voice reaching amplitude 0 naturally),
    /// since ending playback mid-note wouldn't otherwise produce a note-off.
    private func flushGraphMidiOutput() {
        for (voice, _) in graphMidiSoundingNote {
            graphMidiOut.noteOff(channel: GraphMidiChannel.forVoice(voice), note: graphMidiFixedNote)
        }
        graphMidiSoundingNote.removeAll()
    }

    /// Called by PianoRollView while a drone note's handle is being dragged, alongside the note
    /// mutation itself, so RootIndicatorView shows the same value live.
    func updateDrivenDroneDisplay(frequency: Double, amplitude: Double) {
        drivenDroneFrequency = frequency
        drivenDroneAmplitude = amplitude
    }

    // MARK: - Playback

    func play() {
        guard hasAnyNotes, !isPlaying, !isScrubbing else { return }
        audio.startAudio(amp: 1)
        scorePlayer.start(atSample: playheadSample)
        isPlaying = true
        startPlayheadPolling()
    }

    func stop() {
        guard isPlaying else { return }
        scorePlayer.stop()
        stopPlayheadPolling()
        audio.stopAudio()
        flushGraphMidiOutput()
        isPlaying = false
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
    }

    private func startPlayheadPolling() {
        stopPlayheadPolling()
        // .common, not .default, so this keeps firing while the piano roll's own DragGesture is
        // tracking (panning, scrubbing, dragging a handle).
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollPlayback()
        }
        RunLoop.main.add(timer, forMode: .common)
        playheadTimer = timer
    }

    private func stopPlayheadPolling() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func pollPlayback() {
        playheadSample = scorePlayer.currentSample
        if let f = scorePlayer.currentXFrequency { settings.xFrequency = f }
        if let f = scorePlayer.currentYFrequency { settings.yFrequency = f }
        if let f = scorePlayer.currentZFrequency { settings.zFrequency = f }
        drivenDroneFrequency = scorePlayer.currentDroneFrequency
        for voice in PartVoice.allCases {
            updateGraphMidiOutput(voice: voice, at: playheadSample)
        }
        if !scorePlayer.isPlaying {
            stop() // natural end-of-piece
        }
    }

    // MARK: - Scrub

    func beginScrub() {
        guard !isPlaying else { return }
        isScrubbing = true
        audio.startAudio(amp: 1)
    }

    /// Random-access preview of the score at `sample`: looks up each voice's chord directly
    /// (Part.getCurrentNote is documented as fine for occasional/discrete lookups, not
    /// real-time-loop use - exactly this case) rather than stepping ScorePlayer through every
    /// intervening sample.
    func scrub(to sample: Int) {
        playheadSample = max(0, sample)

        for voice in [PartVoice.x, .y, .z] {
            guard let note = part(for: voice).getCurrentNote(timeSlice: playheadSample), note.amplitude > 0 else { continue }
            let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: playheadSample))
            switch voice {
            case .x: settings.xFrequency = frequency; audio.triad.setTriadXPitch(frequency: frequency)
            case .y: settings.yFrequency = frequency; audio.triad.setTriadYPitch(frequency: frequency)
            case .z: settings.zFrequency = frequency; audio.triad.setTriadZPitch(frequency: frequency)
            case .drone: break // loop only ever visits x/y/z - drone is handled separately below
            }
        }

        if let note = dronePart.getCurrentNote(timeSlice: playheadSample), note.amplitude > 0 {
            let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: playheadSample))
            audio.triad.setTriadRootPitch(frequency: frequency)
            drivenDroneFrequency = frequency
            drivenDroneAmplitude = note.getCurrentAmplitude(percentComplete: note.percentComplete(at: playheadSample))
        } else {
            drivenDroneFrequency = nil
            drivenDroneAmplitude = nil
        }

        for voice in PartVoice.allCases {
            updateGraphMidiOutput(voice: voice, at: playheadSample)
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        audio.stopAudio()
        flushGraphMidiOutput()
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
    }

    // MARK: - Playhead positioning (not playback/scrub)

    func setPlayhead(to sample: Int) {
        guard !isPlaying, !isScrubbing else { return }
        playheadSample = max(0, sample)
    }

    // MARK: - Note placement ("Add Note")

    /// Inserts a note for `selectedVoice` at (time, frequency), then disarms placement mode -
    /// called by PianoRollView when a tap lands while `isPlacingNote` is true.
    ///
    /// `Part` documents itself as always tiling the timeline contiguously - "silence is a
    /// zero-amplitude Note, never an absence" - and `getCurrentNote`/`ScorePlayer.advance()`
    /// both trust that invariant (a timeslice with no covering note is treated as an error/
    /// exhausted-part condition, not silence). A freshly-tapped note here can easily leave a
    /// real gap before it - a brand new Part starts with zero notes at all, or the tap simply
    /// isn't adjacent to whatever's already there - so this backfills a silent rest first,
    /// confirmed necessary by live-testing: without it, ScorePlayer.advance() saw every voice's
    /// currentNote as nil from sample 0 (not "silence," but "nothing to track at all") and
    /// ended playback on literally the first sample processed.
    func placeNote(atTime time: Int, frequency: Double) {
        let endTime = time + noteDurationSamples
        let targetPart = part(for: selectedVoice)
        let existingEnd = targetPart.notes.last?.endTime ?? 0
        if time > existingEnd {
            targetPart.insertNote(startTime: existingEnd, endTime: time, startFrequency: frequency, endFrequency: frequency, amplitude: 0)
        }
        targetPart.insertNote(startTime: time, endTime: endTime, startFrequency: frequency, endFrequency: frequency, amplitude: 1.0)
        scoreRevision += 1
        isPlacingNote = false
    }

    // MARK: - Handle editing

    /// Stops playback (if any) before a handle drag begins mutating a Note - ScorePlayer.advance()
    /// reads the same Note objects on the real-time audio thread, so this avoids needing any
    /// locking around the mutation.
    func beginDraggingHandle(_ handle: DraggingHandle) {
        if isPlaying { stop() }
        draggingHandle = handle
    }

    func endDraggingHandle() {
        draggingHandle = nil
    }
}

struct DraggingHandle: Equatable {
    let voice: PartVoice
    let note: Note
    let edge: NoteEdge

    // Note is a class, not Equatable by value - compare by identity.
    static func == (lhs: DraggingHandle, rhs: DraggingHandle) -> Bool {
        lhs.voice == rhs.voice && lhs.edge == rhs.edge && lhs.note === rhs.note
    }
}
