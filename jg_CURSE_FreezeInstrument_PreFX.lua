-- jg_CURSE_FreezeInstrument_PreFX.lua
-- CURSE (Collection of Useful Reaper Scripts and Enhancements)
-- Author: jg
-- Version: 0.1
-- Description:
--   "Intelligent" freeze for instrument tracks: prints ONLY the audio up to a neutral
--   "dummy" FX (kept as first FX), leaving later FX online and editable.
--
--   This script intentionally uses REAPER's *native* freeze implementation (via the
--   FX context menu) so that REAPER creates/maintains "Track Freeze Details" for
--   non-destructive re-freezing and proper unfreeze.
--
-- How it works (mirrors the manual workflow):
--   1) Ensure dummy FX exists and is in FX slot #1 (top of chain)
--   2) Open the track FX chain and select that first FX
--   3) Simulate keystrokes to navigate:
--        Shift+F10 / F / F / Right / Up / Up / Enter
--      ...which triggers: "Freeze track to multichannel, up to last selected FX"
--
-- Requirements:
--   - REAPER v6+
--   - JS_ReaScriptAPI extension (for reliable window focus + key message sending)
--   - SWS is not required
--
-- Notes:
--   - UI automation is inherently brittle across REAPER versions/themes/localizations.
--     The navigation sequence is configurable in `config()`.

local r = reaper

-- Load helper from the same directory (for shared prompts/messages)
local function load_helper()
  local info = debug.getinfo(1, 'S')
  local script_path = info.source:match('^@(.+)$') or ''
  local dir = script_path:match('^(.*)[/\\]') or ''
  local helper_path = dir .. '/jg_CURSE_Helper.lua'
  local ok, H = pcall(dofile, helper_path)
  if ok and type(H) == 'table' then return H end
  r.ShowMessageBox('Failed to load helper at: ' .. helper_path, 'jg_CURSE', 0)
  return nil
end

local H = load_helper()
if not H then return end

-- ============================================================
-- Config
-- ============================================================

-- Edit this method if REAPER changes the context menu structure.
-- The sequence must be in exact order.
local function config()
  return {
    -- The neutral "dummy" FX used as the freeze cut point.
    -- We'll search by substring and instantiate by full name.
    dummyFxFullName = 'JS: Loudness Meter Peak/RMS/LUFS (Cockos)',
    dummyFxMatchSubstr = 'Loudness Meter Peak/RMS/LUFS',

    -- Navigation "cheat-code".
    -- Each entry is one keystroke. Optional `mods` can include: SHIFT, CTRL, ALT.
    -- Keys supported by the default map below: letters, F10, UP, DOWN, LEFT, RIGHT, ENTER.
    navigation = {
      { mods = { 'SHIFT' }, key = 'F10' },
      { key = 'F' },
      { key = 'F' },
      { key = 'RIGHT' },
      { key = 'UP' },
      { key = 'UP' },
      { key = 'ENTER' },
    },

    -- Small delay between keystrokes (seconds). Keeps UI automation more stable.
    keyDelaySeconds = 0.04,

    -- Re-focus the FX list control before *every* navigation step.
    -- This greatly improves reliability when REAPER briefly steals focus.
    refocusBeforeEachStep = true,

    -- After running the freeze action, hide the FX chain again.
    closeFxChainAfter = false,

    -- Process mode: 'selected' tracks (default) or 'last_touched'
    targetMode = 'selected',
  }
end

-- ============================================================
-- JS extension helpers
-- ============================================================

local function has_js_api()
  return type(r.JS_WindowMessage_Send) == 'function'
    and type(r.JS_Window_Find) == 'function'
    and type(r.JS_Window_SetFocus) == 'function'
    and type(r.JS_Window_SetForeground) == 'function'
    and type(r.JS_Mouse_GetState) == 'function'
    and type(r.JS_Mouse_SetPosition) == 'function'
end

-- Virtual-Key mapping (Windows)
local VK = {
  SHIFT = 0x10,
  CTRL  = 0x11,
  ALT   = 0x12,

  ENTER = 0x0D,

  LEFT  = 0x25,
  UP    = 0x26,
  RIGHT = 0x27,
  DOWN  = 0x28,

  F10   = 0x79,
}

-- Mouse button codes for JS API
local MOUSE = {
  LMB = 1,
  RMB = 2,
}

local function key_to_vk(key)
  if not key then return nil end
  local k = tostring(key):upper()
  if VK[k] then return VK[k] end
  -- A-Z
  if #k == 1 then
    local b = k:byte(1)
    if b >= 65 and b <= 90 then return b end
    -- 0-9
    if b >= 48 and b <= 57 then return b end
  end
  return nil
