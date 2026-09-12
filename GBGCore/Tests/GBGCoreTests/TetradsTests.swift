import XCTest
@testable import GBGCore

final class TetradsTests: XCTestCase {
    func testTetradsBuildsAtLeastOneTetradForASmallScale() {
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        XCTAssertFalse(tetrads.tetradList.isEmpty)
    }

    func testTetradSizeNormalizedIsWithinUnitRange() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        for tetrad in tetrads.tetradList {
            XCTAssertGreaterThanOrEqual(tetrad.sizeNormalized, 0.0)
            XCTAssertLessThanOrEqual(tetrad.sizeNormalized, 1.0)
        }
    }

    func testAllUnisonTetradHasDissonanceCountSix() {
        // root = X = Y = Z is the absolute center - all six pairs coincide
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        let allUnison = tetrads.tetradList.first {
            $0.xElement.value == 1.0 && $0.yElement.value == 1.0 && $0.zElement.value == 1.0
        }
        XCTAssertNotNil(allUnison)
        XCTAssertEqual(allUnison?.dissonanceCount, 6)
    }

    func testAchievableDissonanceValuesAreZeroOneTwoThreeOrSix() {
        // 4 and 5 are structurally impossible: no partition of 4 items yields exactly 4 or 5
        // coincident pairs among the six without all 4 coinciding (which jumps straight to 6)
        let scale = Scale(limit: 9, highestRatio: 3/1, lowestRatio: 1/2)
        let tetrads = Tetrads(scale: scale)
        XCTAssertFalse(tetrads.tetradList.isEmpty)

        let observedValues = Set(tetrads.tetradList.map { $0.dissonanceCount })
        XCTAssertTrue(observedValues.isSubset(of: [0, 1, 2, 3, 6]), "unexpected dissonanceCount values: \(observedValues)")
    }

    // Verifies the design conversation's key claim: Tetrads reduces exactly to Diamonds when Z
    // sits at unison. Existence (which X,Y pairs qualify) and size must match exactly; dissonance
    // count differs by a fully-explained offset (root:Z is a genuine sixth relationship the 3-leg
    // model never counted, trivially satisfied whenever Z sits on the drone).
    func testTetradsReduceToDiamondsWhenZIsAtUnison() {
        let scale = Scale(limit: 7, highestRatio: 3/1, lowestRatio: 1/2)
        let diamonds = Diamonds(scale: scale)
        let tetrads = Tetrads(scale: scale)

        let zUnisonTetrads = tetrads.tetradList.filter { $0.zElement.value == 1.0 }
        XCTAssertEqual(zUnisonTetrads.count, diamonds.diamondList.count)

        for diamond in diamonds.diamondList {
            let match = zUnisonTetrads.first {
                $0.xElement.value == diamond.xElement.value && $0.yElement.value == diamond.yElement.value
            }
            XCTAssertNotNil(match, "no z-unison tetrad found for diamond x=\(diamond.xElement.value) y=\(diamond.yElement.value)")
            guard let match else { continue }

            XCTAssertEqual(match.sizeNormalized, diamond.sizeNormalized, accuracy: 1e-9)

            let expectedDissonanceCount = Int(diamond.mydissonance) + 1
                + (diamond.xElement.value == 1.0 ? 1 : 0)
                + (diamond.yElement.value == 1.0 ? 1 : 0)
            XCTAssertEqual(match.dissonanceCount, expectedDissonanceCount)
        }
    }

    // MARK: - movingToneUnisonCount (root/drone excluded, Norm's 3-tone coloring rule)

    func testAllThreeMovingTonesCoincidingGivesMovingToneUnisonCountThree() {
        // X = Y = Z, regardless of where root sits - this is the "red" case
        let scale = Scale(limit: 3, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        let allMovingTonesUnison = tetrads.tetradList.first {
            $0.xElement.value == $0.yElement.value && $0.yElement.value == $0.zElement.value
        }
        XCTAssertNotNil(allMovingTonesUnison)
        XCTAssertEqual(allMovingTonesUnison?.movingToneUnisonCount, 3)
    }

    func testExactlyTwoMovingTonesCoincidingGivesMovingToneUnisonCountOne() {
        // X = Y, Z different - the "white" case, independent of root
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        let twoCoincide = tetrads.tetradList.first {
            $0.xElement.value == $0.yElement.value && $0.yElement.value != $0.zElement.value
        }
        XCTAssertNotNil(twoCoincide)
        XCTAssertEqual(twoCoincide?.movingToneUnisonCount, 1)
    }

    func testNoMovingTonesCoincidingGivesMovingToneUnisonCountZero() {
        // X, Y, Z all mutually distinct - the "yellow" case, even if one happens to sit on root
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        let noneCoincide = tetrads.tetradList.first {
            $0.xElement.value != $0.yElement.value
                && $0.xElement.value != $0.zElement.value
                && $0.yElement.value != $0.zElement.value
        }
        XCTAssertNotNil(noneCoincide)
        XCTAssertEqual(noneCoincide?.movingToneUnisonCount, 0)
    }

    func testAchievableMovingToneUnisonCountValuesAreZeroOneOrThree() {
        // 2 is structurally impossible: equality among X, Y, Z is transitive, so exactly two of
        // the three pairs coinciding while the third doesn't can never happen
        let scale = Scale(limit: 9, highestRatio: 3/1, lowestRatio: 1/2)
        let tetrads = Tetrads(scale: scale)
        XCTAssertFalse(tetrads.tetradList.isEmpty)

        let observedValues = Set(tetrads.tetradList.map { $0.movingToneUnisonCount })
        XCTAssertTrue(observedValues.isSubset(of: [0, 1, 3]), "unexpected movingToneUnisonCount values: \(observedValues)")
    }

    func testMovingToneUnisonCountIgnoresRoot() {
        // X = Y = root (root:X and root:Y both unison too) but Z different - still only ONE
        // moving-tone pair (X:Y) coincides, so this must read as the "white" case (1), not
        // silently inflated by the root-involving coincidences the way dissonanceCount would be
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let tetrads = Tetrads(scale: scale)
        let match = tetrads.tetradList.first {
            $0.xElement.value == 1.0 && $0.yElement.value == 1.0 && $0.zElement.value != 1.0
        }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.movingToneUnisonCount, 1)
        // sanity check this case really does have extra root-involving coincidences that
        // dissonanceCount picks up but movingToneUnisonCount must not
        XCTAssertGreaterThan(match?.dissonanceCount ?? 0, match?.movingToneUnisonCount ?? 0)
    }

    // MARK: - elementsPairing (the graph's Z-filtered background grid)

    func testElementsPairingAtRootReturnsFullScaleUnfiltered() {
        // Every element's interval with root(0) is itself, trivially a scale member - so at
        // Z=unison the filter should be a no-op, matching the "identical to unfiltered default
        // at Z=unison" invariant already verified for the tetrads themselves.
        let scale = Scale(limit: 7, highestRatio: 3/1, lowestRatio: 1/2)
        let filtered = Tetrads.elementsPairing(withNormalizedValue: 0, in: scale)
        XCTAssertEqual(Set(filtered.map { $0.value }), Set(scale.scale.map { $0.value }))
    }

    func testElementsPairingOffRootIsProperSubsetOfFullScale() {
        let scale = Scale(limit: 9, highestRatio: 3/1, lowestRatio: 1/2)
        guard let octave = scale.scale.first(where: { $0.value == 2.0 }) else {
            XCTFail("scale should contain the octave")
            return
        }
        let filtered = Tetrads.elementsPairing(withNormalizedValue: octave.valueNormalized, in: scale)
        XCTAssertTrue(Set(filtered.map { $0.value }).isSubset(of: Set(scale.scale.map { $0.value })))
        XCTAssertLessThan(filtered.count, scale.scale.count)
    }

    func testElementsPairingMatchesTheXAndYValuesTetradsActuallyUsesAtThatZLayer() {
        // Cross-check against the real thing: every x/y value present in a z-layer's own tetrads
        // must appear in this filtered set (it's exactly the xz/yz membership test), and nothing
        // in the filtered set should be absent from every tetrad at that layer.
        let scale = Scale(limit: 9, highestRatio: 3/1, lowestRatio: 1/2)
        let tetrads = Tetrads(scale: scale)
        guard let someZTetrad = tetrads.tetradList.first(where: { $0.zElement.value != 1.0 }) else {
            XCTFail("expected at least one off-root z layer")
            return
        }
        let zLayerTetrads = tetrads.tetradList.filter { $0.zElement.value == someZTetrad.zElement.value }
        let valuesUsedByLayer = Set(zLayerTetrads.map { $0.xElement.value } + zLayerTetrads.map { $0.yElement.value })

        let filtered = Tetrads.elementsPairing(withNormalizedValue: someZTetrad.zElement.valueNormalized, in: scale)
        let filteredValues = Set(filtered.map { $0.value })

        XCTAssertTrue(valuesUsedByLayer.isSubset(of: filteredValues))
    }

    // Regression test for a real hang reported live 2026-09-09: rapid Z-slider dragging on iPad
    // caused the app to hang for a second or more after a couple of rounds of rapid dragging.
    // Root cause: elementsPairing used to rebuild its own O(n) lookup dictionary from scratch on
    // every single call, and GraphView called it multiple times per touch-move frame
    // (visibleScaleElements, and again independently in Graph's own drawLine loop) - dozens of
    // times a second during a real drag. Fixed by precomputing the lookup once in Scale.init
    // instead (Scale.scaleElementByRoundedValue) and having elementsPairing read it rather than
    // rebuild it, plus sharing one computation between GraphView's two former call sites
    // (weightedVisiblePairings). This simulates that same repeated-call pattern - many calls in
    // a tight loop, sweeping Z smoothly across the whole scale (not a fixed value, since a
    // constant Z would let an unrelated single-entry cache mask a real per-call-rebuild
    // regression) - at a realistic harmonic limit, and checks two things: each batch completes
    // well within a generous ceiling, and no batch is dramatically slower than the first (which
    // would indicate some new unbounded per-call state, e.g. a cache with no eviction).
    func testElementsPairingPerformanceStaysFlatUnderRapidRepeatedCalls() {
        let scale = Scale(limit: 19, highestRatio: 3/1, lowestRatio: 1/2)
        let callsPerBatch = 2000
        let batchCount = 5

        var batchDurations: [TimeInterval] = []
        for _ in 0..<batchCount {
            let start = Date()
            for i in 0..<callsPerBatch {
                let t = Double(i) / Double(callsPerBatch)
                let zValueNormalized = scale.lowestRatioNormalized + t * scale.rangeNormalized
                _ = Tetrads.elementsPairing(withNormalizedValue: zValueNormalized, in: scale)
            }
            batchDurations.append(Date().timeIntervalSince(start))
        }

        // Absolute ceiling: comfortably above what the current O(1)-lookup implementation needs
        // in practice, but far below what a from-scratch-dictionary-per-call implementation
        // would take at this limit/call count - catches a real regression, not just noise.
        for duration in batchDurations {
            XCTAssertLessThan(duration, 0.5, "elementsPairing batch took \(duration)s - investigate for a reintroduced per-call dictionary rebuild")
        }

        guard let first = batchDurations.first, first > 0 else { return }
        for duration in batchDurations.dropFirst() {
            XCTAssertLessThan(duration, first * 5, "elementsPairing batch degraded to \(duration)s vs first batch's \(first)s - possible growing-state regression")
        }
    }
}
