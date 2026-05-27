-- @description Map last touched track MIDI to channel n
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # Map last touched track MIDI to channel n
--   Sets "Map input to channel" to MIDI Channel n on the last-touched track
--   # Script Logic
--   Uses the track "I_RECINPUT" integer bitfield.
--   Bits explained (from ReaScript API):
--   - bit 12 (value 4096) = input is MIDI
--   - low 5 bits = channel (0=all, 1..16)
--   - next 6 bits = physical input index (63 = all physical inputs)
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added Reapack Packaging Metadata

local r = reaper

local track = r.GetLastTouchedTrack()
if not track then
  r.ShowMessageBox("No last-touched track found.", "jg_CURSE", 0)
  return
end

local target_zero_based = 15 -- channel 16 -> 15

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
  r.Undo_EndBlock("Map last-touched track input to MIDI channel 16", -1)
  r.ShowMessageBox("Failed to set track state chunk.", "jg_CURSE", 0)
  return
end
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Map last-touched track input to MIDI channel 16", -1)
