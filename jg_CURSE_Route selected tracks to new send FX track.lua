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

-- Load helper from the same directory
local function load_helper()
  local info = debug.getinfo(1, 'S')
  local script_path = info.source:match("^@(.+)$") or ""
  local dir = script_path:match("^(.*)[/\\]") or ""
  local helper_path = dir .. "/jg_CURSE_Helper.lua"
  local ok, H = pcall(dofile, helper_path)
  if ok and type(H) == "table" then return H end
  reaper.ShowMessageBox("Failed to load helper at: " .. helper_path, "jg_CURSE", 0)
  return nil
end

local H = load_helper()
if not H then return end

-- Main
local function main()
  local sel = H.get_selected_tracks()
  if #sel == 0 then
    H.msg("jg_CURSE_RouteSelectedTracksToNewSendFx", "No tracks selected.")
    return
  end

  -- Prompts
  local fxName = H.prompt_name("FX Track Name", "Enter FX track name:", "")
  if not fxName then return end
  local placement = H.prompt_placement(1)
  if not placement then return end
  local usePrefix = H.prompt_prefix("Use 'FX' Prefix?", "Check=1, Uncheck=0:", true)
  if usePrefix == nil then return end

  local finalName = usePrefix and ("FX " .. fxName) or fxName

  -- Determine max channels
  local maxCh = H.get_max_channels(sel)

  -- Insert track
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local insertIndex = H.get_insert_index(sel, placement)
  local fxTrack = H.create_track_at(insertIndex)
  if not fxTrack then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("CURSE: Add FX bus and route", -1)
    H.msg("jg_CURSE_RouteSelectedTracksToNewSendFx", "Failed to create track.")
    return
  end

  H.set_track_name(fxTrack, finalName)
  H.set_track_channels(fxTrack, maxCh)
  H.apply_default_color(fxTrack, "FX")

  -- Route selected tracks to FX track
  for i = 1, #sel do
    local t = sel[i]
    local ch = reaper.GetMediaTrackInfo_Value(t, "I_NCHAN")
    H.create_multichannel_sends(t, fxTrack, math.floor(ch or 2))
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("CURSE: Add FX bus and route", -1)
end

main()
