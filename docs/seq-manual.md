# Seq — User Manual

*Companion to the GBG III manual. Seq is a companion app for reviewing and editing performances
you've recorded in GBG III (Glass Bead Game III) — not something you need for ordinary live
playing. See the main GBG III manual for setup and how to play GBG III itself.*

*Draft — not yet public. Will publish alongside App Store approval for GBG III and Seq.*

---

## Setup

Seq is Mac-only today — macOS 14.2 or later. It installs from the App Store, same as any other
app, as a separate app from GBG III with its own icon.

## How GBG III and Seq talk to each other

There are three separate ways GBG III and Seq connect — it's worth understanding all three,
since they serve different purposes:

1. **Seq → GBG III, live MIDI, same Mac only.** GBG III creates a virtual MIDI destination
   named "Glass Bead Game III" that Seq automatically detects. When both apps are open on the
   same Mac, Seq shows a **"Graph detected — Connect"** button (Seq's own on-screen name for
   GBG III); one tap wires Seq's output straight into GBG III, so a sequence played back in Seq
   can sound through GBG III itself (or drive GBG III's external MIDI/synth output, whatever
   GBG III is currently set up to do). This only works when both apps are running on the *same
   machine* — there's no wireless/network link built in.
2. **GBG III → Seq, live MIDI, any connection CoreMIDI supports.** The reverse direction: Seq
   can capture a performance directly as you play it in GBG III, no file needed at all. See
   **Live capture** below — this one *does* work over USB or Network MIDI, not just same-Mac.
3. **File export/import, any device.** GBG III can save what you've played as a file; Seq can
   open that file. This is how a performance recorded on the iPad reaches Seq on your Mac when
   there's no live connection between them — move the file over however you'd move any file
   (AirDrop, Files app, iCloud Drive, etc.), then open it in Seq. Files are real Standard MIDI
   Files (`.midi`) — any DAW can open one, though only Seq understands the extra, safely-ignored
   metadata that carries the exact scale/tuning a performance was played in and preserves
   Seq's own per-note editing detail losslessly.

## Live capture — recording straight into Seq

The most direct path, when both apps can reach each other over MIDI (same Mac, USB, or Network
MIDI/RTP-MIDI - see below): no Record/Save in GBG III, no Open in Seq, just play and watch the
notes appear.

1. In GBG III's Settings, set **MIDI Destination** to **Seq** (it shows up in that picker like
   any other MIDI destination, since Seq advertises itself the same way GBG III does) and make
   sure **Use Midi** is on.
2. In Seq's transport bar, tap **Capture**. It stays armed (shown as **Stop**) until you tap it
   again - play as long as you like across it.
3. Play in GBG III. X/Y/Z are captured continuously, the same detail level as GBG III's own
   Record feature (drone isn't - there's no touch gesture driving it, same as Record).
4. Tap **Stop** in Seq. The captured performance loads into the piano roll immediately, raw and
   unsegmented - nothing to open, nothing to save first. Apply **Segment** (see below) whenever
   you're ready, or leave it as-is and segment/edit some other time.

Connecting over USB or Network MIDI works the same way once the connection itself exists - pair
the iPad and Mac in **Audio MIDI Setup**'s Network MIDI panel (or plug in over USB), and GBG
III's MIDI Destination picker will show Seq the same way it does on the same Mac. This one known
limitation: Seq assumes GBG III is using its default MPE channel assignment for X/Y/Z - if GBG
III's **Use MPE** is off, live capture won't line up (Record → Save → Open still works
regardless, since files carry no such assumption).

## Recording a performance in GBG III (for Save/Open instead of live capture)

In GBG III's Settings panel, under **Live Recording**:

1. Tap **Record**, then play. GBG III captures your X/Y/Z touch pitch continuously (300 times a
   second) for as long as you're actually touching the graph — gaps between phrases are kept as
   silence, not stitched together.
2. Tap **Record** again to stop.
3. Tap **Save** to export a file (default name "Live Recording"). Move this file to wherever
   Seq will open it from.

The drone voice is never captured this way — there's no touch gesture driving it, so recordings
only ever contain X/Y/Z material.

## Opening a recording in Seq

Use Seq's **Open** button and pick the file. If Seq recognizes it as a raw, unsegmented
recording, it asks:

- **Segment** — automatically break the continuous recorded pitch into discrete notes (see
  below).
- **Load As-Is** — keep it as one long note per gesture, with the full recorded pitch detail
  intact, and edit/segment by hand later if you want.
- **Cancel**

## Segmentation

Segmentation looks for places where your pitch was genuinely "sitting still" (within about
half a semitone of itself for at least a tenth of a second) and treats those as held notes,
splitting between them at the steepest point of the glide connecting them. It's currently
**automatic and all-or-nothing** — there's no per-recording control over the sensitivity yet.
Each resulting note keeps its own recorded micro-pitch detail, so it still plays back with your
actual expressive detail, not a flattened, quantized pitch.

If a stretch of playing never sits still long enough anywhere (a continuous glide, or a very
short gesture), segmentation leaves it as one note rather than guessing at a split.

Segmentation isn't only an import-time choice — the transport bar's own **Segment** button
applies it to whatever's currently loaded, whenever you want. Load or capture a performance raw
first, look at (or play) the unsegmented curve, then press **Segment** to see it split into
discrete notes. Safe to press more than once or on already-segmented material - it only ever
acts on genuinely un-segmented stretches, so it never re-cuts a note you've already placed or
edited by hand.

## The Seq window

Top to bottom:

- **Transport bar** — play/stop, **Capture** (live capture straight from GBG III, see above), a
  scrub slider, a Voice picker (Drone/X/Y/Z) for where new notes get placed, an **Add Note**
  toggle (tap the empty canvas to place a note of the current duration once armed), a duration
  stepper, Save/Open, **Segment** (applies segmentation to whatever's currently loaded), and
  **Panic**.
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

## Sending Seq's output somewhere

Three independent outputs, any combination of which can be on at once:

- **Internal Synth** — Seq's own built-in sound, on by default.
- **Graph Out** — routes to GBG III itself, live, over the same-Mac virtual MIDI connection
  described above (labeled "Graph Out" in Seq's own UI).
- **Synth Out** — a second, independent MIDI output for driving real outboard gear, with its
  own destination picker and its own per-voice MIDI channel assignment (Drone/X/Y/Z, each
  1–16, independently of whatever GBG III itself is using).

## Panic

The red Panic button force-sends a note-off on every channel either output could plausibly be
using, regardless of what Seq's own bookkeeping thinks is currently sounding. Use it if
something gets stuck sounding — a very short note can occasionally slip past Seq's own
note-tracking.

---

*Feedback on this manual, or on Seq itself, welcome — [contact info / link].*
