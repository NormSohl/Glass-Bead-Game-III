//
//  ScorePlayer.swift
//  Glass Bead Game III
//
//  Drives a Score's Parts into a Triad, one sample at a time - the playback counterpart to
//  ScoreCapture. Deliberately depends only on Triad + Part, not Sound: mixer-volume gating
//  (Sound.beginTouch/endTouch, reusing the same reference-counted mechanism the graph's touch
//  zones already share) is a separate, non-real-time-safe concern, left for whenever this is
//  actually wired into Audio's live AVAudioSourceNode callback. Before that happens this gets
//  exercised offline (a synthetic Score, rendered straight to a WAV file, timed against the
//  real-time budget) - see the sequencer design notes.
//
//  Amplitude is one-pole smoothed per voice (see amplitudeSmoothing below) rather than jumping
//  straight to each note's envelope value - confirmed by ear and then measured directly (an
//  isolated two-note boundary showed a 0.134 sample-to-sample jump against a ~0.063 baseline
//  for a smooth tone at that frequency) that unsmoothed note boundaries produce real,
//  measurable discontinuities, audible as pops/crackles. Pitch is never smoothed: phase-
//  continuous synthesis (Tone doesn't reset phase on setPitch) means a frequency change alone
//  never causes a waveform discontinuity, only a click-free re-tuning - so only amplitude needs
//  this.
//

import Foundation
import GBGCore

class ScorePlayer {
    private let triad: Triad
    private let dronePart: Part?
    private let xPart: Part?
    private let yPart: Part?
    private let zPart: Part?

    // One-pole smoothing coefficient for the anti-click amplitude ramp - derived once from
    // sampleRate so the same real-world ramp time applies regardless of sample rate. A few
    // milliseconds eliminates audible clicks without perceptibly softening genuine envelope
    // shapes, which change over whole notes (tens to thousands of milliseconds), not a handful.
    private let amplitudeSmoothing: Double

    // How close to zero the applied (smoothed) amplitudes must settle before playback is
    // considered finished - an exponential ramp never reaches exactly zero, so auto-stop can't
    // just check "every voice ran out of notes" without risking a new click at the cutoff.
    private let silenceThreshold = 0.0001

    private(set) var currentSample: Int = 0
    private(set) var isPlaying: Bool = false

    private var currentDroneNote: Note?
    private var currentXNote: Note?
    private var currentYNote: Note?
    private var currentZNote: Note?

    // The frequency actually pushed into `triad` for each voice this sample, mirrored here so a
    // UI (the sequencer's graph-driving during playback) can read what's currently sounding
    // without duplicating the note-lookup/percentComplete math - nil when that voice has no
    // current note. Set alongside the existing triad.setTriad*Pitch calls below; not a new
    // computation, just also stashing a value already being computed.
    private(set) var currentDroneFrequency: Double?
    private(set) var currentXFrequency: Double?
    private(set) var currentYFrequency: Double?
    private(set) var currentZFrequency: Double?

    // The amplitude actually sent to Triad last sample, per voice - chases each note's own
    // envelope value (or 0, once a voice runs out of notes) rather than jumping straight to it.
    private var appliedDroneAmplitude: Double = 0
    private var appliedXAmplitude: Double = 0
    private var appliedYAmplitude: Double = 0
    private var appliedZAmplitude: Double = 0

    init(triad: Triad, dronePart: Part?, xPart: Part?, yPart: Part?, zPart: Part?, sampleRate: Double, amplitudeRampSeconds: Double = 0.005) {
        self.triad = triad
        self.dronePart = dronePart
        self.xPart = xPart
        self.yPart = yPart
        self.zPart = zPart
        self.amplitudeSmoothing = 1 - exp(-1 / (amplitudeRampSeconds * sampleRate))
    }

    /// Primes each active Part's starting note and begins playback at `atSample`. Not real-time
    /// safe - uses Part's brute-force `getCurrentNote` lookup, meant to be called once before
    /// playback starts, never from inside the audio render loop.
    func start(atSample: Int = 0) {
        currentSample = atSample
        currentDroneNote = dronePart?.getCurrentNote(timeSlice: atSample)
        currentXNote = xPart?.getCurrentNote(timeSlice: atSample)
        currentYNote = yPart?.getCurrentNote(timeSlice: atSample)
        currentZNote = zPart?.getCurrentNote(timeSlice: atSample)
        appliedDroneAmplitude = 0
        appliedXAmplitude = 0
        appliedYAmplitude = 0
        appliedZAmplitude = 0
        currentDroneFrequency = nil
        currentXFrequency = nil
        currentYFrequency = nil
        currentZFrequency = nil
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }

