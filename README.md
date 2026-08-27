# Glass Bead Game III

A touch-driven just-intonation instrument for iPad, published on the App Store. Used for both education and personal performance.

## Premise

The app is built around drone-based playing: a note's motion is far more pronounced against a sustained drone than it is in an unaccompanied melody. Two independently movable tones (X and Y) play against a fixed root/drone, so you can hear what happens between each moving tone and the drone, and what happens between the two moving tones themselves.

Just intonation isn't the starting goal here, it's a consequence. Against a drone, beating between near-but-not-quite-aligned frequencies is very audible, so pure/just ratios are the intervals that resolve it - players naturally reach for them in a drone context. That's why the graph is a lattice of small-integer frequency ratios rather than 12-tone equal temperament.

The interesting part is the emergent melodic patterns that fall out of the lattice's geometry - a source of new melodic material, with a loose kinship to older musics built around slowly shifting drones. This is not a way to make modern common-practice tonal music; it's its own idiom.

The name comes from Hermann Hesse's novel, in which the fictional Glass Bead Game is described as rooted in mathematics, harmonics, and other disciplines - it came to mind on first seeing the lattice visualization, nothing deeper than that.

## What's built

- Live touch performance: drone + two movable tones, snapping to just ratios (or unsnapped with Shift/no-snap)
- Real-time synthesis and/or MIDI output, including MPE (MIDI Polyphonic Expression) so microtonal pitches can drive external synths accurately
- Selectable harmonic limit (3/5/7/9/11/13/17/19) controlling how far the lattice extends
- Square / Diamond / Triangle presentations of the same underlying graph
- Diamonds mark points where the natural harmonics of all three tones (root, X, Y) line up exactly - the precise, absolute consonances

## Roadmap

- **Score-based composition and playback.** Write a piece once and replay it, rather than only improvising live. The `Score`/`Part`/`Note`/`Node` and `Transition`/`Envelope` classes under `Sound/Audio/Score` are the design for this (see `Sound/Audio/Score/Overview.md`) - built out but not yet wired into the app.
- **Dissonance field (`DissonanceView`).** The diamonds are the known answer: exact harmonic alignments. The open question is what's happening in the space between them, and why it's satisfying to play outside a consonance and slide into it. An empirical roughness/beating field now covers the entire graph as a first pass (`GBGCore`'s `Dissonance.swift`, tested but not yet seen rendered on a device): roughness is computed from beat rates between the harmonics of all three tones pairwise, tapering to zero at unison, peaking at 33 beats/sec, and decaying back toward zero by roughly double that. The 33 Hz figure isn't arbitrary - it's Helmholtz's own estimate (via the appendix Alexander Ellis added to his English translation of Helmholtz's *On the Sensations of Tone*) of the beat rate at which two partials sound maximally rough, used as a fixed rate rather than one scaled to register/critical bandwidth the way later models do. It's not yet known whether the resulting gradient is musically useful - that's still to be seen once it can actually be looked at.

## Prior inspiration

- **Alexander Ellis's consonance/dissonance work** (see above) is the direct historical basis for the dissonance field's roughness curve.
- **Harry Partch's "One Footed Bride"** diagram from *Genesis of a Music*, visualizing the Otonality/Utonality relationships in his tonality diamond - a kindred idea to the diamonds in this app's own graph. Not yet dug into in detail; a side quest for another day.

## Repo history

This repo is a continuation of [Glass-Bead-Game-2](https://github.com/NormSohl/Glass-Bead-Game-2), branched with full history. The purpose of this repo is to try expanding the app with Claude Code's help.
