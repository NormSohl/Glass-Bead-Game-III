# Glass Bead Game III — User Manual

*Glass Bead Game III is shortened to* **GBG III** *throughout this manual.*

*Draft — not yet public. Will publish alongside App Store approval for GBG III and Seq.*

This manual is organized in increasing order of complexity: setup, then playing GBG III live,
then the settings you'll reach for occasionally, then connecting outboard MIDI gear. If you
want to record a performance and edit it afterward, see the separate **Seq manual**.

---

## 1. Setup

### Requirements

iPadOS 17.2 or later, or macOS 14.2 or later. GBG III runs natively on both.

### Installing GBG III

Installs from the App Store, same as any other app — nothing special needed.

On first launch, GBG III asks for nothing — no microphone permission, no Bluetooth pairing
prompt. It doesn't touch the microphone (its "recording" feature captures your touch/pen
gestures, not audio - see the Seq manual), and MIDI access needs no permission prompt on either
platform. Audio output is on by default - if you don't hear anything, check your device's
volume before anything else. You can start playing immediately.

GBG III is free software. It doesn't require an account, doesn't ask you to sign in or sign up,
has no in-app purchases or payments of any kind, and doesn't track or transmit your data
anywhere — it makes no network connections at all.

---

## 2. Playing GBG III live

### Touch and pen

Drag a finger or Apple Pencil anywhere on the main graph to play X and Y together — your
touch's horizontal position sets X, vertical sets Y. Z has its own separate touch zone (the
narrow slider alongside the graph), so you can hold a Z position with one hand while playing
X/Y with the other — the standard two-handed setup is a pencil for X/Y in your dominant hand,
a thumb on the Z-slider in the other.

### Keyboard shortcuts

On Mac, your keyboard works immediately. On iPad, connect a Bluetooth or USB keyboard (or a
cheap keypad that emulates one) for the same shortcuts. Defaults:

| Action | Keys |
|---|---|
| Drone (toggle) | D, K |
| Portamento (toggle) | G, H |
| Portamento (hold) | Shift |
| Pedal (hold) | Space, F, J |

All of these are remappable — see **Keyboard Mapping** under Settings.

### Apple Pencil Pro squeeze

On iPad with an Apple Pencil Pro, squeezing the pencil toggles the Pedal — a gesture on the
same hand already holding the pencil, so it doesn't compete with your other hand's work on the
Z-slider. If squeeze doesn't seem to do anything, check **Settings → Apple Pencil → Squeeze**
on the iPad itself: if it's set to "Run Shortcut," iPadOS intercepts the gesture before GBG III
ever sees it. Any other setting works.

### The on-screen controls

Drone, Portamento, Pedal, Panic, and Settings are also always reachable as buttons — in the
window's title bar on Mac, or as a column beside the graph on iPad (on whichever side isn't
currently hosting the Z-slider — see **Z-Slider Side** under Settings). Useful any time you'd
rather tap than remember a key, or on iPad without a keyboard connected.

### Portamento — gliding between pitches

By default, touching the graph snaps to the nearest just-intonation scale degree — you always
land precisely on a tuned pitch. **Portamento** turns that off, so pitch follows your touch
continuously instead, letting you glide between pitches the way you'd slide a finger on a
fretless instrument.

Two ways to use it:
- **Toggle** (G, H, or the button) — turns Portamento on or off for as long as you leave it
  that way, across as many touches as you like.
- **Hold** (Shift) — engages Portamento only while held, for a single glide in the middle of an
  otherwise-snapped phrase, then returns to whatever the toggle state was before you pressed it.

This is one of the two main real-time expressive tools, alongside Pedal — reach for it whenever
you want continuous pitch motion instead of discrete steps.

### Pedal — sustain

**Pedal** works like a piano's damper pedal: it keeps whatever's currently sounding held after
you lift your touch, instead of cutting off the moment you release. That lets you let go of the
graph entirely while a tone continues, or layer a new touch on top of an already-sustained one.

- On Mac, Pedal is **held** (Space, F, or J) — press and hold like a real pedal, release to let
  the sound stop naturally.
