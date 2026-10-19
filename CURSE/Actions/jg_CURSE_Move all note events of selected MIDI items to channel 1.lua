-- @description Move all note events of selected MIDI items to channel 1
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # Move all note events of selected MIDI items to channel 1
--   This script moves all note events inside the selected MIDI items to channel 1.
--   ## Script logic
--   Iterate over selected items, select all note events, move them to channel 1 (right click -> Note Channel -> 1)
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added script

local r = reaper

r.Undo_BeginBlock()

local item_count = r.CountSelectedMediaItems(0)

if item_count == 0 then
  r.ShowMessageBox("No items selected.", "Move Notes to Channel 1", 0)
  return
end

local notes_moved = 0

for i = 0, item_count - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local take = r.GetActiveTake(item)

  -- Skip items with no active take or non-MIDI takes
  if take and r.TakeIsMIDI(take) then
    local note_idx = 0
    while true do
      -- MIDI_GetNote: retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel
      local retval, selected, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, note_idx)
      if not retval then break end

      -- Only update notes that are not already on channel 1 (0-indexed: channel 1 = 0)
      if chan ~= 0 then
        r.MIDI_SetNote(take, note_idx, nil, nil, nil, nil, 0, nil, nil, true)
        notes_moved = notes_moved + 1
      end

      note_idx = note_idx + 1
    end

    -- Notify Reaper that this take's MIDI has changed
    r.MIDI_Sort(take)
  end
end

r.Undo_EndBlock("Move all note events of selected MIDI items to channel 1", -1)

if notes_moved > 0 then
  r.UpdateArrange()
end