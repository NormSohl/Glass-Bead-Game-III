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
// track which axes are currently being driven by incoming MIDI rather than by touch - see
// AppSettings.externallyDrivenVoices.
enum GraphAxis: Hashable {
    case x, y, z
}

class AppSettings: ObservableObject{
    @Published var showDiamonds: Bool = true
    @Published var showSettings: Bool = false // settings panel is a popover now, freeing the right edge for the Z slider
    @Published var showDissonance: Bool = false // opt-in: true per-pixel resolution, recomputes (cached) on toggle/limit/resize
    // Default when Z sits at unison: the background grid only shows the scale degrees that
    // actually pair with the current Z (see Tetrads.elementsPairing) instead of every scale
    // degree regardless of Z - the grid was staying dense/uniform even as the diamonds themselves
    // thinned out at off-root Z layers, which read as clutter rather than structure. Toggle stays
    // available to revert to the full unfiltered grid.
    @Published var filterGraphLines: Bool = true
    @Published var tickLabelStyle: TickLabelStyle = .letters
    @Published var selectedLimit: Limit = Limit.eleven
    // Norm: Z always sits at unison (= the drone's own pitch) until touched, so playing the
    // drone too just doubles a tone already sounding - off by default since Z always covers it;
    // still available via its own toggle. This is the only copy
    // of the drone's enabled state - Sound.enableDrone reads straight through sound.settings
    // (wired below in init()) rather than keeping a separately-defaulted copy.
    // didSet, same reasoning as pedal's own just above: Drone can be toggled from the toolbar
    // button or the D/K key command as well as ControlView's own checkbox, and X/Y/Z's Note
    // toggles live only inside ControlView (mounted only while the settings popover is open) -
    // a didSet here fires regardless of which one changed it. Without this, toggling any of
    // these had no audible effect at all until the next touch begin/end happened to recompute
    // enables (confirmed live, 2026-09-05: Drone toggled mid-touch, or with nothing touched,
    // produced no change whatsoever) - see Sound.refreshVoiceEnables's own comment.
    @Published var playDrone: Bool = false {
        didSet { sound.refreshVoiceEnables() }
    }
    @Published var playNoteX: Bool = true {
        didSet { sound.refreshVoiceEnables() }
    }
    @Published var playNoteY: Bool = true {
        didSet { sound.refreshVoiceEnables() }
    }
    @Published var playNoteZ: Bool = true {
        didSet { sound.refreshVoiceEnables() }
    }
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
    // MPE is the only mode this app ever sends now (see ControlView's "Use Midi MPE" toggle) -
    // there's no separate useMIDI_MPE flag to keep in sync any more.
    @Published var useMIDI: Bool = true
    // iOS only (see ControlView's own toggle) - off by default, matching the rest of AppSettings'
    // opt-in-each-session pattern and, more importantly, not silently advertising a network
    // service just because the app launched.
    @Published var useNetworkMIDI: Bool = false
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
    // written into settings.xFrequency/yFrequency/zFrequency instead").
    @Published var externallyDrivenVoices: Set<GraphAxis> = []
    
    // root pitch
    @Published var rootFrequency: Double = 261.6255653005986 // middle c  // no UI yet if ever. MIDI note number 60
    @Published var rootMidiNote: Int = 60  // middle c

    // X/Y/Z: the graph's three moving tones. HitTestView/ZSliderView publish the currently
    // touched pitch here every frame - this is the graph's one place to read "what's currently
    // selected" from outside the touch-handling views themselves.
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
    
    // support for rotated views - replaced by UI. One @Published struct, not five separate
    // @Published fields, so the five values ControlView's setView() sets per shape always
    // change together as one atomic snapshot rather than five independent publishes - not just
    // tidiness, see GraphViewTransform's own comment for a real crash this was chased through
    // while tracking down (and ultimately unrelated to, see setView()'s comment for the actual
    // cause).
    @Published var graphTransform = GraphViewTransform()
    @Published var border: Double = 40
    
