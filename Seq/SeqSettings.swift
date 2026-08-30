//
//  SeqSettings.swift
//  Seq
//
//  Seq's own minimal settings - not the full Graph AppSettings (Seq has no touch graph, no
//  harmonics picker, no MIDI toggles yet). rootFrequency anchors the piano roll's pitch axis
//  (same default as Graph's AppSettings.rootFrequency); x/y/zFrequency are written by
//  playback/scrub/handle-drag the same way Graph's AppSettings.xFrequency/etc are, but nothing
//  reads them yet in this step - they're a hook point for Step 3's MIDI-out.
//

import Foundation

final class SeqSettings: ObservableObject {
    @Published var rootFrequency: Double = 261.6255653005986 // middle C
    @Published var xFrequency: Double = 261.6255653005986
    @Published var yFrequency: Double = 261.6255653005986
    @Published var zFrequency: Double = 261.6255653005986
}
