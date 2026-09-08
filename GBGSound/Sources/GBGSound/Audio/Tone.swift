//
//  Tone.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/8/22.
//

import Foundation
import AVFoundation
import os

class Tone{
    // Guards every property below that's written from touch/gesture code on the main thread
    // (setPitch/setAmplitude/retrigger) and read from the real-time audio render thread inside
    // AVAudioSourceNode's callback (getValue/incrementPhase, called from Audio.swift's srcNode
    // closure) - there was no synchronization between those two threads at all before 2026-09-07.
    // Root-caused a "pop during pedal sustain" reported only on iPad, never on an identical Mac
    // build - narrowed all the way down by side-by-side testing (same code, same build
    // configuration) to being Release-configuration-only on iOS (Debug on iPad: clean; Debug on
    // Mac: clean; Release on iPad: pops), which is the signature of a data race the optimizer
    // exposes rather than an algorithmic bug - Debug's naive codegen was accidentally hiding a
    // real hazard, not avoiding one. Multiple fields (peakAmplitude + attackSamplesRemaining,
    // written together in setAmplitude/retrigger) need to stay consistent with each other across
    // the thread boundary, which per-field atomics alone wouldn't guarantee - hence a lock around
    // each critical section rather than making individual properties atomic.
    private var lock = os_unfair_lock()

