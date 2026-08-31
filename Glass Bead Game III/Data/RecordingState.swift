//
//  RecordingState.swift
//  Glass Bead Game III
//
//  Captures a live touch performance from the graph as continuous recorded-contour notes - one
//  per touch-gesture per voice - via GBGCore's TransRecordedContour/Part.insertRecordedNote (see
//  the live-record plan's step 3). Deliberately new, standalone Part state, not built on the old
//  in-app SequencerState (Data/SequencerState.swift) - that class is on a deprecation path once
//  the standalone Seq app is confirmed in real use, and new work shouldn't entangle with it.
//
//  Sampling is timer-driven, not tied to the audio render thread the way ScorePlayer.advance()
//  is (see that class's own note on why even its MIDI-only timing depends on the audio engine
//  actually running) - recording capture has no equivalent dependency, since it only reads
//  values HitTestView/ZSliderView already publish continuously every touch-move frame
//  (settings.xFrequency/yFrequency/zFrequency), it never drives playback itself.
//
//  Drone has no live-touch pitch interaction today (just a fixed reference tone + on/off toggle),
//  so dronePart is always left empty here - nothing to capture. An empty Part is a valid,
//  gracefully-handled document, not an error (see SeqDocument/Part).
//

import Foundation
import GBGCore

/// How often the sampling timer ticks while armed - within the plan's ~60-100Hz target. A plain
/// Timer, not a real-time thread; see this file's header note on why that's fine here.
private let recordingSampleHz: Double = 80

final class RecordingState: ObservableObject {
    @Published private(set) var isRecording = false

    private(set) var dronePart = Part(name: "drone")
    private(set) var xPart = Part(name: "x")
    private(set) var yPart = Part(name: "y")
    private(set) var zPart = Part(name: "z")

    private unowned let settings: AppSettings
    private let sampleRateProvider: () -> Double
    private var sampleRate: Double { max(1, sampleRateProvider()) }

    private var recordingStart: Date?
    private var timer: Timer?

    /// One voice's in-progress touch-gesture - nil when that voice isn't currently being
    /// captured (not touched, or touched but recording isn't armed). `referenceFrequency` is
    /// fixed at the moment the touch begins - a touch doesn't pre-decide where it'll land, so
    /// every later sample is a cents-offset deviation from this one fixed point, per the plan's
    /// deviation-from-the-normal-path Transition model.
    private struct ActiveGesture {
        let referenceFrequency: Double
        let startSampleTime: Int
        var samples: [Double]
    }
    private var activeX: ActiveGesture?
    private var activeY: ActiveGesture?
    private var activeZ: ActiveGesture?

    // Where each voice's Part left off - the end of its last finalized note (gesture or
    // backfilled rest) - so a later gesture on the same voice, within the same recording
    // session, can be preceded by a silent rest covering the gap. Required by Part's own tiling
    // invariant ("notes always tile the timeline contiguously with no gaps - silence is a
    // zero-amplitude Note, never an absence", Part.swift's own header comment) - violating this
    // is exactly the bug SequencerState.placeNote hit and fixed earlier this session.
    private var xCursor = 0
    private var yCursor = 0
    private var zCursor = 0

    init(settings: AppSettings, sampleRateProvider: @escaping () -> Double) {
        self.settings = settings
        self.sampleRateProvider = sampleRateProvider
    }

    var hasAnyNotes: Bool {
        [dronePart, xPart, yPart, zPart].contains { $0.notes.contains { $0.amplitude > 0 } }
    }

    func exportDocument() -> SeqDocument {
        SeqDocument(dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)
    }

