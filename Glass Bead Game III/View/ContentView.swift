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
                    #if os(iOS)
                    // Opposite the Z-slider (which defaults to trailing below) so a
                    // performer's other hand doesn't have to reach across the graph for
                    // either one - the same reasoning behind wanting the Z-slider itself
                    // movable to the other side. Not yet tied to a shared handedness setting;
                    // when that's added, both should flip together.
                    ControlColumn(settings: settings, recordingState: recordingState)
                    #endif
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
        #if os(iOS)
        // Apple Pencil Pro squeeze -> Pedal toggle, for live performance: the graphic-entry
        // hand already holds the pencil, so this is a free gesture on that same hand rather
        // than competing with the touch surface. See PencilSqueezeMonitor's own comment for
        // the iPad Settings caveat that can silently swallow this.
        .background(PencilSqueezeMonitor(settings: settings))
        // A physical/Bluetooth keyboard, or a cheap keypad emulating one, driving the same
        // KeyMapping a Mac keyboard would - Norm: "iPad can connect to a keyboard... button
        // pads are cheap," so this keeps that path open rather than treating Pencil-squeeze
        // as the iPad's only input. See KeyboardMonitor's own comment.
        .background(KeyboardMonitor(settings: settings))
        #endif
        .onChange(of: settings.selectedLimit) {
            rebuildScaleDependentState()
        }
        // macOS only - .toolbar has nowhere to attach without a NavigationStack, which this
        // app deliberately doesn't have (would cost a permanent nav-bar strip of vertical
        // space). .primaryAction places these in the window's title bar, next to the traffic
        // lights. The iPad build gets the same five actions via ControlColumn instead - see
        // its own comment below for why that's a column, not a floating overlay.
        #if os(macOS)
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
        #endif
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
        var settings: AppSettings {
            didSet { dispatcher.settings = settings }
        }
        private let dispatcher: KeyActionDispatcher
        private var monitor: Any?
        // Which of the four modifier tokens are currently held - flagsChanged reports the
        // CURRENT full modifier set on every call, not a delta, so this is diffed against each
        // new event to find what actually changed (see .flagsChanged below).
        private var heldModifierTokens: Set<KeyToken> = []

        init(settings: AppSettings) {
            self.settings = settings
            self.dispatcher = KeyActionDispatcher(settings: settings)
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                // Stand down entirely while KeyMappingView's own capture monitor is listening
                // for a new binding - see AppSettings.isCapturingKeyBinding's own comment.
                guard !self.settings.isCapturingKeyBinding else { return event }
                switch event.type {
                case .keyDown:
                    // Space doesn't reliably come through charactersIgnoringModifiers the same
                    // way regular letters do, so key code 49 is checked directly as an alias for
                    // the " " token - same special-casing the original hardcoded version had.
                    let token: KeyToken? = event.keyCode == 49 ? " " : event.charactersIgnoringModifiers?.lowercased()
                    if let token, let action = self.settings.keyMapping.action(for: token) {
                        // isARepeat only gates toggle actions, not consuming the event - gating
                        // both together used to let every repeated keyDown while a key stayed
                        // held fall through unconsumed, straight into macOS's own "no responder
                        // handled this key" system beep. Any matching token is now always
                        // consumed (return nil unconditionally) regardless of repeat state.
                        self.dispatcher.applyKeyDown(action, isARepeat: event.isARepeat)
                        return nil
                    }
                    // Any other bare keypress (no Cmd/Control - those are real menu/system
                    // shortcuts like Cmd+Q, left alone here) has nothing to do in this app - no
                    // text field, no other key command - so it would otherwise fall through
                    // unconsumed to the same system beep fixed above for keys that ARE mapped.
                    // Norm: accidental key hits shouldn't beep during a performance. Bound
                    // modifiers excluded too (same reason as the keys themselves) - computed
                    // live from the current mapping rather than a fixed set, so remapping a
                    // modifier onto/off of an action keeps this in sync automatically.
                    let boundModifierFlags = self.currentlyBoundModifierFlags()
                    if event.modifierFlags.intersection([.command, .control]).isEmpty
                        && event.modifierFlags.intersection(boundModifierFlags).isEmpty {
                        return nil
                    }
                case .keyUp:
                    let token: KeyToken? = event.keyCode == 49 ? " " : event.charactersIgnoringModifiers?.lowercased()
                    if let token, let action = self.settings.keyMapping.action(for: token), action.isMomentary {
                        self.dispatcher.applyKeyUp(action)
                        return nil
                    }
                case .flagsChanged:
                    // Pure modifier keys never generate keyDown/keyUp at all, only flagsChanged -
                    // and it reports the current full modifier set each time, not a delta, so
                    // this diffs against heldModifierTokens to find what actually changed.
                    let newlyHeld = modifierKeyTokens.filter { self.isTokenModifierHeld($0, in: event.modifierFlags) }
                    for token in newlyHeld.subtracting(self.heldModifierTokens) {
                        if let action = self.settings.keyMapping.action(for: token) {
                            self.dispatcher.applyKeyDown(action, isARepeat: false)
                        }
                    }
                    for token in self.heldModifierTokens.subtracting(newlyHeld) {
                        if let action = self.settings.keyMapping.action(for: token), action.isMomentary {
                            self.dispatcher.applyKeyUp(action)
                        }
                    }
                    self.heldModifierTokens = newlyHeld
                default:
                    break
                }
                return event
            }
        }

        private func isTokenModifierHeld(_ token: KeyToken, in flags: NSEvent.ModifierFlags) -> Bool {
            switch token {
            case "shift": return flags.contains(.shift)
            case "option": return flags.contains(.option)
            case "control": return flags.contains(.control)
            case "command": return flags.contains(.command)
            default: return false
            }
        }

        private func currentlyBoundModifierFlags() -> NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            for token in modifierKeyTokens where settings.keyMapping.action(for: token) != nil {
                switch token {
                case "shift": flags.insert(.shift)
                case "option": flags.insert(.option)
                case "control": flags.insert(.control)
                case "command": flags.insert(.command)
                default: break
                }
            }
            return flags
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

