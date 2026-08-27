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
    let rootAmplitude: Double = 0.77
    let xAmplitude: Double = 1.15
    let yAmplitude: Double = 1.15

    var rootPitch: Double = 0.0

    var tone1: Tone
    var tone2: Tone
    var tone3: Tone

    init() {
        // property initializers can't reference sibling instance properties (self isn't
        // available yet), so tone1/2/3 are built here instead, off the amplitude constants above
        tone1 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: rootAmplitude)
        tone2 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: xAmplitude)
        tone3 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: yAmplitude)
    }

    func setTriadSampleRate (sampleRate:Double){
        tone1.setSampleRate(inSampleRate: sampleRate)
        tone2.setSampleRate(inSampleRate: sampleRate)
        tone3.setSampleRate(inSampleRate: sampleRate)
    }

    func setTriadRootPitch(frequency:Double){
        rootPitch = frequency
        tone1.setPitch(inFrequency: rootPitch)
    }

    func enableTriadRootTone(enable: Bool){
        if enable == true {
            tone1.setAmplitude(inAmplitude: rootAmplitude)
        }
        else {
            tone1.setAmplitude(inAmplitude: 0.0)
        }
    }

    func enableTriadXTone(enable: Bool){
        if enable == true {
            tone2.setAmplitude(inAmplitude: xAmplitude)
        }
        else {
            tone2.setAmplitude(inAmplitude: 0.0)
        }
    }

    func enableTriadYTone(enable: Bool){
        if enable == true {
            tone3.setAmplitude(inAmplitude: yAmplitude)
        }
        else {
            tone3.setAmplitude(inAmplitude: 0.0)
        }
    }

    func setTriadXAmplitude(amplitude:Double){
        tone2.setAmplitude(inAmplitude: amplitude)
    }

    func setTriadYAmplitude(amplitude:Double){
        tone3.setAmplitude(inAmplitude: amplitude)
    }

    func getTriadRootPitch() -> Double{
        return rootPitch
    }

    func setTriadXPitch(frequency:Double){
        tone2.setPitch(inFrequency: frequency)
    }

    func setTriadYPitch(frequency:Double){
        tone3.setPitch(inFrequency: frequency)
    }

    func getTriadValue() -> Double{
        let value1 = tone1.getValue()
        let value2 = tone2.getValue()
        let value3 = tone3.getValue()
        let toneMix = (value1+value2+value3) / 3  // want to keep the ampitude equal or below 1.0
        return toneMix
    }

    func incrementTriadPhase(){
        // Advance the phase for the next frame.
        tone1.incrementPhase()
        tone2.incrementPhase()
        tone3.incrementPhase()
    }
}
