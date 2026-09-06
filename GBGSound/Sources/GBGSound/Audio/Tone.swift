//
//  Tone.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation

class Tone{

    // signal. This returns a wave based on the phase input value. Phase is in range 0 to twoPi. Return is in range -1 to 1
    let signal:WaveForm = Sine()//SawToothDown() //is default Additive()
    var sampleRate:Double = 44100.0 {
        didSet {
            updateAmplitudeSmoothingCoefficients()
            updateOnsetDelaySamples()
        }
    }

    // Silence held for this long after a genuine onset (silence -> sounding) before the normal
    // amplitude ramp below is allowed to start - see Triad's per-voice values and comment for
    // why (breaking exact onset synchrony across the four voices of a chord). Zero by default:
    // only Triad's construction opts individual voices into this.
    var onsetDelaySeconds: Double = 0 {
        didSet { updateOnsetDelaySamples() }
    }
    private var onsetDelaySamples: Int = 0
    private var pendingOnsetSamples: Int = 0
    var phaseIncrement: Double = 0
    var currentPhase: Double = 0 // the phase of the waveform is 0 to twoPi. This is useful when calculating sine waves.
    // The amplitude actually applied to the waveform this sample - chases an ADSR shape rather
    // than jumping straight to targetAmplitude. setAmplitude used to write this directly, an
    // instantaneous step that (unless the waveform happened to be at a zero-crossing at that
    // exact instant, vanishingly unlikely) produced a real discontinuity in the output - an
    // audible click/pop, most noticeable exactly where live touch begins/ends
    // (Sound.enableTriadXTone etc. go straight from full amplitude to 0 or back). Same root
    // cause, same fix, as ScorePlayer's own amplitudeSmoothing (see that class's own comment for
    // the measured justification - a 0.134 sample-to-sample jump against a ~0.063 baseline for
    // an unsmoothed note boundary at a similar amplitude scale).
    //
    // Shape (confirmed by ear on 2026-09-05, tuned in two passes - "a bit of attack, fairly
    // rapid but not dramatic decay into sustain, release as it is now", then "more ping at the
    // start, faster attack"): on a genuine onset, amplitude rises toward peakAmplitude (the
    // value passed to setAmplitude) using attackSmoothingCoefficient for attackSamples samples
    // (see that var's own comment for why a fixed sample count, not "until it reaches peak"),
    // then decays to peakAmplitude * sustainLevelFraction using decaySmoothingCoefficient and
    // holds there; on note-off (targetAmplitude back to ~0), it falls to 0 using
    // releaseSmoothingCoefficient - unchanged from the original single-ramp behavior, since that
    // was already tuned specifically to avoid the measured click.
    var amplitude: Double = 0.0
    private var targetAmplitude: Double = 0.0
    private var peakAmplitude: Double = 0.0
    // Counts down the attack phase; decay starts once it hits 0. NOT "amplitude >= peakAmplitude"
    // - that was the original approach here, and it's wrong for a one-pole exponential rise,
    // which only asymptotically approaches its target and (in floating point) doesn't actually
    // satisfy >= until roughly 35-40 time constants in, not the ~1 time constant "attackSeconds"
    // is meant to represent. Confirmed directly: an offline capture of this exact code (see
    // GBGSoundTests.testCaptureOnsetEnvelope) showed amplitude still at 0.9999999999999927, not
    // yet >= peakAmplitude, 100ms after onset with attackSeconds = 0.003 - decay never got a
    // chance to run within any normal note's duration, which is exactly why the ADSR shape read
    // as "articulation... but not very plucky" no matter how the decay/sustain constants were
    // tuned. A fixed sample-count cutover (5 time constants, ~99.3% of the way there - close
    // enough that starting decay from here rather than exact peak is inaudible) fixes this
    // deterministically, the same style as pendingOnsetSamples's countdown above.
    private var attackSamples: Int = 0
    private var attackSamplesRemaining: Int = 0
    private var attackSmoothingCoefficient: Double = 0.0
    private var decaySmoothingCoefficient: Double = 0.0
    private var releaseSmoothingCoefficient: Double = 0.0
    private let sustainLevelFraction: Double = 0.55

