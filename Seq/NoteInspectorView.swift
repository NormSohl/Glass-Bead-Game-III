//
//  NoteInspectorView.swift
//  Seq
//
//  Exact editing for the selected note: start/end time, start/end pitch (a scale ratio like
//  "5/4", or Hz), and the profile dropdown that shapes the bend between them. A held note is
//  just a bend with equal pitches, so "Hold" sets end pitch = start pitch.
//

import SwiftUI
import GBGCore

struct NoteInspectorView: View {
    let scale: Scale
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState

    private static let profiles: [TransitionKind] = [.linear, .easeIn, .easeOut, .easeInEaseOut]

    var body: some View {
        HStack(spacing: 12) {
            if let selection = sequencer.selection {
                editor(for: selection)
                    .id(ObjectIdentifier(selection.note)) // fresh fields per note
            } else {
                Text(hint).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .background(Color(white: 0.08))
        .foregroundStyle(.white)
        .disabled(sequencer.isEditingLocked)
    }

    private var hint: String {
        switch sequencer.editTool {
        case .select: return "Click a note to edit it. Drag its dots to move an end, drag its line to move the whole note. Option = no snapping."
        case .place: return "Click to place a \(voiceNames[sequencer.selectedVoice] ?? "") note. Option = no snapping."
        case .step: return "Click a pitch for each armed voice; the green cursor moves on after the last. ← / → step back / rest."
        }
    }

    @ViewBuilder
    private func editor(for selection: NoteSelection) -> some View {
        let note = selection.note
        Circle().fill(voiceColors[selection.voice] ?? .white).frame(width: 10, height: 10)
        Text(voiceNames[selection.voice] ?? "").bold()

        labeled("Start") {
            CommitField(value: seconds(note.startTime), width: 70) { text in
                guard let value = Double(text) else { return false }
                sequencer.setTime(.start, of: selection, time: Int(value * sequencer.sampleRate))
                return true
            }
        }
        labeled("End") {
            CommitField(value: seconds(note.endTime), width: 70) { text in
                guard let value = Double(text) else { return false }
                sequencer.setTime(.end, of: selection, time: Int(value * sequencer.sampleRate))
                return true
            }
        }
        Text(gridPosition(note) + String(format: "%.3fs long", Double(note.endTime - note.startTime) / sequencer.sampleRate))
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Divider().frame(height: 20)

        labeled("Pitch") {
            CommitField(value: pitch(note.startFrequency), width: 80) { text in
                guard let f = PitchText.parse(text, rootFrequency: settings.rootFrequency) else { return false }
                sequencer.setPitch(.start, of: selection, frequency: f)
                return true
            }
        }
        Image(systemName: "arrow.right").foregroundStyle(.secondary)
        CommitField(value: pitch(note.endFrequency), width: 80) { text in
            guard let f = PitchText.parse(text, rootFrequency: settings.rootFrequency) else { return false }
            sequencer.setPitch(.end, of: selection, frequency: f)
            return true
        }
        Button("Hold") { sequencer.holdPitch(of: selection) }
            .disabled(note.endFrequency == note.startFrequency)
            .help("Make it a held note: end pitch = start pitch")

        Picker("Profile", selection: Binding(
            get: { note.transitionKind },
            set: { sequencer.setProfile($0, of: selection) }
        )) {
            ForEach(Self.profiles, id: \.self) { Text(label(for: $0)).tag($0) }
            if note.recordedPitchBend != nil || note.transitionKind == .recordedContour {
                Divider()
                Text(label(for: .recordedContour)).tag(TransitionKind.recordedContour)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("How the pitch moves from start to end")

        if note.recordedPitchBend != nil {
            Button("Purge Recorded", role: .destructive) { sequencer.purgeRecordedData(of: selection) }
        }

        Button(role: .destructive) {
            sequencer.deleteSelectedNote()
        } label: {
            Image(systemName: "trash")
        }
        .help("Delete note (⌫)")
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            content()
        }
    }

    private func seconds(_ sample: Int) -> String {
        String(format: "%.3f", Double(sample) / sequencer.sampleRate)
    }

    private func pitch(_ frequency: Double) -> String {
        PitchText.format(frequency, rootFrequency: settings.rootFrequency, scale: scale)
    }

    private func gridPosition(_ note: Note) -> String {
        guard let tempo = sequencer.activeTempo else { return "" }
        return "at " + pianoRollTimeLabel(sample: note.startTime, sampleRate: sequencer.sampleRate, tempo: tempo, beatsPerBar: sequencer.beatsPerBar, subdivision: sequencer.gridSubdivision) + ", "
    }

    private func label(for kind: TransitionKind) -> String {
        switch kind {
        case .flat, .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInEaseOut: return "Ease In/Out"
        case .recordedContour: return "Recorded"
        }
    }
}

/// A text field that only applies its value on Return (and snaps back to the model's value if
/// the text didn't parse, or when focus leaves without committing).
private struct CommitField: View {
    let value: String
    let width: CGFloat
    let onCommit: (String) -> Bool

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: width)
            .focused($isFocused)
            .onSubmit {
                if onCommit(draft) {
                    // Blur on the next turn, after the edit has re-rendered this field with the
                    // applied (possibly clamped/snapped) value, so the blur handler shows that.
                    DispatchQueue.main.async { isFocused = false }
                } else {
                    draft = value
                }
            }
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if !isFocused { draft = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { draft = value }
            }
    }
}
