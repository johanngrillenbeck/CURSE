-- jg_CURSE_RouteSelectedTracksToNewSendFx.lua
-- CURSE (Collection of Useful Reaper Scripts and Enhancements)
-- Author: jg
-- Version: 0.1
-- Description:
--   Creates a new FX "bus" track and routes all currently selected tracks to it.
--   - Prompts for FX track name
--   - Prompts for placement: after last selected track OR at end of project
--   - Prompts whether to prefix name with "FX" (checkbox, default ON)
--   - Sets FX track's channel count to the maximum channel count found among selected tracks
--   - Creates sends from each selected track to the FX track, sending all source channels
--
-- Requirements: Reaper 6+, ReaScript API. SWS recommended but not required.
--
-- Notes on multichannel:
--   Reaper send channel mapping: you can set source/dest channel via B_MUTE and I_SRCCHAN/I_DSTCHAN fields.
--   For multichannel, set I_SRCCHAN = -1 to send "all channels" (Reaper uses -1 for automatic/all).
--   Alternatively, we can set the destination track to have the appropriate number of channels and leave default mapping.
--
-- Safety:
--   Script checks for selection and cancels with messages if nothing is selected or user cancels.
--
-- To Do:
--   - Better UI via ReaImGui

local r = reaper

-- Utility: show error message
local function msg(text)
  r.ShowMessageBox(text, "jg_CURSE_AddSendFxToSelectedTracks", 0)
end

-- Get selected tracks
local function get_selected_tracks()
  local tracks = {}
  local cnt = r.CountSelectedTracks(0)
  for i = 0, cnt-1 do
    tracks[#tracks+1] = r.GetSelectedTrack(0, i)
  end
  return tracks
end

-- Determine maximum channel count among given tracks
local function get_max_channels(tracks)
  local maxch = 2
  for i = 1, #tracks do
    local ch = r.GetMediaTrackInfo_Value(tracks[i], "I_NCHAN")
    if ch and ch > maxch then maxch = math.floor(ch) end
  end
  return maxch
end

-- Prompt helpers
local function prompt_fx_name(default)
  local ok, ret = r.GetUserInputs("FX Track Name", 1, "Enter FX track name:", default or "")
  if not ok or ret == "" then return nil end
  return ret
end

local function prompt_placement()
  -- 1: After last selected track, 2: End of project
  local ok, ret = r.GetUserInputs("Placement", 1, "1=After last selected, 2=End:", "1")
  if not ok then return nil end
  ret = tonumber(ret)
  if ret ~= 1 and ret ~= 2 then return nil end
  return ret
end

local function prompt_prefix(defaultChecked)
  -- checkbox via GetUserInputs: we simulate with 0/1 entry
  local default = defaultChecked and "1" or "0"
  local ok, ret = r.GetUserInputs("Use 'FX' Prefix?", 1, "Check=1, Uncheck=0:", default)
  if not ok then return nil end
  if ret ~= "0" and ret ~= "1" then return nil end
  return ret == "1"
end

-- Find insertion index based on placement choice
local function get_insert_index(tracks, placementChoice)
  local total = r.CountTracks(0)
  if placementChoice == 2 then
    return total -- insert at end
  end
  -- After last selected track
  if #tracks == 0 then
    return total -- fallback to end
  end
  local lastIdx = -1
  for i = 1, #tracks do
    local idx = r.GetMediaTrackInfo_Value(tracks[i], "IP_TRACKNUMBER") -- 1-based
    if idx and idx > lastIdx then lastIdx = math.floor(idx) end
  end
  -- Insert after last selected: Reaper insert index is 0-based
  return math.max(0, lastIdx)
end

-- Create a new track at index and return it
local function create_track_at(index)
  r.InsertTrackAtIndex(index, true)
  r.TrackList_AdjustWindows(false)
  return r.GetTrack(0, index)
end

-- Set track name
local function set_track_name(track, name)
  r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

-- Set track channel count
local function set_track_channels(track, nchan)
  r.SetMediaTrackInfo_Value(track, "I_NCHAN", nchan)
end

-- Create send from src to dst, sending all channels
local function create_send_all_channels(src, dst)
  local sendIdx = r.CreateTrackSend(src, dst)
  if sendIdx >= 0 then
    -- Make sure it uses all source channels (-1) and maps to destination starting at 0
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_SRCCHAN", -1)
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_DSTCHAN", 0)
    -- Optional: set send volume to 0 dB
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "D_VOL", 1.0)
  end
end

-- Main
local function main()
  local sel = get_selected_tracks()
  if #sel == 0 then
    msg("No tracks selected.")
    return
  end

  -- Prompts
  local fxName = prompt_fx_name("")
  if not fxName then return end
  local placement = prompt_placement()
  if not placement then return end
  local usePrefix = prompt_prefix(true)
  if usePrefix == nil then return end

  local finalName = usePrefix and ("FX " .. fxName) or fxName

  -- Determine max channels
  local maxCh = get_max_channels(sel)

  -- Insert track
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local insertIndex = get_insert_index(sel, placement)
  local fxTrack = create_track_at(insertIndex)
  if not fxTrack then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("CURSE: Add FX bus and route", -1)
    msg("Failed to create track.")
    return
  end

  set_track_name(fxTrack, finalName)
  set_track_channels(fxTrack, maxCh)

  -- Route selected tracks to FX track
  for i = 1, #sel do
    create_send_all_channels(sel[i], fxTrack)
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("CURSE: Add FX bus and route", -1)
end

main()