    /// Advances playback by exactly one sample, pushing this sample's pitch/amplitude for each
    /// active voice into `triad`. Real-time safe: no allocation, no locking, just array
    /// indexing (Part's O(1) getNextNote) and floating-point math. Call once per sample, before
    /// reading triad.getTriadValue() for that same sample. The four voices are unrolled rather
    /// than looped over a collection - matches the existing style in Triad.incrementTriadPhase/
    /// getTriadValue, and avoids passing per-voice closures on every sample.
    func advance() {
        guard isPlaying else { return }

        if let dronePart {
            while let current = currentDroneNote, currentSample >= current.endTime {
                currentDroneNote = dronePart.getNextNote()
            }
            let targetAmplitude: Double
            if let current = currentDroneNote {
                let percentComplete = current.percentComplete(at: currentSample)
                let frequency = current.getCurrentFrequency(percentComplete: percentComplete)
                triad.setTriadRootPitch(frequency: frequency)
                currentDroneFrequency = frequency
                targetAmplitude = current.getCurrentAmplitude(percentComplete: percentComplete)
            } else {
                currentDroneFrequency = nil
                targetAmplitude = 0
            }
            appliedDroneAmplitude += (targetAmplitude - appliedDroneAmplitude) * amplitudeSmoothing
            triad.setTriadRootAmplitude(amplitude: appliedDroneAmplitude)
        }

        if let xPart {
            while let current = currentXNote, currentSample >= current.endTime {
                currentXNote = xPart.getNextNote()
            }
            let targetAmplitude: Double
            if let current = currentXNote {
                let percentComplete = current.percentComplete(at: currentSample)
                let frequency = current.getCurrentFrequency(percentComplete: percentComplete)
                triad.setTriadXPitch(frequency: frequency)
                currentXFrequency = frequency
                targetAmplitude = current.getCurrentAmplitude(percentComplete: percentComplete)
            } else {
                currentXFrequency = nil
                targetAmplitude = 0
            }
            appliedXAmplitude += (targetAmplitude - appliedXAmplitude) * amplitudeSmoothing
            triad.setTriadXAmplitude(amplitude: appliedXAmplitude)
        }

        if let yPart {
            while let current = currentYNote, currentSample >= current.endTime {
                currentYNote = yPart.getNextNote()
            }
            let targetAmplitude: Double
            if let current = currentYNote {
                let percentComplete = current.percentComplete(at: currentSample)
                let frequency = current.getCurrentFrequency(percentComplete: percentComplete)
                triad.setTriadYPitch(frequency: frequency)
                currentYFrequency = frequency
                targetAmplitude = current.getCurrentAmplitude(percentComplete: percentComplete)
            } else {
                currentYFrequency = nil
                targetAmplitude = 0
            }
            appliedYAmplitude += (targetAmplitude - appliedYAmplitude) * amplitudeSmoothing
            triad.setTriadYAmplitude(amplitude: appliedYAmplitude)
        }

        if let zPart {
            while let current = currentZNote, currentSample >= current.endTime {
                currentZNote = zPart.getNextNote()
            }
            let targetAmplitude: Double
            if let current = currentZNote {
                let percentComplete = current.percentComplete(at: currentSample)
                let frequency = current.getCurrentFrequency(percentComplete: percentComplete)
                triad.setTriadZPitch(frequency: frequency)
                currentZFrequency = frequency
                targetAmplitude = current.getCurrentAmplitude(percentComplete: percentComplete)
            } else {
                currentZFrequency = nil
                targetAmplitude = 0
            }
            appliedZAmplitude += (targetAmplitude - appliedZAmplitude) * amplitudeSmoothing
            triad.setTriadZAmplitude(amplitude: appliedZAmplitude)
        }

        currentSample += 1

        // Every active voice has run out of material AND its fade-out has actually settled -
        // checking only "notes are nil" would risk stopping mid-ramp, trading the note-boundary
        // clicks this smoothing fixes for a new one at the cutoff.
        let allNotesExhausted = currentDroneNote == nil && currentXNote == nil && currentYNote == nil && currentZNote == nil
        let allAmplitudesSettled = abs(appliedDroneAmplitude) < silenceThreshold
            && abs(appliedXAmplitude) < silenceThreshold
            && abs(appliedYAmplitude) < silenceThreshold
            && abs(appliedZAmplitude) < silenceThreshold
        if allNotesExhausted && allAmplitudesSettled {
            isPlaying = false
        }
    }
}
