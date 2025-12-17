--[[
	jg_CURSE_IXix Midi Tool v2 Output Ch1 on MIDI IN

	Sets the IXix "MIDI Tool v2" Output Channel to 1 on the track named "MIDI IN".

	Project: CURSE (Collection of Useful Reaper Scripts and Enhancements)
	Author: jg
	Depends: REAPER 6+ (JSFX: MIDI Tool v2)

	Behavior:
	- Finds the track named exactly "MIDI IN".
	- Finds the first FX instance whose name contains "MIDI Tool v2" (supports both
		display variants like "JS: MIDI Tool v2" and "MIDI Tool v2").
	- Sets its "Output Channel" parameter to channel 1.
	- If track or FX is missing, shows an error message and exits.

	Notes on parameter mapping:
	- In the JSFX source, slider14 is labeled "Output Channel" with range 0..16 where
		0 = "Original" and 1..16 = forced channels. Normalized value = step/16.
]]

local TARGET_TRACK_NAME = "MIDI IN"
local TARGET_FX_SUBSTR = "MIDI Tool v2"
local TARGET_CHANNEL = 1 -- 1..16

-- Load shared helper from same directory
local function script_dir()
  local info = debug.getinfo(1, 'S')
  local src = info.source:match("^@(.+)$") or ""
  return src:match("^(.*)[/\\]") or ""
end

local helper_path = script_dir() .. "/jg_CURSE_Helper.lua"
local H = dofile(helper_path)

-- Main
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local track = H.find_track_by_exact_name(TARGET_TRACK_NAME)
if not track then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("CURSE: Set MIDI Tool Output Ch 1 (track missing)", -1)
  H.msg("CURSE: MIDI Tool Output Channel", "Track '" .. TARGET_TRACK_NAME .. "' not found.\nPlease create it and add '" .. TARGET_FX_SUBSTR .. "'.")
  return
end

local fxIdx = H.find_midi_tool_fx_index(track, TARGET_FX_SUBSTR)
if fxIdx < 0 then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("CURSE: Set MIDI Tool Output Ch 1 (FX missing)", -1)
  H.msg("CURSE: MIDI Tool Output Channel", "'" .. TARGET_FX_SUBSTR .. "' not found on track '" .. TARGET_TRACK_NAME .. "'.")
  return
end

local ok, err = H.set_jsfx_output_channel(track, fxIdx, TARGET_CHANNEL)
if not ok then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("CURSE: Set MIDI Tool Output Ch 1 (param missing)", -1)
  H.msg("CURSE: MIDI Tool Output Channel", err)
  return
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("CURSE: Set MIDI Tool Output Channel to 1", -1)
