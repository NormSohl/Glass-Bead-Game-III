//
//  AudienceGraphView.swift
//  Glass Bead Game III
//
//  The audience-facing window shown on an external display (Stage 4b) - the graph with a
//  display-only X/Y crosshair and Z-slider (Norm, 2026-09-28), no toolbar/controls, centered and letterboxed on
//  black. Reads the same process-wide globals ContentView does (see GraphScaleState's own header
//  comment for why those exist), so it always mirrors the performer's own current scale and
//  settings.graphTransform rotation/scale/offset with zero extra plumbing - GraphSquareView
//  already applies that transform and its own aspect-locked square, unconditionally.
//

import SwiftUI
import GBGCore

struct AudienceGraphView: View {
    @ObservedObject private var graphScale: GraphScaleState = graphScaleState
    @ObservedObject private var settings: AppSettings = appSettings

    // Same fixed width ContentView gives the performer's own slider.
    private let zSliderWidth: CGFloat = 70

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                // Sized directly from the available space rather than measured after layout the
                // way ContentView does: the square takes whatever height fits beside the slider.
                // The gap is the same reserved space ContentView uses for Ratios-mode label bleed
                // (see ratioLabelGap), so the labels GraphSquareView draws internally here land in
                // it instead of under the slider.
                let gap = ratioLabelGap(settings: settings)
                let side = max(0, min(geo.size.height, geo.size.width - zSliderWidth - gap))
                HStack(spacing: gap) {
                    // Same side as the performer's own screen (settings.zSliderSide).
                    if settings.zSliderSide == .right {
                        graphSquare(side: side)
                        zSlider(side: side)
                    } else {
                        zSlider(side: side)
                        graphSquare(side: side)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func graphSquare(side: CGFloat) -> some View {
        GraphSquareView(
            scale: graphScale.scale,
            tetradLayers: graphScale.tetradLayers,
            settings: settings,
            interactive: false,
            squareHeight: side
        )
        .frame(width: side, height: side)
    }

    private func zSlider(side: CGFloat) -> some View {
        ZSliderView(scale: graphScale.scale, settings: settings, graphSquareSize: side, interactive: false)
            .frame(width: zSliderWidth, height: side)
    }
}

// The X/Y crosshair for the projector (Norm, 2026-09-28). HitTestView can't simply be reused
// non-interactively: it owns the performer's touch handling and writes module-scope state
// (`height`) and settings.x/yFrequency from its own touch position, which a second copy at a
// different size would corrupt - the same reason ZSliderView has an `interactive` flag. This
// only reads settings.x/yFrequency (what's actually selected/sounding, whether from touch or
// incoming MIDI) and draws the same white cross HitTestView does, at the same position. Unlike
// the performer's crosshair it doesn't follow pen/mouse hover - the audience sees what's
// played, not where the pen is hovering.
struct AudienceCrosshair: View {
    let scale: Scale
    @ObservedObject var settings: AppSettings

    var body: some View {
        Canvas { context, size in
            let x = scale.convertScaleValueToScreenUnits(normalizedValue: log2(settings.xFrequency / settings.rootFrequency), screenSize: size.width)
            let y = size.height - scale.convertScaleValueToScreenUnits(normalizedValue: log2(settings.yFrequency / settings.rootFrequency), screenSize: size.height)
            let crossSize: Double = 8
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: y + crossSize))
                    path.addLine(to: CGPoint(x: x, y: y - crossSize))
                    path.move(to: CGPoint(x: x - crossSize, y: y))
                    path.addLine(to: CGPoint(x: x + crossSize, y: y))
                }, with: .color(.white),
                lineWidth: 3
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
