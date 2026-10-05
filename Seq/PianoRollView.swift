//
//  PianoRollView.swift
//  Seq
//
//  The note editor: per-scale-degree gridlines, an optional bar/beat grid, one colored line
//  per note (each note is a pitch bend from its start pitch to its end pitch, shaped by its
//  profile - a held note is just start == end), draggable start/end handles, and the playhead,
//  which doubles as the step cursor. What a tap does depends on SequencerState.editTool; drags
//  edit notes in every tool. Pitches snap to the scale and times to the grid unless Option is
//  held.
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

private let handleHitRadius: Double = 10
// How close (screen px) a click must be to a note's line to grab/select the note itself.
private let bodyHitDistance: Double = 6
// Movement (screen px) before a press becomes a drag; anything less is a tap. Lets a tap in the
// Place/Step tools land right next to an existing handle without grabbing it.
private let dragThreshold: Double = 3
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

let voiceColors: [PartVoice: Color] = [
    .drone: .gray,
    .x: .cyan,
    .y: .orange,
    .z: .pink
]

let voiceNames: [PartVoice: String] = [.drone: "Drone", .x: "X", .y: "Y", .z: "Z"]

/// Option held = free placement: no pitch snap to the scale, no time snap to the grid.
private var isFreeModifierHeld: Bool { NSEvent.modifierFlags.contains(.option) }

struct PianoRollView: View {
    let scale: Scale
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState

    // Gesture-local state - only ever touched from .gesture closures, never mutated from the
    // Canvas draw closure, so plain @State is fine here.
    @State private var dragStartLocation: CGPoint?
    @State private var dragDecided = false
    @State private var pendingHit: DraggingHandle?
    @State private var panStartOffsetSamples: Int?
    // A body drag's starting point, so the move is applied relative to it (not accumulated).
    @State private var bodyOrigin: (startTime: Int, startFrequency: Double, endFrequency: Double)?
    // Pitch/time readout drawn next to the cursor while dragging.
    @State private var readout: (location: CGPoint, text: String)?
    @FocusState private var isFocused: Bool

