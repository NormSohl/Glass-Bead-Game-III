import XCTest
@testable import GBGCore

final class DiamondsTests: XCTestCase {
    func testDiamondsBuildsAtLeastOneDiamondForASmallScale() {
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)
        let diamonds = Diamonds(scale: scale)
        XCTAssertFalse(diamonds.DiamondList.isEmpty)
    }

    func testDiamondSizeNormalizedIsWithinUnitRange() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let diamonds = Diamonds(scale: scale)
        for diamond in diamonds.DiamondList {
            XCTAssertGreaterThanOrEqual(diamond.sizeNormalized, 0.0)
            XCTAssertLessThanOrEqual(diamond.sizeNormalized, 1.0)
        }
    }

    func testRootDiamondIsFlaggedWithUnisonDissonance() {
        // the 1/1, 1/1, 1/1 diamond should always exist and carry dissonance 3 (all three legs are unison)
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)
        let diamonds = Diamonds(scale: scale)
        let rootDiamond = diamonds.DiamondList.first {
            $0.xElement.value == 1.0 && $0.yElement.value == 1.0 && $0.zElement.value == 1.0
        }
        XCTAssertNotNil(rootDiamond)
        XCTAssertEqual(rootDiamond?.mydissonance, 3.0)
    }
}
