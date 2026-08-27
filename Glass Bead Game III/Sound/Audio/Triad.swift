//
//  Triad.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

class Triad{
    
    // make drone quieter. Adjust these constants to taste
    static let rootAmplitude: Double = 0.77
    static let XAmplitude: Double = 1.15
    static let YAmplitude: Double = 1.15
    
    static var rootPitch: Double = 0.0
    
    static var tone1: Tone = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: rootAmplitude)
    static var tone2: Tone = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: XAmplitude)
    static var tone3: Tone = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: YAmplitude)
    
    func setTriadSampleRate (sampleRate:Double){
        Triad.tone1.setSampleRate(inSampleRate: sampleRate)
        Triad.tone2.setSampleRate(inSampleRate: sampleRate)
        Triad.tone3.setSampleRate(inSampleRate: sampleRate)
        //print("Triad: setSampleRate: sampleRate = \(sampleRate)")
    }
    
    func setTriadRootPitch(frequency:Double){
        Triad.rootPitch = frequency
        Triad.tone1.setPitch(inFrequency: Triad.rootPitch)
        //audioGeneric.setRootPitch(frequency:frequency)
    }
    
    func enableTriadRootTone(enable: Bool){
        if enable == true {
            Triad.tone1.setAmplitude(inAmplitude: Triad.rootAmplitude)
        }
        else {
            Triad.tone1.setAmplitude(inAmplitude: 0.0)
        }
        //print("Triad: setRootAmplitude: amplitude = \(Triad.tone1.amplitude), enable = \(enable)")
    }
    
    func enableTriadXTone(enable: Bool){
        if enable == true {
            Triad.tone2.setAmplitude(inAmplitude: Triad.XAmplitude)
        }
        else {
            Triad.tone2.setAmplitude(inAmplitude: 0.0)
        }
        //print("Triad: setXAmplitude: amplitude = \(Triad.tone3.amplitude), enable = \(enable)")
    }
    
    func enableTriadYTone(enable: Bool){
        if enable == true {
            Triad.tone3.setAmplitude(inAmplitude: Triad.YAmplitude)
        }
        else {
            Triad.tone3.setAmplitude(inAmplitude: 0.0)
        }
        //print("Triad: setYAmplitude: amplitude = \(Triad.tone3.amplitude), enable = \(enable)")
    }
            
    func setTriadXAmplitude(amplitude:Double){
        Triad.tone2.setAmplitude(inAmplitude: amplitude)
        //print("Triad: setXAmplitude: amplitude = \(amplitude)")
    }
    
    func setTriadYAmplitude(amplitude:Double){
        Triad.tone3.setAmplitude(inAmplitude: amplitude)
        //print("Triad: setYAmplitude: amplitude = \(amplitude)")
    }
    
    func getTriadRootPitch() -> Double{
        return Triad.rootPitch
    }
    
    func setTriadXPitch(frequency:Double){
        Triad.tone2.setPitch(inFrequency: frequency)
    }

    func setTriadYPitch(frequency:Double){
        Triad.tone3.setPitch(inFrequency: frequency)
    }
    
    func getTriadValue() -> Double{
        let value1 = Triad.tone1.getValue()
        let value2 = Triad.tone2.getValue()
        let value3 = Triad.tone3.getValue()
        let toneMix = (value1+value2+value3) / 3  // want to keep the ampitude equal or below 1.0
        return toneMix
    }
    
    func incrementTriadPhase(){
        // Advance the phase for the next frame.
        Triad.tone1.incrementPhase()
        Triad.tone2.incrementPhase()
        Triad.tone3.incrementPhase()
    }
}
