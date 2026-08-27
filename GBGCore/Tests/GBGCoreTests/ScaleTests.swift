import XCTest
@testable import GBGCore

final class ScaleTests: XCTestCase {
    func testUnisonHasZeroDissonanceFlagWhenNotOne() {
        // 3/2 is not 1/1, so dissonance should stay 0
        let element = ScaleElement(numerator: 3, denominator: 2, highestRatio: 2.0)
        XCTAssertEqual(element.dissonance, 0.0)
    }

    func testUnisonElementIsFlaggedDissonant() {
        // 1/1 is the special-cased unison ratio
        let element = ScaleElement(numerator: 1, denominator: 1, highestRatio: 2.0)
        XCTAssertEqual(element.value, 1.0)
        XCTAssertEqual(element.dissonance, 1.0)
    }

    func testValueNormalizedIsLog2OfRatio() {
        // 2/1 is exactly one octave above 1/1, so log2(2) == 1
        let element = ScaleElement(numerator: 2, denominator: 1, highestRatio: 2.0)
        XCTAssertEqual(element.valueNormalized, 1.0, accuracy: 0.0001)
        XCTAssertEqual(element.valueNormalizedCents, 1200.0, accuracy: 0.01)
    }

    func testConvertScaleValueToScreenUnitsMapsFullRangeToScreenSize() {
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)

        // the lowest normalized value in range should map to screen position 0
        let lowEdge = scale.convertScaleValueToScreenUnits(normalizedValue: scale.lowestRatioNormalized, screenSize: 1000)
        XCTAssertEqual(lowEdge, 0, accuracy: 0.01)

        // the highest normalized value in range should map to the full screen size
        let highEdge = scale.convertScaleValueToScreenUnits(normalizedValue: scale.highestRatioNormalized, screenSize: 1000)
        XCTAssertEqual(highEdge, 1000, accuracy: 0.01)
    }

    func testScaleHasNoDuplicateValues() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let values = scale.scale.map { $0.value }
        XCTAssertEqual(values.count, Set(values.map { ($0 * 100000).rounded() }).count)
    }

    func testScaleIsSortedAscending() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let values = scale.scale.map { $0.value }
        XCTAssertEqual(values, values.sorted())
    }

    func testHitTestBoundsCoverWholeRangeWithNoGaps() {
        // consecutive scale elements' bounds should meet exactly at the midpoint between them
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        for i in 1..<scale.scale.count {
            XCTAssertEqual(scale.scale[i - 1].upperBounds, scale.scale[i].lowerBounds, accuracy: 0.0001)
        }
    }
}
