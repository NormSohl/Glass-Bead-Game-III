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
//  The timer itself is a DispatchSourceTimer, not Foundation's RunLoop-based Timer - Norm found
//  the original 80Hz target (chosen against the live-record plan's ~60-100Hz "plenty for vibrato/
//  slides" reasoning) was only actually achieving ~76Hz in a real capture, and 300Hz (closer to
//  what's needed to resolve real musical timing, not just smooth pitch curves) pushes well past
//  where a plain RunLoop Timer stays reliable - GCD's dispatch timers are scheduled off the
//  kernel's own clock rather than RunLoop turns, and hold up at much higher frequencies with less
//  jitter. Still targets the main queue deliberately (not a background queue) - settings.x/y/
//  zFrequency are @Published on AppSettings, main-thread-only state; a background-queue timer
//  reading them alongside HitTestView writing them on the main thread would be a real data race.
//
//  Drone has no live-touch pitch interaction today (just a fixed reference tone + on/off toggle),
//  so dronePart is always left empty here - nothing to capture. An empty Part is a valid,
//  gracefully-handled document, not an error (see SeqDocument/Part).
//

import Foundation
import GBGCore

/// How often the sampling timer ticks while armed - 300Hz, adequate to resolve real musical
/// timing (not just smooth pitch curves, which the original 80Hz target was tuned for).
private let recordingSampleHz: Double = 300

final class RecordingState: ObservableObject {
    @Published private(set) var isRecording = false

    // Set by requestSave() below, observed by ContentView's .fileExporter - the single source
    // of truth for "the save panel should be showing right now," reachable from both the
    // Settings-popover Save button (ControlView) and a keyboard shortcut (KeyActionDispatcher),
    // neither of which can otherwise reach a `.fileExporter` living on ContentView itself (a
    // popover's own content view can't present a panel while the popover is closed - the whole
    // reason a keyboard-triggered save needs this to live somewhere always-present).
    @Published private(set) var pendingExportData: Data?

    // A short-lived status string for ContentView's feedback banner - Norm: reachable feedback
    // for actions (recording start/stop, save) that would otherwise happen silently, especially
    // now they're keyboard-triggerable from outside Settings with no other visible confirmation.
    @Published private(set) var feedbackMessage: String?
    private var feedbackClearWorkItem: DispatchWorkItem?

    private(set) var dronePart = Part(name: "drone")
    private(set) var xPart = Part(name: "x")
    private(set) var yPart = Part(name: "y")
    private(set) var zPart = Part(name: "z")

    private unowned let settings: AppSettings
    private let sampleRateProvider: () -> Double
    private var sampleRate: Double { max(1, sampleRateProvider()) }

    private var recordingStart: Date?
    private var timer: DispatchSourceTimer?

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
        showFeedback("Recording")
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
        let noteCount = [dronePart, xPart, yPart, zPart].reduce(0) { $0 + $1.notes.filter { $0.amplitude > 0 }.count }
        showFeedback(noteCount > 0 ? "Stopped — \(noteCount) note\(noteCount == 1 ? "" : "s")" : "Stopped — nothing captured")
    }

    // MARK: - Save (keyboard-triggerable, outside Settings - see pendingExportData's own comment)

    /// Builds the export data and hands it to ContentView's .fileExporter via pendingExportData -
    /// the same encode step the Settings-popover Save button used to do inline, now shared so a
    /// keyboard shortcut can trigger the identical save panel without opening Settings first.
    func requestSave() {
        guard !isRecording, hasAnyNotes else {
            showFeedback("Nothing to save")
            return
        }
        let scale = MIDIScaleDefinition(
            limit: limitMap[settings.selectedLimit] ?? 5,
            highestRatio: settings.highestRatio,
            lowestRatio: settings.lowestRatio,
            rootFrequency: settings.rootFrequency)
        pendingExportData = SeqMIDICodec.encode(document: exportDocument(), scale: scale, sampleRate: sampleRate)
    }

    /// Called from .fileExporter's isPresented binding once the panel dismisses (success,
    /// failure, or cancel alike) - resets pendingExportData so a later requestSave() can
    /// re-trigger the panel.
    func clearPendingExport() {
        pendingExportData = nil
    }

    /// Called from .fileExporter's own completion closure - separate from clearPendingExport()
    /// since that fires on cancel too (no feedback wanted there), while this only fires with an
    /// actual result.
    func reportSaveResult(_ result: Result<URL, Error>) {
        switch result {
        case .success: showFeedback("Saved")
        case .failure: showFeedback("Save failed")
        }
    }

    private func showFeedback(_ message: String, forSeconds seconds: Double = 1.6) {
        feedbackClearWorkItem?.cancel()
        feedbackMessage = message
        let workItem = DispatchWorkItem { [weak self] in self?.feedbackMessage = nil }
        feedbackClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    // MARK: - Touch lifecycle hooks
    //
    // Called by HitTestView (the graph - X and Y move together, one crosshair) and ZSliderView
    // (Z, its own independent touch). HitTestView's touch also calls sound.beginGraphTouch/
    // endGraphTouch, the thing that actually starts/stops audible sound - this deliberately
    // doesn't call into that (recording capture is independent of what's actually sounding), so
    // Z's own gesture is still captured here even though ZSliderView's touch no longer reaches
    // Sound at all (it can only retune an already-audible Z voice, never start one - see
    // ZSliderView's gesture and Sound.applyZVoiceEnables). No-ops whenever recording isn't armed.

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
        // Z only actually sounds now when the graph itself is being touched, or a previous
        // touch is being held by the pedal (see Sound.applyZVoiceEnables) - a lone Z-slider
        // drag no longer starts sound on its own (see ZSliderView's gesture), so it shouldn't
        // be recorded as a note either: recording one anyway would insert a full-amplitude
        // "phantom" note that plays back audibly despite never having sounded live. Approximate,
        // not exact - if a graph touch or pedal-hold begins *after* this Z drag already started,
        // this call (made every onChanged frame, not just once at drag-start - see ZSliderView)
        // picks it up on the very next frame rather than retroactively; same class of
        // approximation this file already accepts for pedal-extended audible duration outliving
        // a touch's own recorded duration.
        guard activeX != nil || activeY != nil || settings.pedal else { return }
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
        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        let intervalSeconds = 1.0 / recordingSampleHz
        // leeway 0 - a recording session is short (seconds, not hours), so the usual
        // battery-saving reason to allow slack doesn't apply here; precision matters more.
        newTimer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds, leeway: .nanoseconds(0))
        newTimer.setEventHandler { [weak self] in
            self?.tick()
        }
        newTimer.resume()
        timer = newTimer
    }

    private func stopTimer() {
        timer?.cancel()
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
