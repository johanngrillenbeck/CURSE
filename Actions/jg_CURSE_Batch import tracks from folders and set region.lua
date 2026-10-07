-- @description Batch import tracks from folders, set region to item length and name after parent folder
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # 1. Batch import tracks from folders
--   Choose directory that contains only folders whose contents you want to import.
--   Choose file extension(s) of files you want to import
--   Choose how many seconds of gap there should be between the items of each folder, if any.
--   This script will then go into each folder and place their items at the same time position on tracks downward from the current one, generating new ones if need be, sorting items numerically or alphabetically.
--   Note that this script intentionally only goes one level deep, not recursively into the folder tree. You can select the parent folder that contains multiple folders, only those will be checked one level deep from the parent.
--   # 2. Set region to item length and name after parent folder
--   After importing the items of a folder, this script will create a region of the same length as the longest clip inside it and name it after the parent folder.
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added script

local r = reaper

-------------------------------------------------------------------------------
-- Helper loading
-------------------------------------------------------------------------------
local function load_helper()
    local info = debug.getinfo(1, 'S')
    local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
    local helper_path = script_path .. "jg_CURSE_Helper.lua"
    local ok, helper = pcall(dofile, helper_path)
    if ok and type(helper) == "table" then
        return helper
    end
    return nil
end

local H = load_helper()
if not H then
    r.ShowMessageBox("Could not load jg_CURSE_Helper.lua.\nPlease ensure it is in the same directory as this script.", "CURSE Error", 0)
    return
end

-------------------------------------------------------------------------------
-- Dependency check
-------------------------------------------------------------------------------
if not r.JS_Dialog_BrowseForFolder then
    r.ShowMessageBox(
        "This script requires the 'js_ReaScriptAPI' extension to select folders.\n\n" ..
        "Please install it via ReaPack:\n" ..
        "Extensions -> ReaPack -> Browse packages -> search for 'js_ReaScriptAPI'.",
        "CURSE: Missing Dependency", 0)
    return
end

-------------------------------------------------------------------------------
-- Natural / Alphanumeric sorting
-------------------------------------------------------------------------------
-- Splits a string into chunks of letters and numbers for natural sorting
-- (e.g., "track_2" comes before "track_10")
local function natural_sort_key(str)
    local result = {}
    for text, num in tostring(str):gmatch("(%D*)(%d*)") do
        if text ~= "" then
            table.insert(result, text:lower())
        end
        if num ~= "" then
            table.insert(result, tonumber(num, 10))
        end
    end
    return result
end

