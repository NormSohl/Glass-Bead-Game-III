//
//  ControlData.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/3/24.
//
//  This struct contains published data that is shared between the UI and the drawing code

import SwiftUI
import GBGCore

// The graph's X/Y/Z axes - not the drone, which has no crosshair on the main graph. Used to
// track which axes are currently being driven by the sequencer (playback/scrub/handle-editing)
// rather than by touch - see AppSettings.sequencerDrivenVoices and the sequencer memory notes.
enum SequencerVoice: Hashable {
    case x, y, z
}

class AppSettings: ObservableObject{
    @Published var showDiamonds: Bool = true
    @Published var showSettings: Bool = false // settings panel is a popover now, freeing the right edge for the Z slider
    @Published var showDissonance: Bool = false // opt-in: true per-pixel resolution, recomputes (cached) on toggle/limit/resize
    // Default view, not opt-in: at Z=unison (its own default) this looks identical to the old
    // 2D Diamonds default, so this is a pure superset - Diamonds itself stays available via its
    // own toggle if turned back on after switching this off (see DiamondView's showDiamonds &&
    // !showTetrads gating).
    @Published var showTetrads: Bool = true
    // Default when the 3rd moving tone is on: the background grid only shows the scale degrees
    // that actually pair with the current Z (see Tetrads.elementsPairing) instead of every scale
    // degree regardless of Z - the grid was staying dense/uniform even as the diamonds themselves
    // thinned out at off-root Z layers, which read as clutter rather than structure. Toggle stays
    // available to revert to the full unfiltered grid.
    @Published var filterGraphLines: Bool = true
    @Published var selectedLimit: Limit = Limit.eleven
    // Norm: with the 3rd moving tone on by default, Z sits at unison (= the drone's own pitch)
    // until touched, so playing the drone too just doubles a tone already sounding - off by
    // default now that Z covers it; still available via its own toggle. This is the only copy
    // of the drone's enabled state - Sound.enableDrone reads straight through sound.settings
    // (wired below in init()) rather than keeping a separately-defaulted copy.
    @Published var playDrone: Bool = false
    @Published var playNoteX: Bool = true
    @Published var playNoteY: Bool = true
    @Published var playNoteZ: Bool = true
    @Published var snap: Bool = true
    // didSet, not a View's onChange - pedal can now be released from several places (the
    // settings checkbox, the toolbar button, the Space-bar key command), and only the checkbox
    // lives inside a view that's actually mounted the whole time (ControlView only exists while
    // the settings popover is open). A didSet here fires no matter what changed the property, so
    // sound.releasePedal() can't silently stop firing just because the popover happened to be
    // closed when the toolbar button or key command flipped this off.
    @Published var pedal: Bool = false {
        didSet {
            if !pedal { sound.releasePedal() }
        }
    }
    // Loaded once at init from UserDefaults (see KeyMapping.swift) and saved back on every
    // change - deliberately persisted, unlike every other property on this class, since a
    // keyboard remap is a real customization worth keeping across launches, not a session
    // toggle. Read by ContentView's KeyCommandMonitor; written by KeyMappingView.
    @Published var keyMapping: KeyMapping = KeyMapping.loadFromDefaults() {
        didSet { keyMapping.saveToDefaults() }
    }
    // Not persisted, purely transient UI state - true only while KeyMappingView's own capture
    // monitor is actively listening for the next keypress to bind. ContentView's
    // KeyCommandMonitor checks this first and no-ops entirely while it's true, so a key that's
    // already bound to something (e.g. pressing D while trying to bind a new key elsewhere)
    // doesn't also fire its existing action as a side effect of being captured, and so there's
    // no ambiguity about which of the two active local NSEvent monitors sees a given key first.
    @Published var isCapturingKeyBinding: Bool = false
    // Which side the Z-slider sits on (graph's other fixed-width sibling, the iPad
    // ControlColumn, always takes the opposite side automatically - see ContentView's body).
    // Persisted like keyMapping - a real physical setup preference (which hand plays which
    // control), not a session toggle that should reset every launch like most of this class.
    @Published var zSliderSide: ControlsSide = ControlsSide.loadFromDefaults() {
        didSet { zSliderSide.saveToDefaults() }
    }
    // iOS only (GameController framework's GCKeyboardInput only exposes one global
    // keyChangedHandler slot at a time, unlike NSEvent's multiple simultaneous local monitors
    // on macOS) - which action KeyMappingView's capture button is waiting to bind the next
    // physical keypress to. Set by KeyMappingView, read/cleared by ContentView's iOS
    // KeyboardMonitor once a key comes in. nil whenever nothing is being captured.
    @Published var pendingKeyBindingAction: KeyAction? = nil
    @Published var useSynth: Bool = true
    @Published var useMIDI: Bool = true
    @Published var useMIDI_MPE: Bool = true
    @Published var tuneMidi: Bool = false
    // nil = not sounding; 1.0/1.5/2.0 = unison/fifth/octave currently held on all four voices
    // (Midi.verifyRangeSet/verifyRangeStop) - a plain @Published var here, not @State on
    // ControlView, so Stop stays reachable and the "currently sounding" label stays accurate
    // even if the settings popover happens to close and reopen while a tone is still held.
    @Published var verifyRangeRatio: Double? = nil
    @Published var selectedGraphShape: GraphShape = .square

