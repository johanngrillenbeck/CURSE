-- @description Smart freeze (Multichannel)
-- @version 1.0
-- @author Ilias-Timon Poulakis (FeedTheCat), this multichannel version adjustment by Johann Grillenbeck
-- @license MIT
-- @about
--   # Multichannel smart freeze instruments
--   This script allows you to freeze only the Instruments in the FX Chain, keeping all other VSTs online.
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Changed FTC's action ID to the multichannel one, static behaivior to render instruments.

-------------------------------------------------------------------------------
-- Dependency check
-------------------------------------------------------------------------------

if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

-------------------------------------------------------------------------------
-- Local settings
-------------------------------------------------------------------------------

local is_unlock = true
local render_tail = 2000 -- milliseconds
-- Add FX name fragments here when they must render in realtime.
local realtime_fx_names = {}

-------------------------------------------------------------------------------
-- Instrument lookup
-------------------------------------------------------------------------------

function GetLastInstrument(track)
    local instr_fx = reaper.TrackFX_GetInstrument(track)
    for fx = instr_fx + 1, reaper.TrackFX_GetCount(track) - 1 do
        local _, fx_type = reaper.TrackFX_GetNamedConfigParm(track, fx, 'fx_type')
        if type(fx_type) == 'string' and fx_type:match('i$') then instr_fx = fx end
    end
    return instr_fx
end

-------------------------------------------------------------------------------
-- Collect selected tracks, FX, and item bounds
-------------------------------------------------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local GetItemInfo = reaper.GetMediaItemInfo_Value
local item_guids = {}
local item_bounds = {}
local is_realtime = false
local selected_tracks = {}
local tracks_to_freeze = {}
local tracks_without_instrument = {}

local fx_backup_tracks

local sel_track_cnt = reaper.CountSelectedTracks(0)
for t = 0, sel_track_cnt - 1 do
    local track = reaper.GetSelectedTrack(0, t)
    selected_tracks[#selected_tracks + 1] = track

    local fx_cnt = reaper.TrackFX_GetCount(track)
    local instr_fx = GetLastInstrument(track)

    if instr_fx >= 0 then
        -- Detect any enabled FX that requires realtime rendering.
        for fx = 0, fx_cnt - 1 do
            if reaper.TrackFX_GetEnabled(track, fx) then
                local _, fx_name = reaper.TrackFX_GetFXName(track, fx, '')
                if type(fx_name) == 'string' then
                    for _, name in ipairs(realtime_fx_names) do
                        if type(name) == 'string' and name ~= '' and fx_name:lower():match(name:lower()) then
                            is_realtime = true
                        end
                    end
                end
            end
        end
    end

    local freeze_up_to_fx
    if instr_fx >= 0 then
        tracks_to_freeze[#tracks_to_freeze + 1] = track
        if instr_fx < fx_cnt - 1 then
            freeze_up_to_fx = instr_fx
        end
    else
        tracks_without_instrument[#tracks_without_instrument + 1] = track
    end

    if freeze_up_to_fx then
        -- Preserve post-instrument FX on a temporary hidden track.
        local track_cnt = reaper.CountTracks()
        reaper.InsertTrackAtIndex(track_cnt, false)
        local fx_track = reaper.GetTrack(0, track_cnt)

        fx_backup_tracks = fx_backup_tracks or {}
        fx_backup_tracks[track] = fx_track

        -- Keep the temporary FX track out of the TCP and mixer.
        reaper.SetMediaTrackInfo_Value(fx_track, 'B_SHOWINMIXER', 0)
        reaper.SetMediaTrackInfo_Value(fx_track, 'B_SHOWINTCP', 0)
        -- Move FX after the last instrument onto the temporary track.
        for i = fx_cnt, freeze_up_to_fx + 1, -1 do
            reaper.TrackFX_CopyToTrack(track, i, fx_track, 0, true)
        end
    end

    item_bounds[track] = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', 0)
        item_guids[guid] = true

        local lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
        local length = GetItemInfo(item, 'D_LENGTH')
        local start_pos = GetItemInfo(item, 'D_POSITION')
        local end_pos = start_pos + length
        local bounds = {lane = lane, start_pos = start_pos, end_pos = end_pos}
        table.insert(item_bounds[track], bounds)
    end

end

-------------------------------------------------------------------------------
-- Configure freeze render options
-------------------------------------------------------------------------------

local prev_render_tail = reaper.SNM_GetIntConfigVar('rendertail', 0)
local prev_work_render = reaper.SNM_GetIntConfigVar('workrender', 0)

reaper.SNM_SetIntConfigVar('rendertail', render_tail)

local work_render = prev_work_render
local is_include_tail = prev_work_render & 64 == 64
-- Disable "Include tail when freezing entire tracks" for this operation.
if is_include_tail then work_render = work_render - 64 end
-- Limit render speed to realtime when a configured FX requires it.
if is_realtime then work_render = work_render | 8 end
reaper.SNM_SetIntConfigVar('workrender', work_render)

-------------------------------------------------------------------------------
-- Freeze tracks that contain instruments
-------------------------------------------------------------------------------

for _, track in ipairs(tracks_without_instrument) do
    reaper.SetTrackSelected(track, false)
end
if #tracks_to_freeze > 0 then
    reaper.Main_OnCommand(40877, 0)
end
-- Restore the user's original track selection.
for _, track in ipairs(selected_tracks) do
    reaper.SetTrackSelected(track, true)
end

-------------------------------------------------------------------------------
-- Restore render settings and temporary FX
-------------------------------------------------------------------------------

reaper.SNM_SetIntConfigVar('rendertail', prev_render_tail)
reaper.SNM_SetIntConfigVar('workrender', prev_work_render)

if fx_backup_tracks then
    for freeze_track, fx_track in pairs(fx_backup_tracks) do
        local fx_cnt = reaper.TrackFX_GetCount(fx_track)
        -- Return the preserved FX to its original track.
        for i = 0, fx_cnt - 1 do
            reaper.TrackFX_CopyToTrack(fx_track, 0, freeze_track, fx_cnt + i, 1)
        end
        reaper.DeleteTrack(fx_track)
    end
end

-------------------------------------------------------------------------------
-- Restore item lengths and lock state
-------------------------------------------------------------------------------

for _, track in ipairs(selected_tracks) do
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', 0)

        -- Process only items created by the freeze operation.
        if not item_guids[guid] then
            -- Unlock newly rendered items when configured.
            if is_unlock then
                reaper.SetMediaItemInfo_Value(item, 'C_LOCK', 0)
            end

            local is_item_extended = true

            local lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
            local length = GetItemInfo(item, 'D_LENGTH')
            local start_pos = GetItemInfo(item, 'D_POSITION')
            local end_pos = start_pos + length

            for _, bounds in ipairs(item_bounds[track]) do
                if bounds.start_pos == start_pos and bounds.end_pos == end_pos then
                    if bounds.lane == lane then
                        is_item_extended = false
                        break
                    end
                end
            end

            if is_item_extended then
                -- Remove the render tail from extended items.
                local length_without_tail = length - render_tail / 1000
                reaper.SetMediaItemLength(item, length_without_tail, true)
            end

        end
    end
end

-------------------------------------------------------------------------------
-- Finalize project update
-------------------------------------------------------------------------------

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock('Smart-freeze tracks', -1)