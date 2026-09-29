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
    // Wraps the shared, process-wide instances (Glass_Bead_Game_IIIApp.swift) rather than
    // constructing its own - see GraphScaleState.swift's own header comment for why: the
    // external-display audience window needs to reach the exact same settings/scale/
    // tetradLayers ContentView uses, from outside any view's own lifetime.
    @ObservedObject private var settings: AppSettings = appSettings
    @ObservedObject private var graphScale: GraphScaleState = graphScaleState

    // Thin pass-throughs so the rest of this file's existing `scale`/`tetradLayers` references
    // don't all need rewriting to `graphScale.scale`/`graphScale.tetradLayers`.
    private var scale: Scale { graphScale.scale }
    private var tetradLayers: TetradLayers { graphScale.tetradLayers }

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

    // The graph square's own on-screen frame within this view's "contentRoot" coordinate
    // space, captured the same way graphSquareHeight is - needed so the ratio-labels overlay
    // below can be positioned and sized to exactly match the square regardless of which side
    // the Z-slider/ControlColumn currently sit on.
    @State private var graphSquareFrame: CGRect = .zero

    // graphSquareHeight, clamped to always be finite and non-negative before it's ever
    // multiplied into anything - see graphSquare's own offset comment for why this exists (a
    // crash, not just defensive style).
    private var safeGraphSquareHeight: CGFloat {
        graphSquareHeight.isFinite && graphSquareHeight > 0 ? graphSquareHeight : 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(.all)

            VStack(spacing: 0) {
                // Order swaps with settings.zSliderSide rather than just moving the Z-slider
                // alone, so the iPad ControlColumn (leading in the .right/default case here)
                // always ends up on whichever side the Z-slider isn't - one setting moves both,
                // per Norm's ask, instead of two that could drift out of sync.
                // Ratios mode reserves real space here (see ratioLabelGap's own comment) for the
                // ratio-fraction labels' deliberate bleed past the graph square's own edge -
                // painting that bleed on top of the Z-slider/ControlColumn (the first attempt at
                // this fix) put the label text right on top of THEIR own content instead of
                // merely being clipped by it, which is no better - confirmed live 2026-09-07,
                // "the ratios now overlay the z slider." Letters mode has no bleed, so this stays
                // zero there, matching that mode's original tight layout exactly.
                HStack(spacing: ratioLabelGap(settings: settings)) {
                    if settings.zSliderSide == .right {
                        #if os(iOS)
                        ControlColumn(settings: settings)
                        #endif
                        graphSquare
                        zSlider
                    } else {
                        zSlider
                        graphSquare
                        #if os(iOS)
                        ControlColumn(settings: settings)
                        #endif
                    }
                }
            }

            // Ratio-fraction labels for the graph's border, painted here - after (on top of)
            // the whole HStack above - rather than inside GraphSquareView itself. That overlay
            // deliberately bleeds outside the graph square's own bounds so label text isn't
            // squeezed into the border (see RatioLabelsOverlay's own comment), but the
            // Z-slider and (on iPad) ControlColumn sit right beside the square with zero
            // HStack spacing - whichever of those was declared after graphSquare painted over
            // that bleed wherever it reached them, reading as "the outer column of ratios are
            // still clipped" (confirmed live 2026-09-07, right after fixing the earlier true
            // .clipped()-cuts-it-off bug - this is a second, distinct occlusion problem, not
            // the same one recurring). Being the LAST thing drawn in this outermost ZStack
            // guarantees it paints over every sibling regardless of which side the Z-slider is
            // on. GraphSquareView.drawsRatioLabelsInternally is false for this call for exactly
            // this reason - AudienceGraphView has no such siblings and keeps drawing it
            // internally.
            if settings.tickLabelStyle == .ratios, graphSquareFrame != .zero {
                // Same constant as the HStack's own reserved spacing above - the bleed exactly
                // fills that reserved dead space on the left/right (and matches vertically too,
                // where there's no neighboring sibling to protect, just empty window margin).
                let labelBleed = ratioLabelGap(settings: settings)
                let inputs = graphRatioLabelInputs(scale: scale, tetradLayers: tetradLayers, settings: settings)
                RatioLabelsOverlay(scale: scale, elements: inputs.elements, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, tickBorderH: inputs.tickBorderH, tickBorderV: inputs.tickBorderV, labelBleed: labelBleed, trueSize: graphSquareFrame.size, showLabels: true)
                    .frame(width: graphSquareFrame.width + 2 * labelBleed, height: graphSquareFrame.height + 2 * labelBleed)
                    .position(x: graphSquareFrame.midX, y: graphSquareFrame.midY)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "contentRoot")
        .frame (minWidth: 800, minHeight: 500)
        #if os(macOS)
        // Locks the window to always resize both axes together, at whatever ratio has no dead
        // space (see idealWindowSize) - dragging just one edge would otherwise leave black
        // borders, since the Z-slider is fixed-point-size, not proportional, so only a plain
        // resizable window (no ratio lock) can go out of sync with the square graph's own aspect.
        .background(WindowAspectLockView(aspectSize: idealWindowSize()))
        // Keyboard access to Portamento/Pedal, per Norm - "third party pedals can be configured
        // to work with them" (many cheap USB foot pedals emulate a plain keystroke). See
        // KeyCommandMonitor's own header comment for the toggle-vs-momentary distinction.
        .background(KeyCommandMonitor(settings: settings, scale: scale))
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
        // A Bluetooth/USB mouse operated by the free hand around the back of the case -
        // Norm's answer to Pencil-squeeze not firing reliably while the pencil is touching the
        // graph. iOS-only: on macOS the mouse already drives HitTestView's X/Y drag, so giving
        // it a second meaning there would conflict rather than help. See MouseMonitor's own
        // comment for the full reasoning.
        .background(MouseMonitor(settings: settings, scale: scale))
        #endif
        .onChange(of: settings.selectedLimit) {
            graphScale.rebuild(for: settings)
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
                    ControlView(settings: settings)
                        .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 650)
                }
            }
        }
        #endif
    }

    // See GraphSquareView.swift for the actual graph rendering (extracted so the
    // external-display audience view can reuse it) - this wrapper is what's specific to the
    // performer's own window: sizing/measuring the square for the sibling Z-slider.
    @ViewBuilder
    private var graphSquare: some View {
        // safeGraphSquareHeight, not the raw @State, as a defensive guard against a non-finite
        // height reaching GraphSquareView's own offset math - macOS's own
        // .windowResizability(.contentSize) measures this view with an unconstrained/extreme
        // proposed size on at least one pass, and a GeometryReader caught in that pass could in
        // principle report one.
        GraphSquareView(scale: scale, tetradLayers: tetradLayers, settings: settings, squareHeight: safeGraphSquareHeight, drawsRatioLabelsInternally: false)
        .layoutPriority(1)
        .background(
            GeometryReader { proxy in
                // Guarded here at the source, not just where it's consumed (safeGraphSquareHeight)
                // - macOS's .windowResizability(.contentSize) can measure this view with an
                // unconstrained/extreme proposed size on at least one pass, and this
                // GeometryReader caught in that pass can report a non-finite height. zSlider's
                // own .frame(height:) reads graphSquareHeight directly, not through the safe
                // wrapper, so a non-finite value stored here would reach AppKit's layout engine
                // from there too - better to never store one at all.
                Color.clear
                    .onAppear {
                        if proxy.size.height.isFinite { graphSquareHeight = proxy.size.height }
                        graphSquareFrame = proxy.frame(in: .named("contentRoot"))
                    }
                    .onChange(of: proxy.size.height) { if proxy.size.height.isFinite { graphSquareHeight = proxy.size.height } }
                    .onChange(of: proxy.frame(in: .named("contentRoot"))) { _, newFrame in graphSquareFrame = newFrame }
            }
        )
    }

    // Z: its own touch zone, not overlapping the graph - a separate DragGesture here tracks
    // its own touch independently of the graph's, so both can be held at once. Height
    // explicitly matched to the graph square's own rendered height (see graphSquareHeight
    // above) rather than left to fill whatever the row's full height happens to be.
    private var zSlider: some View {
        ZSliderView(scale: scale, settings: settings, graphSquareSize: graphSquareHeight)
            .frame(width: 70, height: graphSquareHeight > 0 ? graphSquareHeight : nil)
    }
}

