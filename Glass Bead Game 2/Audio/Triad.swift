//
//  Triad.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

class Triad{
    
    static var root: Double = 130.813 * 2 // middle c
    
    // make drone quieter.
    static var tone1: Tone = Tone(sampleRate: 44100, frequency: root, amplitude: 0.70) //0.75)  //
    static var tone2: Tone = Tone(sampleRate: 44100, frequency: root, amplitude: 1.15)
    static var tone3: Tone = Tone(sampleRate: 44100, frequency: root, amplitude: 1.15)
    
    func setSampleRate (sampleRate:Double){
        Triad.tone1.setSampleRate(inSampleRate: sampleRate)
        Triad.tone2.setSampleRate(inSampleRate: sampleRate)
        Triad.tone3.setSampleRate(inSampleRate: sampleRate)
        print("Triad: setSampleRate: sampleRate = \(sampleRate)")    }
    
    func setRootPitch(frequency:Double){
        //print("Triad.tone1")
        Triad.root = frequency
        Triad.tone1.setPitch(inFrequency: Triad.root)
    }
    
    func setRootAmplitude(amplitude:Double){
        Triad.tone1.setAmplitude(inAmplitude: amplitude)
        print("Triad: setRootAmplitude: amplitude = \(amplitude)")
    }
    func getRootPitch() -> Double{
        return Triad.root
    }
    
    func setXPitch(frequency:Double){
        //print("Triad.tone2")
        Triad.tone2.setPitch(inFrequency: frequency)
    }

    func setYPitch(frequency:Double){
        //print("Triad.tone3")
        Triad.tone3.setPitch(inFrequency: frequency)
    }
    
    func getValue() -> Double{
        //let value = self.tone1.getValue()
        let value1 = Triad.tone1.getValue()
        let value2 = Triad.tone2.getValue()
        let value3 = Triad.tone3.getValue()
        let toneMix = (value1+value2+value3) / 3  // want to keep the ampitude equal or below 1.0
        return toneMix
    }
    
    func incrementPhase(){
        // Advance the phase for the next frame.
        Triad.tone1.incrementPhase()
        Triad.tone2.incrementPhase()
        Triad.tone3.incrementPhase()
    }
}
