import XCTest
@testable import GBGSound

final class GBGSoundTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }

    // Covers the ADSR envelope (reintroduced 2026-09-07 without the noise-click transient that
    // shipped alongside it the first time - see Tone.swift's own header comment), the onset-delay
    // hold used for Triad's per-voice onset stagger, and a genuine re-strike via retrigger().
    func testOnsetEnvelopeShape() {
        let sampleRate = 44100.0
        let peak = 1.0
        let onsetDelaySeconds = 0.02
        let tone = Tone(sampleRate: sampleRate, frequency: 440, amplitude: 0, onsetDelaySeconds: onsetDelaySeconds)
        tone.setAmplitude(inAmplitude: peak) // simulate note-on

        let onsetDelaySamples = Int((onsetDelaySeconds * sampleRate).rounded())
        for i in 0..<onsetDelaySamples {
            XCTAssertEqual(tone.getValue(), 0, "expected held silence through the onset delay (sample \(i))")
        }

        // Attack: amplitude should reach very close to peak within a few ms (attackSeconds ~3ms).
        for _ in 0..<Int(0.01 * sampleRate) { _ = tone.getValue() }
        XCTAssertGreaterThan(tone.amplitude, peak * 0.9, "expected amplitude to have reached near peak by 10ms after the onset delay")

        // Decay: a 30ms time constant needs ~5 time constants (~150ms) to settle within 1% of
        // sustain (55% of peak).
        for _ in 0..<Int(0.25 * sampleRate) { _ = tone.getValue() }
        XCTAssertEqual(tone.amplitude, peak * 0.55, accuracy: peak * 0.01, "expected amplitude to have settled at the 55% sustain level")

        // retrigger() should force a fresh attack even though the voice never went silent - the
        // pedal-hold re-strike case.
        tone.retrigger()
        for _ in 0..<Int(0.01 * sampleRate) { _ = tone.getValue() }
        XCTAssertGreaterThan(tone.amplitude, peak * 0.9, "expected retrigger() to force a fresh attack back toward peak")
    }

    func testFrequencyPortamentoGlidesRatherThanSnaps() {
        let sampleRate = 44100.0
        let tone = Tone(sampleRate: sampleRate, frequency: 440, amplitude: 1)
        tone.setAmplitude(inAmplitude: 1)
        for _ in 0..<Int(0.05 * sampleRate) { _ = tone.getValue(); tone.incrementPhase() }

        let phaseIncrementBefore = tone.phaseIncrement
        tone.setPitch(inFrequency: 880) // an octave jump
        _ = tone.getValue()
        tone.incrementPhase()
        let phaseIncrementAfterOneSample = tone.phaseIncrement

        // A true instant snap would already equal the target on the very next sample; the
        // portamento should still be partway there.
        let targetPhaseIncrement = (2 * Double.pi / sampleRate) * 880
        XCTAssertNotEqual(phaseIncrementAfterOneSample, targetPhaseIncrement, "expected the frequency change to glide, not snap, on the first sample")
        XCTAssertGreaterThan(phaseIncrementAfterOneSample, phaseIncrementBefore, "expected phaseIncrement to be moving toward the higher target frequency")

        for _ in 0..<Int(0.05 * sampleRate) { _ = tone.getValue(); tone.incrementPhase() }
        XCTAssertEqual(tone.phaseIncrement, targetPhaseIncrement, accuracy: targetPhaseIncrement * 0.01, "expected the glide to have settled at the target frequency well within 50ms")
    }
}
