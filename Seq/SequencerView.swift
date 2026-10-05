//
//  SequencerView.swift
//  Seq
//
//  The whole app's content: transport/I-O controls, the note-entry toolbar and inspector, the
//  drone indicator strip, the timeline ruler, and the note editor. Adapted from Graph's own SequencerView (a panel container there) - here it's
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
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            TransportView(sequencer: sequencer, settings: settings, liveCapture: sequencer.liveCapture)
            EditToolbarView(sequencer: sequencer)
            NoteInspectorView(scale: scale, settings: settings, sequencer: sequencer)
            RootIndicatorView(scale: scale, settings: settings, sequencer: sequencer)
            TimelineRulerView(sequencer: sequencer)
            PianoRollView(scale: scale, settings: settings, sequencer: sequencer)
                .layoutPriority(1)
        }
        .background(Color.black)
        .onAppear { sequencer.undoManager = undoManager }
        .onChange(of: undoManager) { _, newValue in sequencer.undoManager = newValue }
    }
}
