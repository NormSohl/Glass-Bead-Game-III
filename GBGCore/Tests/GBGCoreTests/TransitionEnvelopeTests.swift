import XCTest
@testable import GBGCore

final class TransitionEnvelopeTests: XCTestCase {
    func testTransFlatIsAlwaysZero() {
        let t = TransFlat()
        XCTAssertEqual(t.interpolate(percentComplete: 0), 0)
        XCTAssertEqual(t.interpolate(percentComplete: 0.5), 0)
        XCTAssertEqual(t.interpolate(percentComplete: 1), 0)
    }

    func testTransLinearIsIdentity() {
        let t = TransLinear()
        XCTAssertEqual(t.interpolate(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 1), 1, accuracy: 0.0001)
    }

    func testTransEaseInGoesZeroToOne() {
        let t = TransEaseIn()
        XCTAssertEqual(t.interpolate(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 1), 1, accuracy: 0.0001)
    }

    func testTransEaseOutGoesZeroToOne() {
        let t = TransEaseOut()
        XCTAssertEqual(t.interpolate(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 1), 1, accuracy: 0.0001)
    }

    func testTransEaseInEaseOutGoesZeroToOne() {
        let t = TransEaseInEaseOut()
        XCTAssertEqual(t.interpolate(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(t.interpolate(percentComplete: 1), 1, accuracy: 0.0001)
    }

    func testEnvFlatIsAlwaysOne() {
        let e = EnvFlat()
        XCTAssertEqual(e.interpolate(percentComplete: 0), 1)
        XCTAssertEqual(e.interpolate(percentComplete: 0.5), 1)
        XCTAssertEqual(e.interpolate(percentComplete: 1), 1)
    }

    // NOTE: this locks in the class's *actual* current behavior. Its header comment
    // promises a 0-to-1-to-0 hump, but the formula never reaches 0 and peaks at 2,
    // not 1. Flagging as a likely bug rather than silently encoding it as correct.
    func testEnvHumpStartsAndEndsAtZeroPeakingAtOne() {
        let e = EnvHump()
        XCTAssertEqual(e.interpolate(percentComplete: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(e.interpolate(percentComplete: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(e.interpolate(percentComplete: 1), 0, accuracy: 0.0001)
    }
}
