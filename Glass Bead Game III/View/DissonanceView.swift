//
//  DissonanceView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 4/19/23.
//
//  Renders the roughness/dissonance field (see GBGCore's Dissonance.swift for the math)
//  as a background layer under the grid/diamonds: for every point on the graph, how rough
//  would the root+X+Y triad sound if you played there? The diamonds mark the exact,
//  precise consonances; this fills in what's happening in between them.
//
//  First pass, not yet seen rendered on a device - grid resolution and the color ramp
//  are both plain guesses and likely want tuning once this can actually be looked at.

import SwiftUI

struct DissonanceView: View {
    let scale: Scale
    let settings: AppSettings
    let showDissonance: Bool

    // Cells per axis. Cost scales as resolution^2 * limit^2 * 3, so this is a real
    // perf/smoothness trade-off - not yet profiled on a device.
    private let gridResolution = 40

    var body: some View {
        if showDissonance {
            Canvas { context, size in
                guard let limit = limitMap[settings.selectedLimit], limit > 0 else { return }

                let grid = Dissonance.roughnessGrid(
                    scale: scale,
                    rootFrequency: settings.rootFrequency,
                    limit: limit,
                    resolution: gridResolution
                )
                guard let maxRoughness = grid.flatMap({ $0 }).max(), maxRoughness > 0 else { return }

                let cellWidth = size.width / Double(gridResolution)
                let cellHeight = size.height / Double(gridResolution)

                for row in 0..<gridResolution {
                    // row 0 is the lowest pitch (bottom of the graph); screen Y grows
                    // downward, so invert - same convention as Graph/DiamondView/HitTestView.
                    let cellTop = size.height - Double(row + 1) * cellHeight
                    for col in 0..<gridResolution {
                        let normalizedRoughness = grid[row][col] / maxRoughness
                        let cellLeft = Double(col) * cellWidth
                        let rect = CGRect(x: cellLeft, y: cellTop, width: cellWidth, height: cellHeight)
                        context.fill(Path(rect), with: .color(roughnessColor(normalizedRoughness)))
                    }
                }
            }
        }
    }

    // Inverted from the first pass: no dissonance is light (a warm cream), maximum
    // dissonance is black - opaque throughout, since roughness is now encoded directly in
    // luminance rather than faded into the black background via opacity. A first guess,
    // not a considered design - needs eyes on the actual render to know if it reads well,
    // and note this now fully covers the graph rather than only highlighting hot spots.
    private func roughnessColor(_ normalizedRoughness: Double) -> Color {
        let t = min(max(normalizedRoughness, 0), 1)
        let lightR = 1.0, lightG = 0.957, lightB = 0.878 // warm cream at zero roughness
        return Color(red: lightR * (1 - t), green: lightG * (1 - t), blue: lightB * (1 - t), opacity: 1.0)
    }
}