    // MARK: - Arm/disarm

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        dronePart = Part(name: "drone")
        xPart = Part(name: "x")
        yPart = Part(name: "y")
        zPart = Part(name: "z")
        activeX = nil
        activeY = nil
        activeZ = nil
        xCursor = 0
        yCursor = 0
        zCursor = 0
        recordingStart = Date()
        isRecording = true
        startTimer()
    }

    /// Immediately finalizes whatever's in progress (per voice, whatever samples exist so far)
    /// rather than waiting for any still-held touch to end naturally.
    private func stopRecording() {
        guard isRecording else { return }
        finalizeGesture(&activeX, into: xPart, cursor: &xCursor)
        finalizeGesture(&activeY, into: yPart, cursor: &yCursor)
        finalizeGesture(&activeZ, into: zPart, cursor: &zCursor)
        stopTimer()
        isRecording = false
        recordingStart = nil
    }

    // MARK: - Touch lifecycle hooks
    //
    // Called by HitTestView (the graph - X and Y move together, one crosshair) and ZSliderView
    // (Z, its own independent touch), alongside their existing sound.beginGraphTouch/
    // endGraphTouch/beginZTouch/endZTouch calls - see Sound.swift's own touch-lifecycle
    // functions, which this deliberately doesn't call into (recording capture is independent of
    // what's actually sounding). No-ops whenever recording isn't armed.

    func beginGraphTouch() {
        guard isRecording else { return }
        beginGesture(frequency: settings.xFrequency, active: &activeX, part: xPart, cursor: &xCursor)
        beginGesture(frequency: settings.yFrequency, active: &activeY, part: yPart, cursor: &yCursor)
    }

    func endGraphTouch() {
        guard isRecording else { return }
        finalizeGesture(&activeX, into: xPart, cursor: &xCursor)
        finalizeGesture(&activeY, into: yPart, cursor: &yCursor)
    }

    func beginZTouch() {
        guard isRecording else { return }
        beginGesture(frequency: settings.zFrequency, active: &activeZ, part: zPart, cursor: &zCursor)
    }

    func endZTouch() {
        guard isRecording else { return }
        finalizeGesture(&activeZ, into: zPart, cursor: &zCursor)
    }

    // MARK: - Gesture bookkeeping

    private func beginGesture(frequency: Double, active: inout ActiveGesture?, part: Part, cursor: inout Int) {
        guard active == nil else { return } // a gesture is already in progress on this voice
        let startTime = currentSampleTime()
        if startTime > cursor {
            // Silent backfill rest covering the gap since this voice's last finalized note (or
            // the start of the recording) - see this file's header note on why.
            part.insertNote(startTime: cursor, endTime: startTime, startFrequency: frequency, endFrequency: frequency, amplitude: 0)
        }
        active = ActiveGesture(referenceFrequency: frequency, startSampleTime: startTime, samples: [0])
    }

    private func finalizeGesture(_ active: inout ActiveGesture?, into part: Part, cursor: inout Int) {
        guard let gesture = active else { return }
        active = nil
        let endTime = currentSampleTime()
        guard endTime > gesture.startSampleTime else { return } // degenerate (e.g. instant tap) - drop
        part.insertRecordedNote(
            startTime: gesture.startSampleTime, endTime: endTime,
            startFrequency: gesture.referenceFrequency, endFrequency: gesture.referenceFrequency,
            amplitude: 1,
            recordedPitchBend: gesture.samples)
        cursor = endTime
    }

    private func currentSampleTime() -> Int {
        guard let recordingStart else { return 0 }
        return Int(Date().timeIntervalSince(recordingStart) * sampleRate)
    }

    // MARK: - Sampling timer

    private func startTimer() {
        stopTimer()
        let newTimer = Timer(timeInterval: 1.0 / recordingSampleHz, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        appendSample(to: &activeX, currentFrequency: settings.xFrequency)
        appendSample(to: &activeY, currentFrequency: settings.yFrequency)
        appendSample(to: &activeZ, currentFrequency: settings.zFrequency)
    }

    private func appendSample(to active: inout ActiveGesture?, currentFrequency: Double) {
        guard var gesture = active else { return }
        let cents = 1200 * log2(currentFrequency / gesture.referenceFrequency)
        gesture.samples.append(cents)
        active = gesture
    }
}
