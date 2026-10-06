# Seq — User Manual

*Companion to the GBG III manual. Seq is a companion app for writing sequences note by note
and for capturing, reviewing and editing performances played in GBG III (Glass Bead Game III) —
not something you need for ordinary live playing. See the main GBG III manual for setup and how
to play GBG III itself.*

*Draft — not yet public. GBG III's first release ships on its own; Seq comes later.*

---

## Setup

Seq is Mac-only today — macOS 14.2 or later — and is a separate app from GBG III, with its own
icon.

## How GBG III and Seq talk to each other

There are two separate ways GBG III and Seq connect, one in each direction:

1. **Seq → GBG III, live MIDI.** On the same Mac, GBG III creates a virtual MIDI destination
   named "Glass Bead Game III". Whenever it appears — GBG III already open when Seq starts, or
   launched later — Seq connects **Graph Out** to it automatically (Graph is Seq's on-screen name
   for GBG III). From then on, playing or scrubbing in Seq moves GBG III's X/Y crosshair and Z
   marker in real time and sounds through GBG III itself (or drives GBG III's external
   MIDI/synth output, whatever GBG III is currently set up to do). If you switch Graph Out off,
   it stays off until GBG III is relaunched; **"Graph detected — Connect"** reconnects by hand.
   You may want Seq's **Internal Synth** off while Graph Out is on, so you hear one sound, not
   two. The automatic connection is same-Mac only; to reach GBG III on an iPad, pick the Network
   MIDI session in Graph Out's destination menu and the same session as GBG III's MIDI Source.
2. **GBG III → Seq, live MIDI, any connection CoreMIDI supports.** The reverse direction: Seq
   captures a performance directly as you play it in GBG III. See **Live capture** below — this
   one *does* work over USB or Network MIDI, not just same-Mac, and it's the only way a
   performance gets from GBG III into Seq: GBG III itself doesn't record or save performances.
   To bring in something played on the iPad, connect it to the Mac over Network MIDI or USB and
   capture it live.

Files are Seq's own business: **Save** and **Open** read and write real Standard MIDI Files
(`.mid`), so you can keep pieces, move them between Macs, or open them in any DAW. Only Seq
understands the extra, safely-ignored metadata that carries the exact scale/tuning a piece uses
and preserves Seq's own per-note editing detail losslessly. Seq can also open plain MIDI files
from elsewhere. When a piece carries its scale, Seq's editor uses it: gridlines, pitch snapping
and ratio names all follow the piece.

## Live capture — recording straight into Seq

Works whenever both apps can reach each other over MIDI (same Mac, USB, or Network
MIDI/RTP-MIDI - see below): just play and watch the notes appear in Seq as you play them.

1. In GBG III's Settings, set **MIDI Destination** to **Seq** (it shows up in that picker like
   any other MIDI destination, since Seq advertises itself the same way GBG III does) and make
   sure **Use Midi MPE** is on.
2. In Seq's transport bar, tap **Capture**. It clears X/Y/Z (the drone is kept; ⌘Z brings the
   old notes back) and stays armed (shown as **Stop**) until you tap it again - play as long as
   you like across it. Playback stops if it was running, and play, scrub and note editing are
   unavailable while capturing; Open, Segment and Undo end the capture first.
3. Play in GBG III. X/Y/Z pitch is captured continuously for as long as you're touching the
   graph - gaps between phrases are kept as silence - and Seq draws each note as you play it,
   live, not only once you stop. The drone isn't captured: there's no touch gesture driving it.
4. Tap **Stop** in Seq when you're done. What's already on screen *is* the captured
   performance, raw and unsegmented - nothing to open, nothing to save first. Apply **Segment**
   (see below) whenever you're ready, or leave it as-is and segment/edit some other time.

From an iPad, the connection arrives in Seq as a MIDI *source*, not by the name "Seq", so
there's one more step: in Seq, set **Capture Source** (below the transport bar) to that
connection. Over Network MIDI, pair the iPad and Mac in **Audio MIDI Setup**'s Network MIDI
panel, set GBG III's MIDI Destination to the network session, and pick that session as Seq's
Capture Source. USB is a separate mechanism, not just "plug in the cable": macOS bridges a
USB-connected iPad's MIDI via IDAM (Inter-Device Audio & MIDI), which needs enabling
per-connection in **Audio MIDI Setup**'s *Audio Devices* window (not the MIDI Studio window a
real MIDI interface would show up in) - look for the iPad's own entry there, click **Enable**,
then pick the iPad as Seq's Capture Source. Seq's menus pick up connections made after it
started on their own. Seq assumes GBG III's MPE channel assignment for X/Y/Z - GBG III is
MPE-only, with no separate mode to fall out of sync with, so this always lines up. Set Seq's
**Pitch Bend Range** to match GBG III's (see *Sending Seq's output somewhere*), or captured
pitches come out wrong.

## Opening a file in Seq

Use Seq's **Open** button and pick a `.mid` file. If it holds a raw, unsegmented capture (one
you saved before segmenting), Seq asks:

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
discrete notes. Safe to press more than once: it only acts on notes whose profile is
**Recorded**, so notes you placed, or switched to another profile, are left alone, and an
already-segmented note comes back as itself. A Recorded note whose ends you've moved is
segmented as it now sounds.

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
click a note to select it, then use the inspector to type exact values: start/end time
(with the grid on, as bar.beat.division like a DAW - `3`, `3.2` or `3.2.4`, all counting from 1,
so a note ending at `5` ends on bar 5's downbeat; or in seconds with an `s`, like `1.25s`; with
the grid off, plain seconds), start/end pitch as a ratio of the root (`5/4`, `7/4`) or in Hz
(`440`), choose the profile from the dropdown, **Hold** to make end pitch = start pitch, or
delete it (⌫ also deletes, Esc deselects, Space plays/stops). Pitches snap to the scale and
times to the grid; hold **Option** while clicking or dragging for free placement.

A Recorded note's dots and pitch fields show the pitch it actually sounds at each end, and
changing a note's profile keeps both end pitches where they are - so a capture switched to
Linear becomes a straight line between the same two pitches, and switching back to
**Recorded** restores it exactly. **Purge Recorded** discards the recorded detail for good.

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

**Pitch Bend Range** (next to Internal Synth, ±24 or ±48, default ±24) sets how many semitones a
full pitch bend means, for Graph Out, Synth Out and Capture alike. GBG III doesn't pick this up
over MIDI, so set it to match GBG III's own Settings → Pitch Bend Range, or pitches will come out
wrong in both directions. **Synth Out** tells the synth this range itself (the standard MIDI
Pitch Bend Sensitivity message, RPN 0, on each of its four channels) whenever you switch it on,
change its destination or a channel, change the setting, or press play. A synth that ignores
that message needs its bend range set by hand to match.

## Panic

The red Panic button force-sends a note-off on every channel either output could plausibly be
using, regardless of what Seq's own bookkeeping thinks is currently sounding. Use it if
something gets stuck sounding — a very short note can occasionally slip past Seq's own
note-tracking.
