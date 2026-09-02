//
//  Tone.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

class Tone{

    // signal. This returns a wave based on the phase input value. Phase is in range 0 to twoPi. Return is in range -1 to 1
    let signal:WaveForm = Sine()//SawToothDown() //is default Additive()
    var sampleRate:Double = 44100.0 {
        didSet { updateAmplitudeSmoothingCoefficient() }
    }
    var phaseIncrement: Double = 0
    var currentPhase: Double = 0 // the phase of the waveform is 0 to twoPi. This is useful when calculating sine waves.
    // The amplitude actually applied to the waveform this sample - chases targetAmplitude (see
    // getValue's own ramp step below) rather than jumping straight to it. setAmplitude used to
    // write this directly, an instantaneous step that (unless the waveform happened to be at a
    // zero-crossing at that exact instant, vanishingly unlikely) produced a real discontinuity
    // in the output - an audible click/pop, most noticeable exactly where live touch begins/ends
    // (Sound.enableTriadXTone etc. go straight from full amplitude to 0 or back). Same root
    // cause, same fix, as ScorePlayer's own amplitudeSmoothing (see that class's own comment for
    // the measured justification - a 0.134 sample-to-sample jump against a ~0.063 baseline for
    // an unsmoothed note boundary at a similar amplitude scale).
    var amplitude: Double = 0.0
    private var targetAmplitude: Double = 0.0
    private var amplitudeSmoothingCoefficient: Double = 0.0

    // utility function
    let twoPi = 2 * Double.pi

    init(sampleRate:Double, frequency:Double, amplitude:Double){
        //setSampleRate (inSampleRate: sampleRate)
        self.sampleRate = sampleRate // triggers didSet -> updateAmplitudeSmoothingCoefficient
        setPitch (inFrequency: frequency)
        setAmplitude(inAmplitude: amplitude)
        self.amplitude = targetAmplitude // starting value has nothing to ramp from
        //print("Tone: init: amplitude = \(amplitude)")
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

    // A few milliseconds - same order of magnitude as ScorePlayer's own default
    // (amplitudeRampSeconds) - eliminates the click without perceptibly softening a deliberate
    // touch begin/end, which already reads as instantaneous at this timescale.
    private func updateAmplitudeSmoothingCoefficient(rampSeconds: Double = 0.005) {
        amplitudeSmoothingCoefficient = 1 - exp(-1 / (rampSeconds * sampleRate))
    }

    func setAmplitude(inAmplitude:Double){
        targetAmplitude = inAmplitude
        //print("Tone: setAmplitude: amplitude = \(self.amplitude)")
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
        amplitude += (targetAmplitude - amplitude) * amplitudeSmoothingCoefficient
        return (signal.getValue(phase:currentPhase) * amplitude)// signal is -1 to 1. amplitude is 0 to 1, default is 0.5
    }
}

