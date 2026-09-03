//
//  GraphScaleState.swift
//  Glass Bead Game III
//
//  scale/tetradLayers, promoted out of ContentView's own private @State into a shared
//  ObservableObject - needed so a second window (the external-display audience view) can read
//  the same values ContentView does. A UIWindowSceneDelegate is instantiated by UIKit itself
//  when a scene connects, outside the SwiftUI view tree entirely, so it has no way to reach a
//  view's own @State - only a process-wide global (matching how `sound`, in
//  Glass_Bead_Game_IIIApp.swift, already has to work for the same reason) is reachable from
//  both places.
//
//  Only depends on the scale's shape (limit, highest/lowest ratio), not Z - see
//  ContentView's own historical comment on why this is cached and only rebuilt on
//  settings.selectedLimit change, not recomputed from scratch on every Z-slider touch-move
//  frame.
//

import Foundation
import GBGCore

final class GraphScaleState: ObservableObject {
    @Published private(set) var scale: Scale
    @Published private(set) var tetradLayers: TetradLayers

    init(settings: AppSettings) {
        let initialScale = Scale(
            limit: limitMap[settings.selectedLimit] ?? 1,
            highestRatio: settings.highestRatio,
            lowestRatio: settings.lowestRatio)
        scale = initialScale
        tetradLayers = TetradLayers(scale: initialScale)
    }

    func rebuild(for settings: AppSettings) {
        let newScale = Scale(
            limit: limitMap[settings.selectedLimit] ?? 1,
            highestRatio: settings.highestRatio,
            lowestRatio: settings.lowestRatio)
        scale = newScale
        tetradLayers = TetradLayers(scale: newScale)
    }
}
