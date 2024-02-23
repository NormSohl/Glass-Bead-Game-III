//
//  Tone.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

class Tone{
    
    // signal. This returns a wave based on the phase input value. Phase is in range 0 to twoPi. Return is in range -1 to 1
    let signal:WaveForm = Sine()//SawToothDown() //is default Additive()
    var sampleRate:Double = 44100.0
    var phaseIncrement: Double = 0
    var currentPhase: Double = 0 // the phase of the waveform is 0 to twoPi. This is useful when calculating sine waves.
    var amplitude: Double = 0.0
    
    // utility function
    let twoPi = 2 * Double.pi
    
    init(sampleRate:Double, frequency:Double, amplitude:Double){
        //setSampleRate (inSampleRate: sampleRate)
        setPitch (inFrequency: frequency)
        setAmplitude(inAmplitude: amplitude)
        print("Tone: init: amplitude = \(amplitude)")
    }
    
    func setPitch (inFrequency:Double){
        //print("setPitch called with fq of: ",frequency)
        // The interval to advance the phase each frame.
         phaseIncrement = (twoPi / sampleRate) * inFrequency  // how much does phase change given sample rate and fq.
        //print("setPitch. Frequency: ",inFrequency)
    }
    
    func setSampleRate(inSampleRate:Double){
        self.sampleRate = inSampleRate
    }
    
    func setAmplitude(inAmplitude:Double){
        self.amplitude = inAmplitude
        print("Tone: setAmplitude: amplitude = \(self.amplitude)")
    }
    
    func incrementPhase(){
        // Advance the phase for the next frame.
        currentPhase += self.phaseIncrement
        if currentPhase >= self.twoPi {
            currentPhase -= self.twoPi
        }
        if currentPhase < 0.0 {
            currentPhase += self.twoPi
        }
    }
    
    func getValue() -> Double{
        return (signal.getValue(phase:currentPhase) * amplitude)// signal is -1 to 1. amplitude is 0 to 1, default is 0.5
    }
}
