-- @description Name-match import files as new active takes for selected items
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # Name-match import files as new active takes for selected items
--   Matches selected media items to user-picked audio files by a shared core key
--   (cue number + instrument number, e.g. "1m03_01"), then inserts each matched
--   audio file as a new active take on the corresponding item.
--   # Matching logic
--   - Core key pattern: "%d+m%d+_%d+"  (e.g. "1m03_01")
--   - The key is searched inside the basename of both the item's active take
--     source filename and each picked audio file. Project prefixes and render
--     suffixes are ignored automatically.
--   - Example: "1m03_01_Drums_pre-comb" matches "WOUI_1m03_01_Drums_comb"
-- @links
--   GitHub https://github.com/johanngrillenbeck/CURSE
-- @changelog
--   Added Reapack Packaging Metadata

local r = reaper

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Strip directory and extension, return bare basename
local function basename_no_ext(path)
    local base = path:match("([^/\\]+)$") or path
    return base:match("^(.+)%.[^.]+$") or base
end

-- Find the core matching key inside a filename: e.g. "1m03_01"
local function extract_core_key(filename)
    local base = basename_no_ext(filename)
    -- Accept upper or lower 'm' for robustness
    local key = base:match("%d+[mM]%d+_%d+")
    return key and key:lower() or nil
end

-- Parse a null-separated file list returned by JS_Dialog_BrowseForOpenFiles.
-- Single-file selection: one full path.
-- Multi-file selection: first token = directory, subsequent tokens = filenames.
local function parse_file_list(raw)
    local parts = {}
    for part in (raw .. "\0"):gmatch("([^\0]*)\0") do
        if part ~= "" then parts[#parts + 1] = part end
    end

    if #parts == 0 then return {} end
    if #parts == 1 then return { parts[1] } end

    -- Multiple files: prepend folder to each filename
    local folder = parts[1]
    if not folder:match("[/\\]$") then folder = folder .. "\\" end
    local files = {}
    for i = 2, #parts do
        files[#files + 1] = folder .. parts[i]
    end
    return files
end

-- ─── Guards ───────────────────────────────────────────────────────────────────

if not r.JS_Dialog_BrowseForOpenFiles then
    r.ShowMessageBox(
        "This script requires the js_ReaScriptAPI extension.\n"
        .. "Please install it via ReaPack (Extensions → ReaPack → Browse packages).",
        "jg_CURSE – Missing Extension", 0)
    return
end

local item_count = r.CountSelectedMediaItems(0)
if item_count == 0 then
    r.ShowMessageBox("No media items selected.\n\nSelect the items you want to add renders to, then run the script.",
        "jg_CURSE – Add Renders as Takes", 0)
    return
end

-- ─── Step 1: Collect selected items and their core keys ──────────────────────

local items       = {}  -- { item, key, display_name }
local skipped     = 0

for i = 0, item_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)

    if take and not r.TakeIsMIDI(take) then
        local source   = r.GetMediaItemTake_Source(take)
        local filepath = r.GetMediaSourceFileName(source, "")
        local key      = extract_core_key(filepath)

        if key then
            items[#items + 1] = {
                item         = item,
                key          = key,
                display_name = basename_no_ext(filepath)
            }
        else
            skipped = skipped + 1
        end
    else
        skipped = skipped + 1
    end
end

if #items == 0 then
    r.ShowMessageBox(
        "None of the selected items have active audio takes with a recognisable\n"
        .. "core key (\"<cue>m<nr>_<inst_nr>\", e.g. \"1m03_01\").",
        "jg_CURSE – Add Renders as Takes", 0)
    return
end

-- ─── Step 2: Multi-file picker ────────────────────────────────────────────────

local ok, raw = r.JS_Dialog_BrowseForOpenFiles(
    "Select Rendered Audio Files to Add as Takes",
    "", "",
    "Audio Files\0*.wav;*.aif;*.aiff;*.flac;*.mp3;*.ogg\0All Files\0*.*\0",
    true)   -- allowMultiple = true

if not ok or not raw or raw == "" then
    return  -- user cancelled
end

local picked_files = parse_file_list(raw)

if #picked_files == 0 then
    r.ShowMessageBox("No files could be parsed from the dialog result.",
        "jg_CURSE – Add Renders as Takes", 0)
    return
end

-- ─── Step 3: Build key → file list map ───────────────────────────────────────

local file_map = {}  -- key (string) → list of full paths

for _, fpath in ipairs(picked_files) do
    local key = extract_core_key(fpath)
    if key then
        if not file_map[key] then file_map[key] = {} end
        file_map[key][#file_map[key] + 1] = fpath
    end
end

-- ─── Step 4: Match and insert takes ──────────────────────────────────────────

r.Undo_BeginBlock()

local matched  = 0
local warnings = {}

for _, entry in ipairs(items) do
    local candidates = file_map[entry.key]

    if not candidates or #candidates == 0 then
        warnings[#warnings + 1] =
            "No match:  " .. entry.display_name
            .. "  (key: " .. entry.key .. ")"

    elseif #candidates > 1 then
        local names = {}
        for _, p in ipairs(candidates) do
            names[#names + 1] = "  → " .. basename_no_ext(p)
        end
        warnings[#warnings + 1] =
            "Multiple matches – skipped:  " .. entry.display_name
            .. "  (key: " .. entry.key .. ")\n"
            .. table.concat(names, "\n")

    else
        -- Exactly one match → add as new active take
        local matched_path = candidates[1]

        local new_take = r.AddTakeToMediaItem(entry.item)
        local src      = r.PCM_Source_CreateFromFile(matched_path)

        r.SetMediaItemTake_Source(new_take, src)
        r.GetSetMediaItemTakeInfo_String(
            new_take, "P_NAME", basename_no_ext(matched_path), true)
        r.SetActiveTake(new_take)

        matched = matched + 1
    end
end

r.Undo_EndBlock("jg_CURSE – Add Rendered Files as Takes", -1)
r.UpdateArrange()

-- ─── Step 5: Summary ─────────────────────────────────────────────────────────

local lines = { matched .. " item(s) successfully updated." }

if skipped > 0 then
    lines[#lines + 1] = skipped
        .. " selected item(s) skipped (MIDI take, no audio source, or no recognisable core key)."
end

if #warnings > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Warnings (" .. #warnings .. "):"
    for _, w in ipairs(warnings) do
        lines[#lines + 1] = w
    end
end

r.ShowMessageBox(table.concat(lines, "\n"), "jg_CURSE – Add Renders as Takes", 0)

-- Build peaks for any newly imported source files
r.Main_OnCommand(40047, 0)