end

local function mod_to_vk(mod)
  if not mod then return nil end
  local m = tostring(mod):upper()
  return VK[m]
end

local function send_key(hwnd, vk)
  -- Important: F10 often routes through the "system" keypath (WM_SYSKEY*).
  -- If we send WM_KEY* for F10, some windows/controls won't open the context/menu.
  local downMsg = (vk == VK.F10) and 'WM_SYSKEYDOWN' or 'WM_KEYDOWN'
  local upMsg = (vk == VK.F10) and 'WM_SYSKEYUP' or 'WM_KEYUP'
  r.JS_WindowMessage_Send(hwnd, downMsg, vk, 0, 0, 0)
  r.JS_WindowMessage_Send(hwnd, upMsg, vk, 0, 0, 0)
end

local function send_key_with_mods(hwnd, mods, key)
  mods = mods or {}

  -- press modifiers
  for i = 1, #mods do
    local mvk = mod_to_vk(mods[i])
    if mvk then
      r.JS_WindowMessage_Send(hwnd, 'WM_KEYDOWN', mvk, 0, 0, 0)
    end
  end

  -- press+release key
  local kvk = key_to_vk(key)
  if kvk then
    send_key(hwnd, kvk)
  end

  -- release modifiers (reverse order)
  for i = #mods, 1, -1 do
    local mvk = mod_to_vk(mods[i])
    if mvk then
      r.JS_WindowMessage_Send(hwnd, 'WM_KEYUP', mvk, 0, 0, 0)
    end
  end
end

-- ============================================================
-- FX helpers
-- ============================================================

local function get_track_name(track)
  local _, name = r.GetTrackName(track)
  return name or ''
end

local function track_is_frozen(track)
  -- Heuristic: frozen tracks have FREEZE lines in the state chunk.
  local ok, chunk = r.GetTrackStateChunk(track, '', false)
  if not ok or not chunk then return false end
  return chunk:find('\nFREEZE', 1, true) ~= nil
end

local function find_fx_index_by_substr(track, substr)
  if not track then return -1 end
  local cnt = r.TrackFX_GetCount(track)
  for i = 0, cnt - 1 do
    local _, fxName = r.TrackFX_GetFXName(track, i)
    if fxName and fxName:find(substr, 1, true) then
      return i
    end
  end
  return -1
end

local function ensure_dummy_fx_at_top(track, cfg)
  local idx = find_fx_index_by_substr(track, cfg.dummyFxMatchSubstr)

  if idx < 0 then
    -- Add new instance, then move to top if needed.
    idx = r.TrackFX_AddByName(track, cfg.dummyFxFullName, false, 1)
    if idx < 0 then
      return false, 'Could not insert dummy FX: ' .. tostring(cfg.dummyFxFullName)
    end
  end

  if idx ~= 0 then
    -- Move (not copy) to the top of the same track.
    r.TrackFX_CopyToTrack(track, idx, track, 0, true)
  end

  return true
end

-- ============================================================
-- FX chain window focus
-- ============================================================

local function find_fx_chain_window(track)
  -- Typical window title on Windows: "FX: <track name>"
  -- We try exact first (fast), then non-exact.
  local title = 'FX: ' .. get_track_name(track)
  local hwnd = r.JS_Window_Find(title, true)
  if hwnd and hwnd ~= 0 then return hwnd end
  hwnd = r.JS_Window_Find(title, false)
  if hwnd and hwnd ~= 0 then return hwnd end

  -- Fallback: some setups include additional text; try generic prefix.
  hwnd = r.JS_Window_Find('FX:', false)
  if hwnd and hwnd ~= 0 then return hwnd end

  return nil
end

local function js_get_class_name(hwnd)
  if not r.JS_Window_GetClassName then return nil end
  local ok, a, b = pcall(r.JS_Window_GetClassName, hwnd, '')
  if not ok then return nil end
  -- Different JS API builds return either (string) or (retval, string)
  if type(a) == 'string' then return a end
  if type(b) == 'string' then return b end
  return nil
end

local function js_get_title(hwnd)
  if not r.JS_Window_GetTitle then return nil end
  local ok, a, b = pcall(r.JS_Window_GetTitle, hwnd)
  if not ok then return nil end
  if type(a) == 'string' then return a end
  if type(b) == 'string' then return b end
  return nil
end

