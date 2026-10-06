//
//  SequencerView.swift
//  Seq
//
//  The whole app's content: transport/I-O controls, the note-entry toolbar and inspector, the
//  drone indicator strip (drone has no other visual home), the timeline ruler, and the note
//  editor. The pitch views all use the loaded piece's scale (SequencerState.editorScale).
//

import SwiftUI
import GBGCore

struct SequencerView: View {
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let scale = sequencer.editorScale
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