    // A short, fast-decaying burst of noise layered on top of the amplitude envelope at each
    // onset - the actual "pluck"/"pick" bite the amplitude-only ADSR above can't provide on its
    // own. A pure sine's amplitude can be shaped as percussively as you like and it still won't
    // read as a pluck, because a real pluck's character comes from a bright, noisy transient in
    // the timbre itself (extra harmonic/broadband content right at the attack that dies away
    // fast), not just a fast volume swell - added 2026-09-05 after the ADSR shape alone still
    // read as "articulation... but not very plucky".
    private var clickEnvelope: Double = 0
    private var clickSmoothingCoefficient: Double = 0.0
    private let clickGainFraction: Double = 0.075
    // xorshift32 - deterministic, allocation-free, lock-free: safe to call every sample from the
    // realtime audio thread, unlike Swift's system RNG (Double.random), which isn't documented
    // as real-time safe. Must never be seeded 0 (xorshift's fixed point). Triad gives each of
    // its four Tones a distinct seed so their click bursts aren't identical.
    private var noiseState: UInt32

    // utility function
    let twoPi = 2 * Double.pi

    init(sampleRate:Double, frequency:Double, amplitude:Double, onsetDelaySeconds: Double = 0, noiseSeed: UInt32 = 1) {
        //setSampleRate (inSampleRate: sampleRate)
        self.noiseState = noiseSeed == 0 ? 1 : noiseSeed
        // Swift does NOT call didSet for assignments made from within a class's own
        // initializer (verified directly - it only fires for assignments from outside it), so
        // these two calls can't be left to sampleRate/onsetDelaySeconds's own didSet the way
        // setSampleRate()/the onsetDelaySeconds property setter do from outside init - they're
        // made explicitly here instead. (In practice Audio.swift's post-construction
        // setTriadSampleRate() call was already doing this "for free" from outside init, which
        // is why this was never audibly broken - but a Tone built and used without that
        // follow-up call, e.g. in a test, would otherwise silently stay silent forever.)
        self.sampleRate = sampleRate
        self.onsetDelaySeconds = onsetDelaySeconds
        updateAmplitudeSmoothingCoefficients()
        updateOnsetDelaySamples()
        setPitch (inFrequency: frequency)
        setAmplitude(inAmplitude: amplitude)
        self.amplitude = targetAmplitude // starting value has nothing to ramp from
        pendingOnsetSamples = 0 // starting value is applied directly above, not ramped - nothing to delay
        clickEnvelope = 0 // starting value is applied directly above, not ramped - no click on construction
        //print("Tone: init: amplitude = \(amplitude)")
    }

    private func nextNoise() -> Double {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return (Double(noiseState) / Double(UInt32.max)) * 2 - 1 // -1...1
    }

    func setPitch (inFrequency:Double){
        //print("setPitch called with fq of: ",frequency)
        // The interval to advance the phase each frame.
         phaseIncrement = (twoPi / sampleRate) * inFrequency  // how much does phase change given sample rate and fq.
        //print("setPitch. Frequency: ",inFrequency)
    }

    func setSampleRate(inSampleRate:Double){
        self.sampleRate = inSampleRate
    }

    // Release: a few milliseconds - same order of magnitude as ScorePlayer's own default
    // (amplitudeRampSeconds) - eliminates the click without perceptibly softening a deliberate
    // touch begin/end, which already reads as instantaneous at this timescale. Attack: slower
    // than release but still short - a soft onset, not a slow pad-style swell. Decay: fairly
    // rapid but not dramatic - noticeably quicker than the attack, settling into sustain well
    // within the same note. Click: the noise burst's own decay, independent of and much faster
    // than the amplitude envelope above - a real pluck's bright transient is over quickly.
    private func updateAmplitudeSmoothingCoefficients(attackSeconds: Double = 0.003, decaySeconds: Double = 0.03, releaseSeconds: Double = 0.005, clickSeconds: Double = 0.012) {
        attackSmoothingCoefficient = 1 - exp(-1 / (attackSeconds * sampleRate))
        decaySmoothingCoefficient = 1 - exp(-1 / (decaySeconds * sampleRate))
        releaseSmoothingCoefficient = 1 - exp(-1 / (releaseSeconds * sampleRate))
        clickSmoothingCoefficient = 1 - exp(-1 / (clickSeconds * sampleRate))
        // 5 time constants = ~99.3% of the way to peak - see attackSamplesRemaining's comment.
        attackSamples = max(1, Int((5 * attackSeconds * sampleRate).rounded()))
    }

