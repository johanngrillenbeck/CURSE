-- @description Map selected tracks MIDI input to OMNI - disable mapping
-- @version 0.2
-- @author Johann Grillenbeck
-- @about
--   # Map selected tracks MIDI input to OMNI - disable mapping
--   Disable "Map input to channel" (set to omnichannel / -1) on all selected tracks
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Now uses "GetSelectedTrack" instead of "LastTouchedTrack"
--   Changed name to reflect behavior

local r = reaper

local track_count = r.CountSelectedTracks(0)
if track_count == 0 then
  r.ShowMessageBox("No selected tracks found.", "jg_CURSE", 0)
  return
end

local target_zero_based = -1 -- omnichannel -> -1

r.Undo_BeginBlock()

for i = 0, track_count - 1 do
  local track = r.GetSelectedTrack(0, i)

  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if ok and chunk then
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

    r.SetTrackStateChunk(track, chunk, false)
  end
end

r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Disable MIDI channel map on selected tracks", -1)