    // Which X/Y/Z axes are currently being driven by incoming MIDI (Seq, or any other MIDI
    // controller) rather than touch - see Sound.handleIncomingMidi. Read by HitTestView/
    // ZSliderView ("don't read touch for this axis's crosshair, use whatever's already been
    // written into settings.xFrequency/yFrequency/zFrequency instead"). Used to be read
    // alongside a second set, sequencerDrivenVoices, written by Graph's own in-app sequencer -
    // removed once the standalone Seq app replaced it.
    @Published var externallyDrivenVoices: Set<SequencerVoice> = []
    
    // root pitch
    @Published var rootFrequency: Double = 261.6255653005986 // middle c  // no UI yet if ever. MIDI note number 60
    @Published var rootMidiNote: Int = 60  // middle c

    // X/Y/Z: the graph's three moving tones. HitTestView/ZSliderView publish the currently
    // touched pitch here every frame (X/Y added alongside ScoreCapture, mirroring how
    // ZSliderView already published zFrequency for TetradView to read) - this is the graph's
    // one place to read "what's currently selected" from outside the touch-handling views
    // themselves, e.g. for ScoreCapture to read when writing a chord into a Score.
    @Published var xFrequency: Double = 261.6255653005986 // starts at unison with the root
    @Published var yFrequency: Double = 261.6255653005986 // starts at unison with the root
    @Published var zFrequency: Double = 261.6255653005986 // starts at unison with the root

    // True for exactly the span of a Z-slider touch-drag (ZSliderView's DragGesture,
    // onChanged...onEnded) - not tied to audio/pedal/MIDI at all, unlike Sound's own touch
    // counts. DissonanceView reads this to decide between its own two render qualities: a cheap
    // resolution kept live while this is true, versus progressively refining upward once it
    // goes false (see DissonanceView's header comment).
    @Published var zDragActive: Bool = false

    //@Published var numberOfOctaves: Double = 2
    // Highest ratio =
    // 3/2 gives range of a fifth above 1/1
    // 2/1 gives a range of one octave above 1/1
    // 3/1 is an octave and a fifth above 1/1
    // 4/1 gives two octaves above 1/1
    // 8/1 gives three octaves above 1/1
    @Published var highestRatio: Double = 3/1
    @Published var highestRatioNormalized:Double = 0.0 // initialized in the init function 0 to 1 is an octave. >1 for higher values
    @Published var destinationIndex:Int = 0
    // MIDI Source picker binding, mirroring destinationIndex above - see Midi.setMidiSource.
    @Published var sourceIndex:Int = 0
    
    // Lowest ratio =
    // 2/3 is a fifth below 1/1
    // 1/2 gives a range of one octave below 1/1
    // 1/3 gives a range of one octave and a fifth below 1/1
    // 1/4 gives two octaves below 1/1
    // 1/8 gives three octaves below 1/1
    @Published var lowestRatio: Double = 1/2
    @Published var lowestRatioNormalized: Double = 0.0  // initialized in the init function -1 to 0 for an octave. < -1 for lower values
    
    // combine into range
    @Published var rangeNormalized: Double = 0.0  // initialized in the init function
    
    // support for rotated views - replaced by UI
    