    private func updateOnsetDelaySamples() {
        onsetDelaySamples = max(0, Int((onsetDelaySeconds * sampleRate).rounded()))
    }

    // A silence -> sounding transition (both the currently-ramping target and the actual
    // applied amplitude are ~0, and the new target isn't) is a genuine onset, as opposed to an
    // ordinary in-flight amplitude change (touch pressure, score envelope shaping) - only the
    // former should incur onsetDelaySamples of held silence before the normal ramp in getValue()
    // starts. The epsilon matches ScorePlayer's own silenceThreshold for "settled at zero".
    func setAmplitude(inAmplitude:Double){
        let epsilon = 0.0001
        let isNewOnset = abs(targetAmplitude) < epsilon && abs(amplitude) < epsilon && abs(inAmplitude) >= epsilon
        targetAmplitude = inAmplitude
        if isNewOnset {
            pendingOnsetSamples = onsetDelaySamples
            peakAmplitude = inAmplitude
            attackSamplesRemaining = attackSamples
            clickEnvelope = 1
        }
        //print("Tone: setAmplitude: amplitude = \(self.amplitude)")
    }

    // Forces a fresh attack+click even if the tone is already sounding - for a genuine new
    // "strike" gesture (the pen touching the graph) that should always re-articulate, unlike
    // setAmplitude's onset detection just above, which only fires on a silence -> sounding
    // transition. Without this, a pedal-sustained voice (already nonzero amplitude from a
    // previous note) never gets a fresh attack/click when the pen comes down again on a new
    // position - only its pitch changes - confirmed live 2026-09-05 ("does fire on pen down...
    // but does not fire on pen down when pedal is on"). No-op if the tone isn't currently meant
    // to be sounding at all (targetAmplitude ~0) - nothing to re-articulate.
    func retrigger() {
        let epsilon = 0.0001
        guard targetAmplitude >= epsilon else { return }
        pendingOnsetSamples = onsetDelaySamples
        peakAmplitude = targetAmplitude
        attackSamplesRemaining = attackSamples
        clickEnvelope = 1
    }

    func incrementPhase(){
        // Advance the phase for the next frame.
        currentPhase += self.phaseIncrement
        if currentPhase >= self.twoPi {
            currentPhase -= self.twoPi
        }
        if currentPhase < 0.0 {
            currentPhase += self.twoPi
        }
    }

    func getValue() -> Double{
        if pendingOnsetSamples > 0 {
            pendingOnsetSamples -= 1
            return 0
        }

        let epsilon = 0.0001
        if targetAmplitude < epsilon {
            // Note off: release toward silence, exactly as before this ADSR shape was added.
            amplitude += (0 - amplitude) * releaseSmoothingCoefficient
        } else if attackSamplesRemaining > 0 {
            // Attack: rise toward peakAmplitude (the value set at note-on) for a fixed number of
            // samples - see attackSamplesRemaining's own comment for why not "until amplitude
            // reaches peakAmplitude".
            amplitude += (peakAmplitude - amplitude) * attackSmoothingCoefficient
            attackSamplesRemaining -= 1
        } else {
            // Decay/sustain: settle onto (and then hold at) sustainLevelFraction of peak.
            let sustainLevel = peakAmplitude * sustainLevelFraction
            let coefficient = amplitude > sustainLevel ? decaySmoothingCoefficient : attackSmoothingCoefficient
            amplitude += (sustainLevel - amplitude) * coefficient
        }

        clickEnvelope += (0 - clickEnvelope) * clickSmoothingCoefficient
        let click = nextNoise() * clickEnvelope * clickGainFraction * peakAmplitude

        return (signal.getValue(phase:currentPhase) * amplitude) + click // signal is -1 to 1. amplitude is 0 to 1, default is 0.5
    }
}

