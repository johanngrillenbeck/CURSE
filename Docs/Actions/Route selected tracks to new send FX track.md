---
title: Route selected tracks to new send FX track
layout: default
nav_order: 8
---

# Route selected tracks to new send FX track

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

Creates a new FX "bus" track and routes all currently selected tracks to it.

- Prompts for the FX track name.
- Prompts for placement: after the last selected track or at the end of the project.
- Prompts whether to prefix the name with "FX" (checkbox, default ON).
- Sets the FX track's channel count to the maximum channel count found among selected tracks.
- Creates sends from each selected track to the FX track, sending all source channels.

## Notes on multichannel audio for script development

Reaper send channel mapping can be set with the `B_MUTE`, `I_SRCCHAN`, and `I_DSTCHAN` fields. For multichannel, set `I_SRCCHAN = -1` to send all channels (Reaper uses -1 for automatic/all). Alternatively, set the destination track to the appropriate number of channels and leave the default mapping.