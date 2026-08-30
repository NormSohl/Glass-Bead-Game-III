//
//  PitchBendMath.swift
//  GBGCore
//
//  Pure conversion math extracted from Midi.swift so it can be unit tested
//  without touching CoreMIDI or any hardware output.

import Foundation

public enum PitchBendMath {
    // Converts a frequency, relative to a reference frequency, into a 14-bit MIDI pitch bend value (0...16383, centered at 8192)
    public static func freqToPB(frequency: Double, referenceFrequency: Double, pitchBendRange: Int) -> Int {
        let cents = 1200 * log2(frequency / referenceFrequency)
        return centsToPitchBend(pitchBendRange: pitchBendRange, cents: cents)
    }

    static func centsToPitchBend(pitchBendRange: Int, cents: Double) -> Int {
        let pbRangeInCents = Double(pitchBendRange * 100)
        if cents >= pbRangeInCents {
            return 16383
        }
        if cents < (0 - pbRangeInCents) {
            return 0
        }
        let centsTemp = cents / (100.0 * Double(pitchBendRange))
        let retPB = (centsTemp * 8192) + 8192
        return Int(retPB)
    }

    // Inverse of centsToPitchBend - decodes an incoming 14-bit pitch bend value (0...16383,
    // centered at 8192) back into cents, given the same range the sender declared. Needed for
    // MIDI *input* (an external controller or another app driving the graph) - freqToPB only
    // covers the outgoing direction.
    public static func pitchBendToCents(pitchBendRange: Int, pitchBend: Int) -> Double {
        let normalized = Double(pitchBend - 8192) / 8192.0
        return normalized * Double(pitchBendRange) * 100.0
    }

    // Decodes an incoming MIDI note number + pitch bend into an actual frequency. The note
    // number is interpreted as standard 12-TET/A440 (the same formula NoteList uses) since
    // that's what any generic MIDI source - a controller, another app - sends; the pitch bend
    // then carries this app's own just-intonation offset on top, mirroring how this app's own
    // MIDI *output* always sends a fixed note number and carries the real interval in the bend.
    public static func frequencyFromNoteAndPitchBend(note: Int, pitchBend: Int, pitchBendRange: Int) -> Double {
        let baseFrequency = pow(2.0, Double(note - 69) / 12.0) * 440.0
        let cents = pitchBendToCents(pitchBendRange: pitchBendRange, pitchBend: pitchBend)
        return baseFrequency * pow(2.0, cents / 1200.0)
    }
}
