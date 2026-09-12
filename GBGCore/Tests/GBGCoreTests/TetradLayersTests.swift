import XCTest
@testable import GBGCore

final class TetradLayersTests: XCTestCase {
    func testExactZMatchReturnsSingleFullWeightLayer() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let midKey = layers.sortedZValues[layers.sortedZValues.count / 2]

        let result = layers.bracketingLayers(atZNormalized: midKey)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weight, 1.0)
        XCTAssertFalse(result[0].tetrads.isEmpty)
        for tetrad in result[0].tetrads {
            XCTAssertEqual(Tetrads.rounded(tetrad.zElement.valueNormalized), midKey)
        }
    }

    func testBetweenTwoZValuesReturnsTwoWeightedLayersSummingToOne() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        XCTAssertGreaterThan(layers.sortedZValues.count, 1)

        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        let midpoint = (below + above) / 2

        let result = layers.bracketingLayers(atZNormalized: midpoint)

        XCTAssertEqual(result.count, 2)
        let totalWeight = result.reduce(0.0) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 1e-9)
        // exact midpoint: both sides should be weighted equally
        XCTAssertEqual(result[0].weight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result[1].weight, 0.5, accuracy: 1e-9)
    }

    func testWeightsShiftTowardTheNearerLayer() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        // 90% of the way from below to above - above's layer should carry ~90% of the weight
        let nearAbove = below + (above - below) * 0.9

        let result = layers.bracketingLayers(atZNormalized: nearAbove)

        XCTAssertEqual(result.count, 2)
        let aboveResult = result.first { $0.tetrads.allSatisfy { Tetrads.rounded($0.zElement.valueNormalized) == above } }
        XCTAssertNotNil(aboveResult)
        XCTAssertEqual(aboveResult?.weight ?? 0, 0.9, accuracy: 1e-9)
    }

    func testBelowLowestZClampsToSingleLayerAtFullWeight() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let farBelow = layers.sortedZValues.first! - 10.0

        let result = layers.bracketingLayers(atZNormalized: farBelow)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weight, 1.0)
    }

    func testAboveHighestZClampsToSingleLayerAtFullWeight() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let farAbove = layers.sortedZValues.last! + 10.0

        let result = layers.bracketingLayers(atZNormalized: farAbove)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weight, 1.0)
    }

    // MARK: - nearestLayer (snapped Z - no blend)

    func testNearestLayerAtExactKeyReturnsThatLayerAtFullWeight() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let midKey = layers.sortedZValues[layers.sortedZValues.count / 2]

        let result = layers.nearestLayer(atZNormalized: midKey)

        XCTAssertEqual(result.weight, 1.0)
        XCTAssertFalse(result.tetrads.isEmpty)
        for tetrad in result.tetrads {
            XCTAssertEqual(Tetrads.rounded(tetrad.zElement.valueNormalized), midKey)
        }
    }

    func testNearestLayerBetweenTwoValuesPicksTheCloserOneAtFullWeight() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        // 90% of the way from below to above - nearest should be "above", not a blend
        let nearAbove = below + (above - below) * 0.9

        let result = layers.nearestLayer(atZNormalized: nearAbove)

        XCTAssertEqual(result.weight, 1.0) // always full weight - never a blend
        for tetrad in result.tetrads {
            XCTAssertEqual(Tetrads.rounded(tetrad.zElement.valueNormalized), above)
        }
    }

    func testNearestLayerAtExactMidpointPicksOneSideNotABlend() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        let midpoint = (below + above) / 2

        let result = layers.nearestLayer(atZNormalized: midpoint)

        // exactly one real layer's worth of tetrads, always at full weight - unlike
        // bracketingLayers, there is no valid "both sides" answer here
        XCTAssertEqual(result.weight, 1.0)
        let zValues = Set(result.tetrads.map { Tetrads.rounded($0.zElement.valueNormalized) })
        XCTAssertEqual(zValues.count, 1)
    }

    // MARK: - bracketingZKeys / nearestZKey (the Z-filtered grid's key-only views)

    func testBracketingZKeysMatchesTheKeysBracketingLayersUsed() {
        // Same bracket-finding, just the keys/weights instead of the tetrads at each key - so
        // this must always agree with bracketingLayers on which keys and weights come back.
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        let nearAbove = below + (above - below) * 0.9

        let keys = layers.bracketingZKeys(around: nearAbove)
        let fromLayers = layers.bracketingLayers(atZNormalized: nearAbove)

        XCTAssertEqual(keys.count, fromLayers.count)
        for (key, layer) in zip(keys, fromLayers) {
            XCTAssertEqual(key.weight, layer.weight, accuracy: 1e-9)
            XCTAssertTrue(layer.tetrads.allSatisfy { Tetrads.rounded($0.zElement.valueNormalized) == key.key })
        }
    }

    func testNearestZKeyMatchesTheKeyNearestLayerUsed() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let layers = TetradLayers(scale: scale)
        let below = layers.sortedZValues[0]
        let above = layers.sortedZValues[1]
        let nearAbove = below + (above - below) * 0.9

        let key = layers.nearestZKey(to: nearAbove)
        let fromLayer = layers.nearestLayer(atZNormalized: nearAbove)

        XCTAssertEqual(key, above)
        XCTAssertTrue(fromLayer.tetrads.allSatisfy { Tetrads.rounded($0.zElement.valueNormalized) == key })
    }

    // Locks in an invariant TetradView now depends on for correctness, not just performance:
    // it merges the (at most two) active layers' own tetrad arrays under the assumption that
    // each one already arrives sorted largest-to-smallest by sizeNormalized (see
    // TetradLayers.init's own comment - added 2026-09-09 to replace TetradView's own from-
    // scratch per-frame sort with an O(n) merge of two pre-sorted lists). If this invariant
    // ever broke silently, TetradView's merge would produce the wrong draw order (larger
    // tetrads could overprint smaller ones) with no visible crash - this test exists so that
    // regression is caught here instead.
    func testEachLayersTetradsAreSortedLargestToSmallest() {
        let scale = Scale(limit: 9, highestRatio: 3/1, lowestRatio: 1/2)
        let layers = TetradLayers(scale: scale)
        for key in layers.sortedZValues {
            let tetrads = layers.nearestLayer(atZNormalized: key).tetrads
            for i in 1..<tetrads.count {
                XCTAssertGreaterThanOrEqual(
                    tetrads[i - 1].sizeNormalized, tetrads[i].sizeNormalized,
                    "layer at Z=\(key) is not sorted largest-to-smallest at index \(i)"
                )
            }
        }
    }
}
