//
//  Triad.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

public class Triad{

    // make drone quieter. Adjust these constants to taste
    let rootAmplitude: Double = 0.77
    let xAmplitude: Double = 1.15
    let yAmplitude: Double = 1.15
    let zAmplitude: Double = 1.15

    var rootPitch: Double = 0.0

    var tone1: Tone
    var tone2: Tone
    var tone3: Tone
    var tone4: Tone

    public init() {
        // property initializers can't reference sibling instance properties (self isn't
        // available yet), so tone1/2/3/4 are built here instead, off the amplitude constants above
        tone1 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: rootAmplitude)
        tone2 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: xAmplitude)
        tone3 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: yAmplitude)
        tone4 = Tone(sampleRate: 44100, frequency: rootPitch, amplitude: zAmplitude)
    }

    func setTriadSampleRate (sampleRate:Double){
        tone1.setSampleRate(inSampleRate: sampleRate)
        tone2.setSampleRate(inSampleRate: sampleRate)
        tone3.setSampleRate(inSampleRate: sampleRate)
        tone4.setSampleRate(inSampleRate: sampleRate)
    }

    public func setTriadRootPitch(frequency:Double){
        rootPitch = frequency
        tone1.setPitch(inFrequency: rootPitch)
    }

    public func enableTriadRootTone(enable: Bool){
        if enable == true {
            tone1.setAmplitude(inAmplitude: rootAmplitude)
        }
        else {
            tone1.setAmplitude(inAmplitude: 0.0)
        }
    }

    public func enableTriadXTone(enable: Bool){
        if enable == true {
            tone2.setAmplitude(inAmplitude: xAmplitude)
        }
        else {
            tone2.setAmplitude(inAmplitude: 0.0)
        }
    }

    public func enableTriadYTone(enable: Bool){
        if enable == true {
            tone3.setAmplitude(inAmplitude: yAmplitude)
        }
        else {
            tone3.setAmplitude(inAmplitude: 0.0)
        }
    }

    public func enableTriadZTone(enable: Bool){
        if enable == true {
            tone4.setAmplitude(inAmplitude: zAmplitude)
        }
        else {
            tone4.setAmplitude(inAmplitude: 0.0)
        }
    }

    func setTriadRootAmplitude(amplitude:Double){
        tone1.setAmplitude(inAmplitude: amplitude)
    }

    func setTriadXAmplitude(amplitude:Double){
        tone2.setAmplitude(inAmplitude: amplitude)
    }

    func setTriadYAmplitude(amplitude:Double){
        tone3.setAmplitude(inAmplitude: amplitude)
    }

    func setTriadZAmplitude(amplitude:Double){
        tone4.setAmplitude(inAmplitude: amplitude)
    }

    func getTriadRootPitch() -> Double{
        return rootPitch
    }

    public func setTriadXPitch(frequency:Double){
        tone2.setPitch(inFrequency: frequency)
    }

    public func setTriadYPitch(frequency:Double){
        tone3.setPitch(inFrequency: frequency)
    }

    public func setTriadZPitch(frequency:Double){
        tone4.setPitch(inFrequency: frequency)
    }

    func getTriadValue() -> Double{
        let value1 = tone1.getValue()
        let value2 = tone2.getValue()
        let value3 = tone3.getValue()
        let value4 = tone4.getValue()
        let toneMix = (value1+value2+value3+value4) / 4  // want to keep the amplitude equal or below 1.0
        return toneMix
    }

    func incrementTriadPhase(){
        // Advance the phase for the next frame.
        tone1.incrementPhase()
        tone2.incrementPhase()
        tone3.incrementPhase()
        tone4.incrementPhase()
    }
}
