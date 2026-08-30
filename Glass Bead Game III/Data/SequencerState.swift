//
//  SequencerState.swift
//  Glass Bead Game III
//
//  Owns the sequencer's document data (the four voices' Parts) and its transport/editing state
//  (playhead, play/scrub/drag state, pan/zoom). Deliberately separate from AppSettings, which is
//  UI toggles and the graph's live touch state - this is document data with a different
//  invalidation cadence.
//
//  This is also the sole writer of AppSettings.sequencerDrivenVoices - see the focus-model
//  design notes: the main graph is left completely alone unless the sequencer is actively
//  playing, scrubbing, or a note handle is being dragged, and it's this class that decides
//  which of those is currently true.
//

import Foundation
import GBGCore

// All four of the sequencer's Parts - unlike AppSettings.SequencerVoice (x/y/z only, the axes
// with a crosshair on the main graph), this covers drone too, since every voice's notes need
// handles in the piano roll even though drone has no on-graph representation.
enum PartVoice: Hashable {
    case drone, x, y, z

    // Only x/y/z have a crosshair on the main graph to hand off - drone's equivalent is
    // RootIndicatorView, driven separately (see SequencerState.updateDrivenVoices).
    var graphAxis: SequencerVoice? {
        switch self {
        case .drone: return nil
        case .x: return .x
        case .y: return .y
        case .z: return .z
        }
    }
}

final class SequencerState: ObservableObject {
    let dronePart = Part(name: "drone")
    let xPart = Part(name: "x")
    let yPart = Part(name: "y")
    let zPart = Part(name: "z")

    let sampleRate: Double
    let minimumNoteLengthSamples: Int
    private let settings: AppSettings
    private(set) var scorePlayer: ScorePlayer!

    @Published var noteDurationSeconds: Double = 0.5
    var noteDurationSamples: Int { max(1, Int(noteDurationSeconds * sampleRate)) }

    @Published private(set) var playheadSample: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isScrubbing: Bool = false

    // The drone's current frequency while playing or scrubbing, for RootIndicatorView - drone
    // has no crosshair on the main graph, so it isn't routed through
    // AppSettings.sequencerDrivenVoices the way X/Y/Z are.
    @Published private(set) var drivenDroneFrequency: Double?
    @Published private(set) var drivenDroneAmplitude: Double?

    // Hand-rolled pan/zoom for the piano roll, matching how every other interactive view in this
    // app already pans (see PianoRollView) rather than using ScrollView.
    @Published var offsetSamples: Int = 0
    @Published var pixelsPerSecond: Double = 120

    // Bumped after every mutation to Part/Note contents (a captured chord, a handle drag) so
    // PianoRollView's Canvas redraws - Part/Note are plain classes with no Combine publishing of
    // their own.
    @Published var scoreRevision: Int = 0

    @Published var draggingHandle: DraggingHandle? {
        didSet { updateSequencerDrivenVoices() }
    }

    private var playheadTimer: Timer?

    init(sampleRate: Double, settings: AppSettings) {
        self.sampleRate = sampleRate
        self.settings = settings
        self.minimumNoteLengthSamples = max(1, Int(0.02 * sampleRate))
        scorePlayer = ScorePlayer(
            triad: sound.audio.triad,
            dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart,
            sampleRate: sampleRate)
        sound.audio.scorePlayer = scorePlayer
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

    private func updateSequencerDrivenVoices() {
        if isPlaying || isScrubbing {
            settings.sequencerDrivenVoices = [.x, .y, .z]
        } else if let axis = draggingHandle?.voice.graphAxis {
            settings.sequencerDrivenVoices = [axis]
        } else {
            settings.sequencerDrivenVoices = []
        }
        // Dragging a non-drone handle ends any stale drone-drive display from a previous drag;
        // dragging a drone handle itself is displayed live by PianoRollView via
        // updateDrivenDroneDisplay, called alongside the note mutation.
        if draggingHandle?.voice != .drone {
            drivenDroneFrequency = nil
            drivenDroneAmplitude = nil
        }
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
        sound.beginTouch(amp: 1)
        scorePlayer.start(atSample: playheadSample)
        isPlaying = true
        updateSequencerDrivenVoices()
        startPlayheadPolling()
    }

    func stop() {
        guard isPlaying else { return }
        scorePlayer.stop()
        stopPlayheadPolling()
        sound.endTouch(pedal: false)
        isPlaying = false
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
        updateSequencerDrivenVoices()
    }

    private func startPlayheadPolling() {
        stopPlayheadPolling()
        // .common, not .default, so this keeps firing while the piano roll's own DragGesture is
        // tracking (panning, scrubbing, dragging a handle) - exactly when you'd most want the
        // playhead/graph to keep moving.
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
        if !scorePlayer.isPlaying {
            stop() // natural end-of-piece
        }
    }

    // MARK: - Scrub

    func beginScrub() {
        guard !isPlaying else { return }
        isScrubbing = true
        sound.beginTouch(amp: 1)
        updateSequencerDrivenVoices()
    }

    /// Random-access preview of the score at `sample`: looks up each voice's chord directly
    /// (Part.getCurrentNote is documented as fine for occasional/discrete lookups, not
    /// real-time-loop use - exactly this case) rather than stepping ScorePlayer through every
    /// intervening sample. Pushes pitches straight into Sound (audio + MIDI, same as a live
    /// graph touch) so scrubbing is audible, not just visual. A silence/backfill note
    /// (amplitude 0) is skipped rather than pushed, so scrubbing through a still-blank stretch
    /// doesn't produce a stray 0Hz artifact.
    func scrub(to sample: Int) {
        playheadSample = max(0, sample)

        for voice in [PartVoice.x, .y, .z] {
            guard let note = part(for: voice).getCurrentNote(timeSlice: playheadSample), note.amplitude > 0 else { continue }
            let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: playheadSample))
            switch voice {
            case .x: settings.xFrequency = frequency; sound.setXPitch(frequency: frequency)
            case .y: settings.yFrequency = frequency; sound.setYPitch(frequency: frequency)
            case .z: settings.zFrequency = frequency; sound.setZPitch(frequency: frequency)
            case .drone: break // loop only ever visits x/y/z - drone is handled separately below
            }
        }

        if let note = dronePart.getCurrentNote(timeSlice: playheadSample), note.amplitude > 0 {
            let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: playheadSample))
            // Direct triad call, not sound.setRootPitch - that would also shift the MIDI
            // reference pitch, a much wider-reaching side effect. ScorePlayer.advance() makes
            // this same distinction for exactly this reason; scrub mirrors it for consistency.
            sound.audio.triad.setTriadRootPitch(frequency: frequency)
            drivenDroneFrequency = frequency
            drivenDroneAmplitude = note.getCurrentAmplitude(percentComplete: note.percentComplete(at: playheadSample))
        } else {
            drivenDroneFrequency = nil
            drivenDroneAmplitude = nil
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        sound.endTouch(pedal: false)
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
        updateSequencerDrivenVoices()
    }

    // MARK: - Playhead positioning (not playback/scrub - e.g. Add Note's advance, or a tap on
    // empty piano-roll background to relocate the playhead)

    func setPlayhead(to sample: Int) {
        guard !isPlaying, !isScrubbing else { return }
        playheadSample = max(0, sample)
    }

    func advancePlayhead(by duration: Int) {
        playheadSample = max(0, playheadSample + duration)
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
