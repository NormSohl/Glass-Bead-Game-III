//
//  AudienceGraphView.swift
//  Glass Bead Game III
//
//  The audience-facing window shown on an external display (Stage 4b) - just the graph, no
//  toolbar/controls/Z-slider, centered and letterboxed on black. Reads the same process-wide
//  globals ContentView does (see GraphScaleState's own header comment for why those exist),
//  so it always mirrors the performer's own current scale and settings.graphTransform rotation/
//  scale/offset with zero extra plumbing - GraphSquareView already applies that transform and
//  its own aspect-locked square, unconditionally.
//

import SwiftUI
import GBGCore

struct AudienceGraphView: View {
    @ObservedObject private var graphScale: GraphScaleState = graphScaleState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GraphSquareView(
                scale: graphScale.scale,
                tetradLayers: graphScale.tetradLayers,
                settings: appSettings,
                interactive: false
            )
        }
    }
}
