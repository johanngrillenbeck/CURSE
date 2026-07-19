-- @description Map last touched track MIDI input to channel [1-16]
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # Map last touched track MIDI input to channel [1-16]
--   Sets "Map input to channel" to MIDI Channel [1-16] on the last-touched track
--   # Script Logic
--   Uses the track "I_RECINPUT" integer bitfield.
--   Bits explained (from ReaScript API):
--   - bit 12 (value 4096) = input is MIDI
--   - low 5 bits = channel (0=all, 1..16)
--   - next 6 bits = physical input index (63 = all physical inputs)
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added script as a metapackage
-- @metapackage
-- @provides
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 01.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 02.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 03.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 04.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 05.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 06.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 07.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 08.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 09.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 10.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 11.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 12.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 13.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 14.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 15.lua
--   [main] . > jg_CURSE_Map last touched track MIDI input to channel 16.lua



local r = reaper

-- Determine which channel slot this instance is installed as by reading the filename.
-- e.g. "jg_CURSE_Map selected tracks MIDI input to channel 07.lua" -> channel 7
local script_path = select(2, r.get_action_context())
local script_name = script_path:match('([^/\\_]+)%.lua$')
local channel = tonumber(script_name and script_name:match('channel (%d+)'))
if not channel or channel < 1 or channel > 16 then
  r.ShowMessageBox(
    "Could not determine MIDI channel from script filename.\nExpected a filename containing 'channel XX' (01-16).",
    "jg_CURSE", 0)
  return
end

local target_zero_based = channel - 1 -- REAPER uses 0-based channel index

-- Set the last-touched track's MIDI input mapping to the slot channel
local track = r.GetLastTouchedTrack()
if not track then
  r.ShowMessageBox("No last-touched track found.", "jg_CURSE", 0)
  return
end

-- Read chunk
local ok, chunk = r.GetTrackStateChunk(track, "", false)
if not ok or not chunk then
  r.ShowMessageBox("Failed to read track state chunk.", "jg_CURSE", 0)
  return
end

-- Replace existing MIDI_INPUT_CHANMAP if present
local replaced
chunk, replaced = chunk:gsub("MIDI_INPUT_CHANMAP%s+%-?%d+", "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based))

-- If not present, insert before the first occurrence of MIDIOUT or NAME, otherwise append near top
if replaced == 0 then
  local insert_pos = chunk:find("\nMIDIOUT") or chunk:find("\nNAME")
  if insert_pos then
    local before = chunk:sub(1, insert_pos)
    local after = chunk:sub(insert_pos + 1)
    chunk = before .. "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based) .. "\n" .. after
  else
    -- fallback: put at start
    chunk = "MIDI_INPUT_CHANMAP " .. tostring(target_zero_based) .. "\n" .. chunk
  end
end

-- Apply change with undo
local undo_label = string.format("Map last-touched track MIDI input to channel %d", channel)
r.Undo_BeginBlock()
local setok = r.SetTrackStateChunk(track, chunk, false)
if not setok then
  r.Undo_EndBlock(undo_label, -1)
  r.ShowMessageBox("Failed to set track state chunk.", "jg_CURSE", 0)
  return
end
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock(undo_label, -1)

