//
//  TransportView.swift
//  Glass Bead Game III
//
//  Play/Stop, Scrub, and Add Note - the sequencer's basic controls. Deliberately kept simple:
//  Norm was explicit these need more interaction thought once they exist to try, not before.
//

import SwiftUI
import GBGCore

struct TransportView: View {
    @ObservedObject var settings: AppSettings
    let sound: Sound
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

            Button {
                SequencerCapture.captureChordAtPlayhead(sequencer: sequencer, settings: settings, sound: sound)
            } label: {
                Label("Add Note", systemImage: "plus.circle.fill")
            }

            Stepper(
                "Duration: \(String(format: "%.2f", sequencer.noteDurationSeconds))s",
                value: $sequencer.noteDurationSeconds,
                in: 0.05...4.0,
                step: 0.05
            )
            .frame(width: 220)

            Spacer()

            Button {
                settings.showSequencer = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
        }
        .tint(tintColor)
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black)
    }
}
