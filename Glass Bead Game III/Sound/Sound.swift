//
//  Sound.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 3/14/24.
//
// This class serves to abstract internal audio control. Audio output can be to internal synthesis or to external midi output.
// These are very different but both are controlled by a single set of abstracted functions which are defined here.

import Foundation
import GBGCore
import GBGSound

class Sound {
    var midi = Midi()
    var audio = Audio()
    
    var outputToAudio = true
    var outputToMidi = true

    // Attached once by AppSettings.init() (sound.settings = self) - Sound is a plain global
    // constructed before any AppSettings exists, so this starts nil and is filled in as soon as
    // one is. enableDrone/enableX/enableY/enableZ below read straight through it rather than
    // keeping their own copies: those used to be separate stored `var`s with their own hardcoded
    // defaults, written only by ControlView's onChange(of: settings.playDrone) (etc.) - which
    // fires on toggle changes, never at launch, so the two defaults had to be hand-kept in sync
    // and silently drifted out of sync at least once (drone audibly playing despite the Drone
    // toggle showing unchecked). Reading straight through settings removes the second copy
    // entirely - the toggle's own state is the only state, so there's nothing left to drift.
    weak var settings: AppSettings?
    var enableDrone: Bool { settings?.playDrone ?? false }
    var enableX: Bool { settings?.playNoteX ?? false }
    var enableY: Bool { settings?.playNoteY ?? false }
    var enableZ: Bool { settings?.playNoteZ ?? false }

    // How many touch zones (the X/Y graph, the Z slider) are currently held down. X/Y and Z are
    // independent simultaneous touches now, but they share one audio engine/MIDI stream - so
    // starting/stopping the engine is reference-counted rather than gated by either touch alone,
    // or releasing one finger while the other is still held would wrongly silence everything.
    private var activeTouchCount = 0


