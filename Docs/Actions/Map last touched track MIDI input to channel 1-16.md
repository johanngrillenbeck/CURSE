---
title: Map last touched track MIDI input to channel 1-16
layout: default
nav_order: 3
---

# Map last touched track MIDI input to channel [1-16]

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

Sets "Map input to channel" to MIDI Channel [1-16] on the last-touched track.

## Script Logic

Uses the track `I_RECINPUT` integer bitfield:

- Bit 12 (value 4096) indicates MIDI input.
- The low 5 bits encode the channel (0 = all, 1–16 = channel).
- The next 6 bits encode the physical input index (63 = all physical inputs).