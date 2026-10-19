---
title: Name-match import files as new active takes for selected items
layout: default
nav_order: 6
---

# Name-match import files as new active takes for selected items

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

Matches selected media items to user-picked audio files by a shared core key (cue number + instrument number, e.g. "1m03_01"), then inserts each matched audio file as a new active take on the corresponding item.

## Matching logic

- Core key pattern: `%d+m%d+_%d+` (e.g. `1m03_01`).
- The key is searched inside the basename of both the item's active take source filename and each picked audio file. Project prefixes and render suffixes are ignored automatically.
- Example: `1m03_01_Drums_pre-comb` matches `WOUI_1m03_01_Drums_comb`.