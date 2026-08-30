//
//  SequencerState.swift
//  Seq
//
//  Owns the sequencer's document data (the four voices' Parts), transport/editing state
//  (playhead, play/scrub/drag state, pan/zoom), and - for this step - Seq's own internal-synth
//  audio engine. Ported from Graph's in-app sequencer and adapted: no AppSettings/Sound
//  coupling (Seq has no touch graph or crosshair to follow), no sequencerDrivenVoices (that
//  mechanism only makes sense when a local crosshair exists to drive - Graph's copy keeps it,
//  Seq's doesn't need it). MIDI-out (Step 3 of the standalone-sequencer plan) will add a second
//  driver alongside the internal synth here; for now this is audio-only.
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
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        audio.stopAudio()
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
    func placeNote(atTime time: Int, frequency: Double) {
        let endTime = time + noteDurationSamples
        part(for: selectedVoice).insertNote(startTime: time, endTime: endTime, startFrequency: frequency, endFrequency: frequency, amplitude: 1.0)
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
