//
//  EditToolbarView.swift
//  Seq
//
//  Note-entry controls: the tool (Select / Place / Step), what that tool needs (the voice for
//  Place; the armed voices and Back/Rest for Step), the length of a new note, and the optional
//  BPM grid.
//

import SwiftUI
import GBGCore

struct EditToolbarView: View {
    @ObservedObject var sequencer: SequencerState

    // Note lengths offered with the grid on, in beats.
    private static let beatLengths: [(label: String, beats: Double)] = [
        ("1/4 beat", 0.25), ("1/3 beat", 1.0 / 3), ("1/2 beat", 0.5), ("1 beat", 1), ("2 beats", 2), ("3 beats", 3), ("4 beats", 4), ("8 beats", 8),
    ]
    private static let subdivisions: [(label: String, value: Int)] = [("Beat", 1), ("1/2", 2), ("1/3", 3), ("1/4", 4)]

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $sequencer.editTool) {
                Label("Select", systemImage: "cursorarrow").tag(EditTool.select)
                Label("Place", systemImage: "pencil").tag(EditTool.place)
                Label("Step", systemImage: "forward.end").tag(EditTool.step)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            .help("Select: click a note to edit it. Place: click to put a note there. Step: click pitches to fill the step at the green cursor, which then moves on.")

            switch sequencer.editTool {
            case .select:
                EmptyView()
            case .place:
                Picker("Voice", selection: $sequencer.selectedVoice) {
                    ForEach(SequencerState.stepOrder, id: \.self) { voice in
                        Text(voiceNames[voice] ?? "").tag(voice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            case .step:
                HStack(spacing: 4) {
                    ForEach(SequencerState.stepOrder, id: \.self) { voice in
                        Toggle(voiceNames[voice] ?? "", isOn: Binding(
                            get: { sequencer.stepVoices.contains(voice) },
                            set: { on in
                                if on { sequencer.stepVoices.insert(voice) } else { sequencer.stepVoices.remove(voice) }
                            }
                        ))
                        .toggleStyle(.button)
                        .tint(voiceColors[voice] ?? .white)
                    }
                }
                .help("Voices each step fills, in this order - one click per voice")
                Button { sequencer.stepBack() } label: { Image(systemName: "chevron.left") }
                    .help("Step back (←)")
                Button { sequencer.advanceStep() } label: { Label("Rest", systemImage: "chevron.right") }
                    .help("Skip ahead one step, leaving silence or finishing a partial chord (→)")
            }

            lengthControl

            Divider().frame(height: 20)

            Toggle("Grid", isOn: $sequencer.gridEnabled)
            if sequencer.gridEnabled {
                TextField("BPM", value: $sequencer.gridBPM, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text("BPM").foregroundStyle(.secondary)
                Stepper("\(sequencer.beatsPerBar)/bar", value: $sequencer.beatsPerBar, in: 1...16)
                    .fixedSize()
                Picker("Snap", selection: $sequencer.gridSubdivision) {
                    ForEach(Self.subdivisions, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var lengthControl: some View {
        if sequencer.gridEnabled {
            Picker("Length", selection: $sequencer.noteDurationBeats) {
                ForEach(Self.beatLengths, id: \.beats) { Text($0.label).tag($0.beats) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        } else {
            Stepper(
                "Length: \(String(format: "%.2f", sequencer.noteDurationSeconds))s",
                value: $sequencer.noteDurationSeconds,
                in: 0.05...8.0,
                step: 0.05
            )
            .fixedSize()
        }
    }
}
