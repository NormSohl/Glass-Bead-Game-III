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

    // How many touch zones are currently held down and able to start/stop the shared audio
    // engine - currently just the graph (X/Y, via beginGraphTouch/endGraphTouch). The Z-slider
    // is deliberately NOT one of these zones -
    // Norm, after practicing with it: dragging Z must never sound (or silence) a note by itself,
    // only retune whatever's already audible because the graph or the pedal is holding it. Kept
    // as a reference count rather than a simple flag because more than one of these zones can be
    // held at once - releasing one while another is still held must not wrongly silence
    // everything.
    private var activeTouchCount = 0

    // True exactly while the pedal is the only thing keeping a previously-touched voice
    // audible - the last real touch just ended while pedal was already held. Deliberately
    // distinct from settings.pedal itself, which can be true with nothing ever having been
    // touched at all (pedal pressed before playing a note): only in this genuine hand-off case
    // should a voice's own Play toggle be able to silence or re-sound it without a real touch -
    // otherwise pedal being merely *engaged*, with nothing ever played, would let a stray Play-
    // toggle flip start a note out of nowhere. Set in endGraphTouch the moment
    // activeTouchCount reaches 0 while pedal is held; cleared by releasePedal, the actual end
    // of a pedal-sustained passage.
    private var pedalIsSustaining = false

    // What applyGraphVoiceEnables/applyZVoiceEnables/applyDroneVoiceEnable actually gate on -
    // either a real touch is active right now, or the pedal is genuinely sustaining one from a
    // moment ago (see pedalIsSustaining's own comment). Introduced so a voice's own Play toggle
    // can take effect during a pedal-held passage (Norm: toggling Drone off while pedal held a
    // note should silence just that note, not require lifting the pedal first) without the
    // plain activeTouchCount > 0 check silencing every *other* voice pedal was also holding -
    // confirmed live: before this, calling these functions at all during pedal-sustain (no
    // active touch) unconditionally disabled X/Y/Z/drone alike, regardless of their own toggle
    // state, since the old check had no way to represent "pedal legitimately holds this."
    private var sustained: Bool { activeTouchCount > 0 || (pedalIsSustaining && settings?.pedal == true) }

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
    // X/Y follow "is anything being touched" (activeTouchCount) rather than graphTouchCount
    // specifically, same rule Z/drone already use below - so a pedal-sustained X/Y voice can't
    // be silenced by some other zone's activity, the same property the original fix relied on.
    // (The Z-slider itself is no longer one of the zones that can change activeTouchCount at
    // all - see the note on that var's own declaration above - so this is now purely about the
    // graph's own touch/pedal interplay, not Z.)
    private func applyGraphVoiceEnables(){
        audio.triad.enableTriadXTone(enable: enableX && (sustained || xExternallyDriven))
        audio.triad.enableTriadYTone(enable: enableY && (sustained || yExternallyDriven))
        midi.xMidiEnable = enableX && (sustained || xExternallyDriven)
        midi.yMidiEnable = enableY && (sustained || yExternallyDriven)
    }

    // Z follows "is anything being touched" - Norm wants Z, when enabled, to always sound
    // whenever the graph is touched, at 1/1 by default or whatever the Z-slider was last
    // dragged to - the Z-slider's own touch no longer factors in at all (it can retune Z, via
    // sound.setZPitch, but can't start or stop it - see ZSliderView's gesture). Called from
    // beginGraphTouch/endGraphTouch and releasePedal below, same as applyDroneVoiceEnable.
    private func applyZVoiceEnables(){
        audio.triad.enableTriadZTone(enable: enableZ && sustained)
        midi.zMidiEnable = enableZ && sustained
    }

    // Drone has no touch zone of its own, so it follows "is anything being touched" - any zone
    // beginning/ending legitimately affects it, unlike X/Y above (Z now follows the same rule,
    // see applyZVoiceEnables just above).
    private func applyDroneVoiceEnable(){
        audio.triad.enableTriadRootTone(enable: enableDrone && sustained)
        midi.rootMidiEnable = enableDrone && sustained
    }

    /// Re-applies all three groups above immediately - for AppSettings' own didSet on the four
    /// play-toggles (Drone/X/Y/Z), which otherwise have no way to take audible effect until the
    /// next touch begin/end happens to recompute enables. Norm, confirmed live: toggling Drone
    /// mid-touch (or with nothing touched) produced no audible change at all, since nothing ever
    /// called back into Sound just because a toggle changed - enableDrone/enableX/Y/Z reading
    /// straight through settings (see that comment above) keeps the *value* always current, but
    /// only fixed a different bug (the two-copies-drifting one); it never made toggling one
    /// re-run the apply functions on its own. Safe to call unconditionally, touched or not,
    /// pedal-sustained or not - each apply function's own `sustained` check (see that var's
    /// comment) already does the right thing for a pedal-held passage: it lets the toggled
    /// voice respond immediately without disturbing whatever else pedal is also holding.
    func refreshVoiceEnables() {
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
    }

    private func startEngine(amp: Float){
        if outputToAudio {audio.startAudio(amp: amp)}
        if outputToMidi {midi.startMidi()}
    }

    private func stopEngine(){
        audio.stopAudio()
        midi.stopMidi()
    }

    /// Call when the graph (X/Y) touch zone begins - the pen touching the graph is the only
    /// thing that can start a note. Touches the graph's own voice group plus Z and drone (both
    /// follow "is anything touched," not their own zone - see applyZVoiceEnables/
    /// applyDroneVoiceEnable), so Z and the drone become audible too, at whatever pitch/level
    /// they were last set to.
    func beginGraphTouch(amp: Float) {
        activeTouchCount += 1
        pedalIsSustaining = false // a real touch is active again - see that var's own comment
        applyGraphVoiceEnables()
        applyZVoiceEnables()
        applyDroneVoiceEnable()
        // Every pen-down is a fresh strike, even for a voice the pedal is already sustaining
        // from a previous note - the enable calls just above only retrigger a voice that was
        // actually silent (see Tone.setAmplitude's onset detection); a pedal-held voice never
        // goes silent, so without this its attack wouldn't fire again on a new touch, only its
        // pitch would change.
        audio.triad.retriggerAll()
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    /// Forces a fresh attack on the graph's held voices without any of beginGraphTouch's other
    /// bookkeeping (activeTouchCount, enable re-application, engine start) - for a new physical
    /// touch-down that lands while the pedal is already holding a previous note sounding.
    /// beginGraphTouch itself doesn't get called at all in that case at the gesture layer, since
    /// the engine is already running and isSound never got reset (see HitTestView's own isSound/
    /// isTouchDown comment) - but the new touch is still a fresh strike and should re-articulate.
    func retriggerTouch() {
        audio.triad.retriggerAll()
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
        } else if activeTouchCount == 0 {
            // The hand-off moment: this was the last active touch, and pedal is holding it -
            // see pedalIsSustaining's own comment for why this needs recording rather than
            // just inferring it from settings.pedal being true.
            pedalIsSustaining = true
        }
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
        pedalIsSustaining = false // the sustained passage genuinely ends here
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
        pedalIsSustaining = false
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

    // outputToMidi gates every MIDI call below, matching startEngine's own
    // `if outputToMidi {midi.startMidi()}` - these four used to call straight into `midi`
    // unconditionally, regardless of the toggle, an inconsistency confirmed live 2026-09-09
    // while investigating a rapid-Z-slider-dragging hang (updatePitchBend's own `guard isPlaying`
    // already no-ops most of these calls in practice, so this wasn't the hang's actual cause,
    // but it's a real bug on its own: turning MIDI off was never actually stopping these calls).
    func setRootPitch(frequency: Double){
        audio.triad.setTriadRootPitch (frequency: frequency)
        if outputToMidi { midi.setMidiReferencePitch(frequency: frequency) }
    }

    func setXPitch(frequency: Double){
        audio.triad.setTriadXPitch(frequency: frequency)
        if outputToMidi { midi.setMidiXPitch(frequency: frequency) }
    }

    func setYPitch(frequency: Double){
        audio.triad.setTriadYPitch(frequency: frequency)
        if outputToMidi { midi.setMidiYPitch(frequency: frequency) }
    }

    func setZPitch(frequency: Double){
        audio.triad.setTriadZPitch(frequency: frequency)
        if outputToMidi { midi.setMidiZPitch(frequency: frequency) }
    }
    
    func setPitchBendRangeMPE(pitchBendRange: Int){
        midi.setMidiPitchBendRangeMPE(pitchBendRange: pitchBendRange)
    }

    func setRootNote(midiNote: Int){
        midi.setRootNote(note: midiNote)
    }

    // MARK: - External MIDI drive (generic MIDI input)
    //
    // Lets an external MIDI source - a controller, a sequencer, a DAW - drive
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
    private var lastIncomingNote: [GraphAxis: Int] = [:]

    private func voiceForChannel(_ channel: Int) -> GraphAxis? {
        switch channel {
        case midi.xMidiMPEChannel: return .x
        case midi.yMidiMPEChannel: return .y
        case midi.zMidiMPEChannel: return .z
        default: return nil // the root/drone channel is handled separately, before this is ever
                             // called - see handleIncomingMidi's isRootChannel check and the
                             // drone external-drive section below.
        }
    }

    private func frequencyForIncoming(note: Int, pitchBend: Int) -> Double {
        let range = settings?.pitchBendRangeMPE ?? 24
        return PitchBendMath.frequencyFromNoteAndPitchBend(note: note, pitchBend: pitchBend, pitchBendRange: range)
    }

    /// Wired up as `midi.onEvent` in initSound() - the single entry point for everything this
    /// app does in response to incoming MIDI. Channel-to-voice interpretation lives here
    /// (in the app target), not in GBGSound's Midi class, which reports events generically.
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

    private func beginExternalDrive(voice: GraphAxis, frequency: Double) {
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

    private func updateExternalDrivePitch(voice: GraphAxis, frequency: Double) {
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

    private func endExternalDrive(voice: GraphAxis) {
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

    // MARK: - External MIDI drive: drone
    //
    // A separate, parallel path from X/Y/Z's above rather than folded into GraphAxis -
    // drone has no crosshair on the graph, so GraphAxis (which exists specifically to mark
    // "something other than touch owns this crosshair") has no case for it and shouldn't gain
    // one just for this. Drives audio.triad.setTriadRootPitch + midi.setMidiRootPitch directly,
    // never setRootPitch/midi.setMidiReferencePitch - the latter would move the reference
    // frequency every other voice's pitch-bend is encoded against, as a side effect of just
    // wanting drone to sound.
    private var droneExternallyDriven = false
    private var lastIncomingDroneNote: Int?

    private func isRootChannel(_ channel: Int) -> Bool {
        channel == midi.rootMidiMPEChannel
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
