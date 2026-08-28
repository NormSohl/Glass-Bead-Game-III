//
//  ContentView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    // Scale/Diamonds/TetradLayers only depend on the scale's shape (limit, highest/lowest
    // ratio) - not on Z. They're cached here and recomputed only via onChange(of:
    // settings.selectedLimit) below, rather than as plain `let`s in body: settings.zFrequency
    // now publishes on every Z-slider touch-move frame, and recomputing Tetrads (the basis of
    // tetradLayers) from scratch on every frame would be the "hundreds of ms at worst" cost
    // from the design notes running many times a second instead of once per limit change.
    @State private var scale: Scale
    @State private var diamonds: Diamonds
    @State private var tetradLayers: TetradLayers

    init() {
        let initialSettings = AppSettings()
        _settings = StateObject(wrappedValue: initialSettings)
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
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea(.all)

            HStack(spacing: 0) {
                ZStack(){
                    Color.black.ignoresSafeArea(.all)
                    GraphView(scale: scale,
                              diamonds: diamonds,
                              tetradLayers: tetradLayers,
                              settings: settings
                    )
                    .rotationEffect(.degrees(settings.viewRotation))
                    .scaleEffect(CGSize(width: settings.viewScale, height: settings.viewScale))
                    .offset(x: settings.viewOffsetX, y: settings.viewOffsetY)
                }
                .aspectRatio(1/1, contentMode: settings.contentMode)
                .layoutPriority(1)
                .background()
                .animation(.easeIn, value: settings.viewRotation)

                // Z: its own touch zone, not overlapping the graph - a separate DragGesture here
                // tracks its own touch independently of the graph's, so both can be held at once.
                ZSliderView(scale: scale, settings: settings)
                    .frame(width: 70)
            }

            // settings moved off the graph into a popover so the right edge is free for the Z slider
            Button {
                settings.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding()
            .popover(isPresented: $settings.showSettings) {
                ControlView(settings: settings)
                    .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 650)
            }
        }
        .frame (minWidth: 800, minHeight: 500)
        .onChange(of: settings.selectedLimit) {
            rebuildScaleDependentState()
        }
    }
}