local function natural_compare(a, b)
    local key_a = natural_sort_key(a)
    local key_b = natural_sort_key(b)
    local count = math.min(#key_a, #key_b)

    for i = 1, count do
        local val_a, val_b = key_a[i], key_b[i]
        local type_a, type_b = type(val_a), type(val_b)

        if type_a ~= type_b then
            -- Numbers sort before strings if different types coincide
            return type_a == "number"
        elseif val_a ~= val_b then
            return val_a < val_b
        end
    end

    return #key_a < #key_b
end

-------------------------------------------------------------------------------
-- Path and file utilities
-------------------------------------------------------------------------------
local function get_file_extension(path)
    return path:match("%.([^%.\\/]+)$")
end

local function basename_no_ext(path)
    local filename = path:match("([^\\/]+)$") or path
    return filename:match("^(.*)%.[^%.]+$") or filename
end

-------------------------------------------------------------------------------
-- Enumerate subdirectories and files
-------------------------------------------------------------------------------
local function get_subdirectories(parent_dir)
    local subdirs = {}
    local idx = 0
    while true do
        local subdir = r.EnumerateSubdirectories(parent_dir, idx)
        if not subdir or subdir == "" then break end
        table.insert(subdirs, subdir)
        idx = idx + 1
    end
    table.sort(subdirs, natural_compare)
    return subdirs
end

local function get_matching_files(folder_path, allowed_extensions)
    local files = {}
    local idx = 0
    while true do
        local file = r.EnumerateFiles(folder_path, idx)
        if not file or file == "" then break end

        local ext = get_file_extension(file)
        if ext and allowed_extensions[ext:lower()] then
            table.insert(files, file)
        end
        idx = idx + 1
    end
    table.sort(files, natural_compare)
    return files
end

-------------------------------------------------------------------------------
-- Track management (visible in TCP)
-------------------------------------------------------------------------------
-- Collects visible TCP tracks starting at selected track downwards
-- Also handles dynamically inserting new visible tracks if more tracks are needed
local function create_track_manager(start_track)
    local start_track_idx = r.CSurf_TrackToID(start_track, false) - 1 -- 0-based index in project
    local num_tracks = r.CountTracks(0)
    local visible_tracks = {}

    for i = start_track_idx, num_tracks - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then
            table.insert(visible_tracks, tr)
        end
    end

    local function get_track_at_slot(slot_idx)
        -- slot_idx is 1-based index (for file 1, 2, 3...)
        if slot_idx <= #visible_tracks then
            return visible_tracks[slot_idx]
        end

        -- Need to allocate new track(s) at project bottom
        while #visible_tracks < slot_idx do
            local new_idx = r.CountTracks(0)
            r.InsertTrackAtIndex(new_idx, true)
            local new_track = r.GetTrack(0, new_idx)
            table.insert(visible_tracks, new_track)
        end

        return visible_tracks[slot_idx]
    end

    return get_track_at_slot
end

-------------------------------------------------------------------------------
-- Main function
-------------------------------------------------------------------------------
local function main()
    -- 1. Ensure a starting track is selected
    local start_track = r.GetSelectedTrack(0, 0)
    if not start_track then
        r.ShowMessageBox("Please select a starting track first.\nFiles will be imported downward from this track.", "CURSE: No Track Selected", 0)
        return
    end

    -- 2. Browse for parent folder
    local retval, parent_folder = r.JS_Dialog_BrowseForFolder("Select Parent Folder Containing Subfolders to Import", "")
    if retval ~= 1 or not parent_folder or parent_folder == "" then
        return
    end

    -- Normalise trailing slash
    parent_folder = parent_folder:gsub("[\\/]+$", "")

    -- 3. Ask user for file extensions and gap
    local input_ok, input_str = r.GetUserInputs(
        "Batch Import Options",
        2,
        "File extension(s) (e.g. wav, aif):,Gap between folders (seconds):,extrawidth=100",
        "wav, 0.0"
    )
    if not input_ok then
        return
    end

    local ext_input, gap_input = input_str:match("^(.-),(.*)$")
    if not ext_input then
        ext_input = "wav"
        gap_input = "0.0"
    end

    -- Parse allowed extensions table
    local allowed_extensions = {}
    local ext_count = 0
    for ext in ext_input:gmatch("[^,;%s]+") do
        local clean_ext = ext:gsub("^%.+", ""):lower()
        if clean_ext ~= "" then
            allowed_extensions[clean_ext] = true
            ext_count = ext_count + 1
        end
    end

    if ext_count == 0 then
        r.ShowMessageBox("No valid file extensions specified.", "CURSE: Invalid Input", 0)
        return
    end

    -- Parse gap seconds
    local gap_seconds = tonumber(gap_input:match("[%d%.]+")) or 0.0
    if gap_seconds < 0 then
        gap_seconds = 0.0
    end

    -- 4. Enumerate subdirectories and files
    local subdirs = get_subdirectories(parent_folder)
    if #subdirs == 0 then
        r.ShowMessageBox("No subdirectories found inside:\n" .. parent_folder, "CURSE: No Subfolders Found", 0)
        return
    end

    local sep = package.config:sub(1, 1) or "/"
    local folder_groups = {}
    local total_files = 0

    for _, dir_name in ipairs(subdirs) do
        local dir_path = parent_folder .. sep .. dir_name
        local files = get_matching_files(dir_path, allowed_extensions)
        if #files > 0 then
            table.insert(folder_groups, {
                name = dir_name,
                path = dir_path,
                files = files
            })
            total_files = total_files + #files
        end
    end

    if #folder_groups == 0 or total_files == 0 then
        r.ShowMessageBox("No matching audio files found in any subfolder under:\n" .. parent_folder, "CURSE: No Files Found", 0)
        return
    end

    -- 5. Prepare track manager and import items
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local get_track = create_track_manager(start_track)
    local current_time = r.GetCursorPosition()

    for _, group in ipairs(folder_groups) do
        local folder_max_length = 0

        for slot_idx, filename in ipairs(group.files) do
            local file_path = group.path .. sep .. filename
            local target_track = get_track(slot_idx)

            -- Add media item and take
            local item = r.AddMediaItemToTrack(target_track)
            local take = r.AddTakeToMediaItem(item)

            -- Load audio source
            local src = r.PCM_Source_CreateFromFile(file_path)
            r.SetMediaItemTake_Source(take, src)

            -- Set take name to filename without extension
            local take_name = basename_no_ext(filename)
            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
            r.SetActiveTake(take)

            -- Determine source length
            local src_len = r.GetMediaSourceLength(src)
            if not src_len or src_len <= 0 then
                src_len = 0.1
            end

            -- Position and size item
            r.SetMediaItemInfo_Value(item, "D_POSITION", current_time)
            r.SetMediaItemInfo_Value(item, "D_LENGTH", src_len)

            if src_len > folder_max_length then
                folder_max_length = src_len
            end
        end

        -- Create region for folder if it had items
        if folder_max_length > 0 then
            local rgn_start = current_time
            local rgn_end = current_time + folder_max_length
            r.AddProjectMarker2(0, true, rgn_start, rgn_end, group.name, -1, 0)

            -- Advance time for next folder
            current_time = rgn_end + gap_seconds
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("CURSE: Batch import tracks from folders and set region", -1)
end

main()