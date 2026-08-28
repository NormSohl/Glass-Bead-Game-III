import XCTest
@testable import GBGCore

final class ScoreTests: XCTestCase {

    private func makeScoreWithThreeParts() -> (score: Score, drone: Part, x: Part, y: Part) {
        let score = Score(name: "test", beatsPerMin: 120)
        let drone = Part(name: "drone")
        let x = Part(name: "x")
        let y = Part(name: "y")
        score.addPart(drone)
        score.addPart(x)
        score.addPart(y)
        return (score, drone, x, y)
    }

    func testGetTriadNotesMapsPartsInOrder() {
        let (score, drone, x, y) = makeScoreWithThreeParts()

        let triadParts = score.getTriadNotes(timeSlice: 0)

        XCTAssertTrue(triadParts.drone === drone)
        XCTAssertTrue(triadParts.x === x)
        XCTAssertTrue(triadParts.y === y)
    }

    func testGetLengthInSamplesIsTheLongestPart() {
        let (score, drone, x, y) = makeScoreWithThreeParts()
        drone.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
        x.insertNote(startTime: 0, endTime: 500, startFrequency: 440, endFrequency: 440, amplitude: 1)
        y.insertNote(startTime: 0, endTime: 300, startFrequency: 330, endFrequency: 330, amplitude: 1)

        XCTAssertEqual(score.getLengthInSamples(), 500)
    }

    // Chord identity is defined purely by shared startTime across Parts (no linking object), so
    // ripple time edits have to shift every Part in lockstep - otherwise notes that used to
    // sound together would drift apart in absolute time.
    func testInsertTimeShiftsEveryPartInLockstepKeepingChordsAligned() {
        let (score, drone, x, y) = makeScoreWithThreeParts()
        for part in [drone, x, y] {
            part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
            part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)
        }

        score.insertTime(at: 100, duration: 50)

        for part in [drone, x, y] {
            XCTAssertEqual(part.notes[1].startTime, 150)
            XCTAssertEqual(part.notes[1].endTime, 250)
        }
    }

    func testDeleteTimeShiftsEveryPartInLockstep() {
        let (score, drone, x, y) = makeScoreWithThreeParts()
        for part in [drone, x, y] {
            part.insertNote(startTime: 0, endTime: 100, startFrequency: 220, endFrequency: 220, amplitude: 1)
            part.insertNote(startTime: 100, endTime: 200, startFrequency: 440, endFrequency: 440, amplitude: 1)
            part.insertNote(startTime: 200, endTime: 300, startFrequency: 330, endFrequency: 330, amplitude: 1)
        }

        score.deleteTime(from: 100, duration: 100)

        for part in [drone, x, y] {
            XCTAssertEqual(part.notes.count, 2)
            XCTAssertEqual(part.notes[1].startTime, 100)
            XCTAssertEqual(part.notes[1].startFrequency, 330)
        }
    }
}
