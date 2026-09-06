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

    // Fixed stereo pan position per voice, spread across ~3/4 of the field (-0.75...+0.75),
    // left to right: Z, X, Y, drone - same spec and channel-role mapping as monk-mpe's own
    // pan table (see that project's src/mpe_engine.c), kept consistent since both apps read
    // the same X/Y/Z/root roles out of this graph.
    private static let rootPan = 0.75  // drone, rightmost
    private static let xPan = -0.25
    private static let yPan = 0.25
    private static let zPan = -0.75    // leftmost

    // Equal-power pan law: pan -1...+1 maps to angle 0...pi/2.
    private static func panGains(_ pan: Double) -> (left: Double, right: Double) {
        let angle = (pan + 1.0) * (Double.pi / 4.0)
        return (cos(angle), sin(angle))
    }

    private let rootGains = Triad.panGains(Triad.rootPan)
    private let xGains = Triad.panGains(Triad.xPan)
    private let yGains = Triad.panGains(Triad.yPan)
    private let zGains = Triad.panGains(Triad.zPan)

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

    // Each tone's getValue() has a side effect (it advances its own amplitude-smoothing ramp -
    // see Tone.getValue's own comment), so it must be called exactly once per tone per sample,
    // never once per output channel - the per-channel pan gains below are applied to that
    // single captured value, not by calling getValue() again.
    func getTriadValue() -> (left: Double, right: Double){
        let value1 = tone1.getValue() // root/drone
        let value2 = tone2.getValue() // X
        let value3 = tone3.getValue() // Y
        let value4 = tone4.getValue() // Z

        // Same /4 normalization as the old mono mix, to keep amplitude at or below 1.0 - still
        // safe headroom-wise even at the loudest plausible pan combination, since each gain
        // factor is itself <= 1.
        let left = (value1 * rootGains.left + value2 * xGains.left + value3 * yGains.left + value4 * zGains.left) / 4
        let right = (value1 * rootGains.right + value2 * xGains.right + value3 * yGains.right + value4 * zGains.right) / 4
        return (left, right)
    }

    func incrementTriadPhase(){
        // Advance the phase for the next frame.
        tone1.incrementPhase()
        tone2.incrementPhase()
        tone3.incrementPhase()
        tone4.incrementPhase()
    }
}
