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
import Combine
import GBGCore
import GBGSound

// All four of the sequencer's Parts, including drone (unlike Graph's GraphAxis, which is
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
// Not private - LiveCaptureState.swift reuses these same constants for the reverse (Graph->Seq)
// direction, so the two stay governed by one definition rather than risking drift between them.
enum GraphMidiChannel {
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
let graphMidiFixedNote = 60
// Middle C's own 12-TET frequency - the reference PitchBendMath.freqToPB encodes every send
// against, matching what Graph's own receive-side decode (PitchBendMath.
// frequencyFromNoteAndPitchBend, called with the same fixed note above) assumes.
private let graphMidiReferenceFrequency = 261.6255653005986

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

    // Live capture (Graph -> Seq, over the same graphMidiOut connection object but the reverse
    // direction) - see LiveCaptureState.swift. Writes directly into this class's own xPart/
    // yPart/zPart (passed in at construction below) rather than a separate copy merged in
    // afterward, so the piano roll shows a gesture growing as it's played - Norm: "I want to see
    // recording in Seq in real time, not after stopping recording." Public so TransportView can
    // observe it directly as its own ObservedObject (SwiftUI won't re-render on a nested
    // object's own @Published changes otherwise).
    private(set) var liveCapture: LiveCaptureState!

    /// Starts/stops live capture. Stops playback first if it's running - the same guard
    /// loadDocument already has, needed here too since capture writes into these same Part
    /// instances and ScorePlayer.advance() reads them from the audio render thread; the two
    /// must never run at once. No document to load afterward - liveCapture already wrote
    /// straight into xPart/yPart/zPart while it ran.
    func toggleLiveCapture() {
        if isPlaying { stop() }
        if !liveCapture.isCapturing { checkpoint("Capture") }
        liveCapture.toggleCapturing()
    }
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

