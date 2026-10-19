-- @description CURSE Helper
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # CURSE Helper
--   Common functions to avoid duplication across CURSE scripts.
--   Exposes helpers for selection, channels, prompts, insertion, track ops, and routing.
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added Reapack Packaging Metadata

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

-- Find a track by exact name (case-sensitive)
function H.find_track_by_exact_name(name)
  local trackCount = reaper.GetNumTracks()
  for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(track)
    if tname == name then
      return track
    end
  end
  return nil
end

-- Find the first FX index (normal or input/rec FX) whose name contains nameSubstr
-- Returns -1 if not found. The returned index is suitable for TrackFX_* APIs.
function H.find_midi_tool_fx_index(track, nameSubstr)
  if not track then return -1 end

  local fxCount = reaper.TrackFX_GetCount(track)
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, "")
    if fxName and fxName:find(nameSubstr, 1, true) then
      return i
    end
  end

  local recCount = reaper.TrackFX_GetRecCount(track)
  for i = 0, recCount - 1 do
    local idx = 0x1000000 + i
    local _, fxName = reaper.TrackFX_GetFXName(track, idx, "")
    if fxName and fxName:find(nameSubstr, 1, true) then
      return idx
    end
  end

  return -1
end

-- Find a parameter index by exact parameter name
function H.find_fx_param_index(track, fxIdx, paramName)
  local paramCount = reaper.TrackFX_GetNumParams(track, fxIdx)
  for p = 0, paramCount - 1 do
    local _, pname = reaper.TrackFX_GetParamName(track, fxIdx, p, "")
    if pname == paramName then
      return p
    end
  end
  return -1
end

-- Set the JSFX "Output Channel" parameter for IXix MIDI Tool v2
-- channel: 1..16
function H.set_jsfx_output_channel(track, fxIdx, channel)
  local steps = 16
  local stepValue = math.max(1, math.min(steps, channel))
  local normalized = stepValue / steps

  local paramIdx = H.find_fx_param_index(track, fxIdx, "Output Channel")
  if paramIdx < 0 then
    return false, "'Output Channel' parameter not found in MIDI Tool v2"
  end

  reaper.TrackFX_SetParamNormalized(track, fxIdx, paramIdx, normalized)
  return true
end

return H
