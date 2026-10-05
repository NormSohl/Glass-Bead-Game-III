//
//  TimelineRulerView.swift
//  Seq
//
//  The labeled time ruler above the note editor, sharing its pan/zoom. Seconds with the grid
//  off; bar numbers and beat ticks with it on. Click or drag here to put the playhead (the step
//  cursor) somewhere - snapped to the grid unless Option is held.
//

import SwiftUI
import AppKit
import GBGCore

struct TimelineRulerView: View {
    @ObservedObject var sequencer: SequencerState

    var body: some View {
        Canvas { context, size in
            if let tempo = sequencer.activeTempo {
                drawBars(context: context, size: size, tempo: tempo)
            } else {
                drawSeconds(context: context, size: size)
            }
            drawPlayheadMarker(context: context, size: size)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(baseline, with: .color(.white.opacity(0.3)))
        }
        .frame(height: 24)
        .background(Color(white: 0.1))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let raw = max(0, x2sample(value.location.x))
                    sequencer.setPlayhead(to: NSEvent.modifierFlags.contains(.option) ? raw : sequencer.snapTime(raw))
                }
        )
    }

    private func x(_ sample: Int) -> Double {
        pianoRollSampleToScreenX(sample: sample, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
    }

    private func x2sample(_ x: Double) -> Int {
        pianoRollScreenXToSample(x: x, offsetSamples: sequencer.offsetSamples, pixelsPerSecond: sequencer.pixelsPerSecond, sampleRate: sequencer.sampleRate)
    }

    private func tick(_ path: inout Path, x: Double, height: Double, size: CGSize) {
        path.move(to: CGPoint(x: x, y: size.height))
        path.addLine(to: CGPoint(x: x, y: size.height - height))
    }

    private func label(_ context: GraphicsContext, _ text: String, x: Double) {
        context.draw(Text(text).font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.8)), at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
    }

    private func drawSeconds(context: GraphicsContext, size: CGSize) {
        let step = pianoRollNiceTimeStepSeconds(pixelsPerSecond: sequencer.pixelsPerSecond)
        let minorSamples = Int(step / 5 * sequencer.sampleRate)
        guard minorSamples > 0 else { return }
        var major = Path(), minor = Path()
        var index = sequencer.offsetSamples / minorSamples
        while true {
            let sample = index * minorSamples
            let px = x(sample)
            if px > size.width { break }
            if px >= 0 {
                if index % 5 == 0 {
                    tick(&major, x: px, height: size.height, size: size)
                    let seconds = Double(sample) / sequencer.sampleRate
                    label(context, step >= 1 ? String(format: "%.0fs", seconds) : String(format: "%gs", (seconds * 1000).rounded() / 1000), x: px)
                } else {
                    tick(&minor, x: px, height: 5, size: size)
                }
            }
            index += 1
        }
        context.stroke(major, with: .color(.white.opacity(0.4)))
        context.stroke(minor, with: .color(.white.opacity(0.25)))
    }

    private func drawBars(context: GraphicsContext, size: CGSize, tempo: TempoInfo) {
        let beatSamples = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sequencer.sampleRate)
        guard beatSamples > 0 else { return }
        let beatPixels = beatSamples / sequencer.sampleRate * sequencer.pixelsPerSecond
        let beatsPerBar = max(1, sequencer.beatsPerBar)
        // Label every bar, or every 2nd/4th/... when bars get too narrow to fit a number.
        let barPixels = beatPixels * Double(beatsPerBar)
        var labelEvery = 1
        while barPixels * Double(labelEvery) < 28 { labelEvery *= 2 }

        let first = Int((Double(sequencer.offsetSamples - tempo.downbeatOffset) / beatSamples).rounded(.down)) - 1
        let last = Int((Double(x2sample(size.width) - tempo.downbeatOffset) / beatSamples).rounded(.up)) + 1
        guard first <= last else { return }
        var barTicks = Path(), beatTicks = Path()
        for n in first...last {
            let px = x(tempo.downbeatOffset + Int((Double(n) * beatSamples).rounded()))
            guard px >= 0, px <= size.width else { continue }
            if n % beatsPerBar == 0 {
                tick(&barTicks, x: px, height: size.height, size: size)
                let bar = Int((Double(n) / Double(beatsPerBar)).rounded(.down)) + 1
                if (bar - 1) % labelEvery == 0 { label(context, "\(bar)", x: px) }
            } else if beatPixels >= 6 {
                tick(&beatTicks, x: px, height: 6, size: size)
            }
        }
        context.stroke(barTicks, with: .color(.yellow.opacity(0.6)))
        context.stroke(beatTicks, with: .color(.yellow.opacity(0.35)))
    }

    private func drawPlayheadMarker(context: GraphicsContext, size: CGSize) {
        let px = x(sequencer.playheadSample)
        guard px >= -6, px <= size.width + 6 else { return }
        var triangle = Path()
        triangle.move(to: CGPoint(x: px - 6, y: size.height - 10))
        triangle.addLine(to: CGPoint(x: px + 6, y: size.height - 10))
        triangle.addLine(to: CGPoint(x: px, y: size.height))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(sequencer.editTool == .step ? .green : .white))
    }
}