#if os(iOS)
import UIKit

// Bridges Apple Pencil Pro's squeeze gesture into a single settings.pedal toggle - the iOS
// analog of KeyCommandMonitor's own NSEvent-bridging trick above, just via
// UIPencilInteraction instead. Fires once per squeeze, on .ended rather than .began, so a
// squeeze reads as one clean toggle - matching how D/K/G/H already toggle rather than hold.
//
// iOS 17.5+, Apple Pencil Pro only - older Pencils have no squeeze gesture at all. Also
// depends on a *device-global* preference: Settings > Apple Pencil > Squeeze on the iPad
// itself. If that's set to "Run Shortcut," the system intercepts the gesture before this
// app's delegate ever sees it - any other choice (e.g. the default "Show Contextual
// Palette") lets it through. Not something this code can override or detect.
private struct PencilSqueezeMonitor: UIViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if #available(iOS 17.5, *) {
            let interaction = UIPencilInteraction()
            interaction.delegate = context.coordinator
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.settings = settings
    }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var settings: AppSettings

        init(settings: AppSettings) {
            self.settings = settings
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else { return }
            settings.pedal.toggle()
        }
    }
}

// The same five actions as macOS's window-titlebar toolbar (Drone/Portamento/Pedal/Panic/
// Settings), laid out top-to-bottom in a fixed-width column instead - a floating overlay
// was considered and rejected: Norm wants zero vertical space lost to a nav bar (ruling out
// NavigationStack + .toolbar), and a column sized as a normal HStack sibling, exactly like
// ZSliderView already is, achieves that for free via the graph's own .layoutPriority(1) +
// .aspectRatio(.fit) - the square simply shrinks to whatever width remains, same mechanism
// already proven for the Z-slider, rather than drawing over the content.
private struct ControlColumn: View {
    @ObservedObject var settings: AppSettings
    let recordingState: RecordingState