- On iPad, Pencil squeeze and the on-screen button are both **toggles** instead — squeeze once
  to engage, again to release, since there's no natural physical "hold" gesture for a squeeze.

### Panic

If something ever gets stuck sounding, the red **Panic** button force-silences every voice
immediately. A pure safety net — reach for it any time something doesn't stop when you expect.

---

## 3. Settings

Settings is a popover reached from the gear icon (title bar on Mac, on-screen controls on
iPad). Most of it is display/exploration, not performance-critical, so you'll reach for these
occasionally rather than mid-phrase.

- **Diamonds** — shows/hides the diamond markers at valid scale intersections. Turn it off for
  a cleaner, less cluttered view, especially with Dissonance Field on underneath.
- **Dissonance Field** — a continuous roughness/consonance visualization behind the grid. Turn
  it on when exploring unfamiliar harmonic territory and you want to *see* where the consonant
  regions are, not just the marked diamonds; leave it off otherwise to save a little rendering
  overhead.
- **Filter Grid to Z** — thins the background grid down to just the scale degrees relevant to
  your current Z position, matching how the diamonds themselves thin out. Turn it off if you'd
  rather see the full, uniform grid regardless of where Z sits.
- **Note X / Note Y / Note Z** — mutes an individual voice without hiding its crosshair. Use
  this to practice or explore one or two axes at a time, or to silence a voice you're about to
  reposition before bringing it back in.
- **Harmonics** — picks the prime limit (3 through 19) that generates the scale. Lower limits
  give simpler, more consonant intervals; higher limits open up more exotic, complex ones.
  Change this to shift the harmonic character of everything available to play.
- **View** — Square, Diamond, or Triangle: different visual arrangements of the same pitch
  lattice. Mostly a presentation/exploration choice — try a different one to see the same
  structure from a different angle, or for a change of look when performing.
- **Z-Slider Side** — Left or Right. Moves the Z-slider (and, on iPad, the on-screen control
  column) to whichever side suits your grip - set this once for how you actually hold the
  device/pencil.
- **Live Recording** — captures a performance to hand off to Seq for review/editing. See the
  separate Seq manual for the full recording/import workflow.
- **Keyboard Mapping** — see §2 above for what's remappable.

---

## 4. Connecting outboard MIDI gear

GBG III's **MIDI Destination** and **MIDI Source** pickers (under Use MIDI) list whatever your
Mac or iPad already sees as MIDI ports — physical USB-MIDI interfaces, virtual/IAC ports,
Bluetooth MIDI devices, or Network MIDI sessions. GBG III draws no distinction between these:
if your device already shows up in your Mac's Audio MIDI Setup or your iPad's Bluetooth
settings, it'll show up here too, listed by whatever name that device gives itself. There's no
separate in-app Bluetooth pairing screen — pair the device at the system level first.

- **MIDI Destination** is where GBG III sends pitch/note data to — an external synth, a
  Eurorack MIDI-to-CV interface, or (on the same Mac) Seq.
- **MIDI Source** is where GBG III listens for incoming MIDI from — an external controller, or
  Seq's own live output.
- **Use internal synth** — GBG III's own built-in sound. Turn this off once your outboard gear
  is working and you'd rather hear only that.

### Enabling MPE

**Use MPE** turns on MIDI Polyphonic Expression — each voice (Drone/X/Y/Z) gets its own MIDI
channel with independent pitch bend, rather than sharing a smaller set of fixed channels. Turn
this on only if your receiving gear actually understands MPE; GBG III sends standard MPE
configuration and per-channel pitch bend either way, but a receiver that doesn't understand MPE
will just see several ordinary channels each bending independently, which may or may not be
what you want.

Default channel assignments: with MPE on, Drone/X/Y/Z use channels 5/2/3/4; with MPE off, they
use channels 4/1/2/3. Either way, X/Y/Z occupy the first three channels and Drone comes last —
useful if your receiver is only listening for your three main voices.

### Pitch bend range

GBG III declares its pitch bend range to the receiver automatically (±12 semitones without MPE,
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

*Feedback on this manual, or on GBG III itself, welcome — [contact info / link].*
