//
//  ContentView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI
import GBGCore
import GBGSound

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var recordingState: RecordingState

    // Scale/Diamonds/TetradLayers only depend on the scale's shape (limit, highest/lowest
    // ratio) - not on Z. They're cached here and recomputed only via onChange(of:
    // settings.selectedLimit) below, rather than as plain `let`s in body: settings.zFrequency
    // now publishes on every Z-slider touch-move frame, and recomputing Tetrads (the basis of
    // tetradLayers) from scratch on every frame would be the "hundreds of ms at worst" cost
    // from the design notes running many times a second instead of once per limit change.
    @State private var scale: Scale
    @State private var diamonds: Diamonds
    @State private var tetradLayers: TetradLayers

    // The graph square's own rendered height, captured via GeometryReader below - the square
    // (aspectRatio 1/1, contentMode .fit) ends up shorter than the row's full available height
    // once the Z-slider's fixed 70pt is subtracted from the available width, since width becomes
    // the limiting dimension. An HStack doesn't force siblings to a shared height, so without
    // this the Z-slider's own Ticks/gridlines/diamonds would lay out across the *row's* full
    // height while the square renders shorter and vertically centered within it - Norm's "letters,
    // ticks, and intervals" not lining up. Explicitly sizing ZSliderView to this captured height
    // makes both sides use the identical pixel range for the same scale.convertScaleValueToScreenUnits
    // mapping.
    @State private var graphSquareHeight: CGFloat = 0

    init() {
        let initialSettings = AppSettings()
        _settings = StateObject(wrappedValue: initialSettings)
        _recordingState = StateObject(wrappedValue: RecordingState(settings: initialSettings, sampleRateProvider: { sound.audio.sampleRate }))
        let initialScale = Scale(
            limit: limitMap[initialSettings.selectedLimit] ?? 1,
            highestRatio: initialSettings.highestRatio,
            lowestRatio: initialSettings.lowestRatio)
        _scale = State(initialValue: initialScale)
        _diamonds = State(initialValue: Diamonds(scale: initialScale))
        _tetradLayers = State(initialValue: TetradLayers(scale: initialScale))
    }

    private func rebuildScaleDependentState() {
        let newScale = Scale(
            limit: limitMap[settings.selectedLimit] ?? 1,
            highestRatio: settings.highestRatio,
            lowestRatio: settings.lowestRatio)
        scale = newScale
        diamonds = Diamonds(scale: newScale)
        tetradLayers = TetradLayers(scale: newScale)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(.all)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(){
                        Color.black.ignoresSafeArea(.all)
                        GraphView(scale: scale,
                                  diamonds: diamonds,
                                  tetradLayers: tetradLayers,
                                  settings: settings,
                                  recordingState: recordingState
                        )
                        .rotationEffect(.degrees(settings.viewRotation))
                        .animation(.easeIn, value: settings.viewRotation)
                        .scaleEffect(CGSize(width: settings.viewScale, height: settings.viewScale))
                        .offset(x: settings.viewOffsetX, y: settings.viewOffsetY)
                    }
                    .aspectRatio(1/1, contentMode: settings.contentMode)
                    .layoutPriority(1)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { graphSquareHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { graphSquareHeight = proxy.size.height }
                        }
                    )

                    // Z: its own touch zone, not overlapping the graph - a separate DragGesture here
                    // tracks its own touch independently of the graph's, so both can be held at once.
                    // Hidden entirely while the 3rd moving tone is off - Norm: nothing for it
                    // to control then (no tetrad view to drive), so no point showing a control
                    // surface for it. Height explicitly matched to the graph square's own
                    // rendered height (see graphSquareHeight above) rather than left to fill
                    // whatever the row's full height happens to be.
                    if settings.showTetrads {
                        ZSliderView(scale: scale, settings: settings, graphSquareSize: graphSquareHeight, recordingState: recordingState)
                            .frame(width: 70, height: graphSquareHeight > 0 ? graphSquareHeight : nil)
                    }
                }
            }
        }
        .frame (minWidth: 800, minHeight: 500)
        #if os(macOS)
        // Locks the window to always resize both axes together, at whatever ratio currently has
        // no dead space (see idealWindowSize) - dragging just one edge would otherwise leave
        // black borders, since the Z-slider is fixed-point-size, not proportional, so only a
        // plain resizable window (no ratio lock) can go out of sync with the square graph's own
        // aspect. Recomputed whenever the Z-slider (3rd moving tone) shows/hides, since that
        // changes the content's natural ratio.
        .background(WindowAspectLockView(aspectSize: idealWindowSize(thirdToneShown: settings.showTetrads)))
        // Keyboard access to Portamento/Pedal, per Norm - "third party pedals can be configured
        // to work with them" (many cheap USB foot pedals emulate a plain keystroke). See
        // KeyCommandMonitor's own header comment for the toggle-vs-momentary distinction.
        .background(KeyCommandMonitor(settings: settings))
        #endif
        .onChange(of: settings.selectedLimit) {
            rebuildScaleDependentState()
        }
        // .primaryAction places these in the window's title bar on macOS (next to the traffic
        // lights) and as trailing nav-bar items on iOS - native chrome on both platforms, rather
        // than floating buttons drawn over the content.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Drone - the last of the settings-popover controls Norm wanted promoted to the
                // toolbar. Norm floated a bee for this one ("drone" is also a male bee) - SF
                // Symbols has no literal bee glyph (confirmed by trying "bee"/"bee.fill" directly,
                // both render as nothing), so this is a honeycomb instead: keeps the bee/hive
                // association without an actual insect. Moved to first position per Norm.
                Button {
                    settings.playDrone.toggle()
                } label: {
                    // .tint() doesn't actually recolor a plain icon-only macOS toolbar button
                    // (confirmed live - a real click toggled the state with zero visible change)
                    // - foregroundStyle on the glyph itself is what actually works for an SF
                    // Symbol here. TetradView.uiAccentColor, not .accentColor - accentColor
                    // follows the user's own System Settings accent color choice, which on
                    // Norm's Mac is orange, clashing with the yellow diamonds; this fixed, toned-
                    // down blue (also matching the graph's own border below) is complementary to
                    // yellow and independent of whatever the system accent happens to be set to.
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundStyle(settings.playDrone ? TetradView.uiAccentColor : Color.primary)
                }
                .help("Drone (D or K) - the sustained reference tone")
            }
            ToolbarItem(placement: .primaryAction) {
                // Portamento toggle - direct toolbar access to the same settings.snap the
                // "Snapping" checkbox in ControlView used to control (removed once this existed;
                // both drove the same property). Norm: important enough to reach without opening
                // the settings popover first. Scribble icon, chosen over waveform.path (the
                // original - Norm: "does not say portamento to me") and a couple curve/diagonal-
                // line candidates compared directly in the toolbar - a loose freeform line
                // reading as "continuous/unconstrained." Tint now reflects on/off state (Norm:
                // none of these four toggles showed any visible state at all, an earlier
                // "deliberately no active-state color" call reversed on request).
                Button {
                    settings.snap.toggle()
                } label: {
                    // Inverted relative to the other three buttons' own pattern: settings.snap
                    // is "is grid-snapping active" (true = Portamento OFF), but this button is
                    // framed to the user as "Portamento" itself - the underlying HitTestView
                    // chain is snapped = !isShift, isShift = !settings.snap, so
                    // snapped == settings.snap directly. Lighting up on settings.snap==true
                    // would show the icon as "on" exactly when Portamento is actually off.
                    Image(systemName: "scribble")
                        .foregroundStyle(!settings.snap ? TetradView.uiAccentColor : Color.primary)
                }
                .help("Portamento (G or H) - drag continuously between pitches instead of snapping to scale degrees")
            }
            ToolbarItem(placement: .primaryAction) {
                // Pedal - a live-performance control, per Norm, so worth reaching without
                // opening the settings popover first, same reasoning as Portamento above.
                // Infinity icon, chosen over shoeprints.fill (the original) and a couple other
                // candidates compared directly in the toolbar - abstractly represents "keeps
                // sounding indefinitely," which is exactly what sustain does.
                Button {
                    settings.pedal.toggle()
                } label: {
                    Image(systemName: "infinity")
                        .foregroundStyle(settings.pedal ? TetradView.uiAccentColor : Color.primary)
                }
                .help("Pedal (Space, held) - sustain: keep the current notes sounding after you release them")
            }
            ToolbarItem(placement: .primaryAction) {
                // Panic - manual escape hatch for a voice stuck sounding (a touch/pedal/
                // external-MIDI-drive bookkeeping bug leaving something on indefinitely,
                // e.g. the activeTouchCount desync beginExternalDrive used to allow). Norm
                // asked for this directly after hitting a hang during Seq segmented playback.
                // Deliberately its own destructive-looking color (unlike the other toggle
                // buttons, which stay plain) - this isn't a mode toggle, it's a "stop
                // everything now" action, worth visually standing out.
                Button {
                    sound.panic()
                } label: {
                    Image(systemName: "exclamationmark.octagon.fill")
                }
                .tint(.red)
                .help("Panic - force-silence every voice if something is stuck sounding")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    settings.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .help("Settings - scale, tuning, MIDI, and view options")
                .popover(isPresented: $settings.showSettings) {
                    ControlView(settings: settings, recordingState: recordingState)
                        .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 650)
                }
            }
        }
    }
}

