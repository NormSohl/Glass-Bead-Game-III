//
//  SeqSettings.swift
//  Seq
//
//  Seq's own minimal settings - not the full Graph AppSettings. rootFrequency anchors the
//  editor's pitch axis (set from the loaded piece's scale; same default as Graph's
//  AppSettings.rootFrequency); pitchBendRange is the persisted MIDI bend range.
//

import Foundation

final class SeqSettings: ObservableObject {
    @Published var rootFrequency: Double = 261.6255653005986 // middle C

    // Pitch bend range (semitones) for every MIDI pitch-bend Seq sends (Graph Out, Synth Out)
    // and decodes (live capture). Graph doesn't adopt a sender's range over MIDI - it encodes
    // and decodes with its own Settings -> Pitch Bend Range - so this has to be set to match it.
    // Same choices and default as Graph's AppSettings.pitchBendRangeMPE.
    static let pitchBendRangeChoices = [24, 48]
    @Published var pitchBendRange: Int = {
        let saved = UserDefaults.standard.integer(forKey: "Seq.pitchBendRange")
        return SeqSettings.pitchBendRangeChoices.contains(saved) ? saved : 24
    }() {
        didSet { UserDefaults.standard.set(pitchBendRange, forKey: "Seq.pitchBendRange") }
    }
}
