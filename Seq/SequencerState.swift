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

    // The currently loaded document's detected tempo (step 4 of the live-record plan) - set
    // straight from whatever SeqDocument.loadDocument was last given (nil for a plain hand-built
    // piece, a plain "Load As-Is" import, or a segmented import over unmetered/melismatic
    // material - all three are the same "no confident grid" case to PianoRollView). Metadata
    // only: never touches a Note's own startTime/endTime, just gates the optional bar-line
    // overlay and its opt-in snap-on-drag.
    @Published private(set) var tempoInfo: TempoInfo?

    @Published var draggingHandle: DraggingHandle?

    // Which voice "Add Note" places into, and whether the next canvas tap places a note instead
    // of moving the playhead - see PianoRollView's tap handling.
    @Published var selectedVoice: PartVoice = .x
    @Published var isPlacingNote: Bool = false

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
        synthMidiOut.initMidi()
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
        let pitchBendValue = PitchBendMath.freqToPB(frequency: frequency, referenceFrequency: graphMidiReferenceFrequency, pitchBendRange: graphMidiPitchBendRange)

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
    private let synthMidiOut = SeqMidiOut()
    @Published var synthOutputEnabled: Bool = false
    @Published var synthDestinationIndex: Int = 0 {
        didSet { synthMidiOut.setMidiDestination(destination: synthDestinationIndex) }
    }
    var synthMidiDestinations: [SeqMidiOut.MidiEndpointInfo] { synthMidiOut.midiDestinations }

    @Published var synthDroneChannel: Int = 1
    @Published var synthXChannel: Int = 2
    @Published var synthYChannel: Int = 3
    @Published var synthZChannel: Int = 4

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

    // MARK: - Save/load (Step 5)

    func exportDocument() -> SeqDocument {
        SeqDocument(dronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)
    }

    /// Replaces the current piece's contents in place - SequencerState's own dronePart/xPart/
    /// yPart/zPart stay the same objects (ScorePlayer and the UI already hold references to
    /// them), only their notes change. Stops any active playback/scrub first, same guard
    /// beginDraggingHandle already uses, since a load mutating Part.notes out from under
    /// ScorePlayer.advance() mid-playback would be exactly the unsynchronized-mutation risk
    /// that guard exists to avoid.
    func loadDocument(_ document: SeqDocument) {
        if isPlaying { stop() }
        if isScrubbing { endScrub() }
        document.apply(toDronePart: dronePart, xPart: xPart, yPart: yPart, zPart: zPart)
        tempoInfo = document.tempoInfo
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

    /// Runs the live-record plan's step 4 segmentation pass on `document` and loads the result.
    /// Segments every note in all four parts via `Part.segmentAllNotes` - a safe no-op
    /// passthrough for notes without a `recordedPitchBend` buffer (see that function's own doc
    /// comment), so this is safe to call even on a document that mixes raw-recording and plain
    /// hand-placed notes, not just a pure recording. Detects tempo from the segmented pieces'
    /// own onset times and carries it along as the resulting SeqDocument's metadata - nil (no
    /// confident tempo) is the correct, expected outcome for unmetered/melismatic material, not
    /// a failure (see TempoDetection.swift's own doc comment).
    func loadSegmentedDocument(_ document: SeqDocument) {
        let rawDrone = Part(name: "drone")
        let rawX = Part(name: "x")
        let rawY = Part(name: "y")
        let rawZ = Part(name: "z")
        document.apply(toDronePart: rawDrone, xPart: rawX, yPart: rawY, zPart: rawZ)

        let segmentedDrone = rawDrone.segmentAllNotes(sampleRate: sampleRate)
        let segmentedX = rawX.segmentAllNotes(sampleRate: sampleRate)
        let segmentedY = rawY.segmentAllNotes(sampleRate: sampleRate)
        let segmentedZ = rawZ.segmentAllNotes(sampleRate: sampleRate)

        let onsets = [segmentedDrone, segmentedX, segmentedY, segmentedZ]
            .flatMap { $0.notes }
            .filter { $0.amplitude > 0 } // rests aren't musical onsets
            .map { $0.startTime }
            .sorted()
        let tempo = detectTempo(onsetTimes: onsets, sampleRate: sampleRate)

        let finalDocument = SeqDocument(dronePart: segmentedDrone, xPart: segmentedX, yPart: segmentedY, zPart: segmentedZ, tempoInfo: tempo)
        loadDocument(finalDocument)
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
