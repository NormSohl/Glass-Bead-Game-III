import XCTest
@testable import GBGCore

final class TimeEntryTests: XCTestCase {
    private let sampleRate = 48000.0
    // 120 BPM: a beat is 0.5s = 24000 samples; sixteenths are 6000.
    private func grid(subdivision: Int = 4, beatsPerBar: Int = 4, downbeat: Int = 0, bpm: Double = 120) -> TimeGrid {
        TimeGrid(tempo: TempoInfo(bpm: bpm, downbeatOffset: downbeat, confidence: 1), beatsPerBar: beatsPerBar, subdivision: subdivision, sampleRate: sampleRate)
    }

    func testParseBarBeatDivision() {
        let g = grid()
        XCTAssertEqual(TimeText.parse("1", grid: g, sampleRate: sampleRate), 0)
        XCTAssertEqual(TimeText.parse("2", grid: g, sampleRate: sampleRate), 96000)
        XCTAssertEqual(TimeText.parse("2.3", grid: g, sampleRate: sampleRate), 96000 + 48000)
        XCTAssertEqual(TimeText.parse("2.3.2", grid: g, sampleRate: sampleRate), 96000 + 48000 + 6000)
        XCTAssertEqual(TimeText.parse(" 1.1.4 ", grid: g, sampleRate: sampleRate), 18000)
    }

    func testParseHonorsDownbeatOffset() {
        XCTAssertEqual(TimeText.parse("1.2", grid: grid(downbeat: 1000), sampleRate: sampleRate), 25000)
    }

    func testParseRejectsOutOfRangeAndGarbage() {
        let g = grid()
        for bad in ["0", "1.5", "1.0", "1.1.5", "1.1.1.1", "1..2", "a.b", "", "-1"] {
            XCTAssertNil(TimeText.parse(bad, grid: g, sampleRate: sampleRate), bad)
        }
    }

    func testSecondsWithSuffixWorkEitherWay() {
        XCTAssertEqual(TimeText.parse("1.25s", grid: grid(), sampleRate: sampleRate), 60000)
        XCTAssertEqual(TimeText.parse("1.25 S", grid: nil, sampleRate: sampleRate), 60000)
        XCTAssertEqual(TimeText.parse("1.25", grid: nil, sampleRate: sampleRate), 60000)
        XCTAssertNil(TimeText.parse("-1s", grid: nil, sampleRate: sampleRate))
        XCTAssertNil(TimeText.parse("1.2.3", grid: nil, sampleRate: sampleRate))
    }

    func testFormatOnGrid() {
        let g = grid()
        XCTAssertEqual(TimeText.format(0, grid: g, sampleRate: sampleRate), "1.1.1")
        XCTAssertEqual(TimeText.format(96000 + 48000 + 6000, grid: g, sampleRate: sampleRate), "2.3.2")
        XCTAssertEqual(TimeText.format(24000, grid: grid(subdivision: 1), sampleRate: sampleRate), "1.2")
    }

    func testFormatOffGridFallsBackToSuffixedSeconds() {
        XCTAssertEqual(TimeText.format(60001, grid: grid(), sampleRate: sampleRate), "1.250s")
        XCTAssertEqual(TimeText.format(60000, grid: nil, sampleRate: sampleRate), "1.250")
    }

    func testRoundTripIncludingTriplets() {
        // 1/3-beat divisions at 100 BPM don't land on whole samples - format must still read
        // back exactly what parse produced.
        let g = grid(subdivision: 3, beatsPerBar: 3, bpm: 100)
        for text in ["1.1.1", "1.2.3", "4.3.2", "17.1.2"] {
            let sample = TimeText.parse(text, grid: g, sampleRate: sampleRate)!
            XCTAssertEqual(TimeText.format(sample, grid: g, sampleRate: sampleRate), text)
        }
    }

    func testOffGridSecondsRoundTrip() {
        let g = grid()
        let text = TimeText.format(12345, grid: g, sampleRate: sampleRate)
        XCTAssertTrue(text.hasSuffix("s"))
        let back = TimeText.parse(text, grid: g, sampleRate: sampleRate)!
        XCTAssertLessThanOrEqual(abs(back - 12345), Int(sampleRate / 1000))
    }
}
