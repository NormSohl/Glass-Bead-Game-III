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
    // starting/stopping is reference-counted rather than gated by either touch alone, or
    // releasing one finger while the other is still held would wrongly silence everything.
    private var activeTouchCount = 0

    func initSound(){
        midi.initMidi()
    }

    func startSound(amp: Float){
        audio.triad.enableTriadRootTone(enable: enableDrone)
        audio.triad.enableTriadXTone(enable: enableX)
        audio.triad.enableTriadYTone(enable: enableY)
        audio.triad.enableTriadZTone(enable: enableZ)

        midi.rootMidiEnable = enableDrone
        midi.xMidiEnable = enableX
        midi.yMidiEnable = enableY
        midi.zMidiEnable = enableZ

        if outputToAudio {audio.startAudio(amp: amp)}
        if outputToMidi {midi.startMidi()}
    }

    func stopSound(){
        audio.stopAudio()
        midi.stopMidi()
    }

    /// Call when a touch zone (graph or Z slider) begins. Starts sound only on the 0->1
    /// transition, so a second simultaneous touch doesn't redundantly restart it.
    func beginTouch(amp: Float) {
        activeTouchCount += 1
        if activeTouchCount == 1 {
            startSound(amp: amp)
        }
    }

    /// Call when a touch zone ends. Stops sound only once every touch has ended (unless `pedal`
    /// is held, matching the existing sustain-pedal behavior - sound keeps going regardless of
    /// touch state until the pedal itself is released).
    func endTouch(pedal: Bool) {
        activeTouchCount = max(0, activeTouchCount - 1)
        if activeTouchCount == 0 && !pedal {
            stopSound()
        }
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
