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
notes appear in the piano roll as you play them.

1. In GBG III's Settings, set **MIDI Destination** to **Seq** (it shows up in that picker like
   any other MIDI destination, since Seq advertises itself the same way GBG III does) and make
   sure **Use Midi MPE** is on.
2. In Seq's transport bar, tap **Capture**. It stays armed (shown as **Stop**) until you tap it
   again - play as long as you like across it. This stops playback if it was running, since the
   two can't happen at once.
3. Play in GBG III. X/Y/Z are captured continuously, the same detail level as GBG III's own
   Record feature (drone isn't - there's no touch gesture driving it, same as Record) - and the
   piano roll draws each note as you play it, live, not only once you stop.
4. Tap **Stop** in Seq when you're done. What's already in the piano roll *is* the captured
   performance, raw and unsegmented - nothing to open, nothing to save first. Apply **Segment**
   (see below) whenever you're ready, or leave it as-is and segment/edit some other time.

Connecting over Network MIDI works the same way once the connection itself exists - pair the
iPad and Mac in **Audio MIDI Setup**'s Network MIDI panel, and GBG III's MIDI Destination picker
will show Seq the same way it does on the same Mac. USB is a separate mechanism, not just "plug
in the cable": macOS bridges a USB-connected iPad's MIDI via IDAM (Inter-Device Audio & MIDI),
which needs enabling per-connection in **Audio MIDI Setup**'s *Audio Devices* window (not the
MIDI Studio window a real MIDI interface would show up in) - look for the iPad's own entry there
and click **Enable**. Seq assumes
GBG III's MPE channel assignment for X/Y/Z - GBG III is MPE-only now, with no separate mode to
fall out of sync with, so this always lines up (Record → Save → Open never depended on this
either, since files carry no such assumption).

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
  scrub slider, Save/Open, **Segment** (applies segmentation to whatever's currently loaded),
  and **Panic**.
- **Edit bar** — the tool (**Select**, **Place**, **Step**), the controls that tool needs, the
  length of a new note (seconds, or beats with the grid on), and the **Grid** switch with its
  BPM, beats per bar and snap resolution.
- **Note inspector** — exact values for the selected note (see below).
- **Root indicator** — a thin strip showing where the drone currently sits, since the drone has
  no on-screen crosshair of its own.
- **Timeline** — a labeled ruler: seconds with the grid off, bar numbers with it on. Click or
  drag it to move the playhead.
- **Note editor** — the main canvas. Scale-degree gridlines run horizontally; with the grid on,
  bar/beat lines run vertically.

**Notes are pitch bends.** Every note goes from a start pitch to an end pitch, shaped by its
profile (Linear, Ease In, Ease Out, Ease In/Out, or Recorded for captured material). A held
note is simply one whose start and end pitch are the same. Each voice (X, Y, Z, Drone) is
independent: its notes can start and stop anywhere, with silence between them, and moving one
note never moves another.

**Entering notes:**

- **Place** — pick a voice, click where the note goes. It gets the current length.
- **Step** — arm the voices a step should fill (X, Y, Z by default; add Drone if you like).
  The playhead turns green and becomes the step cursor. Click a pitch for each armed voice in
  turn (the cursor says which is next); after the last one the cursor moves on by the note
  length, so a three-note chord is three clicks and all three start together, like Graph's.
  **Rest** (or →) skips ahead leaving silence, or finishes a partial chord; ← steps back.
  Click the ruler to put the cursor anywhere.

**Editing a note:** in any tool, drag a note's start or end dot to move that end in time and
pitch, or drag its line to move the whole note (a bend keeps its interval). In **Select**,
click a note to select it, then use the inspector to type exact values: start/end time in
seconds, start/end pitch as a ratio of the root (`5/4`, `7/4`) or in Hz (`440`), choose the
profile from the dropdown, **Hold** to make end pitch = start pitch, or delete it (⌫ also
deletes, Esc deselects, Space plays/stops). Pitches snap to the scale and times to the grid;
hold **Option** while clicking or dragging for free placement. A note with recorded detail can
switch back to **Recorded** any time, or **Purge Recorded** to discard it.

**Undo:** ⌘Z undoes the last edit (a whole drag counts as one), ⇧⌘Z redoes; the Edit menu names
the step. Open, Segment and Capture are undoable steps too.

Older files and plain MIDI imports open with their notes converted to this model (an old "Flat"
note becomes a held note - it sounds exactly the same).

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
