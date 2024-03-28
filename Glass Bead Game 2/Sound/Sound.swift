//
//  Sound.swift
//  Glass Bead Game 2
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
    //var outputToMidiMPE = true
    
    var enableDrone = true
    var enableX = true
    var enableY = true
    
    func initSound(){
        midi.initMidi()
    }
    
    func startSound(amp: Float){
        audio.triad.enableTriadRootTone(enable: enableDrone)
        audio.triad.enableTriadXTone(enable: enableX)
        audio.triad.enableTriadYTone(enable: enableY)
        
        midi.rootMidiEnable = enableDrone
        midi.xMidiEnable = enableX
        midi.yMidiEnable = enableY
        
        if outputToAudio {audio.startAudio(amp: amp)}
        if outputToMidi {midi.startMidi()}
    }
    
    func stopSound(){
        audio.stopAudio()
        midi.stopMidi()
    }
    
    func setRootPitch(frequency: Double){
        audio.triad.setTriadRootPitch (frequency: frequency)
        midi.setMidiRootPitch(frequency: frequency)
    }
    
    func setXPitch(frequency: Double){
        audio.triad.setTriadXPitch(frequency: frequency)
        midi.setMidiXPitch(frequency: frequency)
    }
    
    func setYPitch(frequency: Double){
        audio.triad.setTriadYPitch(frequency: frequency)
        midi.setMidiYPitch(frequency: frequency)
    }
    
    func setPitchBendRange(pitchBendRange: Int){
        midi.setMidiPitchBendRange(PitchBendRange: pitchBendRange)
    }
    
    func setPitchBendRangeMPE(pitchBendRange: Int){
        midi.setMidiPitchBendRangeMPE(PitchBendRange: pitchBendRange)
    }
    
    func setRootNote(midiNote: Int){
        midi.setRootNote(Note: midiNote)
    }
}
