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

import Foundation

class ScorePlayer {
    private let triad: Triad
    private let dronePart: Part?
    private let xPart: Part?
    private let yPart: Part?
    private let zPart: Part?

    private(set) var currentSample: Int = 0
    private(set) var isPlaying: Bool = false

    private var currentDroneNote: Note?
    private var currentXNote: Note?
    private var currentYNote: Note?
    private var currentZNote: Note?

    init(triad: Triad, dronePart: Part?, xPart: Part?, yPart: Part?, zPart: Part?) {
        self.triad = triad
        self.dronePart = dronePart
        self.xPart = xPart
        self.yPart = yPart
        self.zPart = zPart
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
            if let current = currentDroneNote {
                let percentComplete = current.percentComplete(at: currentSample)
                triad.setTriadRootPitch(frequency: current.getCurrentFrequency(percentComplete: percentComplete))
                triad.setTriadRootAmplitude(amplitude: current.getCurrentAmplitude(percentComplete: percentComplete))
            } else {
                triad.setTriadRootAmplitude(amplitude: 0)
            }
        }

        if let xPart {
            while let current = currentXNote, currentSample >= current.endTime {
                currentXNote = xPart.getNextNote()
            }
            if let current = currentXNote {
                let percentComplete = current.percentComplete(at: currentSample)
                triad.setTriadXPitch(frequency: current.getCurrentFrequency(percentComplete: percentComplete))
                triad.setTriadXAmplitude(amplitude: current.getCurrentAmplitude(percentComplete: percentComplete))
            } else {
                triad.setTriadXAmplitude(amplitude: 0)
            }
        }

        if let yPart {
            while let current = currentYNote, currentSample >= current.endTime {
                currentYNote = yPart.getNextNote()
            }
            if let current = currentYNote {
                let percentComplete = current.percentComplete(at: currentSample)
                triad.setTriadYPitch(frequency: current.getCurrentFrequency(percentComplete: percentComplete))
                triad.setTriadYAmplitude(amplitude: current.getCurrentAmplitude(percentComplete: percentComplete))
            } else {
                triad.setTriadYAmplitude(amplitude: 0)
            }
        }

        if let zPart {
            while let current = currentZNote, currentSample >= current.endTime {
                currentZNote = zPart.getNextNote()
            }
            if let current = currentZNote {
                let percentComplete = current.percentComplete(at: currentSample)
                triad.setTriadZPitch(frequency: current.getCurrentFrequency(percentComplete: percentComplete))
                triad.setTriadZAmplitude(amplitude: current.getCurrentAmplitude(percentComplete: percentComplete))
            } else {
                triad.setTriadZAmplitude(amplitude: 0)
            }
        }

        currentSample += 1

        // every active voice has run out of material - nothing left to play
        if currentDroneNote == nil && currentXNote == nil && currentYNote == nil && currentZNote == nil {
            isPlaying = false
        }
    }
}
