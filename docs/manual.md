# Glass Bead Game III — User Manual

*Draft — not yet public. Will publish alongside App Store approval for Graph and Seq.*

This manual covers three things: setting up Graph (and Seq, if you're on a Mac), how to use
Seq to record, review, and edit performances, and how to connect outboard MIDI gear.

---

## 1. Setup

### Requirements

| | Graph | Seq |
|---|---|---|
| iPad | iPadOS 17.2 or later | Not currently supported |
| Mac | macOS 14.2 or later | macOS 14.2 or later |

Seq is a Mac-only companion app today. Graph runs natively on both iPad and Mac.

### Installing Graph

*[Installation steps depend on final distribution method — TestFlight link or App Store
listing. Placeholder until that's finalized.]*

On first launch, Graph asks for nothing — no microphone permission, no Bluetooth pairing
prompt. It doesn't touch the microphone (its "recording" feature captures your touch/pen
gestures, not audio - see §2), and MIDI access needs no permission prompt on either platform.
You can start playing immediately.

### Installing Seq

*[Same placeholder as above.]* Seq is a separate app from Graph, with its own icon, though it's
designed to work closely with Graph when both are running on the same Mac (see §2).

### iPad performance setup

If you're using Graph live on an iPad with an Apple Pencil Pro:

- **Squeeze** toggles the sustain pedal — a free gesture on the same hand already holding the
  pencil, so it doesn't compete with your other hand.
- Check **Settings → Apple Pencil → Squeeze** on the iPad itself if squeeze doesn't seem to do
  anything: if it's set to "Run Shortcut," iPadOS intercepts the gesture before Graph ever sees
  it. Any other setting works.
- A Bluetooth or USB keyboard (or a cheap keypad that emulates one) can drive Drone, Portamento,
  and Pedal too — see **Keyboard Mapping** in Settings to see or change the bindings.
- The on-screen control column (Drone/Portamento/Pedal/Panic/Settings) and the Z-slider always
  sit on opposite sides of the graph. **Z-Slider Side** in Settings flips both together, so you
  can set up for either hand.

---

## 2. Using Seq

### How Graph and Seq talk to each other

There are two separate ways Graph and Seq connect — it's worth understanding both, since they
serve different purposes:

1. **Live MIDI, same Mac only.** Graph creates a virtual MIDI destination named
   "Glass Bead Game III" that Seq automatically detects. When both apps are open on the same
   Mac, Seq shows a **"Graph detected — Connect"** button; one tap wires Seq's output straight
   into Graph, so a sequence played back in Seq can sound through Graph itself (or drive Graph's
   external MIDI/synth output, whatever Graph is currently set up to do). This only works when
   both apps are running on the *same machine* — there's no wireless/network link built in.
2. **File export/import, any device.** Graph can save what you've played as a file; Seq can
   open that file. This is how a performance recorded on the iPad reaches Seq on your Mac —
   move the file over however you'd move any file (AirDrop, Files app, iCloud Drive, etc.), then
   open it in Seq.

### Recording a performance in Graph

In Graph's Settings panel, under **Live Recording**:

1. Tap **Record**, then play. Graph captures your X/Y/Z touch pitch continuously (300 times a
   second) for as long as you're actually touching the graph — gaps between phrases are kept as
   silence, not stitched together.
2. Tap **Record** again to stop.
3. Tap **Save** to export a file (default name "Live Recording"). Move this file to wherever
   Seq will open it from.

The drone voice is never captured this way — there's no touch gesture driving it, so recordings
only ever contain X/Y/Z material.

### Opening a recording in Seq

Use Seq's **Open** button and pick the file. If Seq recognizes it as a raw, unsegmented
recording, it asks:

- **Segment** — automatically break the continuous recorded pitch into discrete notes (see
  below).
- **Load As-Is** — keep it as one long note per gesture, with the full recorded pitch detail
  intact, and edit/segment by hand later if you want.
- **Cancel**

### Segmentation

Segmentation looks for places where your pitch was genuinely "sitting still" (within about
half a semitone of itself for at least a tenth of a second) and treats those as held notes,
splitting between them at the steepest point of the glide connecting them. It's currently
**automatic and all-or-nothing** — there's no per-recording control over the sensitivity yet.
Each resulting note keeps its own recorded micro-pitch detail, so it still plays back with your
actual expressive detail, not a flattened, quantized pitch.

If a stretch of playing never sits still long enough anywhere (a continuous glide, or a very
short gesture), segmentation leaves it as one note rather than guessing at a split.

### The Seq window

Top to bottom:

- **Transport bar** — play/stop, a scrub slider, a Voice picker (Drone/X/Y/Z) for where new
  notes get placed, an **Add Note** toggle (tap the empty canvas to place a note of the current
  duration once armed), a duration stepper, Save/Open, and **Panic**.
- **Root indicator** — a thin strip showing where the drone currently sits, since the drone has
  no on-screen crosshair of its own.
- **Piano roll** — the main editing canvas. Scale-degree gridlines run horizontally; an amber
  beat grid appears automatically when Seq can detect a steady tempo in what you played (it's
  fine, and expected, for this not to appear on freely-timed material).

**Editing a note:** drag its start/end handle to move that boundary (it snaps to the beat grid
when Seq has detected one). Tap the small square at a note's midpoint to choose how it
transitions into the next note — Flat, Linear, Ease In, Ease Out, Ease In/Out, or (only if the
note has recorded detail) Recorded, which also lets you permanently discard that recorded detail
if you'd rather have a clean curve instead.

**Zoom:** pinch on a trackpad, or use a mouse's scroll wheel — both zoom the timeline
horizontally and the pitch axis vertically together.

### Sending Seq's output somewhere

Three independent outputs, any combination of which can be on at once:

- **Internal Synth** — Seq's own built-in sound, on by default.
- **Graph Out** — routes to Graph itself, live, over the same-Mac virtual MIDI connection
  described above.
- **Synth Out** — a second, independent MIDI output for driving real outboard gear, with its
  own destination picker and its own per-voice MIDI channel assignment (Drone/X/Y/Z, each
  1–16, independently of whatever Graph itself is using).

### Panic

The red Panic button force-sends a note-off on every channel either output could plausibly be
using, regardless of what Seq's own bookkeeping thinks is currently sounding. Use it if
something gets stuck sounding — a very short note can occasionally slip past Seq's own
note-tracking.

---

## 3. Connecting outboard MIDI gear

Graph's **MIDI Destination** and **MIDI Source** pickers (Settings, under Use MIDI) list
whatever your Mac or iPad already sees as MIDI ports — physical USB-MIDI interfaces, virtual/IAC
ports, Bluetooth MIDI devices, or Network MIDI sessions. Graph draws no distinction between
these: if your device already shows up in your Mac's Audio MIDI Setup or your iPad's Bluetooth
settings, it'll show up here too, listed by whatever name that device gives itself. There's no
separate in-app Bluetooth pairing screen — pair the device at the system level first.

- **MIDI Destination** is where Graph sends pitch/note data to — an external synth, a
  Eurorack MIDI-to-CV interface, etc.
- **MIDI Source** is where Graph listens for incoming MIDI from — an external controller, or
  Seq's own live output (see §2).

### Enabling MPE

**Use MPE** turns on MIDI Polyphonic Expression — each voice (Drone/X/Y/Z) gets its own MIDI
channel with independent pitch bend, rather than sharing a smaller set of fixed channels. Turn
this on only if your receiving gear actually understands MPE; Graph sends standard MPE
configuration and per-channel pitch bend either way, but a receiver that doesn't understand MPE
will just see several ordinary channels each bending independently, which may or may not be
what you want.

Default channel assignments: with MPE on, Drone/X/Y/Z use channels 5/2/3/4; with MPE off, they
use channels 4/1/2/3. Either way, X/Y/Z occupy the first three channels and Drone comes last —
useful if your receiver is only listening for your three main voices.

### Pitch bend range

Graph declares its pitch bend range to the receiver automatically (±12 semitones without MPE,
±24 semitones with it) using the standard MIDI RPN 0 message. Well-behaved gear picks this up
on its own. **Real analog/modular gear often doesn't** — if notes sound in the wrong octave or
with a squashed/exaggerated bend, you'll likely need to set your receiving instrument's own
pitch bend range by hand to match (±12 or ±24 semitones, matching whether MPE is on).

### Tune Midi

For gear that has to be tuned by hand and can't be retuned over MIDI (most modular/analog
synths): press **Tune Midi**. This sounds all four voices at a straight 440 Hz (A) and tells you
which MIDI channels are carrying it. Tune your instrument's own oscillator by ear (or with a
tuner) against that reference, then press **Stop** to return to normal playing.

### Verify Pitch Bend Range

Even after setting your gear's pitch bend range to match (above), it's worth confirming the
result actually sounds right — real gear doesn't always respond exactly as declared. Use
**Unison / Fifth / Octave** to sound all four voices together at those exact just-intonation
intervals (not the tempered approximations most gear defaults to), and listen for whether your
instrument's actual response matches. **Stop** returns to normal playing.

---

*Feedback on this manual, or on Graph/Seq themselves, welcome — [contact info / link].*
