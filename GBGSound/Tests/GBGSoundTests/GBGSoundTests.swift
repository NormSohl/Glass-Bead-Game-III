import XCTest
@testable import GBGSound

final class GBGSoundTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }

    // Diagnostic, not a regression test: renders a single Tone's envelope sample-by-sample and
    // prints it, to directly verify (rather than trust by ear) that the attack/decay/sustain
    // shape and the onset click are actually doing what Tone.swift's comments say. Never calls
    // incrementPhase(), so currentPhase stays at its initial 0 and Sine.getValue(phase: 0) is
    // exactly 0 for every sample - that isolates getValue()'s raw return to just the click term
    // (nextNoise() * clickEnvelope * clickGainFraction * peakAmplitude), with the tone term
    // contributing nothing to interfere with reading it off directly.
    func testCaptureOnsetEnvelope() {
        let sampleRate = 44100.0
        let peak = 1.0
        let tone = Tone(sampleRate: sampleRate, frequency: 440, amplitude: 0, onsetDelaySeconds: 0, noiseSeed: 0xABCD_1234)
        tone.setAmplitude(inAmplitude: peak) // simulate note-on

        var amplitudeTrace: [(sample: Int, amplitude: Double)] = []
        var clickMagnitudeTrace: [(sample: Int, click: Double)] = []
        let sampleCount = Int(0.1 * sampleRate) // 100ms - comfortably past attack+decay+click

        for i in 0..<sampleCount {
            let rawValue = tone.getValue() // phase never advances, so this is the click alone
            if i % 50 == 0 || i < 20 {
                amplitudeTrace.append((i, tone.amplitude))
                clickMagnitudeTrace.append((i, abs(rawValue)))
            }
        }

        print("=== Tone envelope capture (peak=\(peak)) ===")
        for (sample, amplitude) in amplitudeTrace {
            let ms = Double(sample) / sampleRate * 1000
            print(String(format: "sample %5d (%6.2fms): amplitude = %.4f", sample, ms, amplitude))
        }
        print("=== Click magnitude (|getValue()| with phase fixed at 0, i.e. tone term = 0) ===")
        for (sample, click) in clickMagnitudeTrace {
            let ms = Double(sample) / sampleRate * 1000
            print(String(format: "sample %5d (%6.2fms): |click| = %.4f", sample, ms, click))
        }

        // Attack: amplitude should reach very close to peak within a few ms (attackSeconds ~3ms).
        // Decay: a 30ms time constant needs ~5 time constants (~150ms) to settle within 1% of
        // sustain, so the settling check needs a longer run than the 100ms capture above.
        let attackCheckSample = Int(0.01 * sampleRate) // 10ms, several attack time-constants in
        let decaySettleSampleCount = Int(0.25 * sampleRate) // 250ms
        var toneAtAttackCheck = 0.0
        let tone2 = Tone(sampleRate: sampleRate, frequency: 440, amplitude: 0, onsetDelaySeconds: 0, noiseSeed: 0xABCD_1234)
        tone2.setAmplitude(inAmplitude: peak)
        for i in 0..<decaySettleSampleCount {
            _ = tone2.getValue()
            if i == attackCheckSample { toneAtAttackCheck = tone2.amplitude }
        }
        let toneAfterDecay = tone2.amplitude

        XCTAssertGreaterThan(toneAtAttackCheck, peak * 0.9, "expected amplitude to have reached near peak by 10ms")
        XCTAssertEqual(toneAfterDecay, peak * 0.55, accuracy: peak * 0.01, "expected amplitude to have settled at the 55% sustain level by 250ms")

        // Click: should be large (order of clickGainFraction * peak) in the first sample, and
        // negligible (settled well below 1% of its starting scale) by clickSeconds' tail.
        let tone3 = Tone(sampleRate: sampleRate, frequency: 440, amplitude: 0, onsetDelaySeconds: 0, noiseSeed: 0xABCD_1234)
        tone3.setAmplitude(inAmplitude: peak)
        let firstClick = abs(tone3.getValue())
        for _ in 0..<Int(0.08 * sampleRate) { _ = tone3.getValue() } // run out past the click's decay
        let lateClick = abs(tone3.getValue())

        print("=== Click first-sample magnitude: \(firstClick), late (80ms) magnitude: \(lateClick) ===")
        // Threshold is well below clickGainFraction (currently 0.075, halved twice by ear since
        // this test was written) rather than tied to it, since a uniform -1...1 noise sample's
        // magnitude is only ~half of that gain on average and this seed's actual first sample
        // (~0.0415) should stay comfortably clear of it.
        XCTAssertGreaterThan(firstClick, 0.02, "expected an audible click magnitude right at onset")
        XCTAssertLessThan(lateClick, firstClick * 0.05, "expected the click to have decayed away well before 80ms")
    }
}