local function js_find_first_child_by_class(parentHwnd, wantedClass)
  local getFirstChild = rawget(r, 'JS_Window_GetFirstChild')
  local getNext = rawget(r, 'JS_Window_GetNext')
  if not (getFirstChild and getNext) then return nil end
  local function walk(hwnd)
    local child = getFirstChild(hwnd)
    while child and child ~= 0 do
      local cls = js_get_class_name(child)
      if cls == wantedClass then return child end
      local found = walk(child)
      if found then return found end
      child = getNext(child)
    end
    return nil
  end
  return walk(parentHwnd)
end

local function focus_fx_chain_list(hwndChain)
  -- In REAPER's FX chain window on Windows, the FX list is typically a SysListView32.
  -- We focus it so Shift+F10 opens the FX item's context menu.
  local list = js_find_first_child_by_class(hwndChain, 'SysListView32')
  if list then
    r.JS_Window_SetFocus(list)
    return list
  end

  -- Fallback: at least focus the main chain window.
  r.JS_Window_SetFocus(hwndChain)
  return hwndChain
end

local function get_fx_list_first_item_coords(hwndList)
  -- Get the screen coordinates of the first item in the FX list.
  -- We'll click it to ensure it's selected and has focus.
  if not hwndList or hwndList == 0 then return nil, nil end
  
  local retval, left, top, right, bottom = r.JS_Window_GetRect(hwndList)
  if not retval then return nil, nil end
  
  -- Click in the center of the first item (roughly 20 pixels down from top, centered horizontally)
  local x = math.floor((left + right) / 2)
  local y = top + 20
  
  return x, y
end

local function find_popup_menu()
  -- Popup menus on Windows have class name "#32768"
  -- We need to find it quickly after right-clicking
  local hwnd = r.JS_Window_FindTop('#32768', true)
  if hwnd and hwnd ~= 0 then return hwnd end
  
  -- Fallback: try case-insensitive
  hwnd = r.JS_Window_FindTop('#32768', false)
  if hwnd and hwnd ~= 0 then return hwnd end
  
  return nil
end

local function open_and_select_first_fx(track)
  -- showFlag=1 shows chain and selects FX at index
  r.TrackFX_Show(track, 0, 1)
end

-- ============================================================
-- Main runner (deferred state machine)
-- ============================================================

local State = {
  cfg = nil,
  tracks = nil,
  trackIndex = 1,
  hwnd = nil,
  hwndTarget = nil,
  hwndMenu = nil,
  clickX = nil,
  clickY = nil,
  navIndex = 1,
  nextTime = 0,
  savedSelection = nil,
  activeTrack = nil,
  prepared = false,
}

