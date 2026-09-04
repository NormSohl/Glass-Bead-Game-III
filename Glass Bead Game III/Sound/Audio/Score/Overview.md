# Overview of the Score system

**This document describes the original 2022 design.** Two parts of it were never built and don't
match the current code - noted inline below, not corrected throughout, since the class
hierarchy and Note/Transition/Envelope model it describes are otherwise still accurate and in
real use:

- There's no `loadScore` object and no score text file (`exampleScore.txt` doesn't exist in this
  repo). Real construction happens two other ways instead: `Glass Bead Game III/Data/
  RecordingState.swift` builds `Part`s live from touch/pen input while recording, and GBGCore's
  `SeqMIDICodec`/`StandardMIDIFile` decode them from a Standard MIDI File (Seq's own save
  format, and GBG III's own Live Recording save - see `docs/manual.md`/`docs/seq-manual.md`).
- The `Score` class itself is essentially vestigial today - grep the repo and it's only ever
  instantiated in its own unit test (`GBGCoreTests/ScoreTests.swift`). Real code (`SeqDocument`,
  `RecordingState`, `SequencerState`) holds four named `Part`s directly (drone/x/y/z), with no
  wrapping `Score` object, and `Audio.Triad` has no pointer to a `Score` at all - it's driven
  directly by explicit `setPitch`/enable calls from `Sound.swift`, not by querying a score tree.

Setting those two points aside, this is the model:

```
Superclass: 
* Node

Protocols:
* HasLength
* CanRender

Linked hierarchy:
Score
    Part
        Note
            Transition
            Envelope
```
## Node
Node is the superclass of most of these objects. It includes the bits to manage lists of pointers child nodes, pointer to the parent node, and code to validate all data structures.

## HasLength
This is a protocol for nodes that have duration. It requires a getLengthInSamples function

## CanRender
This is a protocol for nodes that produce output related to the pitch of the three tones. It is designed so that a single call can be made at the start of the tree and the children are queried to provide their own values. It is going to be used to render the graphic output of the sequencer when that is ready. It takes a Double that represents the current sample of the output, or in the case of the graphics, the current column of pixels on the screen.

## Score: Node, HasLength, CanRender
the Score node keeps a list of Part nodes. There are usually three Parts but the system is generalized to have any number.
This object manages:
* name
* beatsPerMin

## Part
The Part node keeps a list of note nodes. This list can be quite big.
This object also manages:
* name
* waveform
WaveForm is a simple class that encapsulates the rendering functionality for a simple repeating waveform like sine, triangle or square.

## Note
Note is a terminal node with no children. It contains all the bits that are needed to determine the pitch and volume of a note at a particular point in the duration of that note. Duration is a 0 to 1 value, with 0 being the start and 1 being the end. 
Frequency is interpolated between start and end frequency based on the transition function.
Amplitude is scaled based on the function envelope, starting from 0 to the Amplitude parameter.
This object manages:
* startTime
* endTime
* startFrequency
* endFrequency
* envelope
* Transition
* Amplitude

## Envelopes and Transitions
![](https://byjus.com/maths/trigonometry-graphs/)
Transitions start and end at different values. Always start at 0 and end at 1
Envelopes start and end at the same value (0) and max at 1 somewhere in the middle

They rely on the function interpolate, which takes a 0 to 1 value indicating how complete the envelope or transition is (0 is start, 1 is end)

These objects conform to the CanInterpolate protocol.

There are several kinds of envelopes that are supported. An envelope takes in a value that indicates the percentage of completion for the envelope, 0 to 1. The envelope returns a value of 0 to 1 indicating the absolute amplitude of the envelope. It is the responsibility of the consuming object to decide what to map the envelope to and how to scale it, either negatively or positively. Envelopes differ from Transitions in that they start and end with 0

* ADSR is the traditional attack, decay, sustain, release envelope invented by Bob Moog.
* Hump is a simple arc derived from a 1/2 section of a sine wave.

Transitions are like envelopes, except that they transition from 0 to 1
* Flat is the exception, because it always has the output of 0, meaning no change.
* EaseIn is half of that semicircle, providing a gentle start and an abrupt end.
* EaseOut is the opposite.

# Overview of audio system
Hierarchy:

AudioUtil
    Triad
        Tone
            Waveform
            
## Audio
The audio system creates an AVAudioSourceNode to manage filling raw audio values into buffers for playback. All functions that interact with the system are in the Audio Class.
The Graph needs three tones which are managed by the Triad class

**Not built this way** - see this doc's own header. `Audio.Triad` has no pointer to a `Score` or
`Part` at all; it's driven directly, frame by frame, by explicit `setPitch`/enable calls from
`Sound.swift` in response to live touch/pen input or incoming MIDI. `Score`/`Part`/`Note` *are*
used for playback, but through a separate path entirely: Seq's `ScorePlayer` reads directly from
a `Part`'s `Note`s (via `getCurrentNote`/`getNextNote`) and writes the resulting frequency/
amplitude straight into its own audio engine each render callback - there's no `Score`-holds-
Triad-holds-Tone-holds-Part chain as described below.

## Tone
Each Tone object manages the low level loops for one tone, and define the waveform used to generate the signal.
Each has an exposed Frequency and Amplitude property that is used to control the rendering of the tone:

* setPitch(Double)  // frequency in Hz.
* setAmplitude(Double)  // 0 to 1 value used to scale the rendered output.
