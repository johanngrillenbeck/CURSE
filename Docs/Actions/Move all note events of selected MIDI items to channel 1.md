---
title: Move all note events of selected MIDI items to channel 1
layout: default
nav_order: 6
---

# Move all note events of selected MIDI items to channel 1

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

This script moves all note events inside the selected MIDI items to channel 1.

## Script logic

Iterates over selected items, selects all note events, and moves them to channel 1 (right click → Note Channel → 1).