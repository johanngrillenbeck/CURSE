-- jg_CURSE_FindMapLinesInTrackChunk.lua
-- Prints chunk lines that mention 'map' or 'MIDI' (case-insensitive)

local r = reaper

local tr = r.GetLastTouchedTrack()
if not tr then r.ShowMessageBox("No last-touched track.", "jg_CURSE", 0) return end

local ok, chunk = r.GetTrackStateChunk(tr, "", false)
if not ok then r.ShowMessageBox("Failed to read track state chunk.", "jg_CURSE", 0) return end

local lines = {}
for line in chunk:gmatch("[^\r\n]+") do
  local l = line:lower()
  if l:find("map") or l:find("midi") then
    lines[#lines+1] = line
  end
end

if #lines == 0 then
  r.ShowMessageBox("No 'map'/'midi' lines found in track chunk.", "jg_CURSE", 0)
  return
end

r.ShowConsoleMsg("--- jg_CURSE: Matching lines START ---\n")
for i=1,#lines do r.ShowConsoleMsg(lines[i] .. "\n") end
r.ShowConsoleMsg("--- jg_CURSE: Matching lines END ---\n")

r.ShowMessageBox("Dumped matching lines to REAPER console.", "jg_CURSE", 0)
