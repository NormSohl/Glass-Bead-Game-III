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

    var body: some View {
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
        // Always .fit, not tied to GraphShape at all (Triangle used to set this to .fill) - see
        // ContentView's own historical note on why: .clipped() only affects rendering, not
        // layout size, so a .fill content mode here would let a caller's own outer height
        // measurement pick up the oversized, unclipped .fill layout size instead of the
        // visually-clipped square.
        .aspectRatio(1/1, contentMode: .fit)
        // Diamond's own 0.75 scale and Triangle's own rotation+scale combination both push
        // content past this frame's own bounds by design - clipped so any of that spills onto
        // nothing beyond this square, rather than bleeding into whatever's next to it.
        .clipped()
    }
}
