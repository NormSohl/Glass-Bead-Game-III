//
//  ContentView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var sequencer: SequencerState

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
        _sequencer = StateObject(wrappedValue: SequencerState(sampleRate: sound.audio.sampleRate, settings: initialSettings))
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
                                  settings: settings
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
                        ZSliderView(scale: scale, settings: settings, graphSquareSize: graphSquareHeight)
                            .frame(width: 70, height: graphSquareHeight > 0 ? graphSquareHeight : nil)
                    }
                }

                // The drone's own on-screen representation - see RootIndicatorView's header
                // comment for why this exists (nothing else on the graph shows drone at all).
                RootIndicatorView(scale: scale, settings: settings, sequencer: sequencer)

                if settings.showSequencer {
                    SequencerView(settings: settings, sound: sound, sequencer: sequencer, scale: scale)
                        .frame(height: 300)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .frame (minWidth: 800, minHeight: 500)
        #if os(macOS)
        // Locks the window to always resize both axes together, at whatever ratio currently has
        // no dead space (see idealWindowSize) - dragging just one edge would otherwise leave
        // black borders, since the Z-slider/RootIndicatorView/sequencer strip are fixed-point-size,
        // not proportional, so only a plain resizable window (no ratio lock) can go out of sync
        // with the square graph's own aspect. Recomputed whenever the sequencer panel or the
        // Z-slider (3rd moving tone) show/hide, since either changes the content's natural ratio.
        .background(WindowAspectLockView(aspectSize: idealWindowSize(sequencerShown: settings.showSequencer, thirdToneShown: settings.showTetrads)))
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
                // Sequencer panel toggle - a panel-slider-style show/hide. Its state gates
                // AppSettings.sequencerDrivenVoices everywhere else: hidden means no sequencer
                // code ever touches the graph.
                Button {
                    withAnimation(.easeInOut) { settings.showSequencer.toggle() }
                } label: {
                    Image(systemName: "pianokeys")
                }
                .help("Sequencer - show or hide the piano-roll editor and transport controls")
            }
            ToolbarItem(placement: .primaryAction) {
                // Portamento toggle - direct toolbar access to the same settings.snap the
                // "Snapping" checkbox in ControlView used to control (removed once this existed;
                // both drove the same property). Norm: important enough to reach without opening
                // the settings popover first. Deliberately no custom active-state color - Norm
                // preferred this match the plain gray-idle/white-on-press look the piano-keys and
                // gear buttons already have, rather than standing out with its own persistent
                // color.
                Button {
                    settings.snap.toggle()
                } label: {
                    Image(systemName: "waveform.path")
                }
                .help("Portamento (G or H) - drag continuously between pitches instead of snapping to scale degrees")
            }
            ToolbarItem(placement: .primaryAction) {
                // Pedal - a live-performance control, per Norm, so worth reaching without
                // opening the settings popover first, same reasoning as Portamento above. Same
                // plain styling (no active-state color) as the other three buttons.
                Button {
                    settings.pedal.toggle()
                } label: {
                    Image(systemName: "shoeprints.fill")
                }
                .help("Pedal (Space, held) - sustain: keep the current notes sounding after you release them")
            }
            ToolbarItem(placement: .primaryAction) {
                // Drone - the last of the settings-popover controls Norm wanted promoted to the
                // toolbar. Norm floated a bee for this one ("drone" is also a male bee) - SF
                // Symbols has no literal bee glyph (confirmed by trying "bee"/"bee.fill" directly,
                // both render as nothing), so this is a honeycomb instead: keeps the bee/hive
                // association without an actual insect.
                Button {
                    settings.playDrone.toggle()
                } label: {
                    Image(systemName: "circle.hexagongrid.fill")
                }
                .help("Drone (D or K) - the sustained reference tone")
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

        init(settings: AppSettings) {
            self.settings = settings
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                switch event.type {
                case .keyDown:
                    // Space (key code 49) - Pedal, momentary: down while held, matching a real
                    // damper pedal's own physical behavior.
                    if event.keyCode == 49 {
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
                    if event.charactersIgnoringModifiers?.lowercased() == "g" && !event.isARepeat {
                        self.settings.snap.toggle()
                        return nil
                    }
                    if event.charactersIgnoringModifiers?.lowercased() == "h" && !event.isARepeat {
                        self.settings.snap.toggle()
                        return nil
                    }
                    // "D"/"K" - Drone, same discrete-toggle treatment and mirroring as
                    // Portamento above (not physically a pedal either).
                    if event.charactersIgnoringModifiers?.lowercased() == "d" && !event.isARepeat {
                        self.settings.playDrone.toggle()
                        return nil
                    }
                    if event.charactersIgnoringModifiers?.lowercased() == "k" && !event.isARepeat {
                        self.settings.playDrone.toggle()
                        return nil
                    }
                case .keyUp:
                    if event.keyCode == 49 {
                        self.settings.pedal = false
                        return nil
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
