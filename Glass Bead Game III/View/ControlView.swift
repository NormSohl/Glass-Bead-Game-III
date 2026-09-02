//
//  ControlView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/2/24.
//

import SwiftUI
import UniformTypeIdentifiers
import GBGCore
import GBGSound

struct ControlView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var recordingState: RecordingState

    // Save (Step 3 of the live-record plan) - exportFile is populated right before isExporting
    // is set true, since .fileExporter needs a real (non-nil) document at the moment it's asked
    // to present. Mirrors Seq/TransportView.swift's own SeqDocumentFile pattern exactly.
    @State private var isExporting = false
    @State private var exportFile: GraphRecordingFile?
    @State private var showKeyMapping = false

    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea(.all)
            ScrollView {
            VStack(
                alignment: .leading
            ){
                let tintcolor = Color(red: 0.2, green: 0.4, blue: 0.8)

                Text("A Glass Bead Game").bold().font(Font.headline).foregroundStyle(.white)
                Divider()
                Toggle(isOn: $settings.showDiamonds, label:{
                    Text("Diamonds")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)
                // Applies to diamond rendering everywhere on the graph, not just the flat
                // Z-independent view - GraphView ANDs this into TetradView's own showTetrads
                // param too, so it also hides the tetrad diamonds on whichever Z plane is
                // current when the 3rd moving tone is on.

                Toggle(isOn: $settings.showDissonance, label:{
                    Text("Dissonance Field")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)

                Toggle(isOn: $settings.showTetrads, label:{
                    Text("3rd Moving Tone")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)
                // Norm: turning this on should start at the 1:1 (unison) plane every time, so
                // the display reads as unchanged at the moment it switches on (unison's tetrad
                // slice is identical to the default 2D view) - it only switches layers once the
                // slider is actually moved off of that plane, never just from toggling on.
                .onChange(of: settings.showTetrads) {
                    if settings.showTetrads {
                        settings.zFrequency = settings.rootFrequency
                    }
                }

                Toggle(isOn: $settings.filterGraphLines, label:{
                    Text("Filter Grid to Z")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)
                // Meaningless without the 3rd moving tone active - there's no Z-layer to filter
                // the grid down to otherwise.
                .disabled(!settings.showTetrads)

                Toggle("Note X", isOn: $settings.playNoteX)
                    .tint(tintcolor)
                    .foregroundStyle(.white)

                Toggle("Note Y", isOn: $settings.playNoteY)
                    .tint(tintcolor)
                    .foregroundStyle(.white)

                Toggle("Note Z", isOn: $settings.playNoteZ)
                    .tint(tintcolor)
                    .foregroundStyle(.white)

                Divider()

                // Live recording capture (step 3 of the live-record plan) - arms/disarms
                // continuous pitch-contour capture from graph touches (see RecordingState), and
                // saves whatever's captured as a raw SeqDocument for Seq to later import and
                // segment. Placed here alongside the other transport-adjacent controls rather
                // than the main toolbar, matching where MIDI Destination/Verify Pitch Bend Range
                // already live below.
                Text("Live Recording").bold().foregroundStyle(.white)
                HStack {
                    Button {
                        recordingState.toggleRecording()
                    } label: {
                        Label(recordingState.isRecording ? "Stop" : "Record", systemImage: recordingState.isRecording ? "stop.circle.fill" : "circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(recordingState.isRecording ? .red : tintcolor)

                    Button {
                        exportFile = GraphRecordingFile(document: recordingState.exportDocument())
                        isExporting = true
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(recordingState.isRecording || !recordingState.hasAnyNotes)
                }
                .foregroundStyle(.white)

                // Reachable from here rather than the main toolbar, matching Live Recording
                // above - this is a "look at this occasionally," not a "reach for every session"
                // control. macOS only - KeyMappingView remaps NSEvent-driven keyboard shortcuts,
                // which don't apply to the iPad performance build (Pedal there is Pencil-squeeze
                // driven instead - see ContentView's PencilSqueezeMonitor).
                #if os(macOS)
                Button {
                    showKeyMapping = true
                } label: {
                    Label("Keyboard Mapping…", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)
                .tint(tintcolor)
                .foregroundStyle(.white)
                .popover(isPresented: $showKeyMapping) {
                    KeyMappingView(settings: settings)
                }
                #endif

                Divider()
#if os(iOS)
                Text("Harmonics:").foregroundStyle(.white)
#endif
                Picker("Harmonics:", selection: $settings.selectedLimit) { // picker does not show label. Don't know why. using Text to fake
                    Text("3").tag(Limit.three)
                    Text("5").tag(Limit.five)
                    Text("7").tag(Limit.seven)
                    Text("9").tag(Limit.nine)
                    Text("11").tag(Limit.eleven)
                    Text("13").tag(Limit.thirteen)
                    Text("17").tag(Limit.seventeen)
                    Text("19").tag(Limit.nineteen)
                }
                .listItemTint(.blue)
                .background(tintcolor)
                .pickerStyle(.segmented)
                Text("(Number of harmonic partials used to generate the scale used in the graph)").foregroundStyle(.white)
                
                Divider()
                
#if os(iOS)
                Text("View:").foregroundStyle(.white)
#endif
                Picker("View:", selection: $settings.selectedGraphShape){
                    ForEach(GraphShape.allCases) { shape in
                        Text(shape.rawValue.capitalized).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .pickerStyle(.segmented)
                .onChange(of: settings.selectedGraphShape){
                    setView()
                }
                
                Divider()
                
                Toggle("Use internal synth", isOn:$settings.useSynth)
                    .tint(tintcolor)
                    .onChange(of: settings.useSynth) {sound.outputToAudio = settings.useSynth}
                    .foregroundStyle(.white)
                
                Toggle("Use Midi", isOn:$settings.useMIDI)
                    .tint(tintcolor)
                    .onChange(of: settings.useMIDI) {sound.outputToMidi = settings.useMIDI}
                    .foregroundStyle(.white)
                
                Toggle("Use MPE", isOn:$settings.useMIDI_MPE)
                    .tint(tintcolor)
                    .onChange(of: settings.useMIDI_MPE) {sound.midi.useMPE(useMpe: settings.useMIDI_MPE)}
                    .disabled(!settings.useMIDI)
                    .foregroundStyle(.white)
                
                Divider().foregroundColor(.white)
#if os(iOS)
                Text("MIDI Destination:").foregroundStyle(.white)
#endif
                Picker("MIDI Destination:" ,selection: $settings.destinationIndex) {
                    ForEach(sound.midi.midiDestinations.indices, id: \.self) { index in
                        Text(sound.midi.midiDestinations[index].name).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .onChange(of: settings.destinationIndex) {
                    let destinationIndex = settings.destinationIndex
                    //print(settings.destinationIndex,destinationIndex)
                    sound.midi.setMidiDestination(destination: destinationIndex)
                }
                .pickerStyle(.menu)
                .disabled(!settings.useMIDI)
                .tint(.white)

#if os(iOS)
                Text("MIDI Source:").foregroundStyle(.white)
#endif
                // Lets an external controller, or eventually a standalone Seq app, drive X/Y/Z
                // over MIDI the same way touch does - see Sound.handleIncomingMidi and the
                // standalone-sequencer foundation plan's step 3.
                Picker("MIDI Source:", selection: $settings.sourceIndex) {
                    ForEach(sound.midi.midiSources.indices, id: \.self) { index in
                        Text(sound.midi.midiSources[index].name).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .onChange(of: settings.sourceIndex) {
                    sound.midi.setMidiSource(source: settings.sourceIndex)
                }
                .pickerStyle(.menu)
                .disabled(!settings.useMIDI || sound.midi.midiSources.isEmpty)
                .tint(.white)

                Divider()

                // Built from the actual channel numbers rather than hardcoded - those moved
                // once already this session (X/Y/Z first, drone last) and differ between MPE
                // and non-MPE besides, so a fixed "1, 2, 3, and 4" string would silently go
                // stale exactly the way this one had, telling the user the wrong channels to
                // check on their receiving synth.
                let tuningMidiChannels = (settings.useMIDI_MPE
                    ? [sound.midi.xMidiMPEChannel, sound.midi.yMidiMPEChannel, sound.midi.zMidiMPEChannel, sound.midi.rootMidiMPEChannel]
                    : [sound.midi.xMidiChannel, sound.midi.yMidiChannel, sound.midi.zMidiChannel, sound.midi.rootMidiChannel]
                ).sorted()
                let details = "Midi channels \(tuningMidiChannels[0]), \(tuningMidiChannels[1]), \(tuningMidiChannels[2]), and \(tuningMidiChannels[3]) are sending A: 440 hz" // to the \(sound.midi.midiDestinations[settings.destinationIndex].name)"

                Text("For modular/analog gear tuned by hand - MIDI can't retune it automatically.")
                    .font(.footnote)
                    .foregroundStyle(.gray)

                Button("Tune Midi"){
                    if settings.tuneMidi == false{
                        sound.midi.tuneStart()
                        settings.tuneMidi = true
                    }
                    else {
                        sound.midi.tuneStop()
                        settings.tuneMidi = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .alert(
                    "Tuning",
                    isPresented: $settings.tuneMidi,
                    presenting: details
                ) { details in
                    Button(role: .cancel) {
                        sound.midi.tuneStop()
                    } label: {
                        Text("Stop")
                    }
                    
                } message:{ details in
                    Text(details)
                }
                .disabled(!settings.useMIDI)

                // Confirms, by ear, that the pitch bend range declared over MIDI (see
                // Midi.sendPitchBendSensitivity) is actually the range the receiver is using -
                // real gear often ignores that declaration and needs its own range set by
                // hand, so this is the only way to actually check. Unison/fifth/octave are
                // just-intonation ratios (1/1, 3/2, 2/1), matching this app's own tuning
                // system, not equal-tempered approximations. Any one can be clicked at any
                // time to jump straight to it - suits going back and forth while adjusting a
                // knob on the receiving synth, rather than a fixed unison->fifth->octave order.
                Text("Verify Pitch Bend Range").foregroundStyle(.white)
                HStack {
                    Button("Unison") {
                        sound.midi.verifyRangeSet(ratio: 1.0)
                        settings.verifyRangeRatio = 1.0
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.verifyRangeRatio == 1.0 ? tintcolor : .gray)

                    Button("Fifth") {
                        sound.midi.verifyRangeSet(ratio: 3.0 / 2.0)
                        settings.verifyRangeRatio = 3.0 / 2.0
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.verifyRangeRatio == 3.0 / 2.0 ? tintcolor : .gray)

                    Button("Octave") {
                        sound.midi.verifyRangeSet(ratio: 2.0)
                        settings.verifyRangeRatio = 2.0
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.verifyRangeRatio == 2.0 ? tintcolor : .gray)

                    Button("Stop") {
                        sound.midi.verifyRangeStop()
                        settings.verifyRangeRatio = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.verifyRangeRatio == nil)
                }
                .disabled(!settings.useMIDI)

                Spacer()
            }.padding([.leading,.trailing,.top], 20)
            }
        }
        .fileExporter(isPresented: $isExporting, document: exportFile, contentType: .json, defaultFilename: "Live Recording") { _ in
            // Nothing else to do either way - the document was already captured at the moment
            // Save was pressed, so a cancelled/failed export just leaves recordingState as-is.
        }
    }

    func setView() {
        // square graph
        switch settings.selectedGraphShape {
        case .square:
            settings.viewRotation = 0.0 // rotation in degrees
            settings.viewScale = 1.0 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .diamond:
            settings.viewRotation = -45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .triangle:
            settings.viewRotation = 45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = -400 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fill
        }
    }
}

/// Thin FileDocument wrapper around SeqDocument for .fileExporter, so Graph can save a live
/// recording using the same JSON persistence Seq's own save/load already uses - mirrors
/// Seq/TransportView.swift's SeqDocumentFile exactly (that one lives in the Seq target, which
/// Graph doesn't depend on, so this is Graph's own copy of the same thin adapter rather than a
/// shared one - SeqDocument itself, the real content, already lives in GBGCore and needs no
/// duplication).
struct GraphRecordingFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var document: SeqDocument

    init(document: SeqDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try JSONDecoder().decode(SeqDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(document)
        return FileWrapper(regularFileWithContents: data)
    }
}

