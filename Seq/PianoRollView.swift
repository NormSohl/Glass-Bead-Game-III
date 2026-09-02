//
//  PianoRollView.swift
//  Seq
//
//  The piano-roll Canvas + gesture surface: per-scale-degree gridlines, one colored "partline"
//  per voice, draggable start/end handles on every note, and the playhead. Ported from Graph's
//  in-app sequencer and adapted: no AppSettings (uses SeqSettings instead), and a tap on empty
//  canvas either moves the playhead (default) or places a new note (while "Add Note" is armed -
//  see SequencerState.isPlacingNote) - Graph's original just moved the playhead, since Graph had
//  a separate live-graph-touch-capture button for adding notes that has no equivalent here.
//

import SwiftUI
import GBGCore
import AppKit

// A plain NSView placed via .background() sits behind the Canvas's own AppKit backing view in
// z-order - AppKit's hitTest for a scrollWheel event finds whichever view is frontmost at that
// point first, so a background view's own scrollWheel(with:) override never actually fires; the
// Canvas's backing view silently absorbs the event above it. A local NSEvent monitor sidesteps
// view-hierarchy hit-testing entirely - it sees matching events at the app level regardless of
// which view AppKit would otherwise have routed them to - so that's what this uses instead, with
// its own explicit bounds check (the monitor fires for scroll anywhere in the window, not just
// this view) so it only reacts while the cursor is actually over the piano roll.
private struct ScrollWheelZoomCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(view: view, onScroll: onScroll)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onScroll: ((CGFloat) -> Void)?
        private weak var view: NSView?
        private var monitor: Any?

        func start(view: NSView, onScroll: @escaping (CGFloat) -> Void) {
            self.view = view
            self.onScroll = onScroll
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.view else { return event }
                let locationInView = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(locationInView) {
                    self.onScroll?(event.scrollingDeltaY)
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// Same reasoning as Graph's own PianoRollView: mutating this from inside the Canvas closure as
// @State caused inconsistent behavior in other views in this codebase, so this follows the same
// module-scope workaround.
var pianoRollCanvasSize: CGSize = .zero

private let handleHitRadius: Double = 20
// Partline curve-sampling density: points per screen pixel of a note's own width, not a flat
// per-note count - a fixed count (24, this used to be) gives wildly different effective time
// resolution depending on note duration: fine for a short segmented piece, but on a long
// as-is recorded note (many seconds), 24 points smooths real recorded-contour detail (visible
// vibrato/slides in the underlying data) into invisibility, while a short note right next to
// it renders that same density of detail proportionally much more finely - so the two could
// look like different "smoothness" even when sampled from equally detailed source data. One
// point every ~3px reads as a continuous curve on screen and scales with both duration and zoom.
private let curveSamplesPerPixel: Double = 1.0 / 3.0
private let minCurveSamplePoints = 8
private let maxCurveSamplePoints = 2000
// Radius for the transition-picker indicator at each note's midpoint - same treatment as the
// start/end handles above, just its own constant since the two are visually distinct markers.
private let transitionIndicatorHitRadius: Double = 12
// Step 4 (live-record plan): a handle drag snaps to the nearest beat-grid line when within this
// many screen pixels of it - a fixed pixel count, not a fraction of the beat period, so the feel
// stays consistent across zoom levels/tempi instead of a period-relative window spanning almost
// a whole beat at an extreme fast-tempo/zoomed-out combination.
private let snapTimeThresholdPixels: Double = 10

let voiceColors: [PartVoice: Color] = [
    .drone: .gray,
    .x: .cyan,
    .y: .orange,
    .z: .pink
]

// Identifies which note's transition-picker menu is currently open - a voice/note pair, same
// identity-comparison shape as DraggingHandle above (Note is a class, compared by reference).
private struct TransitionMenuTarget: Equatable {
    let voice: PartVoice
    let note: Note

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.voice == rhs.voice && lhs.note === rhs.note
    }
}

struct PianoRollView: View {
    let scale: Scale
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState

    // Gesture-local state - only ever touched from .gesture closures, never the Canvas draw
    // closure, so plain @State is fine here.
    @State private var dragStartLocation: CGPoint?
    @State private var panStartOffsetSamples: Int?

    // Per-note transition picker (Step 4) - which note's menu, if any, is currently open. A
    // popover anchored to a zero-size view positioned at that note's own midpoint, rather than
    // anything drawn inside the Canvas itself - Canvas content can't host real SwiftUI controls.
    @State private var transitionMenuTarget: TransitionMenuTarget?

    private var transitionMenuIsPresented: Binding<Bool> {
        Binding(
            get: { transitionMenuTarget != nil },
            set: { if !$0 { transitionMenuTarget = nil } }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                pianoRollCanvasSize = size
                drawGridlines(context: context, size: size)
                drawBeatGrid(context: context, size: size)
                drawPartlines(context: context, size: size)
                drawPlayhead(context: context, size: size)
            }
            .background(Color.black)
            .background(ScrollWheelZoomCatcher(onScroll: handleScrollZoom))
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)

            if let target = transitionMenuTarget {
                let location = midpointLocation(voice: target.voice, note: target.note, canvasSize: pianoRollCanvasSize)
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(location)
                    .popover(isPresented: transitionMenuIsPresented, arrowEdge: .top) {
                        transitionMenu(for: target)
                    }
            }
        }
    }

    // MARK: - Drawing

    private func drawGridlines(context: GraphicsContext, size: CGSize) {
        var path = Path()
        for element in scale.scale {
            let y = pianoRollFrequencyToScreenY(
                frequency: settings.rootFrequency * element.value,
                rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: size.height, verticalZoomFactor: sequencer.verticalZoomFactor)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.gray.opacity(0.3)))

        let step = pianoRollNiceTimeStepSeconds(pixelsPerSecond: sequencer.pixelsPerSecond)
        let stepSamples = Int(step * sequencer.sampleRate)
        guard stepSamples > 0 else { return }
        let firstLineSample = (sequencer.offsetSamples / stepSamples) * stepSamples
        var timePath = Path()
        var sample = firstLineSample
        while pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate) < size.width {
            let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
            if x >= 0 {
                timePath.move(to: CGPoint(x: x, y: 0))
                timePath.addLine(to: CGPoint(x: x, y: size.height))
            }
            sample += stepSamples
        }
        context.stroke(timePath, with: .color(.gray.opacity(0.15)))
    }

    // Step 4 (live-record plan): an optional beat grid, drawn only when the currently loaded
    // document carries a confident detected tempo (sequencer.tempoInfo). Visually distinct from
    // the plain time gridlines above (a warm amber tint, heavier weight) so it reads as "the
    // beat," not just another ruler line - no tempoInfo, no lines, today's appearance unchanged.
    private func drawBeatGrid(context: GraphicsContext, size: CGSize) {
        guard let tempo = sequencer.tempoInfo else { return }
        let periodSamples = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sequencer.sampleRate)
        guard periodSamples > 0 else { return }

        let firstVisibleSample = sequencer.offsetSamples
        let lastVisibleSample = sequencer.offsetSamples + Int(Double(size.width) / sequencer.pixelsPerSecond * sequencer.sampleRate)
        let firstBeatIndex = Int((Double(firstVisibleSample - tempo.downbeatOffset) / periodSamples).rounded(.down)) - 1
        let lastBeatIndex = Int((Double(lastVisibleSample - tempo.downbeatOffset) / periodSamples).rounded(.up)) + 1
        guard firstBeatIndex <= lastBeatIndex else { return }

        var path = Path()
        for n in firstBeatIndex...lastBeatIndex {
            let sample = tempo.downbeatOffset + Int((Double(n) * periodSamples).rounded())
            let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
            guard x >= 0, x <= size.width else { continue }
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(path, with: .color(.yellow.opacity(0.35)), lineWidth: 1.5)
    }

    private func drawPartlines(context: GraphicsContext, size: CGSize) {
        for voice in PartVoice.allCases {
            let part = sequencer.part(for: voice)
            let color = voiceColors[voice] ?? .white

            for note in part.notes where note.amplitude > 0 {
                let noteDurationSeconds = Double(note.endTime - note.startTime) / sequencer.sampleRate
                let notePixelWidth = noteDurationSeconds * sequencer.pixelsPerSecond
                let sampledCurvePoints = min(maxCurveSamplePoints, max(minCurveSamplePoints, Int(notePixelWidth * curveSamplesPerPixel)))

                var path = Path()
                for step in 0...sampledCurvePoints {
                    let percent = Double(step) / Double(sampledCurvePoints)
                    let sample = note.startTime + Int(Double(note.endTime - note.startTime) * percent)
                    let frequency = note.getCurrentFrequency(percentComplete: percent)
                    let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
                    let y = pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: size.height, verticalZoomFactor: sequencer.verticalZoomFactor)
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), lineWidth: 3)

                for edge in [NoteEdge.start, .end] {
                    let handle = handleLocation(voice: voice, note: note, edge: edge, canvasSize: size)
                    let isActive = sequencer.draggingHandle == DraggingHandle(voice: voice, note: note, edge: edge)
                    context.fill(
                        Path(ellipseIn: CGRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)),
                        with: .color(isActive ? .white : color)
                    )
                }

                // Transition-picker indicator (Step 4) - a small white square at the note's own
                // screen-space midpoint, deliberately square rather than round so it reads as a
                // distinct control from the circular start/end handles above.
                let mid = midpointLocation(voice: voice, note: note, canvasSize: size)
                let isMenuOpen = transitionMenuTarget == TransitionMenuTarget(voice: voice, note: note)
                let markerRect = CGRect(x: mid.x - 6, y: mid.y - 6, width: 12, height: 12)
                context.fill(Path(markerRect), with: .color(isMenuOpen ? .white : .white.opacity(0.85)))
                context.stroke(Path(markerRect), with: .color(color), lineWidth: 1.5)
            }
        }
    }

    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        let x = pianoRollSampleToScreenX(sample: sequencer.playheadSample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
        guard x >= 0, x <= size.width else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.white), lineWidth: 2)
    }

    private func handleLocation(voice: PartVoice, note: Note, edge: NoteEdge, canvasSize: CGSize) -> CGPoint {
        let sample = edge == .start ? note.startTime : note.endTime
        let frequency = edge == .start ? note.startFrequency : note.endFrequency
        let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
        let y = pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: canvasSize.height, verticalZoomFactor: sequencer.verticalZoomFactor)
        return CGPoint(x: x, y: y)
    }

    // Screen-space midpoint of a note's own span - time: midpoint of start/endTime, frequency:
    // midpoint of start/endFrequency. An approximate resting spot for the transition-picker
    // indicator, not meant to track the note's actual curve at that instant.
    private func midpointLocation(voice: PartVoice, note: Note, canvasSize: CGSize) -> CGPoint {
        let sample = (note.startTime + note.endTime) / 2
        let frequency = (note.startFrequency + note.endFrequency) / 2
        let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
        let y = pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: canvasSize.height, verticalZoomFactor: sequencer.verticalZoomFactor)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Hit testing

    private func hitTestHandle(at location: CGPoint) -> DraggingHandle? {
        var best: (handle: DraggingHandle, distance: Double)?
        for voice in PartVoice.allCases {
            let part = sequencer.part(for: voice)
            for note in part.notes where note.amplitude > 0 {
                for edge in [NoteEdge.start, .end] {
                    let point = handleLocation(voice: voice, note: note, edge: edge, canvasSize: pianoRollCanvasSize)
                    let distance = Double(hypot(point.x - location.x, point.y - location.y))
                    guard distance <= handleHitRadius else { continue }
                    if best == nil || distance < best!.distance {
                        best = (DraggingHandle(voice: voice, note: note, edge: edge), distance)
                    }
                }
            }
        }
        return best?.handle
    }

    private func hitTestTransitionIndicator(at location: CGPoint) -> TransitionMenuTarget? {
        var best: (target: TransitionMenuTarget, distance: Double)?
        for voice in PartVoice.allCases {
            let part = sequencer.part(for: voice)
            for note in part.notes where note.amplitude > 0 {
                let point = midpointLocation(voice: voice, note: note, canvasSize: pianoRollCanvasSize)
                let distance = Double(hypot(point.x - location.x, point.y - location.y))
                guard distance <= transitionIndicatorHitRadius else { continue }
                if best == nil || distance < best!.distance {
                    best = (TransitionMenuTarget(voice: voice, note: note), distance)
                }
            }
        }
        return best?.target
    }

    // MARK: - Gestures

    // Gesture locations are plain SwiftUI top-down screen coordinates throughout - matching
    // PianoRollCoordinates' own convention (its frequency<->screen-Y functions flip internally,
    // so callers never need to).
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let location = value.location

                if let dragging = sequencer.draggingHandle {
                    applyHandleDrag(dragging, to: location)
                    return
                }
                if dragStartLocation == nil {
                    dragStartLocation = location
                    if let hit = hitTestHandle(at: location) {
                        sequencer.beginDraggingHandle(hit)
                        applyHandleDrag(hit, to: location)
                        return
                    }
                    panStartOffsetSamples = sequencer.offsetSamples
                }
                guard let start = dragStartLocation, let panStart = panStartOffsetSamples else { return }
                let deltaSamples = -Int((location.x - start.x) / sequencer.pixelsPerSecond * sequencer.sampleRate)
                sequencer.offsetSamples = max(0, panStart + deltaSamples)
            }
            .onEnded { value in
                defer {
                    sequencer.endDraggingHandle()
                    dragStartLocation = nil
                    panStartOffsetSamples = nil
                }
                guard sequencer.draggingHandle == nil else { return } // handle drag already fully applied live
                guard abs(value.translation.width) < 4 && abs(value.translation.height) < 4 else { return }

                if sequencer.isPlacingNote {
                    let sample = pianoRollScreenXToSample(x: value.location.x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
                    let frequency = pianoRollScreenYToFrequency(y: value.location.y, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: pianoRollCanvasSize.height, verticalZoomFactor: sequencer.verticalZoomFactor)
                    sequencer.placeNote(atTime: max(0, sample), frequency: frequency)
                } else if let target = hitTestTransitionIndicator(at: value.location) {
                    // Step 4: a tap on a note's own transition-picker indicator opens its menu
                    // instead of moving the playhead - checked after the placement-mode branch
                    // above (placing a note always wins a tap, even one that happens to land near
                    // an existing indicator) but before the plain playhead-move fallback below.
                    transitionMenuTarget = target
                } else {
                    let sample = pianoRollScreenXToSample(x: value.location.x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
                    sequencer.setPlayhead(to: sample)
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                sequencer.pixelsPerSecond = min(max(sequencer.pixelsPerSecond * value, 20), 800)
                sequencer.verticalZoomFactor = min(max(sequencer.verticalZoomFactor * value, 0.3), 10)
            }
    }

    // Scroll-wheel zoom (Step: mouse-only Mac support) - MagnificationGesture only fires from a
    // trackpad's pinch gesture, nothing for a plain mouse, which is what this app is actually
    // being tested with on this Mac. Same pixelsPerSecond clamp as the pinch path above, just a
    // different input source driving it. SwiftUI has no cross-platform scroll-wheel gesture, so
    // this drops to a small NSViewRepresentable to catch NSEvent.scrollWheel directly.
    private func handleScrollZoom(deltaY: CGFloat) {
        let factor = 1 + (deltaY * 0.01)
        sequencer.pixelsPerSecond = min(max(sequencer.pixelsPerSecond * factor, 20), 800)
        sequencer.verticalZoomFactor = min(max(sequencer.verticalZoomFactor * factor, 0.3), 10)
    }

    private func applyHandleDrag(_ handle: DraggingHandle, to location: CGPoint) {
        let part = sequencer.part(for: handle.voice)
        var newTime = pianoRollScreenXToSample(x: location.x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
        let newFrequency = pianoRollScreenYToFrequency(y: location.y, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: pianoRollCanvasSize.height, verticalZoomFactor: sequencer.verticalZoomFactor)

        // Step 4: snap to the nearest beat-grid line when a confident tempo grid exists and the
        // drag landed within snapTimeThresholdPixels of it - mirrors PitchHitTest.swift's own
        // windowed-snap idiom (lowerBounds/upperBounds gating a snap), applied to time instead of
        // pitch. No tempoInfo -> this whole block is skipped, so today's unconditional drag
        // behavior is unchanged when there's no grid to snap to.
        if let tempo = sequencer.tempoInfo {
            let snapped = pianoRollNearestBeatSample(to: newTime, tempo: tempo, sampleRate: sequencer.sampleRate)
            let snapWindowSamples = Int(snapTimeThresholdPixels / sequencer.pixelsPerSecond * sequencer.sampleRate)
            if abs(snapped - newTime) <= snapWindowSamples {
                newTime = snapped
            }
        }

        switch handle.edge {
        case .start:
            part.moveNoteBoundary(of: handle.note, edge: .start, to: newTime, minimumNoteLength: sequencer.minimumNoteLengthSamples)
            handle.note.startFrequency = newFrequency
        case .end:
            part.moveNoteBoundary(of: handle.note, edge: .end, to: newTime, minimumNoteLength: sequencer.minimumNoteLengthSamples)
            handle.note.endFrequency = newFrequency
        }

        switch handle.voice {
        case .x: settings.xFrequency = newFrequency
        case .y: settings.yFrequency = newFrequency
        case .z: settings.zFrequency = newFrequency
        case .drone: sequencer.updateDrivenDroneDisplay(frequency: newFrequency, amplitude: handle.note.amplitude)
        }

        sequencer.scoreRevision += 1
    }

    // MARK: - Transition picker (Step 4)
    //
    // General editing feature, not exclusive to recorded/segmented notes - every note in the
    // piano roll gets this menu via its own indicator (drawPartlines above). `Recorded` and the
    // purge action only appear when the note actually has a buffer to offer.

    private static let basicTransitionKinds: [TransitionKind] = [.flat, .linear, .easeIn, .easeOut, .easeInEaseOut]

    private func label(for kind: TransitionKind) -> String {
        switch kind {
        case .flat: return "Flat"
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInEaseOut: return "Ease In/Out"
        case .recordedContour: return "Recorded"
        }
    }

    @ViewBuilder
    private func transitionMenu(for target: TransitionMenuTarget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Transition").font(.caption).foregroundStyle(.secondary)
            ForEach(Self.basicTransitionKinds, id: \.rawValue) { kind in
                Button(label(for: kind)) {
                    target.note.selectTransition(kind)
                    sequencer.scoreRevision += 1
                    transitionMenuTarget = nil
                }
            }

            if target.note.recordedPitchBend != nil {
                Divider()
                Button(label(for: .recordedContour)) {
                    target.note.selectTransition(.recordedContour)
                    sequencer.scoreRevision += 1
                    transitionMenuTarget = nil
                }
                Button("Purge Recorded Data", role: .destructive) {
                    // If the recorded contour is what's currently sounding, fall back to Flat
                    // before discarding the buffer it depends on - never leave the active
                    // transition referencing data that no longer exists.
                    if target.note.transitionKind == .recordedContour {
                        target.note.selectTransition(.flat)
                    }
                    target.note.recordedPitchBend = nil
                    sequencer.scoreRevision += 1
                    transitionMenuTarget = nil
                }
            }
        }
        .padding(10)
        .frame(minWidth: 160)
    }
}
