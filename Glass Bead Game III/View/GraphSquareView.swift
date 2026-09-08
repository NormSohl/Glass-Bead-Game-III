//
//  GraphSquareView.swift
//  Glass Bead Game III
//
//  The graph itself - GraphView wrapped in settings.graphTransform's rotation/scale/offset,
//  locked to a 1:1 square. Extracted from ContentView's own former `graphSquare` computed
//  property so a second, non-interactive window (AudienceGraphView, for external-display
//  projection) can show exactly the same thing the performer sees without duplicating this
//  logic - ContentView.graphSquare is now a thin wrapper around this plus the Z-slider-sizing
//  GeometryReader that's specific to that one window.
//

import SwiftUI
import GBGCore

struct GraphSquareView: View {
    let scale: Scale
    let tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings
    @ObservedObject var recordingState: RecordingState
    // false for a display-only audience view - see GraphView's own interactive flag.
    var interactive: Bool = true
    // The square's own rendered height from the previous layout pass, used to scale
    // settings.graphTransform's offsetX/offsetY (fractions of the square's own side, not raw
    // pixels - a fixed pixel offset tuned for one window/screen size would be wrong on any
    // other). The caller measures this via its own GeometryReader wrapping this view and feeds
    // it back in here - deliberately "one frame behind" rather than computed synchronously,
    // since there's no way to know a view's own rendered size before it's rendered; matches
    // ContentView's own former graphSquareHeight comment on why that lag is fine in practice.
    var squareHeight: CGFloat = 0
    // false for ContentView's own performer window, where the Z-slider and (on iPad)
    // ControlColumn sit as siblings immediately beside this view in the same HStack with zero
    // spacing - a later-declared sibling paints over an earlier one's bled content wherever
    // they overlap, so the labels' bleed was getting covered by whichever of those siblings
    // came after graphSquare in the HStack (confirmed live 2026-09-07: right-side labels
    // "still clipped" - actually occluded by the Z-slider drawn on top, not truly clipped).
    // ContentView instead renders its own top-level copy of this same overlay, positioned via
    // a captured on-screen frame, painted after its whole HStack so it's guaranteed to be on
    // top of every sibling. AudienceGraphView has no such siblings, so it keeps this true
    // (the default) and draws the labels right here as before.
    var drawsRatioLabelsInternally: Bool = true

    var body: some View {
        // Outer ZStack has NO clip of its own - it exists only so the ratio-label bleed overlay
        // below can sit as a sibling of the clipped square instead of a descendant of it. Both
        // children are independently locked to the same 1:1 aspect ratio, so they always resolve
        // to the identical square size/position - the clip only affects the inner one.
        ZStack {
            ZStack {
                Color.black.ignoresSafeArea(.all)
                GraphView(scale: scale,
                          tetradLayers: tetradLayers,
                          settings: settings,
                          recordingState: recordingState,
                          interactive: interactive
                )
                .rotationEffect(.degrees(settings.graphTransform.rotation))
                .animation(.easeIn, value: settings.graphTransform.rotation)
                .scaleEffect(CGSize(width: settings.graphTransform.scale, height: settings.graphTransform.scale))
                .offset(x: settings.graphTransform.offsetX * squareHeight, y: settings.graphTransform.offsetY * squareHeight)
            }
            // Unconditional again (briefly made Diamond/Triangle-only, 2026-09-07) - that detour
            // was to work around tickBorderH/V being asymmetric in Ratios mode, which made this
            // composite genuinely non-square and squeezing it into a forced-square box distorted
            // the grid (confirmed live: "look at the 1/1 diamond... nowhere near" the grid
            // lines). Border is symmetric again now (see tickBorderSizes, GraphView.swift -
            // ratio label width comes from RatioLabelsOverlay's own deliberate bleed instead of
            // widening the border), so the composite genuinely IS square again and this no
            // longer distorts anything - and it's needed unconditionally: without it, this
            // ZStack's own Color.black.ignoresSafeArea(.all) is unboundedly greedy, and on iPad
            // reported a huge ideal size to the containing HStack, pushing the Z-slider/
            // ControlColumn out to the screen's outer edges instead of sitting snug against the
            // graph (confirmed live 2026-09-07) - GraphView's own internal
            // .fixedSize(horizontal:) only constrains GraphView itself, not this greedy
            // background sitting above it in the same ZStack.
            .aspectRatio(1/1, contentMode: .fit)
            .clipped()

            // Ratio-fraction labels: a sibling of the clipped square above, not a descendant of
            // it, so its deliberate labelBleed padding (see RatioLabelsOverlay's own comment)
            // can extend past the square's own edge without the outer .clipped() above cutting
            // the outer/far label column off - confirmed live 2026-09-07 ("the outer column of
            // ratios are now clipped") once that .clipped() was restored to fix the iPad
            // greedy-background regression. Its own .aspectRatio(1/1, .fit) below matches the
            // inner square exactly, so the GeometryReader inside sees the same true size.
            if drawsRatioLabelsInternally {
                GeometryReader { proxy in
                    let labelBleed = 40.0
                    let inputs = graphRatioLabelInputs(scale: scale, tetradLayers: tetradLayers, settings: settings)
                    RatioLabelsOverlay(scale: scale, elements: inputs.elements, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, tickBorderH: inputs.tickBorderH, tickBorderV: inputs.tickBorderV, labelBleed: labelBleed, trueSize: proxy.size, showLabels: settings.tickLabelStyle == .ratios)
                        .frame(width: proxy.size.width + 2 * labelBleed, height: proxy.size.height + 2 * labelBleed)
                        .offset(x: -labelBleed, y: -labelBleed)
                }
                .aspectRatio(1/1, contentMode: .fit)
                .allowsHitTesting(false)
            }
        }
    }
}
