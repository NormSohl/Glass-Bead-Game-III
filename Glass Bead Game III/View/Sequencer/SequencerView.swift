//
//  SequencerView.swift
//  Glass Bead Game III
//
//  Thin container: transport controls over the piano roll.
//

import SwiftUI
import GBGCore

struct SequencerView: View {
    @ObservedObject var settings: AppSettings
    let sound: Sound
    @ObservedObject var sequencer: SequencerState
    let scale: Scale

    var body: some View {
        VStack(spacing: 0) {
            TransportView(settings: settings, sound: sound, sequencer: sequencer)
            PianoRollView(scale: scale, settings: settings, sequencer: sequencer)
                .layoutPriority(1)
        }
        .background(Color.black)
    }
}
