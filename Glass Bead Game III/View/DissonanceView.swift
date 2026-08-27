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

                let weighting: Dissonance.HarmonicWeighting = settings.useLinearHarmonicWeighting
                    ? { Dissonance.linearHarmonicWeight($0, limit: limit) }
                    : Dissonance.harmonicWeight

                let grid = Dissonance.roughnessGrid(
                    scale: scale,
                    rootFrequency: settings.rootFrequency,
                    limit: limit,
                    resolution: gridResolution,
                    weighting: weighting
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

    // Gamma < 1 lifts the midtones before coloring, without touching the peak (still full
    // intensity at t=1). Picked by comparing renders at 1.0/0.5/0.35/0.25: without it, the
    // color/opacity are normalized against the field's global max (the unison ring, ~4.6),
    // which squashed the third/fourth/fifth ridges toward near-invisible. 0.5 keeps unison
    // reading as the clear strongest point while making those ridges legible.
    private let gamma = 0.5

    // Low roughness fades toward transparent, so consonant regions blend into the black
    // background instead of competing with the diamonds/grid drawn on top of this layer;
    // high roughness glows warm.
    private func roughnessColor(_ normalizedRoughness: Double) -> Color {
        let t = pow(min(max(normalizedRoughness, 0), 1), gamma)
        return Color(red: t, green: t * 0.35, blue: t * 0.15, opacity: t * 0.9)
    }
}