    // signal. This returns a wave based on the phase input value. Phase is in range 0 to twoPi. Return is in range -1 to 1
    let signal:WaveForm = Sine()//SawToothDown() //is default Additive()
    var sampleRate:Double = 44100.0 {
        didSet {
            updateAmplitudeSmoothingCoefficients()
            updateFrequencySmoothingCoefficient()
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
    // A short portamento on frequency itself, separate from (and much shorter than) any pitch
    // glide a performer plays deliberately by dragging - added 2026-09-07 for a pop reported when
    // a new touch lands on a pedal-held, already-fully-audible voice at a different graph
    // position. What's different about a brand-new touch (vs. continuous within-touch dragging,
    // which already updates frequency smoothly every frame) is that its very first frame snaps
    // phaseIncrement straight to the new position with zero glide, and unlike a pedal-off note
    // that transition isn't masked by a fade through silence. A pure frequency step doesn't
    // create a waveform discontinuity (phase stays continuous - see setAmplitude's own comment
    // on this), so this is an audible instantaneous retune, not a waveform glitch, and needs its
    // own smoothing rather than zero-crossing-style gating.
    private var currentFrequency: Double = 0
    private var targetFrequency: Double = 0
    private var frequencySmoothingCoefficient: Double = 0.0
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
    // Reintroduced 2026-09-07 without the noise-click "pluck" transient that shipped alongside it
    // the first time (2026-09-05 - 2026-09-07): a separate pop reported during pedal-sustained
    // play was root-caused all the way to a genuine data race between this thread and the audio
    // render thread (see the lock's own comment at the top of this class) - not the envelope or
    // the click at all, so the envelope shape was safe to bring back once that lock was in place.
    // Shape (confirmed by ear 2026-09-05, tuned in two passes - "a bit of
    // attack, fairly rapid but not dramatic decay into sustain, release as it is now", then "more
    // ping at the start, faster attack"): on a genuine onset, amplitude rises toward peakAmplitude
    // (the value passed to setAmplitude) using attackSmoothingCoefficient for attackSamples
    // samples (see that var's own comment for why a fixed sample count, not "until it reaches
    // peak"), then decays to peakAmplitude * sustainLevelFraction using decaySmoothingCoefficient
    // and holds there; on note-off (targetAmplitude back to ~0), it falls to 0 using
    // releaseSmoothingCoefficient.
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

    // utility function
    let twoPi = 2 * Double.pi

    init(sampleRate:Double, frequency:Double, amplitude:Double, onsetDelaySeconds: Double = 0) {
        //setSampleRate (inSampleRate: sampleRate)
        // Swift does NOT call didSet for assignments made from within a class's own
        // initializer (verified directly - it only fires for assignments from outside it), so
        // these calls can't be left to sampleRate/onsetDelaySeconds's own didSet the way
        // setSampleRate()/the onsetDelaySeconds property setter do from outside init - they're
        // made explicitly here instead. (In practice Audio.swift's post-construction
        // setTriadSampleRate() call was already doing this "for free" from outside init, which
        // is why this was never audibly broken - but a Tone built and used without that
        // follow-up call, e.g. in a test, would otherwise silently stay silent forever.)
        self.sampleRate = sampleRate
        self.onsetDelaySeconds = onsetDelaySeconds
        updateAmplitudeSmoothingCoefficients()
        updateFrequencySmoothingCoefficient()
        updateOnsetDelaySamples()
        setPitch (inFrequency: frequency)
        self.currentFrequency = targetFrequency // starting value has nothing to glide from
        self.phaseIncrement = (twoPi / sampleRate) * currentFrequency
        setAmplitude(inAmplitude: amplitude)
        self.amplitude = targetAmplitude // starting value has nothing to ramp from
        pendingOnsetSamples = 0 // starting value is applied directly above, not ramped - nothing to delay
        //print("Tone: init: amplitude = \(amplitude)")
    }

    func setPitch (inFrequency:Double){
        //print("setPitch called with fq of: ",frequency)
        // Sets the glide target only - currentFrequency (and phaseIncrement, derived from it)
        // chases this in incrementPhase() below, rather than jumping here directly.
        os_unfair_lock_lock(&lock)
        targetFrequency = inFrequency
        os_unfair_lock_unlock(&lock)
        //print("setPitch. Frequency: ",inFrequency)
    }

    private func updateFrequencySmoothingCoefficient(portamentoSeconds: Double = 0.008) {
        frequencySmoothingCoefficient = 1 - exp(-1 / (portamentoSeconds * sampleRate))
    }

    func setSampleRate(inSampleRate:Double){
        self.sampleRate = inSampleRate
    }

    // Release: a few milliseconds - same order of magnitude as ScorePlayer's own default
    // (amplitudeRampSeconds) - eliminates the click without perceptibly softening a deliberate
    // touch begin/end, which already reads as instantaneous at this timescale. Attack: slower
    // than release but still short - a soft onset, not a slow pad-style swell. Decay: fairly
    // rapid but not dramatic - noticeably quicker than the attack, settling into sustain well
    // within the same note.
    private func updateAmplitudeSmoothingCoefficients(attackSeconds: Double = 0.003, decaySeconds: Double = 0.03, releaseSeconds: Double = 0.005) {
        attackSmoothingCoefficient = 1 - exp(-1 / (attackSeconds * sampleRate))
        decaySmoothingCoefficient = 1 - exp(-1 / (decaySeconds * sampleRate))
        releaseSmoothingCoefficient = 1 - exp(-1 / (releaseSeconds * sampleRate))
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
        os_unfair_lock_lock(&lock)
        let epsilon = 0.0001
        let isNewOnset = abs(targetAmplitude) < epsilon && abs(amplitude) < epsilon && abs(inAmplitude) >= epsilon
        targetAmplitude = inAmplitude
        if isNewOnset {
            pendingOnsetSamples = onsetDelaySamples
            peakAmplitude = inAmplitude
            attackSamplesRemaining = attackSamples
        }
        os_unfair_lock_unlock(&lock)
        //print("Tone: setAmplitude: amplitude = \(self.amplitude)")
    }

    // Forces a fresh attack even if the tone is already sounding - for a genuine new "strike"
    // gesture (the pen touching the graph) that should always re-articulate, unlike
    // setAmplitude's onset detection just above, which only fires on a silence -> sounding
    // transition. Without this, a pedal-sustained voice (already nonzero amplitude from a
    // previous note) never gets a fresh attack when the pen comes down again on a new position -
    // only its pitch changes. No-op if the tone isn't currently meant to be sounding at all
    // (targetAmplitude ~0) - nothing to re-articulate.
    func retrigger() {
        os_unfair_lock_lock(&lock)
        let epsilon = 0.0001
        guard targetAmplitude >= epsilon else {
            os_unfair_lock_unlock(&lock)
            return
        }
        // No pendingOnsetSamples here, unlike setAmplitude's onset path: this voice is already
        // sounding (targetAmplitude >= epsilon, guarded above), so there's no silence to hold
        // through - forcing getValue() to return a hard 0 for onsetDelaySamples would itself be
        // an audible mute-and-pop discontinuity.
        peakAmplitude = targetAmplitude
        attackSamplesRemaining = attackSamples
        os_unfair_lock_unlock(&lock)
    }

    func incrementPhase(){
        os_unfair_lock_lock(&lock)
        // Chase targetFrequency (see setPitch/currentFrequency's own comments) before deriving
        // this frame's phaseIncrement from it - portamento lives here, not in setPitch itself.
        currentFrequency += (targetFrequency - currentFrequency) * frequencySmoothingCoefficient
        phaseIncrement = (twoPi / sampleRate) * currentFrequency
        os_unfair_lock_unlock(&lock)
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
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

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

        return (signal.getValue(phase:currentPhase) * amplitude) // signal is -1 to 1. amplitude is 0 to 1, default is 0.5
    }
}
