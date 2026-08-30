//
//  TransportView.swift
//  Seq
//
//  Play/Stop, Scrub, and note placement - the sequencer's basic controls. Adapted from Graph's
//  own TransportView: Graph's "Add Note" captured the live graph's current touch as a chord,
//  which has no equivalent here (Seq has no touch graph) - replaced with a voice picker + an
//  "Add Note" arm/disarm toggle, with actual placement happening on the next piano-roll tap (see
//  PianoRollView/SequencerState.placeNote). The "close panel" button is dropped entirely - Seq
//  is the whole app/window, not a panel inside another app.
//

import SwiftUI

struct TransportView: View {
    @ObservedObject var sequencer: SequencerState

    private let tintColor = Color(red: 0.2, green: 0.4, blue: 0.8)

    var body: some View {
        HStack(spacing: 16) {
            Button {
                if sequencer.isPlaying { sequencer.stop() } else { sequencer.play() }
            } label: {
                Image(systemName: sequencer.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
            }
            .disabled(!sequencer.hasAnyNotes && !sequencer.isPlaying)

            Slider(
                value: Binding(
                    get: { Double(sequencer.playheadSample) },
                    set: { sequencer.scrub(to: Int($0)) }
                ),
                in: 0...Double(max(sequencer.scoreLengthSamples, 1)),
                onEditingChanged: { editing in
                    if editing { sequencer.beginScrub() } else { sequencer.endScrub() }
                }
            )
            .disabled(sequencer.isPlaying)

            Picker("Voice", selection: $sequencer.selectedVoice) {
                Text("Drone").tag(PartVoice.drone).foregroundStyle(voiceColors[.drone] ?? .white)
                Text("X").tag(PartVoice.x).foregroundStyle(voiceColors[.x] ?? .white)
                Text("Y").tag(PartVoice.y).foregroundStyle(voiceColors[.y] ?? .white)
                Text("Z").tag(PartVoice.z).foregroundStyle(voiceColors[.z] ?? .white)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                sequencer.isPlacingNote.toggle()
            } label: {
                Label("Add Note", systemImage: "plus.circle.fill")
            }
            .tint(sequencer.isPlacingNote ? .green : tintColor)

            Stepper(
                "Duration: \(String(format: "%.2f", sequencer.noteDurationSeconds))s",
                value: $sequencer.noteDurationSeconds,
                in: 0.05...4.0,
                step: 0.05
            )
            .frame(width: 220)

            Spacer()
        }
        .tint(tintColor)
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black)
    }
}