    // square graph: default. should really zero these out at init and let the UI set the appropriate values, even for defaults
    @Published var viewRotation: Double = 0.0 // rotation in degrees
    @Published var viewScale: Double = 1.0 // scaling 1.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
    @Published var viewOffsetX: Double = 0.0 // horizontal offset
    @Published var viewOffsetY: Double = 0.0 // Vertical offset, inverted. negative numbers to go up
    @Published var contentMode: ContentMode = .fit
    @Published var border: Double = 40
    
    // MIDI data
    @Published var pitchBendRange: Int = 12
    @Published var pitchBendRangeMPE: Int = 24
    
    init(){
        self.highestRatioNormalized = log(self.highestRatio) / log(2)
        self.lowestRatioNormalized = log(self.lowestRatio) / log(2)
        
        // combine highest and lowest normalized ratios to give the full range of the graph
        self.rangeNormalized = self.highestRatioNormalized - self.lowestRatioNormalized // positive, need to handle negative value
        
        sound.setRootPitch(frequency: self.rootFrequency)
        sound.setRootNote(midiNote: self.rootMidiNote)
        // MPE's range first, then the non-MPE range, then the mode itself - Midi.useMPE
        // defaults true (matching useMIDI_MPE's own default below) and each range setter
        // immediately re-declares whichever range is currently active via RPN 0 (see
        // Midi.sendPitchBendSensitivity), so setting the *inactive* range first would
        // transmit it as if it were current. This order keeps every message correct instead
        // of sending a wrong value that a moment later gets corrected.
        sound.setPitchBendRangeMPE(pitchBendRange: self.pitchBendRangeMPE)
        sound.setPitchBendRange(pitchBendRange: self.pitchBendRange)
        // Midi.useMPE is a separate stored var with its own hardcoded default, not something
        // that reads straight through settings the way enableDrone/enableX/Y/Z do (see the
        // comment on those below) - it wasn't drifting silently before only because both
        // defaults happened to independently be true, the exact fragility that comment
        // describes. Norm: "make MPE default if it is not" - explicitly syncing it here means
        // the real answer no longer depends on two hardcoded defaults staying coincidentally
        // aligned. Matters musically, not just cosmetically: the graph's default range (3/1
        // above root to 1/2 below, ~19 semitones up and 12 down) only fits inside MPE's wider
        // pitchBendRangeMPE - the plain pitchBendRange would clip everything above +12
        // semitones.
        sound.setUseMPE(useMpe: self.useMIDI_MPE)
        // X/Y/Z's underlying Midi/Audio pitch state otherwise stays at Midi's own raw 0.0
        // default (garbage - a 0Hz-derived pitch bend clamps to the minimum) until each one's
        // own view actually publishes a real value. X/Y happen to get seeded as a side effect
        // of HitTestView's Canvas rendering once on mount even before any touch, but
        // ZSliderView deliberately skips that for Z until the Z-slider's own first touch (the
        // hasTouched guard, there to stop the marker jumping to a wrong position on mount) -
        // and Z can now sound from a plain graph touch alone (see Sound.applyZVoiceEnables),
        // so without this it would send that garbage pitch the first time that happens in a
        // session. Pushing all three explicitly here removes the accidental dependency on
        // HitTestView's side effect too, not just fixing Z.
        sound.setXPitch(frequency: self.xFrequency)
        sound.setYPitch(frequency: self.yFrequency)
        sound.setZPitch(frequency: self.zFrequency)
        // Lets Sound's enableDrone/enableX/enableY/enableZ read playDrone/playNoteX/Y/Z straight
        // through this instance instead of keeping their own separately-defaulted copies.
        sound.settings = self
    }
}

enum Limit: String, CaseIterable, Identifiable {
    case three, five, seven, nine, eleven, thirteen, seventeen, nineteen
    var id: Self { self }
}

enum GraphShape: String, CaseIterable, Identifiable {
    case square, diamond, triangle
    var id: Self {self}
}

enum ControlsSide: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: Self { self }
}

extension ControlsSide {
    private static let userDefaultsKey = "GlassBeadGameIII.zSliderSide"

    static func loadFromDefaults() -> ControlsSide {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let decoded = ControlsSide(rawValue: raw) else {
            return .right
        }
        return decoded
    }

    func saveToDefaults() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

let limitMap: [Limit: Int] = [
    Limit.three: 3,
    Limit.five: 5,
    Limit.seven: 7,
    Limit.nine: 9,
    Limit.eleven: 11,
    Limit.thirteen: 13,
    Limit.seventeen: 17,
    Limit.nineteen: 19
]

