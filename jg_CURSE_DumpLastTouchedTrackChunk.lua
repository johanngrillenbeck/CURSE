-- jg_CURSE_DumpLastTouchedTrackChunk.lua
-- Diagnostic: prints the last-touched track's state chunk to the ReaScript console
-- Author: jg

local r = reaper

local tr = r.GetLastTouchedTrack()
if not tr then
  r.ShowMessageBox("No last-touched track found.", "jg_CURSE", 0)
  return
end

local ok, chunk = r.GetTrackStateChunk(tr, "", false)
if not ok then
  r.ShowMessageBox("Failed to read track state chunk.", "jg_CURSE", 0)
  return
end

r.ShowConsoleMsg("--- jg_CURSE: Last-touched track state chunk START ---\n")
r.ShowConsoleMsg(chunk .. "\n")
r.ShowConsoleMsg("--- jg_CURSE: Last-touched track state chunk END ---\n")

r.ShowMessageBox("Dumped last-touched track state chunk to the ReaScript console. Open View -> Show REAPER console to copy.", "jg_CURSE", 0)
