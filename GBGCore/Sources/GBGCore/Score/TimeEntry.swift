//
//  TimeEntry.swift
//  GBGCore
//
//  Time parsing and display for Seq's note inspector. With a beat grid, positions read as
//  "bar.beat.division" (all 1-based, like a DAW), and seconds are written with an "s" suffix;
//  without one, everything is plain seconds.
//

import Foundation

public struct TimeGrid {
    public let tempo: TempoInfo
    public let beatsPerBar: Int
    /// Divisions per beat - the snap resolution (1 = beats, 4 = sixteenths in 4/4).
    public let subdivision: Int
    public let sampleRate: Double

    public init(tempo: TempoInfo, beatsPerBar: Int, subdivision: Int, sampleRate: Double) {
        self.tempo = tempo
        self.beatsPerBar = max(1, beatsPerBar)
        self.subdivision = max(1, subdivision)
        self.sampleRate = sampleRate
    }

    var divisionSamples: Double { 60.0 / tempo.bpm * sampleRate / Double(subdivision) }

    /// Sample time of grid division `index` (0 = the downbeat), rounded the same way Seq's
    /// grid snap rounds, so a snapped note reads back as an exact grid position.
    func sample(atDivision index: Int) -> Int {
        tempo.downbeatOffset + Int((Double(index) * divisionSamples).rounded())
    }
}

public enum TimeText {
    /// "bar.beat.division" for a sample exactly on the grid ("bar.beat" when the grid's
    /// subdivision is whole beats), or nil if it falls between divisions.
    public static func gridPosition(_ sample: Int, grid: TimeGrid) -> String? {
        guard grid.divisionSamples > 0 else { return nil }
        let index = Int(((Double(sample - grid.tempo.downbeatOffset)) / grid.divisionSamples).rounded())
        guard grid.sample(atDivision: index) == sample else { return nil }
        let perBar = grid.beatsPerBar * grid.subdivision
        let bar = Int((Double(index) / Double(perBar)).rounded(.down))
        let withinBar = index - bar * perBar
        let beat = withinBar / grid.subdivision + 1
        let division = withinBar % grid.subdivision + 1
        return grid.subdivision > 1 ? "\(bar + 1).\(beat).\(division)" : "\(bar + 1).\(beat)"
    }

    /// What the inspector shows: the grid position when there's a grid and the time is on it,
    /// otherwise seconds - "1.250s" with a grid (so it can't be mistaken for bar.beat), "1.250"
    /// without one.
    public static func format(_ sample: Int, grid: TimeGrid?, sampleRate: Double) -> String {
        let seconds = String(format: "%.3f", Double(sample) / sampleRate)
        guard let grid else { return seconds }
        return gridPosition(sample, grid: grid) ?? seconds + "s"
    }

    /// Parses a typed time into a sample position (never negative). Seconds always work with an
    /// "s" suffix ("1.25s"). With a grid, unsuffixed input is a grid position: "3" (bar),
    /// "3.2" (bar.beat), "3.2.4" (bar.beat.division), each part a whole number, beat within
    /// beatsPerBar and division within the subdivision. Without a grid, unsuffixed input is
    /// seconds. Nil for anything else.
    public static func parse(_ text: String, grid: TimeGrid?, sampleRate: Double) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("s") || grid == nil {
            let number = trimmed.hasSuffix("s") ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed
            guard let seconds = Double(number), seconds >= 0, seconds.isFinite else { return nil }
            return Int((seconds * sampleRate).rounded())
        }
        guard let grid else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), !parts.contains(nil) else { return nil }
        let bar = parts[0]!
        let beat = parts.count > 1 ? parts[1]! : 1
        let division = parts.count > 2 ? parts[2]! : 1
        guard bar >= 1, (1...grid.beatsPerBar).contains(beat), (1...grid.subdivision).contains(division) else { return nil }
        let index = ((bar - 1) * grid.beatsPerBar + (beat - 1)) * grid.subdivision + (division - 1)
        return max(0, grid.sample(atDivision: index))
    }
}
