//
//  ControlView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/2/24.
//

import SwiftUI
import GBGCore
import GBGSound

struct ControlView: View {
    @ObservedObject var settings: AppSettings
    @State private var showKeyMapping = false

    // A USB cable plugged in (or anything else that newly appeared) after this popover last
    // checked never shows up on its own - the source/destination lists are only scanned once at
    // launch plus whenever this fires. See Midi.refreshMidiPorts's own comment.
    private var midiRefreshButton: some View {
        Button {
            sound.midi.refreshMidiPorts()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(!settings.useMIDI)
        .help("Re-scan for MIDI destinations/sources - use this after plugging in a cable")
    }

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
                // Hides the tetrad diamonds on whichever Z plane is current - not the grid
                // itself, which "Filter Grid to Z" below controls separately.

                Toggle(isOn: $settings.showDissonance, label:{
                    Text("Dissonance Field")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)

                Toggle(isOn: $settings.filterGraphLines, label:{
                    Text("Filter Grid to Z")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)

                Picker("Border Labels", selection: $settings.tickLabelStyle) {
                    ForEach(TickLabelStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .tint(tintcolor)

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

                // Reachable from here rather than the main toolbar - this is a "look at this
                // occasionally," not a "reach for every session" control. Cross-platform: on the
                // iPad performance build this drives a physical/Bluetooth keyboard's bindings (see
                // ContentView's KeyboardMonitor) alongside Pencil-squeeze, not instead of it.
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

#if os(iOS)
                Text("Z-Slider Side:").foregroundStyle(.white)
#endif
                // Right-handers wanted the Z-slider on the left instead of Norm's own default -
                // one setting for both, not two: the iPad ControlColumn always takes whichever
                // side this isn't (see ContentView's body), so there's no way for the two to
                // end up on the same side or drift out of sync with each other.
                Picker("Z-Slider Side:", selection: $settings.zSliderSide) {
                    ForEach(ControlsSide.allCases) { side in
                        Text(side.rawValue.capitalized).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .pickerStyle(.segmented)

                Divider()

                Toggle("Use internal synth", isOn:$settings.useSynth)
                    .tint(tintcolor)
                    .onChange(of: settings.useSynth) {sound.outputToAudio = settings.useSynth}
                    .foregroundStyle(.white)
                
                // Labeled "MPE" now that it's the only mode this app ever sends - MPE is a
                // strict superset of plain MIDI 1.0 (a receiver that doesn't understand its
                // extra zone-declaration RPN just ignores it and still gets normal per-channel
                // note-on/off + pitch bend), and the app's own default pitch bend range (~19
                // semitones up, 12 down) doesn't fit inside the ±12 semitones a non-MPE
                // declaration could safely assume most receivers honor - see
                // Sound/Sound.swift's git history for the removed "Use MPE" toggle this
                // replaced.
                Toggle("Use Midi MPE", isOn:$settings.useMIDI)
                    .tint(tintcolor)
                    .onChange(of: settings.useMIDI) {sound.outputToMidi = settings.useMIDI}
                    .foregroundStyle(.white)

#if os(iOS)
                // iPadOS has no system-level "Network MIDI" panel the way macOS's Audio MIDI
                // Setup does, so this is the only way to reach that transport at all on iPad -
                // Mac doesn't need it (Norm can already do this via Audio MIDI Setup), hence
                // iOS-only rather than a redundant option there. Once enabled, whatever it's
                // connected to shows up in MIDI Destination/Source below like any other port.
                Toggle("Enable Network MIDI", isOn: $settings.useNetworkMIDI)
                    .tint(tintcolor)
                    .onChange(of: settings.useNetworkMIDI) { sound.midi.setNetworkMIDIEnabled(settings.useNetworkMIDI) }
                    .disabled(!settings.useMIDI)
                    .foregroundStyle(.white)
                Text("Connect over USB, or pair with your Mac's Network MIDI session (Audio MIDI Setup) on the same Wi-Fi network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif

                Divider().foregroundColor(.white)
#if os(iOS)
                // The refresh button sits on the label's row here rather than beside the picker
                // (as on macOS): the popover is only ~340pt wide, and sharing a row squeezed the
                // picker until a name like "Network Session 1" wrapped onto a second line that
                // overflowed onto "MIDI Source:" below (seen live 2026-09-28). This way the
                // picker gets the full row, same as MIDI Source's.
                HStack {
                    Text("MIDI Destination:").foregroundStyle(.white)
                    Spacer()
                    midiRefreshButton
                }
#endif
                HStack {
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
                    .lineLimit(1)
#if os(macOS)
                    midiRefreshButton
#endif
                }

#if os(iOS)
                Text("MIDI Source:").foregroundStyle(.white)
#endif
                // Lets an external controller or sequencer drive X/Y/Z over MIDI the same way
                // touch does - see Sound.handleIncomingMidi.
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
                .lineLimit(1)

                Divider()

                // Built from the actual channel numbers rather than hardcoded - those moved
                // once already this session (X/Y/Z first, drone last), so a fixed "1, 2, 3, and
                // 4" string would silently go stale exactly the way this one had, telling the
                // user the wrong channels to check on their receiving synth.
                let tuningMidiChannels = [
                    sound.midi.xMidiMPEChannel, sound.midi.yMidiMPEChannel,
                    sound.midi.zMidiMPEChannel, sound.midi.rootMidiMPEChannel
                ].sorted()
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
                // Two rows: all four buttons on one line don't fit the ~340pt popover - Stop was
                // pushed off the edge entirely and "Unison" wrapped (seen live 2026-09-28).
                VStack(alignment: .leading) {
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
                    }
                    .lineLimit(1)

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
    }

    // Diamond/Triangle's 0.75 scale (not the exact 1/sqrt(2) ~ 0.7071 that would inscribe a
    // 45-degree-rotated square exactly, and not the 0.73 this used before) - found via a live
    // debugger session that selecting either one crashed the app outright (reproduced with zero
    // UI interaction at all, just launching with this rotation+scale as the *default* - not
    // about Picker/.onChange, timing, or publish count, all suspected and ruled out first).
    // AppKit's Auto Layout engine hit `Assertion failed: (!isnan(minY))` in
    // _nsis_frameInEngine, and bisecting the scale value directly (rebuild + relaunch per
    // value) found a narrow crashing band roughly between 0.73 and 0.75 - some numerical edge
    // case internal to Auto Layout's own constraint solving at that specific rotated+scaled
    // size, not a bug in this app's own geometry math. 0.75 sits safely outside it, confirmed
    // repeatedly; .clipped() (see ContentView's graphSquare) contains the resulting slightly
    // larger overflow regardless of exactly which safe value is used here.
    private static let diamondTriangleScale = 0.75

    func setView() {
        switch settings.selectedGraphShape {
        case .square:
            settings.graphTransform = GraphViewTransform()

        case .diamond:
            settings.graphTransform = GraphViewTransform(rotation: -45.0, scale: Self.diamondTriangleScale)

        case .triangle:
            // offsetY was a hardcoded -400 (raw pixels), tuned for one specific window size and
            // wrong on any other - most visibly on the iPad's very different screen, where it
            // badly overflowed into the ControlColumn next to it. -0.4 (40% of the square's own
            // current side, wherever that ends up) reproduces the same proportion this was
            // presumably tuned against, but stays correct across window/screen sizes.
            settings.graphTransform = GraphViewTransform(rotation: 45.0, scale: Self.diamondTriangleScale, offsetY: -0.4)
        }
    }
}