#if os(macOS)
import AppKit

// Bridges a raw NSEvent local key monitor into SwiftUI, the same zero-size-NSView-in-the-
// background trick WindowAspectLockView below uses. SwiftUI's own .keyboardShortcut only gives a
// single discrete "activated" callback (like a click) - fine for Portamento and Drone (plain
// toggles, not physically a pedal), but wrong for Pedal: a real damper pedal, and any third-party
// USB pedal configured to emulate this same key, is *held* - down while sustaining, released when
// not - which needs separate keyDown/keyUp tracking, not one press-to-flip event. Space is
// unused elsewhere in the app; many inexpensive USB foot pedals default to sending Space without
// any reconfiguration at all.
private struct KeyCommandMonitor: NSViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.settings = settings
    }

    final class Coordinator {
        var settings: AppSettings
        private var monitor: Any?
        // Portamento's own toggle value (settings.snap) right before Shift was pressed for
        // momentary portamento (see .flagsChanged below) - nil whenever Shift isn't currently
        // being held for this purpose. Restored on release rather than just forcing snap back
        // to true, so a G/H toggle that was already active before the Shift press survives it
        // (holding Shift only means "force portamento on for as long as I hold it," not
        // "portamento is off the moment I let go"). Option was tried first (physically next to
        // Space on Norm's keyboard) but didn't actually work live - switched to Shift instead,
        // which also matches HitTestView's own separate pre-existing shift-held-while-dragging
        // behavior conceptually, even though that's a different code path.
        private var snapBeforeShiftHeld: Bool?

        init(settings: AppSettings) {
            self.settings = settings
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                switch event.type {
                case .keyDown:
                    // Space (key code 49) or F/J - Pedal, momentary: down while held, matching a
                    // real damper pedal's own physical behavior. F/J are additional keys for the
                    // same momentary press/release (not a toggle - that wouldn't fit how a pedal
                    // actually behaves), Norm's own choice, sitting at the home-row index-finger
                    // position either hand can reach without retraining.
                    if event.keyCode == 49 || event.charactersIgnoringModifiers?.lowercased() == "f" || event.charactersIgnoringModifiers?.lowercased() == "j" {
                        self.settings.pedal = true
                        return nil
                    }
                    // "G"/"H" (Glide) - Portamento, a discrete toggle rather than momentary,
                    // since it isn't physically a pedal. isARepeat filters out the auto-repeat
                    // keyDown stream macOS sends while a key stays held, which would otherwise
                    // flip the toggle many times a second instead of once per press. Norm plays
                    // left-handed - G and D sit under a right-hander's left hand at rest on the
                    // home row (G is the left index finger's stretch key, D its middle finger's
                    // home key), so H and K mirror them at the same finger positions under the
                    // *right* hand instead (A-S-D-F-G | H-J-K-L-; mirrors position-for-position
                    // around the F/J gap: G<->H, D<->K) - either hand can reach its own pair
                    // without retraining a specific handedness.
                    // isARepeat only gates the toggle itself, not consuming the event - gating
                    // both together (the original bug here) let every repeated keyDown while
                    // the key stayed held fall through unconsumed, past the end of this switch,
                    // straight into macOS's own "no responder handled this key" system beep -
                    // audible proof the event wasn't actually being swallowed. Any matching
                    // character is now always consumed (return nil unconditionally), whether or
                    // not this particular keyDown is the one that actually toggles anything.
                    let character = event.charactersIgnoringModifiers?.lowercased()
                    if character == "g" || character == "h" {
                        if !event.isARepeat { self.settings.snap.toggle() }
                        return nil
                    }
                    // "D"/"K" - Drone, same discrete-toggle treatment and mirroring as
                    // Portamento above (not physically a pedal either).
                    if character == "d" || character == "k" {
                        if !event.isARepeat { self.settings.playDrone.toggle() }
                        return nil
                    }
                    // Any other bare keypress (no Cmd/Control - those are real menu/system
                    // shortcuts like Cmd+Q, left alone here) has nothing to do in this app - no
                    // text field, no other key command - so it would otherwise fall through
                    // unconsumed to the same "no responder handled this" system beep fixed above
                    // for the keys this view does recognize. Norm: accidental key hits shouldn't
                    // beep during a performance. Swallowed, not acted on. Shift excluded too,
                    // same reason Option was before the momentary-Portamento key moved to Shift -
                    // it's meaningful now (see .flagsChanged below), not a stray key.
                    if event.modifierFlags.intersection([.command, .control, .shift]).isEmpty {
                        return nil
                    }
                case .keyUp:
                    if event.keyCode == 49 || event.charactersIgnoringModifiers?.lowercased() == "f" || event.charactersIgnoringModifiers?.lowercased() == "j" {
                        self.settings.pedal = false
                        return nil
                    }
                case .flagsChanged:
                    // Shift, held on its own - momentary Portamento, mirroring how Space already
                    // works for Pedal. Deliberately separate from G/H's existing discrete toggle
                    // rather than replacing it - both stay available side by side. Pure modifier
                    // keys never generate keyDown/keyUp at all, only flagsChanged (with no
                    // isARepeat concept - it just reports the current modifier set each time any
                    // modifier changes), so this needs its own case rather than fitting into the
                    // keyDown/keyUp handling above. Guarded by snapBeforeShiftHeld so a
                    // flagsChanged fired by some *other* modifier changing while Shift stays held
                    // doesn't re-trigger the capture/restore logic.
                    let shiftHeld = event.modifierFlags.contains(.shift)
                    if shiftHeld, self.snapBeforeShiftHeld == nil {
                        self.snapBeforeShiftHeld = self.settings.snap
                        self.settings.snap = false
                    } else if !shiftHeld, let previousSnap = self.snapBeforeShiftHeld {
                        self.settings.snap = previousSnap
                        self.snapBeforeShiftHeld = nil
                    }
                default:
                    break
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// SwiftUI has no direct scene modifier for this, so it's bridged via a zero-size NSView tucked
// into the background - once it's in the view hierarchy, .window is available.
//
// NSWindow.aspectRatio alone (the obvious API) turned out to only reliably constrain resizes
// driven from the bottom-right resize corner - dragging a single edge (the normal way to resize
// on modern any-edge-resizable macOS windows) could change one dimension without AppKit
// recomputing the other, which is exactly the "Y locks correctly, X still lets black borders in"
// gap Norm found. windowWillResize(_:to:) is the version that's symmetric regardless of which
// edge/corner started the drag: whichever dimension actually changed becomes the driving one,
// and the other is recomputed to match the ratio - so this implements the constraint directly
// instead of relying on aspectRatio's built-in (apparently asymmetric) enforcement.
private struct WindowAspectLockView: NSViewRepresentable {
    let aspectSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window, aspectSize: aspectSize) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window, aspectSize: aspectSize) }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private var aspectSize: CGSize = .zero
        private weak var attachedWindow: NSWindow?

        func attach(to window: NSWindow?, aspectSize: CGSize) {
            self.aspectSize = aspectSize
            guard let window, attachedWindow !== window else { return }
            attachedWindow = window
            window.delegate = self
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            guard aspectSize.width > 0, aspectSize.height > 0 else { return frameSize }
            let ratio = aspectSize.width / aspectSize.height
            let current = sender.frame.size
            let widthDelta = abs(frameSize.width - current.width)
            let heightDelta = abs(frameSize.height - current.height)
            if widthDelta >= heightDelta {
                return NSSize(width: frameSize.width, height: frameSize.width / ratio)
            } else {
                return NSSize(width: frameSize.height * ratio, height: frameSize.height)
            }
        }
    }
}
#endif
