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
}
