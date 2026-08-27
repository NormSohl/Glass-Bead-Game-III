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
- **Dissonance field (`DissonanceView`).** The diamonds are the known answer: exact harmonic alignments. The open question is what's happening in the space between them, and why it's satisfying to play outside a consonance and slide into it. The plan is an empirical roughness/beating field covering the entire graph, inspired by Alexander Ellis's dissonance-curve work (the appendix Ellis added to his translation of Helmholtz's *On the Sensations of Tone*). Roughness would be computed from beat rates between the harmonics of all three tones pairwise, tapering to zero at unison, peaking around an arbitrary ~30 beats/sec ("maximum roughness"), and decaying back toward zero by ~60 beats/sec - both pragmatic starting constants, not derived from a formal model. As of this writing it's never been implemented or plotted, so it's not yet known whether the resulting gradient is musically useful.

## Repo history

This repo is a continuation of [Glass-Bead-Game-2](https://github.com/NormSohl/Glass-Bead-Game-2), branched with full history. The purpose of this repo is to try expanding the app with Claude Code's help.
