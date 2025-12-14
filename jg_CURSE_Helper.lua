-- jg_CURSE_Helper.lua
-- Shared utilities for CURSE Reaper scripts (routing, prompts, track ops)
-- Author: jg
-- Version: 0.1
-- Description:
--   Common functions to avoid duplication across CURSE scripts.
--   Exposes helpers for selection, channels, prompts, insertion, track ops, and routing.

local r = reaper

local H = {}

function H.msg(title, text)
  r.ShowMessageBox(text, title or "jg_CURSE", 0)
end

function H.get_selected_tracks()
  local tracks = {}
  local cnt = r.CountSelectedTracks(0)
  for i = 0, cnt-1 do
    tracks[#tracks+1] = r.GetSelectedTrack(0, i)
  end
  return tracks
end

function H.get_max_channels(tracks)
  local maxch = 2
  for i = 1, #tracks do
    local ch = r.GetMediaTrackInfo_Value(tracks[i], "I_NCHAN")
    if ch and ch > maxch then maxch = math.floor(ch) end
  end
  return maxch
end

-- Generic name prompt
function H.prompt_name(title, label, default)
  local ok, ret = r.GetUserInputs(title or "Track Name", 1, (label or "Enter track name:"), default or "")
  if not ok or ret == "" then return nil end
  return ret
end

-- Placement: 1=after last selected, 2=end of project
function H.prompt_placement(default)
  local ok, ret = r.GetUserInputs("Placement", 1, "1=After last selected, 2=End:", tostring(default or 1))
  if not ok then return nil end
  ret = tonumber(ret)
  if ret ~= 1 and ret ~= 2 then return nil end
  return ret
end

-- Prefix checkbox: returns boolean
function H.prompt_prefix(title, label, defaultChecked)
  local default = defaultChecked and "1" or "0"
  local ok, ret = r.GetUserInputs(title or "Use Prefix?", 1, (label or "Check=1, Uncheck=0:"), default)
  if not ok then return nil end
  if ret ~= "0" and ret ~= "1" then return nil end
  return ret == "1"
end

function H.get_insert_index(tracks, placementChoice)
  local total = r.CountTracks(0)
  if placementChoice == 2 then
    return total
  end
  if #tracks == 0 then
    return total
  end
  local lastIdx = -1
  for i = 1, #tracks do
    local idx = r.GetMediaTrackInfo_Value(tracks[i], "IP_TRACKNUMBER")
    if idx and idx > lastIdx then lastIdx = math.floor(idx) end
  end
  return math.max(0, lastIdx)
end

function H.create_track_at(index)
  r.InsertTrackAtIndex(index, true)
  r.TrackList_AdjustWindows(false)
  return r.GetTrack(0, index)
end

function H.set_track_name(track, name)
  r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

function H.set_track_channels(track, nchan)
  r.SetMediaTrackInfo_Value(track, "I_NCHAN", nchan)
end

function H.create_send_all_channels(src, dst)
  local sendIdx = r.CreateTrackSend(src, dst)
  if sendIdx >= 0 then
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_SRCCHAN", 0)
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_DSTCHAN", 0)
    r.SetTrackSendInfo_Value(src, 0, sendIdx, "D_VOL", 1.0)
  end
  return sendIdx
end

function H.disable_master_send(track)
  r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
end

-- Create sends covering all channel pairs (1/2, 3/4, ...) up to numChannels
function H.create_multichannel_sends(src, dst, numChannels)
  local pairs = math.max(1, math.floor(numChannels / 2))
  for i = 0, pairs - 1 do
    local sendIdx = r.CreateTrackSend(src, dst)
    if sendIdx >= 0 then
      local offset = i * 2
      r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_SRCCHAN", offset)
      r.SetTrackSendInfo_Value(src, 0, sendIdx, "I_DSTCHAN", offset)
      r.SetTrackSendInfo_Value(src, 0, sendIdx, "D_VOL", 1.0)
    end
  end
end

-- Config loading and color helpers
function H.load_config()
  local info = debug.getinfo(1, 'S')
  local helper_path = info.source:match("^@(.+)$") or ""
  local dir = helper_path:match("^(.*)[/\\]") or ""
  local cfg_path = dir .. "/jg_CURSE_Config.lua"
  local ok, cfg = pcall(dofile, cfg_path)
  if ok and type(cfg) == "table" then return cfg end
  return { colors = { FX = "faf06b", Bus = "906bfa" } }
end

local function hex_to_rgb(hex)
  if not hex then return nil end
  local s = tostring(hex):gsub("#", "")
  if #s ~= 6 then return nil end
  local r_ = tonumber(s:sub(1,2), 16)
  local g_ = tonumber(s:sub(3,4), 16)
  local b_ = tonumber(s:sub(5,6), 16)
  if not (r_ and g_ and b_) then return nil end
  return r_, g_, b_
end

function H.set_track_color_hex(track, hex)
  local r_, g_, b_ = hex_to_rgb(hex)
  if not r_ then return false end
  local native = r.ColorToNative(r_, g_, b_)
  -- Mark as custom color with 0x1000000 flag
  r.SetTrackColor(track, native | 0x1000000)
  return true
end

function H.apply_default_color(track, kind)
  local cfg = H.load_config()
  local hex = cfg and cfg.colors and cfg.colors[kind]
  if hex then H.set_track_color_hex(track, hex) end
end

return H
