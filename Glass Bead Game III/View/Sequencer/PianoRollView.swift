//
//  PianoRollView.swift
//  Glass Bead Game III
//
//  The piano-roll Canvas + gesture surface: per-scale-degree gridlines mirroring the main
//  graph's, one colored "partline" per voice, draggable start/end handles on every note, and the
//  playhead. Panning is hand-rolled via DragGesture + state, matching how every other
//  interactive view in this app already pans (GraphView/ZSliderView use Canvas + DragGesture,
//  never ScrollView).
//

import SwiftUI
import GBGCore

// Same reasoning as HitTestView's module-scope `height`/ZSliderView's `zSliderHeight`: mutating
// this from inside the Canvas closure as @State caused inconsistent behavior in those views, so
// this follows the same workaround.
var pianoRollCanvasSize: CGSize = .zero

private let handleHitRadius: Double = 20
private let sampledCurvePoints = 24

private let voiceColors: [PartVoice: Color] = [
    .drone: .gray,
    .x: .cyan,
    .y: .orange,
    .z: .pink
]

struct PianoRollView: View {
    let scale: Scale
    @ObservedObject var settings: AppSettings
    @ObservedObject var sequencer: SequencerState

    // Gesture-local state - unlike pianoRollCanvasSize above, these are only ever touched from
    // .gesture closures (never the Canvas draw closure), so plain @State is fine here, matching
    // HitTestView's own hoverLocation.
    @State private var dragStartLocation: CGPoint?
    @State private var panStartOffsetSamples: Int?

    var body: some View {
        Canvas { context, size in
            pianoRollCanvasSize = size
            drawGridlines(context: context, size: size)
            drawPartlines(context: context, size: size)
            drawPlayhead(context: context, size: size)
        }
        .background(Color.black)
        .gesture(dragGesture)
        .simultaneousGesture(magnificationGesture)
    }

    // MARK: - Drawing

    private func drawGridlines(context: GraphicsContext, size: CGSize) {
        var path = Path()
        for element in scale.scale {
            let y = pianoRollFrequencyToScreenY(
                frequency: settings.rootFrequency * element.value,
                rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: size.height)
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

    private func drawPartlines(context: GraphicsContext, size: CGSize) {
        for voice in [PartVoice.drone, .x, .y, .z] {
            let part = sequencer.part(for: voice)
            let color = voiceColors[voice] ?? .white

            for note in part.notes where note.amplitude > 0 {
                var path = Path()
                for step in 0...sampledCurvePoints {
                    let percent = Double(step) / Double(sampledCurvePoints)
                    let sample = note.startTime + Int(Double(note.endTime - note.startTime) * percent)
                    let frequency = note.getCurrentFrequency(percentComplete: percent)
                    let x = pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
                    let y = pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: size.height)
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
        let y = pianoRollFrequencyToScreenY(frequency: frequency, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: canvasSize.height)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Hit testing

    private func hitTestHandle(at location: CGPoint) -> DraggingHandle? {
        var best: (handle: DraggingHandle, distance: Double)?
        for voice in [PartVoice.drone, .x, .y, .z] {
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

    // MARK: - Gestures

    // Gesture locations are plain SwiftUI top-down screen coordinates throughout - matching
    // PianoRollCoordinates' own convention (its frequency<->screen-Y functions flip internally,
    // so callers never need to). No manual flipping needed here, unlike HitTestView's
    // hoverLocation (whose own pitchHitTest math works in bottom-up space internally).
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
                if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                    let sample = pianoRollScreenXToSample(x: value.location.x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
                    sequencer.setPlayhead(to: sample)
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                sequencer.pixelsPerSecond = min(max(sequencer.pixelsPerSecond * value, 20), 800)
            }
    }

    private func applyHandleDrag(_ handle: DraggingHandle, to location: CGPoint) {
        let part = sequencer.part(for: handle.voice)
        let newTime = pianoRollScreenXToSample(x: location.x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
        let newFrequency = pianoRollScreenYToFrequency(y: location.y, rootFrequency: settings.rootFrequency, scale: scale, canvasHeight: pianoRollCanvasSize.height)

        switch handle.edge {
        case .start:
            part.moveNoteBoundary(of: handle.note, edge: .start, to: newTime, minimumNoteLength: sequencer.minimumNoteLengthSamples)
            handle.note.startFrequency = newFrequency
        case .end:
            part.moveNoteBoundary(of: handle.note, edge: .end, to: newTime, minimumNoteLength: sequencer.minimumNoteLengthSamples)
            handle.note.endFrequency = newFrequency
        }

        if let axis = handle.voice.graphAxis {
            switch axis {
            case .x: settings.xFrequency = newFrequency
            case .y: settings.yFrequency = newFrequency
            case .z: settings.zFrequency = newFrequency
            }
        } else {
            sequencer.updateDrivenDroneDisplay(frequency: newFrequency, amplitude: handle.note.amplitude)
        }

        sequencer.scoreRevision += 1
    }
}
