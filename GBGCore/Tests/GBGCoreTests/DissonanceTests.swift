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

    // MARK: linearHarmonicWeight (alternative to 1/n)

    func testLinearHarmonicWeightIsOneAtFundamental() {
        XCTAssertEqual(Dissonance.linearHarmonicWeight(1, limit: 11), 1.0, accuracy: 0.0000001)
    }

    func testLinearHarmonicWeightIsOneOverLimitAtTheLimit() {
        XCTAssertEqual(Dissonance.linearHarmonicWeight(11, limit: 11), 1.0 / 11.0, accuracy: 0.0000001)
    }

    func testLinearHarmonicWeightDecreasesMonotonically() {
        let limit = 11
        var previous = Double.greatestFiniteMagnitude
        for n in 1...limit {
            let weight = Dissonance.linearHarmonicWeight(n, limit: limit)
            XCTAssertLessThan(weight, previous)
            previous = weight
        }
    }

    func testLinearHarmonicWeightStaysAboveOneOverNForMiddleHarmonics() {
        // the whole point of trying this weighting: middle harmonics should carry more
        // relative weight than the curved 1/n falloff gives them
        let limit = 11
        for n in 2..<limit {
            XCTAssertGreaterThan(Dissonance.linearHarmonicWeight(n, limit: limit), Dissonance.harmonicWeight(n))
        }
    }

    // MARK: harmonicFrequency

    func testHarmonicFrequencyIsFundamentalTimesHarmonicNumber() {
        XCTAssertEqual(Dissonance.harmonicFrequency(fundamental: 100, harmonicNumber: 1), 100)
        XCTAssertEqual(Dissonance.harmonicFrequency(fundamental: 100, harmonicNumber: 3), 300)
    }

    // MARK: roughness(beatRate:) - the Gaussian bell

    func testRoughnessPeaksAtThePeakBeatRate() {
        XCTAssertEqual(Dissonance.roughness(beatRate: Dissonance.peakRoughnessBeatRate), 1.0, accuracy: 0.0000001)
    }

    func testRoughnessIsSymmetricAroundThePeak() {
        let peak = Dissonance.peakRoughnessBeatRate
        XCTAssertEqual(Dissonance.roughness(beatRate: peak - 10), Dissonance.roughness(beatRate: peak + 10), accuracy: 0.0000001)
        XCTAssertEqual(Dissonance.roughness(beatRate: peak - 20), Dissonance.roughness(beatRate: peak + 20), accuracy: 0.0000001)
    }

    func testRoughnessTapersToPracticallyZeroAtUnisonAndByTwiceThePeak() {
        XCTAssertLessThan(Dissonance.roughness(beatRate: 0), 0.02)
        XCTAssertLessThan(Dissonance.roughness(beatRate: 2 * Dissonance.peakRoughnessBeatRate), 0.02)
    }

    func testRoughnessStaysLowWellBeyondThePeak() {
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

    func testRoughnessBetweenTonesHitsPeakWhenFundamentalsAreThePeakBeatRateApart() {
        // limit 1: only the fundamentals (weight 1 each) are compared
        let result = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 200 + Dissonance.peakRoughnessBeatRate, limit: 1)
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

    // MARK: pluggable weighting scheme

    func testRoughnessBetweenTonesDefaultsToLinearWeighting() {
        let limit = 5
        let withDefault = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: limit)
        let withExplicitLinear = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: limit, weighting: { Dissonance.linearHarmonicWeight($0, limit: limit) })
        XCTAssertEqual(withDefault, withExplicitLinear, accuracy: 0.0000001)
    }

    func testLinearWeightingDiffersFromOneOverNWeighting() {
        let limit = 5
        let oneOverN = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: limit, weighting: Dissonance.harmonicWeight)
        let linear = Dissonance.roughnessBetweenTones(frequencyA: 200, frequencyB: 250, limit: limit, weighting: { Dissonance.linearHarmonicWeight($0, limit: limit) })
        XCTAssertNotEqual(oneOverN, linear, accuracy: 0.0000001)
    }

    func testRoughnessGridAcceptsACustomWeighting() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let limit = 5
        let oneOverN = Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: limit, resolution: 6, weighting: Dissonance.harmonicWeight)
        let linear = Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: limit, resolution: 6, weighting: { Dissonance.linearHarmonicWeight($0, limit: limit) })
        XCTAssertNotEqual(oneOverN[3][3], linear[3][3], accuracy: 0.0000001)
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

    // MARK: roughnessGrid

    func testRoughnessGridHasRequestedDimensions() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let grid = Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: 5, resolution: 10)
        XCTAssertEqual(grid.count, 10)
        for row in grid {
            XCTAssertEqual(row.count, 10)
        }
    }

    func testRoughnessGridIsEmptyForInvalidInputs() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        XCTAssertTrue(Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: 5, resolution: 0).isEmpty)
        XCTAssertTrue(Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: 0, resolution: 10).isEmpty)
    }

    func testRoughnessGridValuesAreNeverNegative() {
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let grid = Dissonance.roughnessGrid(scale: scale, rootFrequency: 261.63, limit: 5, resolution: 10)
        for row in grid {
            for value in row {
                XCTAssertGreaterThanOrEqual(value, 0.0)
            }
        }
    }

    func testRoughnessGridCellMatchesDirectFrequencyMapping() {
        // spot-check that grid[row][col] corresponds to the frequency you'd get by mapping
        // that cell's center fraction through the same lowest/range normalization Scale uses
        let scale = Scale(limit: 5, highestRatio: 2.0, lowestRatio: 0.5)
        let rootFrequency = 200.0
        let limit = 5
        let resolution = 8
        let grid = Dissonance.roughnessGrid(scale: scale, rootFrequency: rootFrequency, limit: limit, resolution: resolution)

        let row = 3, col = 6
        let yFraction = (Double(row) + 0.5) / Double(resolution)
        let xFraction = (Double(col) + 0.5) / Double(resolution)
        let yFrequency = rootFrequency * pow(2, scale.lowestRatioNormalized + scale.rangeNormalized * yFraction)
        let xFrequency = rootFrequency * pow(2, scale.lowestRatioNormalized + scale.rangeNormalized * xFraction)
        let expected = Dissonance.totalRoughness(rootFrequency: rootFrequency, xFrequency: xFrequency, yFrequency: yFrequency, limit: limit)

        XCTAssertEqual(grid[row][col], expected, accuracy: 0.0000001)
    }

    func testTotalRoughnessAtUnisonTriadIsLowerThanASpreadOutTriad() {
        // root, X, and Y all on top of each other: every pairwise beat rate involving the
        // fundamentals is 0 (near-zero roughness). A triad whose fundamentals sit one and two
        // peak-beat-rates apart lands pairwise roughness right at the peak, so it should score higher.
        let root = 200.0
        let peak = Dissonance.peakRoughnessBeatRate
        let unison = Dissonance.totalRoughness(rootFrequency: root, xFrequency: root, yFrequency: root, limit: 1)
        let spread = Dissonance.totalRoughness(rootFrequency: root, xFrequency: root + peak, yFrequency: root + 2 * peak, limit: 1)
        XCTAssertLessThan(unison, spread)
    }
}
