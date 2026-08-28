//
//  TetradLayers.swift
//  GBGCore
//
//  The two-layer crossfade mechanism from the depth-slider design notes: groups a Tetrads set
//  by its Z value, and for a given slider position, looks up the (at most two) bracketing
//  layers with linear crossfade weights. See glass_bead_game_iii_depth_slider_design memory
//  notes for the full design conversation.
//
//  Grouping the whole Tetrads set once (a one-time cost per limit/scale change, same as Tetrads
//  itself) turns out simpler than the design conversation's original framing of "only compute
//  the two layers currently needed, refresh on bracket-cross" - since Tetrads already computes
//  every (X,Y,Z) triple in one pass regardless of Z, there's no cheaper way to get one layer
//  than to get them all, so grouping the full result once and doing a cheap dictionary lookup
//  per slider move is both simpler and cheaper than recomputing per bracket-cross.
//
//  Diamonds are discrete existence facts, not a sampled continuous field, so crossfading
//  between two real layers never loses information the way interpolating a continuous field
//  would (see the Performance section of the design notes) - each layer here is always exact,
//  freshly-grouped data; only the blend weight between two exact layers is linear.

import Foundation

struct TetradLayers {
    let scale: Scale
    private let tetradsByZ: [Double: [TetradElement]]
    let sortedZValues: [Double] // rounded valueNormalized keys, ascending

    init(scale: Scale) {
        self.scale = scale
        let tetrads = Tetrads(scale: scale)
        var grouped: [Double: [TetradElement]] = [:]
        for tetrad in tetrads.tetradList {
            let key = Tetrads.rounded(tetrad.zElement.valueNormalized)
            grouped[key, default: []].append(tetrad)
        }
        self.tetradsByZ = grouped
        self.sortedZValues = grouped.keys.sorted()
    }

    /// The layer(s) bracketing `zValueNormalized`: one layer at full weight if it lands exactly
    /// on a Z value (or beyond the lowest/highest Z the scale has), or two layers with linear
    /// crossfade weights (summing to 1.0) if it falls between two adjacent Z values.
    func bracketingLayers(atZNormalized zValueNormalized: Double) -> [(tetrads: [TetradElement], weight: Double)] {
        guard let lowest = sortedZValues.first, let highest = sortedZValues.last else { return [] }

        if zValueNormalized <= lowest {
            return [(tetradsByZ[lowest] ?? [], 1.0)]
        }
        if zValueNormalized >= highest {
            return [(tetradsByZ[highest] ?? [], 1.0)]
        }

        // largest key <= zValueNormalized, and the key immediately above it
        var belowIndex = 0
        for (index, key) in sortedZValues.enumerated() {
            if key <= zValueNormalized { belowIndex = index } else { break }
        }
        let belowKey = sortedZValues[belowIndex]
        let aboveKey = sortedZValues[belowIndex + 1]

        let fraction = (zValueNormalized - belowKey) / (aboveKey - belowKey)
        let belowWeight = 1 - fraction
        let aboveWeight = fraction

        var layers: [(tetrads: [TetradElement], weight: Double)] = []
        if belowWeight > 0 { layers.append((tetradsByZ[belowKey] ?? [], belowWeight)) }
        if aboveWeight > 0 { layers.append((tetradsByZ[aboveKey] ?? [], aboveWeight)) }
        return layers
    }
}
