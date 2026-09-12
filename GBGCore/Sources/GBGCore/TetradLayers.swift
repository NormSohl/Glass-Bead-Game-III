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

public struct TetradLayers {
    public let scale: Scale
    private let tetradsByZ: [Double: [TetradElement]]
    public let sortedZValues: [Double] // rounded valueNormalized keys, ascending

    public init(scale: Scale) {
        self.scale = scale
        let tetrads = Tetrads(scale: scale)
        var grouped: [Double: [TetradElement]] = [:]
        for tetrad in tetrads.tetradList {
            let key = Tetrads.rounded(tetrad.zElement.valueNormalized)
            grouped[key, default: []].append(tetrad)
        }
        // Pre-sorted largest-to-smallest by sizeNormalized here, once, rather than TetradView
        // re-sorting its own combined draw list from scratch on every single frame during a
        // Z-slider drag - TetradView only ever needs to merge the (at most two) already-sorted
        // layers it's currently cross-fading between, an O(n) merge instead of an O(n log n)
        // sort repeated every frame. Confirmed live 2026-09-09 as part of the same investigation
        // into hangs building up during rapid Z dragging. Safe to do once and never again: the
        // tetrads within one layer never change after this - only which layers are active, and
        // their cross-fade weight, changes as Z moves.
        for key in grouped.keys {
            grouped[key]?.sort { $0.sizeNormalized > $1.sizeNormalized }
        }
        self.tetradsByZ = grouped
        self.sortedZValues = grouped.keys.sorted()
    }

    /// The layer(s) bracketing `zValueNormalized`: one layer at full weight if it lands exactly
    /// on a Z value (or beyond the lowest/highest Z the scale has), or two layers with linear
    /// crossfade weights (summing to 1.0) if it falls between two adjacent Z values.
    public func bracketingLayers(atZNormalized zValueNormalized: Double) -> [(tetrads: [TetradElement], weight: Double)] {
        bracketingKeys(around: zValueNormalized).map { (tetradsByZ[$0.key] ?? [], $0.weight) }
    }

    /// Same bracket-finding as `bracketingLayers`, but the Z keys and weights themselves rather
    /// than the tetrads at each key - for callers (the Z-filtered background grid) that need to
    /// look something else up per key (which scale degrees pair with that Z) rather than the
    /// tetrads directly, and so would otherwise have to unpack the key back out of
    /// `tetrads.first?.zElement.valueNormalized` themselves.
    public func bracketingZKeys(around zValueNormalized: Double) -> [(key: Double, weight: Double)] {
        bracketingKeys(around: zValueNormalized)
    }

    private func bracketingKeys(around zValueNormalized: Double) -> [(key: Double, weight: Double)] {
        guard let lowest = sortedZValues.first, let highest = sortedZValues.last else { return [] }

        if zValueNormalized <= lowest {
            return [(lowest, 1.0)]
        }
        if zValueNormalized >= highest {
            return [(highest, 1.0)]
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

        var keys: [(key: Double, weight: Double)] = []
        if belowWeight > 0 { keys.append((belowKey, belowWeight)) }
        if aboveWeight > 0 { keys.append((aboveKey, aboveWeight)) }
        return keys
    }

    /// The single nearest layer to `zValueNormalized`, always at full weight - no blend. For a
    /// snapped Z position: the Z-slider snaps to the full scale (the same grid X/Y snap to), but
    /// a tetrad only exists at the sparser subset of that grid where all three cross-ratios
    /// happen to also be scale members, so "snapped" and "sits exactly on a Z layer" are not the
    /// same thing - most snapped positions land *between* two real layers under
    /// bracketingLayers, which would show a permanent, never-resolving two-layer blend even
    /// though nothing is moving. This picks the layer the snap is nearest to instead, so a
    /// settled/snapped position always reads as exactly one layer, the way a snap implies it
    /// should. bracketingLayers' continuous blend is for unsnapped motion, where showing two
    /// layers mid-transition is exactly the point.
    public func nearestLayer(atZNormalized zValueNormalized: Double) -> (tetrads: [TetradElement], weight: Double) {
        guard let nearest = nearestZKey(to: zValueNormalized) else {
            return ([], 0)
        }
        return (tetradsByZ[nearest] ?? [], 1.0)
    }

    /// The single nearest Z key to `zValueNormalized`, with no blend - same "closer, not
    /// averaged" semantics as `nearestLayer`, exposed as just the key for the same reason
    /// `bracketingZKeys` exists alongside `bracketingLayers`.
    public func nearestZKey(to zValueNormalized: Double) -> Double? {
        sortedZValues.min(by: { abs($0 - zValueNormalized) < abs($1 - zValueNormalized) })
    }
}