    var body: some View {
        // Anchored to the top, not centered - cheap insurance against a resting palm: Norm's
        // drawing hand rests its palm/wrist trailing the pencil tip, generally mid-to-lower on
        // the canvas, so pushing the buttons as high as they'll go is free distance from that
        // even before confirming whether it's a real problem (see the palm-rejection memory
        // notes for the actual fix if it turns out not to be enough on its own).
        VStack(spacing: 24) {
            button("circle.hexagongrid.fill", active: settings.playDrone, label: "Drone") {
                settings.playDrone.toggle()
            }
            // Inverted relative to the other three, same as the macOS toolbar's own version:
            // settings.snap is "is grid-snapping active" (true = Portamento OFF).
            button("scribble", active: !settings.snap, label: "Portamento") {
                settings.snap.toggle()
            }
            button("infinity", active: settings.pedal, label: "Pedal") {
                settings.pedal.toggle()
            }
            // Always red, unlike the toggle buttons above - this isn't a mode toggle, it's a
            // "stop everything now" action, worth visually standing out (matches macOS's own
            // Panic button).
            Button {
                sound.panic()
            } label: {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Panic")
            Button {
                settings.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .popover(isPresented: $settings.showSettings) {
                ControlView(settings: settings, recordingState: recordingState)
                    .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 650)
            }

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .frame(width: 60)
    }

    private func button(_ systemName: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(active ? TetradView.uiAccentColor : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

import GameController

// Bridges a physical/Bluetooth keyboard into the same KeyMapping-driven dispatch macOS's
// KeyCommandMonitor already uses, via KeyActionDispatcher - Norm: "iPad can connect to a
// keyboard... button pads are cheap," so a cheap USB/Bluetooth keypad works here exactly like
// a real keyboard would, no separate binding model needed.
//
// GCKeyboardInput.keyChangedHandler is a single global any-key handler - unlike NSEvent's
// multiple simultaneous local monitors on macOS, only one handler can be installed at a time.
// KeyMappingView's capture flow works around that by setting settings.pendingKeyBindingAction
// rather than installing its own competing handler (see that view's iOS branch): this same
// handler checks that first, on every press, before falling through to normal dispatch.
//
// keyChangedHandler models each key as a discrete button transition (pressed true once, false
// once), not a text field's repeat stream - so unlike NSEvent's keyDown, there's no isARepeat
// concept to gate here at all.
private struct KeyboardMonitor: UIViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.install()
        return UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.settings = settings
    }

    final class Coordinator {
        var settings: AppSettings {
            didSet { dispatcher.settings = settings }
        }
        private let dispatcher: KeyActionDispatcher
        private var connectObserver: Any?

        init(settings: AppSettings) {
            self.settings = settings
            self.dispatcher = KeyActionDispatcher(settings: settings)
        }

        func install() {
            attach(GCKeyboard.coalesced?.keyboardInput)
            // GCKeyboard.coalesced can read nil even with a keyboard already attached (a
            // known quirk when checked too early in a view's own lifecycle) - the connect
            // notification is the reliable path, and covers a keyboard paired after launch too.
            connectObserver = NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] notification in
                self?.attach((notification.object as? GCKeyboard)?.keyboardInput)
            }
        }

        private func attach(_ input: GCKeyboardInput?) {
            guard let input else { return }
            input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                guard let self, let token = KeyboardMonitor.token(for: keyCode) else { return }
                // A pending capture from KeyMappingView's "+" button always wins over normal
                // dispatch, and only reacts to the press half of the gesture.
                if pressed, let pendingAction = self.settings.pendingKeyBindingAction {
                    self.settings.keyMapping.bind(token, to: pendingAction)
                    self.settings.pendingKeyBindingAction = nil
                    self.settings.isCapturingKeyBinding = false
                    return
                }
                guard !self.settings.isCapturingKeyBinding,
                      let action = self.settings.keyMapping.action(for: token) else { return }
                if pressed {
                    self.dispatcher.applyKeyDown(action, isARepeat: false)
                } else if action.isMomentary {
                    self.dispatcher.applyKeyUp(action)
                }
            }
        }

        deinit {
            if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        }
    }

    // Translates GCKeyCode - GameController's physical-key vocabulary - into the same
    // KeyToken strings KeyMapping already persists, so one KeyMapping (and one
    // KeyMappingView) drives both platforms' monitors instead of needing a parallel iOS-only
    // binding model.
    fileprivate static func token(for keyCode: GCKeyCode) -> KeyToken? {
        switch keyCode {
        case .spacebar: return " "
        case .leftShift, .rightShift: return "shift"
        case .leftAlt, .rightAlt: return "option"
        case .leftControl, .rightControl: return "control"
        case .leftGUI, .rightGUI: return "command"
        default: break
        }
        let letterCodes: [GCKeyCode: Character] = [
            .keyA: "a", .keyB: "b", .keyC: "c", .keyD: "d", .keyE: "e", .keyF: "f", .keyG: "g",
            .keyH: "h", .keyI: "i", .keyJ: "j", .keyK: "k", .keyL: "l", .keyM: "m", .keyN: "n",
            .keyO: "o", .keyP: "p", .keyQ: "q", .keyR: "r", .keyS: "s", .keyT: "t", .keyU: "u",
            .keyV: "v", .keyW: "w", .keyX: "x", .keyY: "y", .keyZ: "z",
        ]
        if let letter = letterCodes[keyCode] { return String(letter) }
        return nil
    }
}
#endif
