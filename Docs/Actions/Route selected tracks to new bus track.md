---
title: Route selected tracks to new bus track
layout: default
nav_order: 7
---

# Route selected tracks to new bus track

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

Creates a new Bus track and routes all currently selected tracks to it via sends.

- Disables the selected tracks' Master/Parent send so audio flows through the Bus to Master.
- Prompts for the Bus track name.
- Prompts for placement: after the last selected track or at the end of the project.
- Prompts whether to prefix the name with "B" (checkbox, default ON).
- Sets the Bus track's channel count to the maximum channel count found among selected tracks.
- Creates sends from each selected track to the Bus track, sending all source channels.

## Notes on multichannel audio for script development

Reaper send channel mapping can be set with the `B_MUTE`, `I_SRCCHAN`, and `I_DSTCHAN` fields. For multichannel, set `I_SRCCHAN = -1` to send all channels (Reaper uses -1 for automatic/all). Alternatively, set the destination track to the appropriate number of channels and leave the default mapping.