    func initSound(){
        midi.initMidi()
        // Midi.onEvent already dispatches to the main queue from CoreMIDI's own receive
        // thread, but that alone isn't enough to avoid SwiftUI's "publishing changes from
        // within view updates" undefined behavior - confirmed via a real crash/warning log
        // while live-testing external MIDI drive (Console showed this firing on every single
        // incoming event). A second async hop here pushes the actual @Published mutations
        // (in handleIncomingMidi and everything it calls) to a genuinely fresh run-loop turn,
        // decoupled from whatever SwiftUI happens to be doing on the main queue at the moment
        // CoreMIDI's own dispatch lands - same "don't mutate published state synchronously
        // inside another callback" precedent this app already established elsewhere (see the
        // dissonance field's RefinementTrigger/ImageCache split).
        midi.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleIncomingMidi(channel: event.channel, kind: event.kind)
            }
        }
    }

    // Split into three independent groups rather than one "recompute everything" function -
    // Norm: pedal-sustained graph notes were cutting out the moment the Z-slider was touched,
    // because a single shared apply-everything call, fired from *any* zone's begin/end, was
    // recomputing X/Y's enable from graphTouchCount even when it was the Z-slider (not the
    // graph) that triggered the call. graphTouchCount was correctly 0 at that point (the graph
    // touch had already ended) - the touch count was right, but recomputing X/Y at all in
    // response to an unrelated zone's touch was the bug: a pedal-sustained voice must only ever
    // be touched by its own zone's begin/end, or the pedal being released, never by another
    // zone's activity. Each begin/end below now only calls the group(s) it actually owns.
    // X/Y follow "is anything being touched" (activeTouchCount), same rule Z/drone already
    // use below - not graphTouchCount specifically. Norm: while the Z-slider is being dragged
    // (graph itself untouched), X and Y should still be heard at whatever pitch they were most
    // recently set to, not go silent just because the graph zone specifically isn't held. This
    // used to be graphTouchCount-gated, deliberately isolated from Z's own touch (see this
    // file's git history for the pedal-cutout bug that isolation originally fixed) - now that
    // beginZTouch/endZTouch call this function too (below), a plain activeTouchCount check
    // gets the same pedal-safety property for free: those functions still skip recomputing
    // anything while pedal is held, exactly like beginGraphTouch/endGraphTouch already do.
    private func applyGraphVoiceEnables(){
        audio.triad.enableTriadXTone(enable: enableX && (activeTouchCount > 0 || xExternallyDriven))
        audio.triad.enableTriadYTone(enable: enableY && (activeTouchCount > 0 || yExternallyDriven))
        midi.xMidiEnable = enableX && (activeTouchCount > 0 || xExternallyDriven)
        midi.yMidiEnable = enableY && (activeTouchCount > 0 || yExternallyDriven)
    }

    // Z follows "is anything being touched" - Norm wants Z, when enabled, to always sound
    // whenever the graph is touched, at 1/1 by default or whatever the Z-slider was last
    // dragged to, not only while the Z-slider itself is actively held. Called from every
    // zone's begin/end below, same as applyDroneVoiceEnable and (now) applyGraphVoiceEnables
    // above, for that reason.
    private func applyZVoiceEnables(){
        audio.triad.enableTriadZTone(enable: enableZ && activeTouchCount > 0)
        midi.zMidiEnable = enableZ && activeTouchCount > 0
    }

    // Drone has no touch zone of its own, so it follows "is anything being touched" - any zone
    // beginning/ending legitimately affects it, unlike X/Y above (Z now follows the same rule,
    // see applyZVoiceEnables just above).
    private func applyDroneVoiceEnable(){
        audio.triad.enableTriadRootTone(enable: enableDrone && activeTouchCount > 0)
        midi.rootMidiEnable = enableDrone && activeTouchCount > 0
    }

    private func startEngine(amp: Float){
        if outputToAudio {audio.startAudio(amp: amp)}
        if outputToMidi {midi.startMidi()}
    }

    private func stopEngine(){
        audio.stopAudio()
        midi.stopMidi()
    }

    /// Call when the graph (X/Y) touch zone begins. Touches the graph's own voice group plus
    /// Z and drone (both follow "is anything touched," not their own zone - see
    /// applyZVoiceEnables/applyDroneVoiceEnable), independent of whether the Z-slider is also
    /// currently held - the shared engine itself starts only on the overall 0->1 transition,
    /// so an already-active Z-slider touch doesn't get redundantly restarted.
    func beginGraphTouch(amp: Float) {
        activeTouchCount += 1
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    /// Call when the graph touch zone ends. Disables X/Y (unless `pedal` is held, matching the
    /// existing sustain behavior - voices keep sounding regardless of touch state until the
    /// pedal itself is released), re-evaluates Z/drone the same way, and stops the shared
    /// engine only once every zone has ended.
    func endGraphTouch(pedal: Bool) {
        activeTouchCount = max(0, activeTouchCount - 1)
        if !pedal {
            applyGraphVoiceEnables()
            applyZVoiceEnables()
            applyDroneVoiceEnable()
            if activeTouchCount == 0 { stopEngine() }
        }
    }

    /// Z-slider touch begin/end. Touches all three groups, same as beginGraphTouch/
    /// endGraphTouch - X/Y now follow activeTouchCount (see applyGraphVoiceEnables' own
    /// comment), so a Z-only touch legitimately affects them too: X/Y should be heard at
    /// their most recent pitch while Z is being changed, even though the graph itself isn't
    /// touched. Pedal safety carries over unchanged - endZTouch skips recomputing anything
    /// while pedal is held, exactly like endGraphTouch does, so a pedal-sustained voice still
    /// can't be silenced by Z-slider activity.
    func beginZTouch(amp: Float) {
        activeTouchCount += 1
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    func endZTouch(pedal: Bool) {
        activeTouchCount = max(0, activeTouchCount - 1)
        if !pedal {
            applyGraphVoiceEnables()
            applyZVoiceEnables()
            applyDroneVoiceEnable()
            if activeTouchCount == 0 { stopEngine() }
        }
    }

    /// For touch sources that aren't a specific voice zone - currently just the sequencer's
    /// play/scrub, which manages each voice's amplitude directly (ScorePlayer writes it every
    /// sample, bypassing the enable-flag mechanism above entirely) and only needs the shared
    /// engine gated, not applyLiveVoiceEnables.
    func beginTouch(amp: Float) {
        activeTouchCount += 1
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    func endTouch(pedal: Bool) {
        activeTouchCount = max(0, activeTouchCount - 1)
        if activeTouchCount == 0 && !pedal { stopEngine() }
    }

    /// Call when the pedal toggle itself is released (not a touch ending) - Norm: a real damper
    /// pedal silences whatever it was sustaining the instant it's lifted, not on the next key
    /// press. Nothing was calling this before, so unchecking "pedal" while a touch-released note
    /// was still sustaining left it sounding indefinitely - confirmed directly by logging live
    /// tone amplitudes across a release-while-sustaining test. No-op if something is still
    /// actively touched (lifting the pedal mid-touch shouldn't cut off an active touch, only
    /// whatever was ONLY still sounding because of the pedal).
    func releasePedal() {
        guard activeTouchCount == 0 else { return }
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        stopEngine()
    }

    /// Emergency stop: forces every voice silent and every touch/pedal/external-MIDI-drive
    /// bookkeeping flag back to zero, regardless of what got them stuck in the first place -
    /// the manual escape hatch for whatever the state-tracking bugs this is meant to guard
    /// against haven't been found and fixed yet (see beginExternalDrive/beginExternalDroneDrive
    /// for one real example: an unmatched extra note-on used to desync activeTouchCount
    /// permanently). Safe to call at any time, touched or not.
    func panic() {
        activeTouchCount = 0
        xExternallyDriven = false
        yExternallyDriven = false
        zExternallyDriven = false
        droneExternallyDriven = false
        lastIncomingNote.removeAll()
        lastIncomingDroneNote = nil
        settings?.externallyDrivenVoices.removeAll()
        settings?.pedal = false
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        stopEngine()
    }

    func setRootPitch(frequency: Double){
        audio.triad.setTriadRootPitch (frequency: frequency)
        midi.setMidiReferencePitch(frequency: frequency)
    }
    
    func setXPitch(frequency: Double){
        audio.triad.setTriadXPitch(frequency: frequency)
        midi.setMidiXPitch(frequency: frequency)
    }
    
    func setYPitch(frequency: Double){
        audio.triad.setTriadYPitch(frequency: frequency)
        midi.setMidiYPitch(frequency: frequency)
    }

    func setZPitch(frequency: Double){
        audio.triad.setTriadZPitch(frequency: frequency)
        midi.setMidiZPitch(frequency: frequency)
    }
    
    func setPitchBendRange(pitchBendRange: Int){
        midi.setMidiPitchBendRange(pitchBendRange: pitchBendRange)
    }

    func setPitchBendRangeMPE(pitchBendRange: Int){
        midi.setMidiPitchBendRangeMPE(pitchBendRange: pitchBendRange)
    }

    func setUseMPE(useMpe: Bool){
        midi.useMPE(useMpe: useMpe)
    }

    func setRootNote(midiNote: Int){
        midi.setRootNote(note: midiNote)
    }

    // MARK: - External MIDI drive (generic MIDI input, step 3 of the standalone-sequencer plan)
    //
    // Lets an external MIDI source - a controller, or eventually a standalone Seq app - drive
    // X/Y/Z independently via note-on/note-off on that voice's own channel (see
    // Midi.onEvent/handleIncomingMidi below). Unlike a graph touch, which always moves X and Y
    // together as one crosshair, each externally-driven voice enables/disables on its own,
    // since a MIDI controller can hold an X note without an adjoining Y note - so this needs
    // its own per-voice bools rather than reusing graphTouchCount, though it still folds into
    // the shared activeTouchCount for engine start/stop and Z/drone's existing "any touch"
    // gating (applyZVoiceEnables/applyDroneVoiceEnable need no changes for that reason - only
    // applyGraphVoiceEnables gained a per-voice OR above, since external drive enables X/Y
    // independently where a touch never could).
    private var xExternallyDriven = false
    private var yExternallyDriven = false
    private var zExternallyDriven = false

    // Remembers the most recent note-on per voice so a later pitch-bend-only message (which
    // carries no note number of its own) can still be decoded into a frequency.
    private var lastIncomingNote: [SequencerVoice: Int] = [:]

    private func voiceForChannel(_ channel: Int) -> SequencerVoice? {
        let mpe = settings?.useMIDI_MPE ?? false
        let xChannel = mpe ? midi.xMidiMPEChannel : midi.xMidiChannel
        let yChannel = mpe ? midi.yMidiMPEChannel : midi.yMidiChannel
        let zChannel = mpe ? midi.zMidiMPEChannel : midi.zMidiChannel
        switch channel {
        case xChannel: return .x
        case yChannel: return .y
        case zChannel: return .z
        default: return nil // the root/drone channel is handled separately, before this is ever
                             // called - see handleIncomingMidi's isRootChannel check and the
                             // drone external-drive section below.
        }
    }

    private func frequencyForIncoming(note: Int, pitchBend: Int) -> Double {
        let mpe = settings?.useMIDI_MPE ?? false
        let range = mpe ? (settings?.pitchBendRangeMPE ?? 24) : (settings?.pitchBendRange ?? 12)
        return PitchBendMath.frequencyFromNoteAndPitchBend(note: note, pitchBend: pitchBend, pitchBendRange: range)
    }

    /// Wired up as `midi.onEvent` in initSound() - the single entry point for everything this
    /// app does in response to incoming MIDI. Channel-to-voice interpretation lives here
    /// (in the app target), not in GBGSound's Midi class, which reports events generically -
    /// see the standalone-sequencer plan's step 3 notes on keeping that layer low-level.
    func handleIncomingMidi(channel: Int, kind: Midi.MidiInputEvent.Kind) {
        // CC64 (Sustain Pedal) - standard convention is >=64 down, <64 up, and it isn't scoped
        // to any one voice's channel the way note-on/pitch-bend are (a real pedal sends it on
        // whatever channel its controller is set to, often channel 1 regardless of which
        // channels X/Y/Z/root actually use) - so this is handled before the per-voice/root
        // routing below, on any incoming channel. Mirrors the Space-bar key command (the
        // primary, always-available path - see ContentView) rather than replacing it:
        // AppSettings.pedal is the single source of truth either way, so a pedal and the
        // keyboard can be used interchangeably without conflict.
        if case .controlChange(let controller, let value) = kind, controller == 64 {
            settings?.pedal = value >= 64
            return
        }
        if isRootChannel(channel) {
            handleIncomingDroneMidi(kind: kind)
            return
        }
        guard let voice = voiceForChannel(channel) else { return }
        switch kind {
        case .noteOn(let note, _):
            lastIncomingNote[voice] = note
            beginExternalDrive(voice: voice, frequency: frequencyForIncoming(note: note, pitchBend: 8192))
        case .noteOff:
            lastIncomingNote[voice] = nil
            endExternalDrive(voice: voice)
        case .pitchBend(let value):
            guard let note = lastIncomingNote[voice] else { return }
            updateExternalDrivePitch(voice: voice, frequency: frequencyForIncoming(note: note, pitchBend: value))
        case .controlChange:
            break
        }
    }

    private func beginExternalDrive(voice: SequencerVoice, frequency: Double) {
        // A note-on for a voice that's already externally driven (e.g. a second note-on with
        // no intervening note-off - possible if a sender's own note tracking desyncs, as Seq's
        // polling-based MIDI-out can if a note shorter than its poll interval gets skipped)
        // must not double-count activeTouchCount: the matching single note-off would then only
        // decrement it back to 1, never reaching 0, leaving the engine stuck on indefinitely -
        // a real hang, not just a redundant call. Treat it as a pitch update instead, the same
        // way already-driven voices are handled everywhere else in this file.
        let alreadyDriven: Bool
        switch voice {
        case .x: alreadyDriven = xExternallyDriven
        case .y: alreadyDriven = yExternallyDriven
        case .z: alreadyDriven = zExternallyDriven
        }
        guard !alreadyDriven else {
            updateExternalDrivePitch(voice: voice, frequency: frequency)
            return
        }
        switch voice {
        case .x:
            xExternallyDriven = true
            setXPitch(frequency: frequency)
            settings?.xFrequency = frequency
        case .y:
            yExternallyDriven = true
            setYPitch(frequency: frequency)
            settings?.yFrequency = frequency
        case .z:
            zExternallyDriven = true
            setZPitch(frequency: frequency)
            settings?.zFrequency = frequency
        }
        settings?.externallyDrivenVoices.insert(voice)
        activeTouchCount += 1
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 1 { startEngine(amp: 1) }
    }

    private func updateExternalDrivePitch(voice: SequencerVoice, frequency: Double) {
        switch voice {
        case .x:
            guard xExternallyDriven else { return }
            setXPitch(frequency: frequency)
            settings?.xFrequency = frequency
        case .y:
            guard yExternallyDriven else { return }
            setYPitch(frequency: frequency)
            settings?.yFrequency = frequency
        case .z:
            guard zExternallyDriven else { return }
            setZPitch(frequency: frequency)
            settings?.zFrequency = frequency
        }
    }

    private func endExternalDrive(voice: SequencerVoice) {
        switch voice {
        case .x:
            guard xExternallyDriven else { return }
            xExternallyDriven = false
        case .y:
            guard yExternallyDriven else { return }
            yExternallyDriven = false
        case .z:
            guard zExternallyDriven else { return }
            zExternallyDriven = false
        }
        settings?.externallyDrivenVoices.remove(voice)
        activeTouchCount = max(0, activeTouchCount - 1)
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 0 { stopEngine() }
    }

    // MARK: - External MIDI drive: drone (phase 2 of the standalone-sequencer plan)
    //
    // A separate, parallel path from X/Y/Z's above rather than folded into SequencerVoice -
    // drone has no crosshair on the graph, so SequencerVoice (which exists specifically to mark
    // "something other than touch owns this crosshair") has no case for it and shouldn't gain
    // one just for this. Drives audio.triad.setTriadRootPitch + midi.setMidiRootPitch directly,
    // never setRootPitch/midi.setMidiReferencePitch - the latter would move the reference
    // frequency every other voice's pitch-bend is encoded against, as a side effect of just
    // wanting drone to sound. SequencerState.scrub's own drone case set this same precedent for
    // exactly this reason.
    private var droneExternallyDriven = false
    private var lastIncomingDroneNote: Int?

    private func isRootChannel(_ channel: Int) -> Bool {
        let mpe = settings?.useMIDI_MPE ?? false
        return channel == (mpe ? midi.rootMidiMPEChannel : midi.rootMidiChannel)
    }

    private func handleIncomingDroneMidi(kind: Midi.MidiInputEvent.Kind) {
        switch kind {
        case .noteOn(let note, _):
            lastIncomingDroneNote = note
            beginExternalDroneDrive(frequency: frequencyForIncoming(note: note, pitchBend: 8192))
        case .noteOff:
            lastIncomingDroneNote = nil
            endExternalDroneDrive()
        case .pitchBend(let value):
            guard let note = lastIncomingDroneNote else { return }
            updateExternalDroneDrivePitch(frequency: frequencyForIncoming(note: note, pitchBend: value))
        case .controlChange:
            break
        }
    }

    private func beginExternalDroneDrive(frequency: Double) {
        // Same re-entry guard as beginExternalDrive above, and for the same reason - an
        // unmatched extra note-on must not double-count activeTouchCount.
        guard !droneExternallyDriven else {
            updateExternalDroneDrivePitch(frequency: frequency)
            return
        }
        droneExternallyDriven = true
        audio.triad.setTriadRootPitch(frequency: frequency)
        midi.setMidiRootPitch(frequency: frequency)
        activeTouchCount += 1
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 1 { startEngine(amp: 1) }
    }

    private func updateExternalDroneDrivePitch(frequency: Double) {
        guard droneExternallyDriven else { return }
        audio.triad.setTriadRootPitch(frequency: frequency)
        midi.setMidiRootPitch(frequency: frequency)
    }

    private func endExternalDroneDrive() {
        guard droneExternallyDriven else { return }
        droneExternallyDriven = false
        activeTouchCount = max(0, activeTouchCount - 1)
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        if activeTouchCount == 0 { stopEngine() }
    }
}