// Scroll-wheel Z stepping, shared by macOS's KeyCommandMonitor and iOS's MouseMonitor: one call
// moves Z to the next/previous element of the actual scale - the same ScaleElement list
// ZSliderView draws its gridlines/diamonds from - so it always lands precisely on a real scale
// degree. The nearest-degree lookup means it works even when Z isn't currently sitting exactly
// on one (e.g. right after a drag). Deliberately ignores Portamento (Norm, 2026-09-05): scroll
// always hard-jumps to an exact degree.
private func stepZ(by direction: Int, settings: AppSettings, scale: Scale) {
    guard !scale.scale.isEmpty else { return }
    let currentNormalized = log2(settings.zFrequency / settings.rootFrequency)
    // scale.scale is kept sorted ascending by valueNormalized (see Scale.init in GBGCore), so
    // the closest element by absolute distance is genuinely the nearest scale degree.
    var currentIndex = 0
    var closestDistance = Double.greatestFiniteMagnitude
    for (index, element) in scale.scale.enumerated() {
        let distance = abs(element.valueNormalized - currentNormalized)
        if distance < closestDistance {
            closestDistance = distance
            currentIndex = index
        }
    }
    let newIndex = min(max(currentIndex + direction, 0), scale.scale.count - 1)
    let newFrequency = settings.rootFrequency * pow(2, scale.scale[newIndex].valueNormalized)
    guard newFrequency != settings.zFrequency else { return }
    settings.zFrequency = newFrequency
    sound.setZPitch(frequency: newFrequency)
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
//
// Also monitors the right mouse button (Norm's idea, 2026-09-04): HitTestView's graph drag only
// ever tracks the primary button, so the secondary button on a Mac mouse is otherwise unused -
// bound to Portamento (hold) by default via the same "mouseRight" token the iOS-only MouseMonitor
// already defined, routed through the same handlePhysicalInput so KeyMappingView's remap capture
// works on it for free. Deliberately only consumed (event returned nil) when something is
// actually bound to it, or a remap capture is in progress - otherwise left alone so an unbound
// right-click still falls through to its normal system behavior (e.g. a context menu, if one is
// ever added here).
//
// And the scroll wheel (Norm, 2026-09-28): steps Z one scale degree at a time, same as iOS's
// MouseMonitor - see handleScroll below for how a trackpad/Magic Mouse's continuous scrolling is
// kept from racing through the scale.
private struct KeyCommandMonitor: NSViewRepresentable {
    @ObservedObject var settings: AppSettings
    // For scroll-driven Z stepping - re-pushed every update, since GraphScaleState rebuilds it as
    // a new value whenever settings.selectedLimit changes (same reason as MouseMonitor's).
    let scale: Scale

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings, scale: scale)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.settings = settings
        context.coordinator.scale = scale
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

        var scale: Scale
        // The main window's own background view - scroll events are only acted on when they
        // land in its window, so scrolling inside the Settings/Keyboard Mapping popovers (their
        // own separate windows, still seen by this app-wide local monitor) never moves Z.
        weak var hostView: NSView?

        // A mechanical wheel sends one event per notch (hasPreciseScrollingDeltas false) - one
        // step each, like iOS. A trackpad or Magic Mouse sends many small precise deltas per
        // swipe, so those accumulate here and step once per this many points of scrolling;
        // otherwise even a small swipe would race through the whole scale. A starting guess -
        // tune live.
        private let preciseScrollPointsPerStep: CGFloat = 24
        private var preciseScrollAccumulator: CGFloat = 0

        init(settings: AppSettings, scale: Scale) {
            self.settings = settings
            self.scale = scale
            self.dispatcher = KeyActionDispatcher(settings: settings)
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .rightMouseDown, .rightMouseUp, .scrollWheel]) { [weak self] event in
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
                case .rightMouseDown, .rightMouseUp:
                    let pressed = event.type == .rightMouseDown
                    if self.settings.pendingKeyBindingAction != nil || self.settings.keyMapping.action(for: "mouseRight") != nil {
                        self.dispatcher.handlePhysicalInput(token: "mouseRight", pressed: pressed)
                        return nil
                    }
                case .scrollWheel:
                    self.handleScroll(event)
                default:
                    break
                }
                return event
            }
        }

        private func handleScroll(_ event: NSEvent) {
            guard let window = hostView?.window, event.window === window else { return }
            // Inertial coasting after a trackpad flick isn't the performer's hand - ignore it.
            guard event.momentumPhase.isEmpty else { return }
            // Whichever axis actually moved - holding Shift (Portamento hold by default) makes
            // macOS report a vertical wheel as horizontal. Un-inverted when "natural scrolling"
            // is on, so wheel-away / fingers-up always means Z up, whatever that setting is.
            var delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
            if event.isDirectionInvertedFromDevice { delta = -delta }

            guard event.hasPreciseScrollingDeltas else {
                if delta != 0 { stepZ(by: delta > 0 ? 1 : -1, settings: settings, scale: scale) }
                return
            }
            if event.phase == .began { preciseScrollAccumulator = 0 }
            preciseScrollAccumulator += delta
            while abs(preciseScrollAccumulator) >= preciseScrollPointsPerStep {
                let direction = preciseScrollAccumulator > 0 ? 1 : -1
                stepZ(by: direction, settings: settings, scale: scale)
                preciseScrollAccumulator -= CGFloat(direction) * preciseScrollPointsPerStep
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
            // windowWillResize below only reacts to a resize the user (or the system) already
            // initiated - it can keep the window square once it's dragged, but does nothing to
            // an already-wrong CURRENT size, which is exactly what happens whenever aspectSize
            // itself changes out from under an already-open window (Letters <-> Ratios, since
            // the two modes need different border thickness - see tickBorderSizes) or when macOS
            // restores a previous session's frame from before this aspect existed. Force a
            // resize to match right away whenever the target aspect actually changes, rather
            // than only ever preventing it from getting worse.
            let aspectChanged = self.aspectSize != aspectSize
            self.aspectSize = aspectSize
            guard let window else { return }
            if aspectChanged {
                window.setContentSize(aspectSize)
            }
            guard attachedWindow !== window else { return }
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
            iconButton(systemName: "exclamationmark.octagon.fill", tint: .red, label: "Panic") {
                sound.panic()
            }
            iconButton(systemName: "gearshape.fill", tint: nil, label: "Settings") {
                settings.showSettings = true
            }
            .popover(isPresented: $settings.showSettings) {
                ControlView(settings: settings)
                    .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 650)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 60)
    }

    private func button(_ systemName: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        iconButton(systemName: systemName, tint: active ? TetradView.uiAccentColor : nil, label: label, action: action)
    }

    // Renders the same icon a plain SwiftUI Button would, but with its own hit-testing turned
    // off (.allowsHitTesting(false)) and a FingerAndPencilTapCatcher (FingerAndPencilOnly.swift)
    // overlaid instead - finger, Pencil, and mouse clicks all tap it.
    private func iconButton(systemName: String, tint: Color?, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .overlay(FingerAndPencilTapCatcher(onTap: action))
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
                self.dispatcher.handlePhysicalInput(token: token, pressed: pressed)
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

// A Bluetooth/USB mouse on iPad works the same as on the Mac (Norm, 2026-09-28 - the separate
// iPad-only mouse modes were removed): left-drag plays the graph and Z-slider and taps buttons,
// all through the ordinary `.indirectPointer` touch a mouse click already generates (see
// FingerAndPencilOnly.swift), so the left button needs nothing here. What this adds on top is
// the rest of the Mac's mouse: the right/middle buttons feed the identical
// KeyActionDispatcher.handlePhysicalInput path a keyboard key does (right = Portamento hold by
// default, remappable through Keyboard Mapping), and the scroll wheel steps Z one scale degree
// per detent (the shared stepZ, same as macOS's KeyCommandMonitor).
//
// An earlier version also requested pointer lock (prefersPointerLocked) for back-of-case mouse
// control; confirmed live 2026-09-08 that it never took effect from a controller nested inside
// SwiftUI's hosting hierarchy, and a normal visible pointer is exactly what Mac-style use
// wants, so it's gone.
private struct MouseMonitor: UIViewControllerRepresentable {
    @ObservedObject var settings: AppSettings
    // For scroll-driven Z stepping (handleScroll below) - the same Scale instance GraphView/
    // ZSliderView already draw their gridlines from, not a separate copy.
    let scale: Scale

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.install()
        return UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.settings = settings
        // scale is rebuilt (a new value, not mutated in place) whenever settings.selectedLimit
        // changes - GraphScaleState.rebuild(for:) - so this has to be re-pushed here on every
        // update the same way settings is, or a mid-session limit change would leave scroll-
        // stepping working off a stale scale.
        context.coordinator.scale = scale
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings, scale: scale)
    }

    final class Coordinator {
        var settings: AppSettings {
            didSet { dispatcher.settings = settings }
        }
        var scale: Scale
        private let dispatcher: KeyActionDispatcher
        private var connectObserver: Any?

        // Norm's concern (2026-09-04, before any live test): pressing a physical mouse button
        // tends to jostle the mouse itself very slightly - felt only as an ignorable stray
        // pixel or two normally, but here it would land straight in Z and detune a note at the
        // exact instant Pedal/Portamento engages. Rather than ignore movement for the whole
        // time a button is held (which would defeat the actually-wanted case of dragging Z
        // while Pedal holds a note), only movement arriving in the brief instant right at a
        // button transition is discarded - a deliberate drag a moment later still goes through
        // untouched. 60ms is a guess at "longer than a click's mechanical settle, shorter than
        // any real intentional movement."
        private let jostleSuppressionWindow: TimeInterval = 0.06
        private var jostleSuppressedUntil = Date.distantPast

        private func suppressJostle() {
            jostleSuppressedUntil = Date().addingTimeInterval(jostleSuppressionWindow)
        }

        init(settings: AppSettings, scale: Scale) {
            self.settings = settings
            self.scale = scale
            self.dispatcher = KeyActionDispatcher(settings: settings)
        }

        func install() {
            attach(GCMouse.current)
            // Same reasoning as KeyboardMonitor's own connect-notification fallback -
            // GCMouse.current can plausibly read nil even with a mouse already attached, this
            // session, too early in the view's lifecycle.
            connectObserver = NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] notification in
                self?.attach(notification.object as? GCMouse)
            }
        }

        private func attach(_ mouse: GCMouse?) {
            guard let input = mouse?.mouseInput else { return }

            // Left button: nothing to dispatch - its click-and-drag already arrives as an
            // ordinary touch on whatever it's over (graph, Z-slider, buttons). Still marks the
            // jostle window, so the tiny bump of clicking doesn't nudge Z via the wheel.
            input.leftButton.pressedChangedHandler = { [weak self] _, _, _ in
                self?.suppressJostle()
            }
            input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.suppressJostle()
                self?.dispatcher.handlePhysicalInput(token: "mouseRight", pressed: pressed)
            }
            input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.suppressJostle()
                self?.dispatcher.handlePhysicalInput(token: "mouseMiddle", pressed: pressed)
            }
            // Deliberately no mouseMovedHandler at all - mouse-driven X/Y comes entirely from
            // the real `.indirectPointer` touch HitTestView's own FingerAndPencilDragCatcher
            // accepts (see leftButton's own comment above), which carries genuine absolute
            // position for the whole press. A relative-delta approach
            // built on these raw movement deltas was tried and reverted twice, 2026-09-08 - it
            // never actually corresponded to the mouse's own physical movement no matter how it
            // was scaled ("does not snap to mouse position"; later, even after anchoring it to a
            // real starting point, "cursor appears to move more quickly than the mouse pointer"
            // persisted regardless of the scale factor tried) - the touch itself needs no such
            // approximation at all.
            //
            // One detent = one scale step (Norm, 2026-09-05): each scroll event just moves Z to
            // the next/previous element of the actual scale, same ScaleElement list ZSliderView
            // draws its gridlines/diamonds from - musically exact by construction (always lands
            // precisely on a real scale degree) rather than an approximation that happens to be
            // close. Built on the assumption that one scroll callback == one physical notch, true
            // for a mechanical wheel but very likely NOT true for a non-detented continuous
            // surface (Magic Mouse ball, trackpad two-finger scroll), which fires many small
            // callbacks per finger-length of motion - expect that combination to zip through many
            // scale steps almost instantly, and to need an accumulate-then-step threshold added
            // here if that's how it actually feels.
            input.scroll.valueChangedHandler = { [weak self] _, deltaX, deltaY in
                self?.handleScroll(deltaX: deltaX, deltaY: deltaY)
            }
        }

        // Reacts to whichever of the two scroll axes actually moved - some third-party mice/
        // trackpads report a vertical wheel through the X axis instead of Y. Confirmed live
        // 2026-09-08 to work correctly as written.
        private func handleScroll(deltaX: Float, deltaY: Float) {
            guard Date() >= jostleSuppressedUntil else { return }
            let delta = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
            if delta > 0 {
                stepZ(by: 1, settings: settings, scale: scale)
            } else if delta < 0 {
                stepZ(by: -1, settings: settings, scale: scale)
            }
        }

        deinit {
            if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        }
    }
}
#endif
