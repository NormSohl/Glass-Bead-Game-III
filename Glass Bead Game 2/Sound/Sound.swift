//
//  AudioAbstraction.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 3/14/24.
//
// This class serves to abstract internal audio control. Audio output can be to internal synthesis or to external midi output.
// These are very different but both can be controlled by a single set of abstracted functions which are defined here.

import Foundation

class Sound {
    var midi = Midi()
    var audio = Audio()
    
    // set but not used at the moment. might be easier use case to always send midi data AND audio data, and just use what you want when you need it.
    var outputToAudio = true
    
    func startSound(amp: Float){
        audio.startAudio(amp: amp)
        midi.startMidi()
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
    
    func sesetPitchBendRange(pitchBendRange: UInt8){
        midi.setMidiPitchBendRange(PitchBendRange: pitchBendRange)
    }
}
