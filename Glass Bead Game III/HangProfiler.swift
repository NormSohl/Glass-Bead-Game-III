//
//  HangProfiler.swift
//  Glass Bead Game III
//
//  Temporary diagnostic instrumentation for the rapid-Z-drag hang investigation (2026-09-09/10).
//  Started via the DEVICECTL_CHILD_HANGPROFILE=1 launch environment variable (set from the Mac
//  via `devicectl device process launch -e`), records into a preallocated in-memory buffer (no
//  file I/O during capture, so the act of recording doesn't itself perturb the timing) for a
//  fixed window, then flushes once to Documents/hangprofile.csv for retrieval via
//  `devicectl device copy from --domain-type appDataContainer`. Not wired into any UI - remove
//  once the investigation concludes.
//

import Foundation

final class HangProfiler {
    static let shared = HangProfiler()

    private struct Entry {
        let offsetMs: Double
        let label: StaticString
        let durationMs: Double
    }

    private var entries: [Entry] = []
    private var isRecording = false
    private var startTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    private init() {
        entries.reserveCapacity(50_000)
    }

    func startIfRequested() {
        guard ProcessInfo.processInfo.environment["HANGPROFILE"] == "1" else { return }
        lock.lock()
        isRecording = true
        startTime = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            self?.stopAndWrite()
        }
    }

    // Marks the instant UIKit hands this app a raw touch event, before any app logic runs -
    // used to test whether touch DELIVERY itself stalls during the hang (upstream of this app
    // entirely) versus events arriving normally while something downstream (SwiftUI, this app's
    // own code) fails to act on them. See measure()'s own per-call timing for the latter.
    @inline(__always)
    func recordRawEvent(_ label: StaticString) {
        guard isRecording else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        entries.append(Entry(offsetMs: (now - startTime) * 1000, label: label, durationMs: 0))
        lock.unlock()
    }

    @inline(__always)
    func measure<T>(_ label: StaticString, _ body: () -> T) -> T {
        guard isRecording else { return body() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = body()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        lock.lock()
        entries.append(Entry(offsetMs: (start - startTime) * 1000, label: label, durationMs: elapsed))
        lock.unlock()
        return result
    }

    private func stopAndWrite() {
        lock.lock()
        isRecording = false
        let snapshot = entries
        lock.unlock()

        var csv = "offset_ms,label,duration_ms\n"
        for entry in snapshot {
            csv += "\(entry.offsetMs),\(entry.label),\(entry.durationMs)\n"
        }

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent("hangprofile.csv")
        try? csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
