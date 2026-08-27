import XCTest
@testable import GBGCore

final class DissonanceTests: XCTestCase {

    // MARK: harmonicWeight (1/n falloff)

    func testHarmonicWeightIsOneAtFundamental() {
        XCTAssertEqual(Dissonance.harmonicWeight(1), 1.0)
    }

    func testHarmonicWeightFallsOffAsOneOverN() {
        XCTAssertEqual(Dissonance.harmonicWeight(2), 0.5)
        XCTAssertEqual(Dissonance.harmonicWeight(4), 0.25)
        XCTAssertEqual(Dissonance.harmonicWeight(19), 1.0 / 19.0, accuracy: 0.0000001)
    }

    // MARK: harmonicFrequency

    func testHarmonicFrequencyIsFundamentalTimesHarmonicNumber() {
        XCTAssertEqual(Dissonance.harmonicFrequency(fundamental: 100, harmonicNumber: 1), 100)
        XCTAssertEqual(Dissonance.harmonicFrequency(fundamental: 100, harmonicNumber: 3), 300)
    }

    // MARK: roughness(beatRate:) - the Gaussian bell

    func testRoughnessPeaksAtThirtyBeatsPerSecond() {
        XCTAssertEqual(Dissonance.roughness(beatRate: 30), 1.0, accuracy: 0.0000001)
    }

    func testRoughnessIsSymmetricAroundThePeak() {
        XCTAssertEqual(Dissonance.roughness(beatRate: 20), Dissonance.roughness(beatRate: 40), accuracy: 0.0000001)
        XCTAssertEqual(Dissonance.roughness(beatRate: 10), Dissonance.roughness(beatRate: 50), accuracy: 0.0000001)
    }

    func testRoughnessTapersToPracticallyZeroAtUnisonAndBySixty() {
        XCTAssertLessThan(Dissonance.roughness(beatRate: 0), 0.02)
        XCTAssertLessThan(Dissonance.roughness(beatRate: 60), 0.02)
    }

    func testRoughnessStaysLowWellBeyondSixty() {
        XCTAssertLessThan(Dissonance.roughness(beatRate: 200), 0.0001)
    }

    func testRoughnessIsNeverNegative() {
        for beatRate in stride(from: -50.0, through: 200.0, by: 5.0) {
            XCTAssertGreaterThanOrEqual(Dissonance.roughness(beatRate: beatRate), 0.0)
        }
    }

    // MARK: pairwiseRoughness

    func testPairwiseRoughnessIsRoughnessScaledByBothWeights() {
        let result = Dissonance.pairwiseRoughness(freqA: 200, weightA: 0.5, freqB: 230, weightB: 0.25)
        let expected = Dissonance.roughness(beatRate: 30) * 0.5 * 0.25
        XCTAssertEqual(result, expected, accuracy: 0.0000001)
    }

    func testPairwiseRoughnessUsesAbsoluteBeatRate() {
        // order of A/B frequencies shouldn't matter - only the gap between them does
        let forward = Dissonance.pairwiseRoughness(freqA: 200, weightA: 1, freqB: 230, weightB: 1)
        let backward = Dissonance.pairwiseRoughness(freqA: 230, weightA: 1, freqB: 200, weightB: 1)
        XCTAssertEqual(forward, backward, accuracy: 0.0000001)
    }

    // MARK: roughnessBetweenTones

    func testRoughnessBetweenTonesAtUnisonWithSingleHarmonicMatchesDirectCalculation() {
        // limit 1 means only the fundamentals are compared - unison means beat rate 0
        let result = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 200, limit: 1)
        XCTAssertEqual(result, Dissonance.roughness(beatRate: 0), accuracy: 0.0000001)
    }

    func testRoughnessBetweenTonesHitsPeakWhenFundamentalsAreThirtyHertzApart() {
        // limit 1: only the fundamentals (weight 1 each) are compared, 30 Hz apart is the peak
        let result = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 230, limit: 1)
        XCTAssertEqual(result, 1.0, accuracy: 0.0000001)
    }

    func testRoughnessBetweenTonesIsSymmetricInItsArguments() {
        let forward = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 260, limit: 5)
        let backward = Dissonance.roughnessBetweenTones(frequencyA: 260, frequencyB: 200, limit: 5)
        XCTAssertEqual(forward, backward, accuracy: 0.0000001)
    }

    func testRoughnessBetweenTonesNeverDecreasesAsLimitGrows() {
        // every added harmonic pair contributes a non-negative term
        let atLimitOne = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: 1)
        let atLimitFive = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: 5)
        let atLimitNineteen = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: 19)
        XCTAssertLessThanOrEqual(atLimitOne, atLimitFive)
        XCTAssertLessThanOrEqual(atLimitFive, atLimitNineteen)
    }

    // MARK: totalRoughness

    func testTotalRoughnessIsTheSumOfAllThreePairwiseTonePairs() {
        let root = 200.0, x = 260.0, y = 340.0
        let limit = 7

        let expected = Dissonance.roughnessBetweenTones(frequencyA: root, frequencyB: x, limit: limit)
            + Dissonance.roughnessBetweenTones(frequencyA: root, frequencyB: y, limit: limit)
            + Dissonance.roughnessBetweenTones(frequencyA: x, frequencyB: y, limit: limit)

        let result = Dissonance.totalRoughness(rootFrequency: root, xFrequency: x, yFrequency: y, limit: limit)
        XCTAssertEqual(result, expected, accuracy: 0.0000001)
    }

    func testTotalRoughnessAtUnisonTriadIsLowerThanASpreadOutTriad() {
        // root, X, and Y all on top of each other: every pairwise beat rate involving the
        // fundamentals is 0 (near-zero roughness). A triad whose fundamentals sit ~30 Hz
        // apart lands pairwise roughness right at the peak, so it should score higher.
        let root = 200.0
        let unison = Dissonance.totalRoughness(rootFrequency: root, xFrequency: root, yFrequency: root, limit: 1)
        let spread = Dissonance.totalRoughness(rootFrequency: root, xFrequency: root + 30, yFrequency: root + 60, limit: 1)
        XCTAssertLessThan(unison, spread)
    }
}
