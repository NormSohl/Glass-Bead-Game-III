# Glass Bead Game III

A touch-driven just-intonation instrument for iPad, published on the App Store. Used for both education and personal performance.

## Premise

The app is built around drone-based playing: a note's motion is far more pronounced against a sustained drone than it is in an unaccompanied melody. Two independently movable tones (X and Y) play against a fixed root/drone, so you can hear what happens between each moving tone and the drone, and what happens between the two moving tones themselves.

Just intonation isn't the starting goal here, it's a consequence. Against a drone, beating between near-but-not-quite-aligned frequencies is very audible, so pure/just ratios are the intervals that resolve it - players naturally reach for them in a drone context. That's why the graph is a lattice of small-integer frequency ratios rather than 12-tone equal temperament.

The interesting part is the emergent melodic patterns that fall out of the lattice's geometry - a source of new melodic material, with a loose kinship to older musics built around slowly shifting drones. This is not a way to make modern common-practice tonal music; it's its own idiom.

The name comes from Hermann Hesse's novel, in which the fictional Glass Bead Game is described as rooted in mathematics, harmonics, and other disciplines - it came to mind on first seeing the lattice visualization, nothing deeper than that.

## What's built

- Live touch performance: drone + two movable tones, snapping to just ratios (or unsnapped with Shift/no-snap)
- Real-time synthesis and/or MIDI output. MIDI output is MPE-only (MIDI Polyphonic Expression) so each voice's microtonal pitch bend is independent - safe for any receiver, since MPE's extra zone-declaration message is itself backward-compatible MIDI a non-MPE receiver just ignores
- Selectable harmonic limit (3/5/7/9/11/13/17/19) controlling how far the lattice extends
- Square / Diamond / Triangle presentations of the same underlying graph
- Diamonds mark points where the natural harmonics of all three tones (root, X, Y) line up exactly - the precise, absolute consonances
- **Dissonance field.** The diamonds are the known answer: exact harmonic alignments. `DissonanceView` fills in the open question - what's happening in the space between them - with an empirical roughness/beating field covering the whole graph (`GBGCore`'s `Dissonance.swift`). Roughness sums beat rates between the harmonics of all three tones pairwise, weighted by a linear per-tone harmonic falloff, peaking at 33 beats/sec (Helmholtz's own estimate, via the appendix Alexander Ellis added to his translation of *On the Sensations of Tone*, of the beat rate at which two partials sound maximally rough - a fixed rate rather than one scaled to register/critical bandwidth the way later models do) and decaying back toward zero by roughly double that. A gamma curve lifts the midtones so the third/fourth/fifth read clearly, not just the strongest unison ring. Toggle it on next to Diamonds; a second toggle switches the harmonic weighting to the more standard 1/n falloff for comparison. Whether the field is musically useful in practice is still an open question - it's tuned by eye so far, not yet used in performance.
- **Score-based composition and playback**, via **Seq**, a companion app for both platforms. GBGCore's `Score`/`Part`/`Note`/`Transition`/`Envelope` classes (see `Sound/Audio/Score/Overview.md`) back Seq's piano-roll editing/playback. Seq can capture a GBG III performance live over MIDI (same Mac, or over Network MIDI) - see `docs/seq-manual.md`.
- **Outboard MIDI**: MPE output to external synths/Eurorack, a MIDI Source input for external control or Seq's own live output, sustain-pedal support via MIDI CC64, and (iOS) Network MIDI - see `docs/manual.md`.

## Prior inspiration

- **Alexander Ellis's consonance/dissonance work** (see above) is the direct historical basis for the dissonance field's roughness curve.
- **Harry Partch's "One Footed Bride"** diagram from *Genesis of a Music*, visualizing the Otonality/Utonality relationships in his tonality diamond - a kindred idea to the diamonds in this app's own graph. Not yet dug into in detail; a side quest for another day.

## Repo history

This repo is a continuation of Glass-Bead-Game-2 (the 2024 app, still a private repo), branched with full history. The purpose of this repo is to try expanding the app with Claude Code's help.

## License

MIT. See [LICENSE](LICENSE).