    var body: some View {
        Canvas { context, size in
            pianoRollCanvasSize = size
            drawGridlines(context: context, size: size)
            drawBeatGrid(context: context, size: size)
            drawPartlines(context: context, size: size)
            drawPlayhead(context: context, size: size)
            drawReadout(context: context, size: size)
        }
        .background(Color.black)
        .background(ScrollWheelZoomCatcher(onScroll: handleScrollZoom))
        .gesture(dragGesture)
        .simultaneousGesture(magnificationGesture)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            sequencer.deleteSelectedNote()
            return .handled
        }
        .onKeyPress(.escape) {
            sequencer.select(nil)
            return .handled
        }
        .onKeyPress(.space) {
            if sequencer.isPlaying { sequencer.stop() } else { sequencer.play() }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard sequencer.editTool == .step else { return .ignored }
            sequencer.advanceStep()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard sequencer.editTool == .step else { return .ignored }
            sequencer.stepBack()
            return .handled
        }
    }

    // MARK: - Coordinates

    private func screenX(_ sample: Int) -> Double {
        pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
    }

    private func sample(atX x: Double) -> Int {
        pianoRollScreenXToSample(x: x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
    }

    private func screenY(_ frequency: Double, height: Double = pianoRollCanvasSize.height) -> Double {
        pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: height, verticalZoomFactor: sequencer.verticalZoomFactor)
    }

    private func frequency(atY y: Double) -> Double {
        pianoRollScreenYToFrequency(y: y, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: pianoRollCanvasSize.height, verticalZoomFactor: sequencer.verticalZoomFactor)
    }

    private func snapPitch(_ frequency: Double) -> Double {
        isFreeModifierHeld ? frequency : scale.snappedFrequency(frequency, rootFrequency: settings.rootFrequency)
    }

    private func snapTime(_ sample: Int) -> Int {
        isFreeModifierHeld ? max(0, sample) : sequencer.snapTime(max(0, sample))
    }

    // MARK: - Drawing

    private func drawGridlines(context: GraphicsContext, size: CGSize) {
        var path = Path()
        for element in scale.scale {
            let y = screenY(settings.rootFrequency * element.value, height: size.height)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.gray.opacity(0.3)))

        // Plain seconds lines only when there's no beat grid - otherwise the bar/beat lines
        // below are the time reference and the two would just clutter each other.
        guard sequencer.activeTempo == nil else { return }
        let step = pianoRollNiceTimeStepSeconds(pixelsPerSecond: sequencer.pixelsPerSecond)
        let stepSamples = Int(step * sequencer.sampleRate)
        guard stepSamples > 0 else { return }
        var timePath = Path()
        var sample = (sequencer.offsetSamples / stepSamples) * stepSamples
        while screenX(sample) < size.width {
            let x = screenX(sample)
            if x >= 0 {
                timePath.move(to: CGPoint(x: x, y: 0))
                timePath.addLine(to: CGPoint(x: x, y: size.height))
            }
            sample += stepSamples
        }
        context.stroke(timePath, with: .color(.gray.opacity(0.15)))
    }

    // The optional BPM grid: bar lines strongest, beats lighter, snap subdivisions faintest
    // (and only once they're far enough apart on screen to read as lines, not a wash).
    private func drawBeatGrid(context: GraphicsContext, size: CGSize) {
        guard let tempo = sequencer.activeTempo else { return }
        let subdivision = max(1, sequencer.gridSubdivision)
        let stepSamples = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sequencer.sampleRate) / Double(subdivision)
        guard stepSamples > 0 else { return }
        let stepPixels = stepSamples / sequencer.sampleRate * sequencer.pixelsPerSecond
        let beatsPerBar = max(1, sequencer.beatsPerBar)

        let first = Int((Double(sequencer.offsetSamples - tempo.downbeatOffset) / stepSamples).rounded(.down)) - 1
        let last = Int((Double(sample(atX: size.width) - tempo.downbeatOffset) / stepSamples).rounded(.up)) + 1
        guard first <= last else { return }

        var barPath = Path(), beatPath = Path(), subPath = Path()
        for n in first...last {
            let x = screenX(tempo.downbeatOffset + Int((Double(n) * stepSamples).rounded()))
            guard x >= 0, x <= size.width else { continue }
            let isBeat = n % subdivision == 0
            let isBar = isBeat && (n / subdivision) % beatsPerBar == 0
            if isBar {
                barPath.move(to: CGPoint(x: x, y: 0)); barPath.addLine(to: CGPoint(x: x, y: size.height))
            } else if isBeat {
                beatPath.move(to: CGPoint(x: x, y: 0)); beatPath.addLine(to: CGPoint(x: x, y: size.height))
            } else if stepPixels >= 8 {
                subPath.move(to: CGPoint(x: x, y: 0)); subPath.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        context.stroke(subPath, with: .color(.yellow.opacity(0.08)))
        context.stroke(beatPath, with: .color(.yellow.opacity(0.2)))
        context.stroke(barPath, with: .color(.yellow.opacity(0.45)), lineWidth: 1.5)
    }

    private func drawPartlines(context: GraphicsContext, size: CGSize) {
        for voice in PartVoice.allCases {
            let color = voiceColors[voice] ?? .white
            for note in sequencer.part(for: voice).soundingNotes {
                let isSelected = sequencer.selection == NoteSelection(voice: voice, note: note)
                let path = curvePath(note: note, height: size.height)
                if isSelected {
                    context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 7)
                }
                context.stroke(path, with: .color(color), lineWidth: 3)

                for edge in [NoteEdge.start, .end] {
                    let handle = handleLocation(note: note, edge: edge, height: size.height)
                    let isActive = sequencer.draggingHandle == DraggingHandle(voice: voice, note: note, grip: .edge(edge))
                    let rect = CGRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: rect), with: .color(isActive ? .white : color))
                    if isSelected {
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.white), lineWidth: 1.5)
                    }
                }
            }
        }
    }

    private func curvePoints(note: Note, height: Double) -> [CGPoint] {
        let notePixelWidth = Double(note.endTime - note.startTime) / sequencer.sampleRate * sequencer.pixelsPerSecond
        let count = min(maxCurveSamplePoints, max(minCurveSamplePoints, Int(notePixelWidth * curveSamplesPerPixel)))
        return (0...count).map { step in
            let percent = Double(step) / Double(count)
            let sample = note.startTime + Int(Double(note.endTime - note.startTime) * percent)
            return CGPoint(x: screenX(sample), y: screenY(note.getCurrentFrequency(percentComplete: percent), height: height))
        }
    }

    private func curvePath(note: Note, height: Double) -> Path {
        var path = Path()
        path.addLines(curvePoints(note: note, height: height))
        return path
    }

    // The playhead doubles as the step cursor: green in the Step tool, labeled with the voice
    // the next tap will place.
    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        let x = screenX(sequencer.playheadSample)
        guard x >= 0, x <= size.width else { return }
        let isStep = sequencer.editTool == .step
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(isStep ? .green : .white), lineWidth: 2)

        if isStep, let voice = sequencer.nextStepVoice {
            let label = Text("next: \(voiceNames[voice] ?? "")").font(.caption.bold()).foregroundColor(voiceColors[voice] ?? .white)
            context.draw(label, at: CGPoint(x: x + 6, y: 8), anchor: .topLeading)
        }
    }

    private func drawReadout(context: GraphicsContext, size: CGSize) {
        guard let readout else { return }
        let text = Text(readout.text).font(.caption.monospacedDigit()).foregroundColor(.white)
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: size)
        // Up and to the right of the cursor, flipped inward near the canvas edges.
        var origin = CGPoint(x: readout.location.x + 12, y: readout.location.y - textSize.height - 12)
        if origin.x + textSize.width + 8 > size.width { origin.x = readout.location.x - textSize.width - 20 }
        if origin.y < 0 { origin.y = readout.location.y + 12 }
        let box = CGRect(x: origin.x - 4, y: origin.y - 2, width: textSize.width + 8, height: textSize.height + 4)
        context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        context.draw(resolved, at: origin, anchor: .topLeading)
    }

    private func handleLocation(note: Note, edge: NoteEdge, height: Double = pianoRollCanvasSize.height) -> CGPoint {
        let sample = edge == .start ? note.startTime : note.endTime
        let frequency = edge == .start ? note.startFrequency : note.endFrequency
        return CGPoint(x: screenX(sample), y: screenY(frequency, height: height))
    }

    // MARK: - Hit testing

    private func hitTestHandle(at location: CGPoint) -> DraggingHandle? {
        var best: (handle: DraggingHandle, distance: Double)?
        for voice in PartVoice.allCases {
            for note in sequencer.part(for: voice).soundingNotes {
                for edge in [NoteEdge.start, .end] {
                    let point = handleLocation(note: note, edge: edge)
                    let distance = Double(hypot(point.x - location.x, point.y - location.y))
                    guard distance <= handleHitRadius else { continue }
                    if best == nil || distance < best!.distance {
                        best = (DraggingHandle(voice: voice, note: note, grip: .edge(edge)), distance)
                    }
                }
            }
        }
        return best?.handle
    }

    private func hitTestBody(at location: CGPoint) -> DraggingHandle? {
        var best: (handle: DraggingHandle, distance: Double)?
        for voice in PartVoice.allCases {
            for note in sequencer.part(for: voice).soundingNotes {
                guard location.x >= screenX(note.startTime) - bodyHitDistance,
                      location.x <= screenX(note.endTime) + bodyHitDistance else { continue }
                let points = curvePoints(note: note, height: pianoRollCanvasSize.height)
                for (a, b) in zip(points, points.dropFirst()) {
                    let distance = distanceFrom(location, toSegment: a, b)
                    guard distance <= bodyHitDistance else { continue }
                    if best == nil || distance < best!.distance {
                        best = (DraggingHandle(voice: voice, note: note, grip: .body), distance)
                    }
                }
            }
        }
        return best?.handle
    }

    private func distanceFrom(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return Double(hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
    }

    // MARK: - Gestures

    // Gesture locations are plain SwiftUI top-down screen coordinates throughout - matching
    // PianoRollCoordinates' own convention (its frequency<->screen-Y functions flip internally,
    // so callers never need to).
    //
    // A press is a tap until it moves dragThreshold px. A drag that started on a handle edits
    // that end (time + pitch); one that started on a note's line moves the whole note; anything
    // else pans. A tap selects (Select tool), places a note where it lands (Place tool), or
    // enters the next step voice at that pitch (Step tool).
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let location = value.location
                if dragStartLocation == nil {
                    isFocused = true
                    dragStartLocation = location
                    pendingHit = hitTestHandle(at: location) ?? hitTestBody(at: location)
                    return
                }
                if !dragDecided {
                    guard hypot(value.translation.width, value.translation.height) >= dragThreshold else { return }
                    dragDecided = true
                    if let hit = pendingHit, !sequencer.isEditingLocked {
                        sequencer.beginDraggingHandle(hit)
                        bodyOrigin = (hit.note.startTime, hit.note.startFrequency, hit.note.endFrequency)
                    } else {
                        panStartOffsetSamples = sequencer.offsetSamples
                    }
                }
                if let dragging = sequencer.draggingHandle {
                    applyDrag(dragging, to: location)
                } else if let start = dragStartLocation, let panStart = panStartOffsetSamples {
                    let deltaSamples = -Int((location.x - start.x) / sequencer.pixelsPerSecond * sequencer.sampleRate)
                    sequencer.offsetSamples = max(0, panStart + deltaSamples)
                }
            }
            .onEnded { value in
                defer {
                    sequencer.endDraggingHandle()
                    dragStartLocation = nil
                    dragDecided = false
                    pendingHit = nil
                    panStartOffsetSamples = nil
                    bodyOrigin = nil
                    readout = nil
                }
                guard !dragDecided else { return } // a drag, already fully applied live
                handleTap(at: value.location)
            }
    }

    private func handleTap(at location: CGPoint) {
        switch sequencer.editTool {
        case .select:
            if let hit = pendingHit {
                sequencer.select(NoteSelection(voice: hit.voice, note: hit.note))
            } else {
                sequencer.select(nil)
                sequencer.setPlayhead(to: snapTime(sample(atX: location.x)))
            }
        case .place:
            sequencer.placeNote(atTime: snapTime(sample(atX: location.x)), frequency: snapPitch(frequency(atY: location.y)))
        case .step:
            sequencer.enterStep(frequency: snapPitch(frequency(atY: location.y)))
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

    private func applyDrag(_ dragging: DraggingHandle, to location: CGPoint) {
        let selection = NoteSelection(voice: dragging.voice, note: dragging.note)
        switch dragging.grip {
        case .edge(let edge):
            let time = snapTime(sample(atX: location.x))
            let pitch = snapPitch(frequency(atY: location.y))
            sequencer.setEdge(edge, of: selection, time: time, frequency: pitch)
            let applied = edge == .start ? dragging.note.startTime : dragging.note.endTime
            readout = (location, "\(PitchText.format(pitch, rootFrequency: settings.rootFrequency, scale: scale))  ·  \(timeLabel(applied))")

        case .body:
            guard let origin = bodyOrigin, let start = dragStartLocation else { return }
            let deltaSamples = sample(atX: location.x) - sample(atX: start.x)
            let newStart = snapTime(origin.startTime + deltaSamples)
            // Pitch moves as a ratio, so a bend keeps its interval; the start pitch is what snaps.
            let ratio = frequency(atY: location.y) / frequency(atY: start.y)
            let newStartFrequency = snapPitch(origin.startFrequency * ratio)
            let newEndFrequency = origin.endFrequency * (newStartFrequency / origin.startFrequency)
            sequencer.moveNote(selection, startTime: newStart, startFrequency: newStartFrequency, endFrequency: newEndFrequency)
            readout = (location, "\(PitchText.format(newStartFrequency, rootFrequency: settings.rootFrequency, scale: scale))  ·  \(timeLabel(dragging.note.startTime))")
        }
    }

    private func timeLabel(_ sample: Int) -> String {
        pianoRollTimeLabel(sample: sample, sampleRate: sequencer.sampleRate, tempo: sequencer.activeTempo, beatsPerBar: sequencer.beatsPerBar, subdivision: sequencer.gridSubdivision)
    }
}
