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
}
