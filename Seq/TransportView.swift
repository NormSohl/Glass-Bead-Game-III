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
import UniformTypeIdentifiers
import GBGCore

struct TransportView: View {
    @ObservedObject var sequencer: SequencerState

    private let tintColor = Color(red: 0.2, green: 0.4, blue: 0.8)

    // Save/load (Step 5) - exportFile is populated right before isExporting is set true,
    // since .fileExporter needs a real (non-nil) document at the moment it's asked to present.
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportFile: SeqDocumentFile?

    // Import segmentation prompt (Step 4) - set right after a raw-recording-shaped document is
    // decoded, so the confirmation dialog below has something to act on regardless of which
    // choice the user makes. pendingRawImportScale travels alongside it - the decoded document
    // and its scale are captured together at import time, but only reach SequencerState once
    // the user actually picks Segment or Load As-Is below.
    @State private var pendingRawImport: SeqDocument?
    @State private var pendingRawImportScale: MIDIScaleDefinition?
    @State private var showSegmentPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                Button {
                    let data = SeqMIDICodec.encode(document: sequencer.exportDocument(), scale: sequencer.currentScale, sampleRate: sequencer.sampleRate)
                    exportFile = SeqDocumentFile(data: data)
                    isExporting = true
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!sequencer.hasAnyNotes)

                Button {
                    isImporting = true
                } label: {
                    Label("Open", systemImage: "square.and.arrow.up")
                }

                // Panic - manual escape hatch for a voice stuck sounding, e.g. via a note
                // shorter than pollPlayback's ~30Hz interval getting skipped entirely on the
                // way out to Graph or an external synth (see SequencerState.panic's own doc
                // comment). Deliberately its own destructive-looking color, unlike the plain
                // tintColor the other buttons share - this is a "stop everything now" action,
                // not a mode toggle, worth standing out.
                Button {
                    sequencer.panic()
                } label: {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.title2)
                }
                .tint(.red)
                .help("Panic - force-silence every voice (internal synth and both MIDI outputs) if something is stuck sounding")

                Spacer()
            }

            // Internal synth on/off (Step 6) - the first of Seq's three independent outputs;
            // Graph Out/Synth Out below are the other two. All three can be on at once.
            HStack(spacing: 12) {
                Toggle(isOn: $sequencer.internalSynthEnabled) {
                    Text("Internal Synth")
                }
                Spacer()
            }
            .font(.callout)

            // Graph MIDI-out connection - a second, independent output alongside the internal
            // synth above (both can be on at once, matching Graph's own "internal synth" +
            // "MIDI" checkbox precedent). See SequencerState's Graph MIDI-out section.
            HStack(spacing: 12) {
                Toggle(isOn: $sequencer.graphOutputEnabled) {
                    Text("Graph Out")
                }
                .disabled(sequencer.graphMidiDestinations.isEmpty)

                Picker("Destination", selection: $sequencer.graphDestinationIndex) {
                    ForEach(sequencer.graphMidiDestinations.indices, id: \.self) { index in
                        Text(sequencer.graphMidiDestinations[index].name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(sequencer.graphMidiDestinations.isEmpty)

                if let detected = sequencer.detectedGraphDestinationIndex,
                   detected != sequencer.graphDestinationIndex || !sequencer.graphOutputEnabled {
                    Button {
                        sequencer.connectDetectedGraph()
                    } label: {
                        Label("Graph detected - Connect", systemImage: "link")
                    }
                    .tint(.green)
                }

                Spacer()
            }
            .font(.callout)

            // External synth MIDI-out connection (Step 4) - a second, independent output
            // alongside Graph Out above, with its own destination and user-configurable
            // channel-per-voice (a real synth's routing is arbitrary, unlike Graph's fixed
            // defaults). See SequencerState's external synth MIDI-out section.
            HStack(spacing: 12) {
                Toggle(isOn: $sequencer.synthOutputEnabled) {
                    Text("Synth Out")
                }
                .disabled(sequencer.synthMidiDestinations.isEmpty)

                Picker("Destination", selection: $sequencer.synthDestinationIndex) {
                    ForEach(sequencer.synthMidiDestinations.indices, id: \.self) { index in
                        Text(sequencer.synthMidiDestinations[index].name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(sequencer.synthMidiDestinations.isEmpty)

                channelStepper("D", value: $sequencer.synthDroneChannel, color: voiceColors[.drone] ?? .white)
                channelStepper("X", value: $sequencer.synthXChannel, color: voiceColors[.x] ?? .white)
                channelStepper("Y", value: $sequencer.synthYChannel, color: voiceColors[.y] ?? .white)
                channelStepper("Z", value: $sequencer.synthZChannel, color: voiceColors[.z] ?? .white)

                Spacer()
            }
            .font(.callout)
        }
        .tint(tintColor)
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black)
        .fileExporter(isPresented: $isExporting, document: exportFile, contentType: .midi, defaultFilename: "Untitled Piece") { _ in
            // Nothing else to do either way - the document was already captured at the moment
            // Save was pressed, so a cancelled/failed export just leaves Seq's own state as-is.
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.midi]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? SeqMIDICodec.decode(data, targetSampleRate: sequencer.sampleRate)
            else { return }
            if SequencerState.looksLikeRawRecording(decoded.document) {
                pendingRawImport = decoded.document
                pendingRawImportScale = decoded.scale
                showSegmentPrompt = true
            } else {
                sequencer.loadDocument(decoded.document, scale: decoded.scale)
            }
        }
        // Step 4: an imported document shaped like a raw live recording (see
        // SequencerState.looksLikeRawRecording) offers a choice rather than always segmenting
        // automatically or always loading as one long continuous note either way - both are
        // legitimate things to want, so this asks once at import time instead of guessing.
        .confirmationDialog(
            "This looks like a raw recording",
            isPresented: $showSegmentPrompt,
            presenting: pendingRawImport
        ) { document in
            Button("Segment") { sequencer.loadSegmentedDocument(document, scale: pendingRawImportScale) }
            Button("Load As-Is") { sequencer.loadDocument(document, scale: pendingRawImportScale) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Split it into editable notes, or load the continuous recording unchanged?")
        }
    }

    /// One voice's channel-number stepper for the external synth connection - a compact
    /// "label + number + up/down" control, four of these side by side stand in for a proper
    /// per-voice settings sheet without needing one for just four small integers.
    private func channelStepper(_ label: String, value: Binding<Int>, color: Color) -> some View {
        Stepper(value: value, in: 1...16) {
            Text("\(label): \(value.wrappedValue)").foregroundStyle(color)
        }
        .frame(width: 90)
    }
}

/// Thin FileDocument wrapper around an already-encoded Standard MIDI File for .fileExporter -
/// SeqMIDICodec.encode (GBGCore) does the actual document->bytes work before this is even
/// constructed, so this just carries bytes to disk. init(configuration:) exists solely for
/// FileDocument conformance - Seq's own Open goes through .fileImporter + SeqMIDICodec.decode
/// directly instead (it needs the decoded scale alongside the document, which this type has no
/// way to carry).
struct SeqDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.midi] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