    // MIDI data
    @Published var pitchBendRangeMPE: Int = 24
    
    init(){
        self.highestRatioNormalized = log(self.highestRatio) / log(2)
        self.lowestRatioNormalized = log(self.lowestRatio) / log(2)
        
        // combine highest and lowest normalized ratios to give the full range of the graph
        self.rangeNormalized = self.highestRatioNormalized - self.lowestRatioNormalized // positive, need to handle negative value
        
        sound.setRootPitch(frequency: self.rootFrequency)
        sound.setRootNote(midiNote: self.rootMidiNote)
        // MPE is unconditional now (Midi.initMidi's own enableMPE() call already declared the
        // zone at launch, via RPN 6 - it never touches pitch bend range itself). This is the
        // first and only RPN 0 (Pitch Bend Sensitivity) send, pushing the real value over the
        // placeholder 0 Midi.pitchBendRangeMPE starts with, before anything actually plays.
        // Matters musically, not just cosmetically: the graph's default range (3/1 above root
        // to 1/2 below, ~19 semitones up and 12 down) needs this wider range - a plain,
        // non-MPE-safe ±12 semitones (what many non-MPE receivers reliably honor) would clip
        // everything above +12 semitones, which is most of the graph's own default span.
        sound.setPitchBendRangeMPE(pitchBendRange: self.pitchBendRangeMPE)
        // X/Y/Z's underlying Midi/Audio pitch state otherwise stays at Midi's own raw 0.0
        // default (garbage - a 0Hz-derived pitch bend clamps to the minimum) until each one's
        // own view actually publishes a real value. X/Y happen to get seeded as a side effect
        // of HitTestView's Canvas rendering once on mount even before any touch, but
        // ZSliderView deliberately skips that for Z until the Z-slider's own first drag (the
        // settings.zDragActive guard, there to stop the marker jumping to a wrong position on
        // mount) - and Z can now sound from a plain graph touch alone (see Sound.applyZVoiceEnables),
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

// Lets GBGCore's KeyActionDispatcher (moved there 2026-09-05, see its own header comment) read
// and write exactly the settings it needs without knowing anything about AppSettings itself -
// no change to AppSettings above was needed, since it already had every one of these properties.
extension AppSettings: KeyActionPerforming {}

enum Limit: String, CaseIterable, Identifiable {
    case three, five, seven, nine, eleven, thirteen, seventeen, nineteen
    var id: Self { self }
}

enum GraphShape: String, CaseIterable, Identifiable {
    case square, diamond, triangle
    var id: Self {self}
}

// Two ways to label the graph's border ticks - see Ticks (TickView.swift) for the actual
// drawing. .letters is the original fixed 12-EDO note-name grid (C/D/E/... at the naturals,
// blank dash ticks between); .ratios instead marks the graph's own just-intonation scale
// degrees (Scale.scale, the same ScaleElements the grid lines are drawn from) with a dot and a
// small numerator/slash/denominator label, positioned level with each element's actual line.
enum TickLabelStyle: String, CaseIterable, Identifiable {
    case letters = "Letters"
    case ratios = "Ratios"
    var id: Self { self }
}

// The graph square's rotation/scale/offset, set atomically per GraphShape by ControlView's
// setView() - see AppSettings.graphTransform's own comment for why this is one struct instead
// of separate @Published fields.
struct GraphViewTransform: Equatable {
    var rotation: Double = 0.0 // degrees
    // 1.0 = no change. See ControlView.setView()'s own comment for why Diamond/Triangle use
    // 0.75, not the exact 1/sqrt(2) ~ 0.7071 a 45-degree inscribed-square fit would want.
    var scale: Double = 1.0
    // Fractions of the square's own side (ContentView multiplies by graphSquareHeight), not raw
    // pixels - a fixed pixel offset tuned for one window/screen size is wrong on any other.
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0 // inverted - negative numbers go up
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