    // Length of a newly entered note (Place or Step). In seconds with the grid off; in beats
    // with it on, so step entry walks the beat grid exactly.
    @Published var noteDurationSeconds: Double = 0.5
    @Published var noteDurationBeats: Double = 1
    var noteDurationSamples: Int {
        if let tempo = activeTempo {
            return max(1, Int((noteDurationBeats * pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sampleRate)).rounded()))
        }
        return max(1, Int(noteDurationSeconds * sampleRate))
    }

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
    // Multiplies the piano roll's pitch axis, which otherwise always auto-fits the whole scale
    // range to the canvas height with no independent zoom - see PianoRollCoordinates.swift's
    // pianoRollFrequencyToScreenY. 1.0 is the original auto-fit; >1 zooms in vertically, same
    // "scale the axis, anchor stays put" model pixelsPerSecond already uses horizontally (no
    // separate vertical pan yet - zooming in pushes the top of the range off-canvas, matching
    // how horizontal zoom already pushes later time off the right edge with no auto-pan).
    @Published var verticalZoomFactor: Double = 1.0

    // Bumped after every mutation to Part/Note contents (a placed note, a handle drag) so
    // PianoRollView's Canvas redraws - Part/Note are plain classes with no Combine publishing.
    @Published var scoreRevision: Int = 0

    // The optional BPM grid. Off: the timeline is plain seconds, no time snapping. On: a
    // bar/beat grid is drawn, ruler shows bar numbers, and drags/placement/step durations snap
    // to it (Option-drag escapes). A loaded document's detected tempo (step 4 of the live-record
    // plan) turns it on with that tempo and downbeat; otherwise the person sets BPM by hand.
    // Metadata only: never rewrites existing notes' times on its own.
    @Published var gridEnabled: Bool = false
    @Published var gridBPM: Double = 120
    @Published var beatsPerBar: Int = 4
    // Snap resolution, in divisions per beat (1 = beats, 2 = eighths, 4 = sixteenths in 4/4).
    @Published var gridSubdivision: Int = 4
    @Published var gridDownbeatOffset: Int = 0

    var activeTempo: TempoInfo? {
        guard gridEnabled, gridBPM > 0 else { return nil }
        return TempoInfo(bpm: gridBPM, downbeatOffset: gridDownbeatOffset, confidence: 1)
    }

    /// `sample` snapped to the grid's subdivision, or unchanged with the grid off.
    func snapTime(_ sample: Int) -> Int {
        guard let tempo = activeTempo else { return sample }
        let step = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sampleRate) / Double(max(1, gridSubdivision))
        guard step > 0 else { return sample }
        let index = ((Double(sample) - Double(tempo.downbeatOffset)) / step).rounded()
        return max(0, tempo.downbeatOffset + Int((index * step).rounded()))
    }

    // The scale/root a loaded .mid declared (SeqMIDICodec's document-level metadata) - carried
    // forward so Save writes the same scale back out, not lost the way it was before this
    // existed. Defaults to Graph's own out-of-the-box defaults (limit 11, 3/1..1/2, middle C) for
    // a piece that's never been imported (built from scratch here via Add Note, or opened from a
    // plain third-party .mid with no scale metadata) - there's no independently-tracked "Seq's
    // own scale" concept otherwise, so this is the least surprising fallback.
    @Published private(set) var currentScale = MIDIScaleDefinition(limit: 11, highestRatio: 3.0, lowestRatio: 0.5, rootFrequency: 261.6255653005986)

    @Published var draggingHandle: DraggingHandle?

    // What a tap on empty canvas does - see PianoRollView's gesture handling. Drags on a note's
    // handles or body edit it in every tool.
    @Published var editTool: EditTool = .select
    // Which voice the Place tool puts notes into.
    @Published var selectedVoice: PartVoice = .x
    // The one note the inspector edits and Delete removes.
    @Published var selection: NoteSelection?

    // Step entry: the voices a step fills, in stepOrder, one tap each; after the last armed
    // voice the playhead (the step cursor) advances by the note duration. stepVoiceIndex says
    // which armed voice the next tap places.
    static let stepOrder: [PartVoice] = [.x, .y, .z, .drone]
    @Published var stepVoices: Set<PartVoice> = [.x, .y, .z] {
        didSet { stepVoiceIndex = 0 }
    }
    @Published private(set) var stepVoiceIndex: Int = 0
    var armedStepVoices: [PartVoice] { Self.stepOrder.filter { stepVoices.contains($0) } }
    var nextStepVoice: PartVoice? {
        let armed = armedStepVoices
        return armed.isEmpty ? nil : armed[min(stepVoiceIndex, armed.count - 1)]
    }

    var isEditingLocked: Bool { liveCapture?.isCapturing ?? false }

    private var playheadTimer: Timer?

    // Internal synth on/off (Step 6 - closing a real gap against the plan's own "three
    // independent, simultaneously-enable-able outputs" promise: Graph Out/Synth Out already
    // had their own toggles, internal synth didn't). Gates only the Triad's per-tone
    // audibility, never audio.startAudio/stopAudio themselves - ScorePlayer.advance() only
    // ever runs from inside Audio's real-time render callback (Audio.swift's
    // AVAudioSourceNode block), so the audio engine has to keep running regardless of this
    // toggle or playback timing/MIDI-out (which reads scorePlayer.currentSample/isPlaying)
    // would break too, not just go silent.
    @Published var internalSynthEnabled: Bool = true {
        didSet { applyInternalSynthEnable() }
    }

    private func applyInternalSynthEnable() {
        audio.triad.enableTriadRootTone(enable: internalSynthEnabled)
        audio.triad.enableTriadXTone(enable: internalSynthEnabled)
        audio.triad.enableTriadYTone(enable: internalSynthEnabled)
        audio.triad.enableTriadZTone(enable: internalSynthEnabled)
    }

    init(settings: SeqSettings) {
        self.settings = settings
        self.sampleRate = audio.sampleRate
        self.minimumNoteLengthSamples = max(1, Int(0.02 * sampleRate))
        scorePlayer = ScorePlayer(
            triad: audio.triad,
            dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart,
            sampleRate: sampleRate)
        audio.scorePlayer = scorePlayer
        // No touch-based enable-gating exists in Seq - all four voices are simply gated on
        // internalSynthEnabled alone; whether anything is actually heard beyond that is
        // governed entirely by whether a Part has a nonzero-amplitude note at the current
        // playhead.
        applyInternalSynthEnable()

        graphMidiOut.initMidi()
        if let index = graphMidiOut.midiDestinations.firstIndex(where: { $0.name == graphVirtualDestinationName }) {
            detectedGraphDestinationIndex = index
        }
        // Named "Seq" so it shows up by that name in Graph's own MIDI Destination picker -
        // that picker is the entire UI this needs on Graph's side, already built and already
        // generic (lists whatever CoreMIDI sees, same-Mac/USB/Network MIDI alike).
        graphMidiOut.initMidiInput(name: "Seq")
        liveCapture = LiveCaptureState(midi: graphMidiOut, xPart: xPart, yPart: yPart, zPart: zPart, sampleRateProvider: { [weak self] in self?.sampleRate ?? 44100 }, pitchBendRangeProvider: { [weak settings] in settings?.pitchBendRange ?? 24 })
        // Bumps scoreRevision on every mutation liveCapture makes to xPart/yPart/zPart while
        // capturing, so the piano roll redraws live instead of only once capture stops.
        liveCapture.onUpdate = { [weak self] in self?.scoreRevision += 1 }
        synthMidiOut.initMidi()
        pitchBendRangeSubscription = settings.$pitchBendRange
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] range in self?.sendSynthPitchBendRange(semitones: range) }
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

    // MARK: - MIDI-out engine (shared core, driven per-output below)

    /// Looks up the current note for `voice` at `sample` and drives `output` on `channel`
    /// accordingly - fires note-on when a genuinely new Note starts (by reference identity),
    /// sends an updated pitch-bend on every call while the same note keeps sounding (this is
    /// what carries a Transition's glide/curve over MIDI, not just one flat pitch per note),
    /// and fires note-off once amplitude drops to 0 or no note is found. `sounding` is the
    /// caller's own per-voice tracking slot (graphMidiSoundingNote/synthMidiSoundingNote),
    /// passed by reference so this one function serves both outputs identically. Shared by
    /// both pollPlayback (continuous, ~30Hz during real playback) and scrub (discrete, per
    /// drag update) - both need identical note-on/hold/off logic, just called at different
    /// cadences.
    private func driveMidiOutput(_ output: SeqMidiOut, channel: Int, note: Note?, sample: Int, sounding: inout Note?) {
        guard let note, note.amplitude > 0 else {
            if sounding != nil {
                output.noteOff(channel: channel, note: graphMidiFixedNote)
                sounding = nil
            }
            return
        }

        let frequency = note.getCurrentFrequency(percentComplete: note.percentComplete(at: sample))
        let pitchBendValue = PitchBendMath.freqToPB(frequency: frequency, referenceFrequency: graphMidiReferenceFrequency, pitchBendRange: settings.pitchBendRange)

        if sounding !== note {
            let velocity = min(127, max(1, Int(note.amplitude * 127)))
            output.noteOn(channel: channel, note: graphMidiFixedNote, velocity: velocity)
            sounding = note
        }
        output.pitchBend(channel: channel, value: pitchBendValue)
    }

    /// Flushes any voices still tracked as sounding on `output` - called when a whole
    /// play/scrub session ends (not just per-voice reaching amplitude 0 naturally), since
    /// ending playback mid-note wouldn't otherwise produce a note-off.
    private func flushMidiOutput(_ output: SeqMidiOut, sounding: inout [PartVoice: Note], channelForVoice: (PartVoice) -> Int) {
        for (voice, _) in sounding {
            output.noteOff(channel: channelForVoice(voice), note: graphMidiFixedNote)
        }
        sounding.removeAll()
    }

    private func updateGraphMidiOutput(voice: PartVoice, at sample: Int) {
        guard graphOutputEnabled else { return }
        var sounding = graphMidiSoundingNote[voice]
        driveMidiOutput(graphMidiOut, channel: GraphMidiChannel.forVoice(voice), note: part(for: voice).getCurrentNote(timeSlice: sample), sample: sample, sounding: &sounding)
        graphMidiSoundingNote[voice] = sounding
    }

    private func flushGraphMidiOutput() {
        flushMidiOutput(graphMidiOut, sounding: &graphMidiSoundingNote, channelForVoice: GraphMidiChannel.forVoice)
    }

    // MARK: - External synth MIDI-out (Step 4)
    //
    // A second, independent connection alongside the Graph one above - Norm: "we'll also want
    // a dedicated Seq midi out port to connect with synths." Unlike the Graph connection
    // (fixed channels matching Graph's own established defaults, since Graph's receive side
    // expects them exactly), a real synth's channel routing is arbitrary/whatever the
    // performer's rig expects - user-configurable per voice, defaulting to 1/2/3/4. MPE/RPN
    // pitch-bend-sensitivity declaration is deliberately not sent here (the plan calls it
    // optional for this connection) - a real synth on the receiving end may need its pitch
    // bend range set by hand to match, same caveat Graph's own "Tune Midi" UI already carries
    // for modular/analog gear that can't be retuned automatically over MIDI.
    //
    // Update 2026-10-05: the pitch bend range IS now sent here (RPN 0 on each voice channel, see
    // sendSynthPitchBendRange) whenever the output is switched on, its destination or a channel
    // changes, the Pitch Bend Range setting changes, or playback starts - so a synth that honors
    // RPN 0 follows Seq's setting by itself. Gear that ignores RPN still needs setting by hand.
    private let synthMidiOut = SeqMidiOut()
    @Published var synthOutputEnabled: Bool = false {
        didSet { if synthOutputEnabled { sendSynthPitchBendRange() } }
    }
    @Published var synthDestinationIndex: Int = 0 {
        didSet {
            synthMidiOut.setMidiDestination(destination: synthDestinationIndex)
            sendSynthPitchBendRange()
        }
    }
    var synthMidiDestinations: [SeqMidiOut.MidiEndpointInfo] { synthMidiOut.midiDestinations }

    @Published var synthDroneChannel: Int = 1 { didSet { sendSynthPitchBendRange() } }
    @Published var synthXChannel: Int = 2 { didSet { sendSynthPitchBendRange() } }
    @Published var synthYChannel: Int = 3 { didSet { sendSynthPitchBendRange() } }
    @Published var synthZChannel: Int = 4 { didSet { sendSynthPitchBendRange() } }

    private var pitchBendRangeSubscription: AnyCancellable?

    /// RPN 0 (Pitch Bend Sensitivity) on every channel Synth Out uses, once each. `semitones`
    /// is passed explicitly by the settings subscription, which fires before the new value is
    /// stored.
    private func sendSynthPitchBendRange(semitones: Int? = nil) {
        guard synthOutputEnabled, !synthMidiDestinations.isEmpty else { return }
        let channels = Set([synthDroneChannel, synthXChannel, synthYChannel, synthZChannel]).sorted()
        for channel in channels {
            synthMidiOut.pitchBendSensitivity(channel: channel, semitones: semitones ?? settings.pitchBendRange)
        }
    }

    private func synthChannel(for voice: PartVoice) -> Int {
        switch voice {
        case .drone: return synthDroneChannel
        case .x: return synthXChannel
        case .y: return synthYChannel
        case .z: return synthZChannel
        }
    }

    private var synthMidiSoundingNote: [PartVoice: Note] = [:]

    private func updateSynthMidiOutput(voice: PartVoice, at sample: Int) {
        guard synthOutputEnabled else { return }
        var sounding = synthMidiSoundingNote[voice]
        driveMidiOutput(synthMidiOut, channel: synthChannel(for: voice), note: part(for: voice).getCurrentNote(timeSlice: sample), sample: sample, sounding: &sounding)
        synthMidiSoundingNote[voice] = sounding
    }

    private func flushSynthMidiOutput() {
        flushMidiOutput(synthMidiOut, sounding: &synthMidiSoundingNote, channelForVoice: synthChannel(for:))
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
        sendSynthPitchBendRange() // in case the synth was switched on or reset since
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
        flushSynthMidiOutput()
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
            updateSynthMidiOutput(voice: voice, at: playheadSample)
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
            updateSynthMidiOutput(voice: voice, at: playheadSample)
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        audio.stopAudio()
        flushGraphMidiOutput()
        flushSynthMidiOutput()
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
    }

    /// Emergency stop: silences the internal synth immediately (via stop()/endScrub(), which
    /// mute the mixer and - since ScorePlayer.stop() was fixed alongside this - hard-zero its
    /// amplitudes rather than leaving them frozen mid-note) and broadcasts a MIDI note-off on
    /// every channel either output could possibly be using - not just whatever this session's
    /// own graphMidiSoundingNote/synthMidiSoundingNote tracking currently believes is sounding.
    /// That per-voice tracking is exactly what can desync (pollPlayback runs at a fixed ~30Hz -
    /// see startPlayheadPolling - so a note shorter than one poll interval can be skipped
    /// entirely: a fresh note-on then fires for whatever note the next poll happens to land on,
    /// with no note-off ever sent for the one that got skipped), so a real panic can't rely on
    /// it - it has to hit every channel directly regardless of what's tracked.
    func panic() {
        if isPlaying { stop() }
        if isScrubbing { endScrub() }
        audio.stopAudio()
        for voice in PartVoice.allCases {
            graphMidiOut.noteOff(channel: GraphMidiChannel.forVoice(voice), note: graphMidiFixedNote)
            synthMidiOut.noteOff(channel: synthChannel(for: voice), note: graphMidiFixedNote)
        }
        graphMidiSoundingNote.removeAll()
        synthMidiSoundingNote.removeAll()
        drivenDroneFrequency = nil
        drivenDroneAmplitude = nil
    }

    // MARK: - Playhead positioning (not playback/scrub)

    /// Also the step cursor: moving it starts a fresh step (the next tap is the first armed voice).
    func setPlayhead(to sample: Int) {
        guard !isPlaying, !isScrubbing else { return }
        playheadSample = max(0, sample)
        stepVoiceIndex = 0
    }

    // MARK: - Note entry (Place and Step tools)

    /// Place tool: a held note for `selectedVoice` at (time, frequency), `noteDurationSamples`
    /// long, overwriting whatever that voice had there. Part.placeNote keeps the Part tiled
    /// with silent rests, which ScorePlayer.advance() depends on (a gap reads as an exhausted
    /// part and ends playback).
    func placeNote(atTime time: Int, frequency: Double) {
        insertHeldNote(voice: selectedVoice, at: max(0, time), frequency: frequency)
    }

    /// Step tool: places the next armed voice's note at the playhead (the step cursor). Once
    /// every armed voice has a note in this step, the cursor advances by the note duration -
    /// so a three-voice chord is three taps, and they all start together like Graph's chord.
    func enterStep(frequency: Double) {
        guard let voice = nextStepVoice else { return }
        insertHeldNote(voice: voice, at: playheadSample, frequency: frequency)
        if stepVoiceIndex + 1 >= armedStepVoices.count {
            advanceStep()
        } else {
            stepVoiceIndex += 1
        }
    }

    /// Moves the step cursor one step forward without placing anything (a rest), or finishes
    /// a partly entered chord.
    func advanceStep() {
        guard !isPlaying, !isScrubbing else { return }
        playheadSample += noteDurationSamples
        stepVoiceIndex = 0
    }

    func stepBack() {
        guard !isPlaying, !isScrubbing else { return }
        playheadSample = max(0, playheadSample - noteDurationSamples)
        stepVoiceIndex = 0
    }

    private func insertHeldNote(voice: PartVoice, at time: Int, frequency: Double) {
        guard prepareForEdit() else { return }
        checkpoint("Add Note")
        let note = part(for: voice).placeNote(startTime: time, endTime: time + noteDurationSamples, startFrequency: frequency, endFrequency: frequency)
        selection = NoteSelection(voice: voice, note: note)
        scoreRevision += 1
    }

    // MARK: - Note editing (handles, body drag, inspector)

    /// Stops playback/scrub before anything mutates a Note - ScorePlayer.advance() reads the
    /// same Note objects on the real-time audio thread, so editing only while stopped avoids
    /// needing any locking around the mutation. False while live capture is writing into the
    /// Parts, which edits must not race.
    private func prepareForEdit() -> Bool {
        guard !isEditingLocked else { return false }
        if isPlaying { stop() }
        if isScrubbing { endScrub() }
        return true
    }

    func beginDraggingHandle(_ handle: DraggingHandle) {
        guard prepareForEdit() else { return }
        checkpoint(handle.grip == .body ? "Move Note" : "Edit Note")
        draggingHandle = handle
        selection = NoteSelection(voice: handle.voice, note: handle.note)
    }

    func endDraggingHandle() {
        draggingHandle = nil
    }

    func select(_ selection: NoteSelection?) {
        self.selection = selection
    }

    /// Moves one end of a note in time and pitch together - what a handle drag does.
    func setEdge(_ edge: NoteEdge, of selection: NoteSelection, time: Int, frequency: Double) {
        guard prepareForEdit() else { return }
        part(for: selection.voice).setEdge(edge, of: selection.note, to: time, minimumNoteLength: minimumNoteLengthSamples)
        applyPitch(edge, of: selection, frequency: frequency)
    }

    func setTime(_ edge: NoteEdge, of selection: NoteSelection, time: Int) {
        guard prepareForEdit() else { return }
        checkpoint("Change Time")
        part(for: selection.voice).setEdge(edge, of: selection.note, to: time, minimumNoteLength: minimumNoteLengthSamples)
        scoreRevision += 1
    }

    func setPitch(_ edge: NoteEdge, of selection: NoteSelection, frequency: Double, actionName: String = "Change Pitch") {
        guard prepareForEdit(), frequency > 0 else { return }
        checkpoint(actionName)
        applyPitch(edge, of: selection, frequency: frequency)
    }

    private func applyPitch(_ edge: NoteEdge, of selection: NoteSelection, frequency: Double) {
        guard frequency > 0 else { return }
        switch edge {
        case .start: selection.note.startFrequency = frequency
        case .end: selection.note.endFrequency = frequency
        }
        showDrivenFrequency(voice: selection.voice, frequency: frequency, amplitude: selection.note.amplitude)
        scoreRevision += 1
    }

    /// Moves a whole note: its start to `startTime` (length kept, stopping at neighbors) and
    /// both pitches to the given values - what a body drag does.
    func moveNote(_ selection: NoteSelection, startTime: Int, startFrequency: Double, endFrequency: Double) {
        guard prepareForEdit() else { return }
        part(for: selection.voice).moveNote(selection.note, toStart: startTime)
        selection.note.startFrequency = startFrequency
        selection.note.endFrequency = endFrequency
        showDrivenFrequency(voice: selection.voice, frequency: startFrequency, amplitude: selection.note.amplitude)
        scoreRevision += 1
    }

    func setProfile(_ kind: TransitionKind, of selection: NoteSelection) {
        guard prepareForEdit(), kind != selection.note.transitionKind else { return }
        checkpoint("Change Profile")
        selection.note.selectTransition(kind)
        scoreRevision += 1
    }

    /// Turns a bend back into a held note: end pitch = start pitch.
    func holdPitch(of selection: NoteSelection) {
        setPitch(.end, of: selection, frequency: selection.note.startFrequency, actionName: "Hold Pitch")
    }

    /// Drops a note's recorded contour buffer, falling back to Linear first if that contour is
    /// what's playing - never leave the active transition pointing at discarded data.
    func purgeRecordedData(of selection: NoteSelection) {
        guard prepareForEdit() else { return }
        checkpoint("Purge Recorded Data")
        if selection.note.transitionKind == .recordedContour {
            selection.note.selectTransition(.linear)
        }
        selection.note.recordedPitchBend = nil
        scoreRevision += 1
    }

    func deleteSelectedNote() {
        guard let selection, prepareForEdit() else { return }
        checkpoint("Delete Note")
        part(for: selection.voice).removeNote(selection.note)
        self.selection = nil
        scoreRevision += 1
    }

    private func showDrivenFrequency(voice: PartVoice, frequency: Double, amplitude: Double) {
        switch voice {
        case .x: settings.xFrequency = frequency
        case .y: settings.yFrequency = frequency
        case .z: settings.zFrequency = frequency
        case .drone: updateDrivenDroneDisplay(frequency: frequency, amplitude: amplitude)
        }
    }

    // MARK: - Undo

    // The window's own undo manager (set by SequencerView), so ⌘Z/⇧⌘Z and the Edit menu work
    // with no extra plumbing. Every edit records a snapshot of all four Parts just before it
    // changes anything; undoing restores that snapshot and registers the current state as the
    // redo. A drag is one undo step (checkpointed once, when it begins).
    weak var undoManager: UndoManager?

    private func snapshotAll() -> [PartVoice: PartSnapshot] {
        Dictionary(uniqueKeysWithValues: PartVoice.allCases.map { ($0, part(for: $0).snapshot()) })
    }

    private func checkpoint(_ actionName: String) {
        guard let undoManager else { return }
        let snapshot = snapshotAll()
        undoManager.registerUndo(withTarget: self) { $0.restore(snapshot, actionName: actionName) }
        undoManager.setActionName(actionName)
    }

    private func restore(_ snapshot: [PartVoice: PartSnapshot], actionName: String) {
        // Undo can't run while capture is writing into the Parts; put the step back so it isn't lost.
        guard prepareForEdit() else {
            undoManager?.registerUndo(withTarget: self) { $0.restore(snapshot, actionName: actionName) }
            undoManager?.setActionName(actionName)
            return
        }
        checkpoint(actionName) // the redo (or, when redoing, the next undo)
        for (voice, partSnapshot) in snapshot { part(for: voice).restore(partSnapshot) }
        if let selection, !part(for: selection.voice).soundingNotes.contains(where: { $0 === selection.note }) {
            self.selection = nil
        }
        stepVoiceIndex = 0
        scoreRevision += 1
    }

    // MARK: - Save/load (Step 5)

    func exportDocument() -> SeqDocument {
        SeqDocument(dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart, tempoInfo: activeTempo)
    }

    /// Replaces the current piece's contents in place - SequencerState's own dronePart/xPart/
    /// yPart/zPart stay the same objects (ScorePlayer and the UI already hold references to
    /// them), only their notes change. Stops any active playback/scrub first, same guard
    /// beginDraggingHandle already uses, since a load mutating Part.notes out from under
    /// ScorePlayer.advance() mid-playback would be exactly the unsynchronized-mutation risk
    /// that guard exists to avoid.
    func loadDocument(_ document: SeqDocument, scale: MIDIScaleDefinition? = nil, actionName: String = "Open") {
        if isPlaying { stop() }
        if isScrubbing { endScrub() }
        checkpoint(actionName)
        document.apply(toDronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)
        // Every note is a pitch bend now - fold legacy Flat notes (older files, plain .mid
        // imports) into equal-pitch Linear ones, which sound identical.
        for part in [dronePart, xPart, yPart, zPart] { part.normalizeFlatTransitions() }
        selection = nil
        stepVoiceIndex = 0
        if let tempo = document.tempoInfo {
            gridBPM = tempo.bpm
            gridDownbeatOffset = tempo.downbeatOffset
            gridEnabled = true
        }
        // nil (not "reset to the default") when the source had no scale metadata at all - a
        // plain third-party .mid, say - so a piece with a previously-known scale doesn't
        // silently forget it just because it was reloaded/resegmented.
        if let scale { currentScale = scale }
        scoreRevision += 1
        playheadSample = 0
    }

    // MARK: - Import segmentation (Step 4)

    /// Whether `document` looks like a raw, unsegmented live recording - any note across its
    /// four parts still carrying an active `.recordedContour` transition - rather than a normal
    /// hand-edited or already-segmented piece. Checked directly against the decoded DTOs (no
    /// Part instantiation needed, since `NoteDTO.transitionKind` is already public). See
    /// RecordingState in the Graph target - the only current producer of documents shaped this
    /// way (always one long recordedContour note per touch-gesture, per voice).
    static func looksLikeRawRecording(_ document: SeqDocument) -> Bool {
        [document.dronePart, document.xPart, document.yPart, document.zPart]
            .flatMap { $0.notes }
            .contains { $0.transitionKind == .recordedContour }
    }

    /// Runs the live-record plan's step 4 segmentation pass on `document` and loads the result -
    /// the "segment immediately on import" path. Just loads the raw document as-is, then hands
    /// off to applySegmentation() below for the actual work, so the two paths (segment at
    /// import time vs. load raw now and segment later, as its own explicit step - Norm: "record
    /// the uncut version first... fun to see if the graph changes at all when segmentation is
    /// applied") share one real implementation instead of two.
    func loadSegmentedDocument(_ document: SeqDocument, scale: MIDIScaleDefinition? = nil) {
        loadDocument(document, scale: scale)
        applySegmentation()
    }

    /// Runs segmentation on whatever's currently loaded, in place - lets a raw recording be
    /// loaded first (Load As-Is at import time, or already the result of a previous call to
    /// this) and segmented later as its own deliberate step, rather than only ever at import
    /// time. Segments every note in all four parts via `Part.segmentAllNotes` - a safe no-op
    /// passthrough for notes without a `recordedPitchBend` buffer, so calling this on
    /// already-segmented (or partly hand-edited) material is harmless, not destructive - segments
    /// what there is to segment and leaves the rest untouched. Detects tempo from the segmented
    /// pieces' own onset times and carries it along as metadata - nil (no confident tempo) is
    /// the correct, expected outcome for unmetered/melismatic material, not a failure (see
    /// TempoDetection.swift's own doc comment). Doesn't touch currentScale - segmenting in place
    /// has no new scale information of its own to offer.
    func applySegmentation() {
        let segmentedDrone = dronePart.segmentAllNotes(sampleRate: sampleRate)
        let segmentedX = xPart.segmentAllNotes(sampleRate: sampleRate)
        let segmentedY = yPart.segmentAllNotes(sampleRate: sampleRate)
        let segmentedZ = zPart.segmentAllNotes(sampleRate: sampleRate)

        let onsets = [segmentedDrone, segmentedX, segmentedY, segmentedZ]
            .flatMap { $0.notes }
            .filter { $0.amplitude > 0 } // rests aren't musical onsets
            .map { $0.startTime }
            .sorted()
        let tempo = detectTempo(onsetTimes: onsets, sampleRate: sampleRate)

        let segmentedDocument = SeqDocument(dronePart: segmentedDrone, xPart: segmentedX, yPart: segmentedY, zPart: segmentedZ, tempoInfo: tempo)
        loadDocument(segmentedDocument, actionName: "Segment")
    }
}

enum EditTool: Hashable {
    case select, place, step
}

/// One sounding note, by voice and identity (Note is a class, compared by reference).
struct NoteSelection: Equatable {
    let voice: PartVoice
    let note: Note

    static func == (lhs: NoteSelection, rhs: NoteSelection) -> Bool {
        lhs.voice == rhs.voice && lhs.note === rhs.note
    }
}

/// What a drag on a note grabbed: one end's handle, or the line itself (moves the whole note).
enum DragGrip: Equatable {
    case edge(NoteEdge)
    case body
}

struct DraggingHandle: Equatable {
    let voice: PartVoice
    let note: Note
    let grip: DragGrip

    // Note is a class, not Equatable by value - compare by identity.
    static func == (lhs: DraggingHandle, rhs: DraggingHandle) -> Bool {
        lhs.voice == rhs.voice && lhs.grip == rhs.grip && lhs.note === rhs.note
    }
}
