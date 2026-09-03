//
//  SequencerView.swift
//  Seq
//
//  The whole app's content for this step: transport controls, the drone indicator strip, and
//  the piano roll. Adapted from Graph's own SequencerView (a panel container there) - here it's
//  the entire window, so it also surfaces RootIndicatorView directly (Graph's copy doesn't wire
//  it in at this level; check where Graph does, if anywhere - drone needs a visual home here
//  since there's no other UI in this app that could show it).
//

import SwiftUI
import GBGCore

struct SequencerView: View {
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState
    let scale: Scale

    var body: some View {
        VStack(spacing: 0) {
            TransportView(sequencer: sequencer, liveCapture: sequencer.liveCapture)
            RootIndicatorView(scale: scale, settings: settings, sequencer: sequencer)
            PianoRollView(scale: scale, settings: settings, sequencer: sequencer)
                .layoutPriority(1)
        }
        .background(Color.black)
    }
}
