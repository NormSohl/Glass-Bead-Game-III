//
//  Sound.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 3/14/24.
//
// This class serves to abstract internal audio control. Audio output can be to internal synthesis or to external midi output.
// These are very different but both are controlled by a single set of abstracted functions which are defined here.

import Foundation

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

    // Per-zone touch counts, separate from activeTouchCount above - Norm: touching just the
    // Z-slider was also sounding X/Y, at whatever frequency they'd last been left at rather than
    // anything actually chosen in that touch. X/Y now only sound while the graph itself is
    // touched; Z only while the Z-slider is touched; both can be true at once (true multitouch),
    // each voice reflecting only its own zone regardless of the other.
    private var graphTouchCount = 0
    private var zSliderTouchCount = 0

    func initSound(){
        midi.initMidi()
    }

    // Sets each voice's enabled state from its own toggle AND its own zone's touch count -
    // drone from activeTouchCount (it has no touch zone of its own, so it follows "is anything
    // being touched"), X/Y from graphTouchCount, Z from zSliderTouchCount.
    private func applyLiveVoiceEnables(){
        audio.triad.enableTriadRootTone(enable: enableDrone && activeTouchCount > 0)
        audio.triad.enableTriadXTone(enable: enableX && graphTouchCount > 0)
        audio.triad.enableTriadYTone(enable: enableY && graphTouchCount > 0)
        audio.triad.enableTriadZTone(enable: enableZ && zSliderTouchCount > 0)

        midi.rootMidiEnable = enableDrone && activeTouchCount > 0
        midi.xMidiEnable = enableX && graphTouchCount > 0
        midi.yMidiEnable = enableY && graphTouchCount > 0
        midi.zMidiEnable = enableZ && zSliderTouchCount > 0
    }

    private func startEngine(amp: Float){
        if outputToAudio {audio.startAudio(amp: amp)}
        if outputToMidi {midi.startMidi()}
    }

    private func stopEngine(){
        audio.stopAudio()
        midi.stopMidi()
    }

    /// Call when the graph (X/Y) touch zone begins. X/Y are enabled here (via
    /// applyLiveVoiceEnables), independent of whether the Z-slider is also currently held - the
    /// shared engine itself starts only on the overall 0->1 transition, so an already-active
    /// Z-slider touch doesn't get redundantly restarted.
    func beginGraphTouch(amp: Float) {
        graphTouchCount += 1
        activeTouchCount += 1
        applyLiveVoiceEnables()
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    /// Call when the graph touch zone ends. Disables X/Y (unless `pedal` is held, matching the
    /// existing sustain behavior - voices keep sounding regardless of touch state until the
    /// pedal itself is released) and stops the shared engine only once every zone has ended.
    func endGraphTouch(pedal: Bool) {
        graphTouchCount = max(0, graphTouchCount - 1)
        activeTouchCount = max(0, activeTouchCount - 1)
        if !pedal {
            applyLiveVoiceEnables()
            if activeTouchCount == 0 { stopEngine() }
        }
    }

    /// Z-slider touch begin/end - same as beginGraphTouch/endGraphTouch, for Z instead of X/Y.
    func beginZTouch(amp: Float) {
        zSliderTouchCount += 1
        activeTouchCount += 1
        applyLiveVoiceEnables()
        if activeTouchCount == 1 { startEngine(amp: amp) }
    }

    func endZTouch(pedal: Bool) {
        zSliderTouchCount = max(0, zSliderTouchCount - 1)
        activeTouchCount = max(0, activeTouchCount - 1)
        if !pedal {
            applyLiveVoiceEnables()
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
        applyLiveVoiceEnables()
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

    func setRootNote(midiNote: Int){
        midi.setRootNote(note: midiNote)
    }
}
