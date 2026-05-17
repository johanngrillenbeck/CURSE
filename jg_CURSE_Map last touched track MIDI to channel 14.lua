-- jg_CURSE_MapLastTouchedTrackMIDIToChannel14.lua
-- Set "Map input to channel" to MIDI Channel 14 on the last-touched track
-- Author: jg
-- Version: 0.1

local r = reaper

local track = r.GetLastTouchedTrack()
if not track then
  r.ShowMessageBox("No last-touched track found.", "jg_CURSE", 0)
  return
end

local target_zero_based = 13 -- channel 14 -> 13

local ok, chunk = r.GetTrackStateChunk(track, "", false)
if not ok or not chunk then
  r.ShowMessageBox("Failed to read track state chunk.", "jg_CURSE", 0)
  return
end

local replaced
chunk, replaced = chunk:gsub("MIDI_INPUT_CHANMAP%s+%-?%d+", "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based))

if replaced == 0 then
  local insert_pos = chunk:find("\nMIDIOUT") or chunk:find("\nNAME")
  if insert_pos then
    local before = chunk:sub(1, insert_pos)
    local after = chunk:sub(insert_pos + 1)
    chunk = before .. "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based) .. "\n" .. after
  else
    chunk = "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based) .. "\n" .. chunk
  end
end

r.Undo_BeginBlock()
local setok = r.SetTrackStateChunk(track, chunk, false)
if not setok then
  r.Undo_EndBlock("Map last-touched track input to MIDI channel 14", -1)
  r.ShowMessageBox("Failed to set track state chunk.", "jg_CURSE", 0)
  return
end
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Map last-touched track input to MIDI channel 14", -1)