local function capture_selected_tracks()
  local tracks = {}
  local cnt = r.CountSelectedTracks(0)
  for i = 0, cnt - 1 do
    tracks[#tracks + 1] = r.GetSelectedTrack(0, i)
  end
  return tracks
end

local function restore_selection(saved)
  if not saved then return end
  r.Main_OnCommand(40297, 0) -- Unselect all tracks
  for i = 1, #saved do
    r.SetTrackSelected(saved[i], true)
  end
end

local function init_targets(cfg)
  if cfg.targetMode == 'last_touched' then
    local lt = r.GetLastTouchedTrack()
    if not lt then return nil, 'No last-touched track found.' end
    return { lt }
  end

  local sel = capture_selected_tracks()
  if #sel == 0 then return nil, 'No tracks selected.' end
  return sel
end

local function step_for_track(track)
  -- Safety: freezing already-frozen tracks changes the menu structure.
  -- We fail fast to avoid accidentally triggering the wrong command.
  if track_is_frozen(track) then
    return false, 'Track appears to be frozen already. Unfreeze first to re-run this script.'
  end

  -- Ensure dummy FX is at the top.
  local ok, err = ensure_dummy_fx_at_top(track, State.cfg)
  if not ok then return false, err end

  -- Make this track the only selected track so the FX chain action targets it.
  r.SetOnlyTrackSelected(track)

  -- Open chain and select first FX.
  open_and_select_first_fx(track)

  -- Try to locate and focus the FX chain window.
  local hwnd = find_fx_chain_window(track)
  if not hwnd then
    return false, 'Could not find FX chain window. (JS API window search failed)'
  end

  r.JS_Window_SetForeground(hwnd)

  -- We'll do a more reliable "prepare" step (ensure selection + focus list) on the next defer.
  State.hwnd = hwnd
  State.hwndTarget = nil
  State.navIndex = 1
  State.prepared = false
  State.nextTime = r.time_precise() + 0.06
  return true
end

local function prepare_fx_chain_selection(track)
  -- Focus the FX list control
  local target = focus_fx_chain_list(State.hwnd)
  State.hwndTarget = target

  -- Get coordinates of the first FX item
  local x, y = get_fx_list_first_item_coords(target)
  if not x or not y then
    State.prepared = false
    return false, 'Could not determine FX list item coordinates'
  end
  
  State.clickX = x
  State.clickY = y

  -- Left-click to select the first FX
  r.JS_Mouse_SetPosition(x, y)
  local hwndAt = r.JS_Window_FromPoint(x, y)
  if hwndAt and hwndAt ~= 0 then
    r.JS_WindowMessage_Send(hwndAt, 'WM_LBUTTONDOWN', 0, 0, 0, 0)
    r.JS_WindowMessage_Send(hwndAt, 'WM_LBUTTONUP', 0, 0, 0, 0)
  end

  State.prepared = true
  State.nextTime = r.time_precise() + 0.08  -- Give it a moment to register the click
  return true
end

local function run_navigation_step()
  if not State.prepared then
    local now = r.time_precise()
    if now >= State.nextTime then
      local ok, err = prepare_fx_chain_selection(State.activeTrack)
      if not ok then
        return true  -- Abort this track
      end
    end
    return false
  end

  if State.navIndex > #State.cfg.navigation then
    return true
  end

  local now = r.time_precise()
  if now < State.nextTime then
    return false
  end

  local step = State.cfg.navigation[State.navIndex]

  -- Special handling for the first step (Shift+F10): use right-click instead
  if State.navIndex == 1 and step.key == 'F10' then
    -- Right-click on the first FX item to open context menu
    local hwndAt = r.JS_Window_FromPoint(State.clickX, State.clickY)
    if hwndAt and hwndAt ~= 0 then
      r.JS_WindowMessage_Send(hwndAt, 'WM_RBUTTONDOWN', 0, 0, 0, 0)
      r.JS_WindowMessage_Send(hwndAt, 'WM_RBUTTONUP', 0, 0, 0, 0)
    end
    -- Menu is now open and focused—just continue
    State.navIndex = State.navIndex + 1
    State.nextTime = now + (State.cfg.keyDelaySeconds or 0.05)
    return false
  end

  -- Send keystroke (menu is already focused)
  local kvk = key_to_vk(step.key)
  if kvk then
    send_key(State.hwndTarget, kvk)
  end

  State.navIndex = State.navIndex + 1
  State.nextTime = now + (State.cfg.keyDelaySeconds or 0)
  return false
end

local function advance_track()
  -- Close chain if desired
  if State.cfg.closeFxChainAfter and State.activeTrack then
    r.TrackFX_Show(State.activeTrack, 0, 0) -- hide chain
  end

  State.trackIndex = State.trackIndex + 1
  State.activeTrack = nil
  State.hwnd = nil
  State.hwndTarget = nil
  State.hwndMenu = nil
  State.navIndex = 1
  State.prepared = false
end

local function loop()
  -- Done
  if State.trackIndex > #State.tracks then
    restore_selection(State.savedSelection)
    r.UpdateArrange()
    return
  end

  -- Initialize per-track
  if not State.activeTrack then
    local track = State.tracks[State.trackIndex]
    State.activeTrack = track

    local ok, err = step_for_track(track)
    if not ok then
      -- Fail fast but restore selection
      restore_selection(State.savedSelection)
      H.msg('jg_CURSE_FreezeInstrument_PreFX', tostring(err))
      return
    end
  end

  -- Drive navigation steps
  local doneNav = run_navigation_step()
  if doneNav then
    advance_track()
  end

  r.defer(loop)
end

local function main()
  local cfg = config()
  State.cfg = cfg

  if not has_js_api() then
    H.msg(
      'jg_CURSE_FreezeInstrument_PreFX',
      'This script requires the JS_ReaScriptAPI extension (ReaPack: "js_ReaScriptAPI").\n\n'
        .. 'It is needed to focus the FX chain and send the freeze menu keystrokes.'
    )
    return
  end

  local tracks, err = init_targets(cfg)
  if not tracks then
    H.msg('jg_CURSE_FreezeInstrument_PreFX', tostring(err))
    return
  end

  -- Save selection so we can restore it after processing.
  State.savedSelection = capture_selected_tracks()

  State.tracks = tracks
  State.trackIndex = 1
  State.activeTrack = nil

  loop()
end

main()
