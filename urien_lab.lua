-- ============================================================================
-- BLUEABS URIEN LAB: Training Mode for SF3:3rd Strike on FBNeo
-- ============================================================================
-- A curriculum-based training script that takes you from "knows the moves"
-- to confident Urien pilot. Data-driven exercise system with structured categories.
--
-- Flow:
--   1. Script loads -> game's native character select screen (if character_select.fs exists)
--   2. Pick P1 and P2 characters, both lock in -> fast-forwards to match
--   3. In training mode, press Start to open exercise menu
--   4. Select a combo to practice
--   Alt+1 = Return to character select at any time
--
-- Character Select Controls:
--   D-Pad        = Navigate character grid
--   Jab (P1 Weak Punch)    = Load saved state for opponent
--   Fierce (P1 Strong Punch) = Save current game state for opponent
--
-- Training Controls:
--   Start        = Open/close exercise menu
--   Left/Right   = Switch menu tabs (Exercises / Opponent)
--   Up/Down      = Navigate exercises
--   Jab (P1 Weak Punch)      = Select exercise
--   Strong (P1 Medium Punch)  = Stop exercise (in menu) / Close menu
--   LK (P1 Weak Kick)         = Toggle exercise side (L/R)
--   MK (P1 Medium Kick)       = Tag/untag opponent on exercise
--   Coin         = Toggle exercise capture mode
--   Alt+2        = Toggle numpad notation
--   Alt+3        = Reset current exercise progress
--   Alt+5        = Toggle menu (reliable backup for Start)
-- ============================================================================

-- ============================================================================
-- [1] CONSTANTS & CONFIG
-- ============================================================================

local SCRIPT_VERSION = "0.6.0"
local EXERCISES_VERSION = 1
local SAVE_FILE = "urien_lab_save.txt"
local CAPTURE_FILE = "captured_exercises.txt"
local MATCHUP_FILE = "urien_lab_matchups.txt"

-- Screen dimensions (CPS3 = 384x224)
local SCREEN_W = 384
local SCREEN_H = 224

-- Timing
local SETUP_DELAY_FRAMES = 0        -- Instant transition from SETUP to ACTIVE
local SUCCESS_DISPLAY_FRAMES = 120   -- Show "CLEAR!" for 2 seconds
local FAIL_DISPLAY_FRAMES = 150      -- Show failure for 2.5 seconds (timing feedback needs more read time)

-- Resource recovery
local RECOVERY_DELAY_FRAMES = 20     -- Frames after combo drops before HP starts recovering
local LIFE_RECOVERY_SPEED = 8        -- HP units per frame during recovery
local LIFE_FULL = 0xA0               -- Full HP value
local STUN_RESET_DELAY_FRAMES = 40   -- Frames after combo drops before stun resets
local METER_REFILL_DELAY_FRAMES = 90 -- Frames of no input before meter starts filling

-- Mastery
local MASTERY_THRESHOLD = 3          -- Completions needed to master an exercise

-- Matchup save state slots
local MAX_MATCHUP_SLOTS = 5
local MATCHUP_SLOT_BASE = 8000       -- FBNeo savestate slot numbers start here

-- Character select save states
local CHAR_SAVE_FILE = "urien_lab_characters.txt"
local CHAR_SLOT_BASE = 9000          -- FBNeo savestate slots 9001+

-- Character select save state (game's native char select screen)
local CHARSELECT_SAVE = "character_select.fs"

-- Character select sequence states (inline numbers to save locals)
-- 0=none, 1=P1 selecting, 2=P2 debounce, 3=P2 selecting, 4=transitioning

-- Exercises (record-to-exercise)
local EXERCISE_FILE = "urien_lab_exercises.txt"
local CUSTOM_EXERCISE_FILE = "urien_lab_custom.txt"
local exercise_counter = 0

-- Update & distribution URLs
local GITHUB_RAW_URL  = "https://raw.githubusercontent.com/ChrisDBaldwin/blueabs-urien-lab/main/"
local SAVES_BASE_URL  = "https://voidtalker.com/urien-lab/"
local MANIFEST_URL    = SAVES_BASE_URL .. "manifest.txt"

-- Exercise categories (display order)
local EXERCISE_CATEGORIES = {"combo", "unblockable", "sequence", "parry"}
local CATEGORY_LABELS = {
    combo = "COMBO",
    unblockable = "UNBLOCKABLE",
    sequence = "SEQUENCE",
    parry = "PARRY",
}

-- Timing feedback thresholds (frames from reference)
local TIMING_TIGHT = 3   -- <=3f from reference = green
local TIMING_OK = 8      -- <=8f = yellow, >8f = orange/red

-- Corner detection
local STAGE_LEFT = 0x0040
local STAGE_RIGHT = 0x01C0
local CORNER_THRESHOLD = 0x0020

-- Colors (RRGGBBAA format for FBNeo gui.box / gui.text)
local COLOR = {
    bg_dark      = 0x101010F0,
    bg_panel     = 0x181820F0,
    bg_header    = 0x181828F0,
    bg_success   = 0x002200F0,
    bg_fail      = 0x220000F0,
    text_white   = 0xFFFFFFFF,
    text_gray    = 0x888888FF,
    text_green   = 0x00FF00FF,
    text_yellow  = 0xFFFF00FF,
    text_red     = 0xFF4444FF,
    text_cyan    = 0x00FFFFFF,
    text_orange  = 0xFF8800FF,
    border       = 0x444488FF,
    border_light = 0x6666AAFF,
    highlight    = 0x8888FFFF,
    step_done    = 0x00DD00FF,
    step_current = 0xFFFF00FF,
    step_pending = 0x666666FF,
    transparent  = 0x00000000,
    menu_top     = 0x0A0A12FF,   -- fully opaque dark, menu gradient top
    menu_bottom  = 0x14141EFF,   -- fully opaque slightly lighter, menu gradient bottom
    text_outline = 0x101008FF,   -- dark outline for all text (matches Grouflon convention)
    -- Timing feedback
    timing_tight   = 0x00FF00FF,  -- green: within TIMING_TIGHT frames
    timing_ok      = 0xFFFF00FF,  -- yellow: within TIMING_OK frames
    timing_loose   = 0xFF8800FF,  -- orange: beyond TIMING_OK frames
    -- Charge meter
    charge_fill    = 0x0080FFFF,  -- cyan: charge bar fill
    charge_timer   = 0xFF8000FF,  -- orange: timer bar fill
    charge_full_border = 0xFEFEFEFF,  -- light gray: fully charged border
    charge_border  = 0x000000FF,  -- black: bar background/border
}

-- Notation mode
local NOTATION_SF = 1
local NOTATION_NUMPAD = 2

-- Exercise engine states
local STATE_IDLE    = "idle"
local STATE_SETUP   = "setup"
local STATE_ACTIVE  = "active"
local STATE_SUCCESS = "success"
local STATE_FAIL    = "fail"
local STATE_MENU    = "menu"

-- App-level states
local APP_CHARSELECT = "charselect"
local APP_TRAINING   = "training"

-- Max objects for projectile scan
local MAX_GAME_OBJECTS = 30

-- ============================================================================
-- [1b] UPDATE & DISTRIBUTION
-- ============================================================================

--- Detect platform: "windows" or "unix"
local function detect_platform()
    if package.config:sub(1,1) == "\\" then
        return "windows"
    end
    return "unix"
end

--- Download a file from url to dest. Returns true on success.
local function download_file(url, dest)
    local platform = detect_platform()
    local null_redirect = platform == "windows" and " 2>nul" or " 2>/dev/null"
    -- Primary: curl
    local cmd = 'curl -sfL --connect-timeout 2 --max-time 10 -o "' .. dest .. '" "' .. url .. '"' .. null_redirect
    local result = os.execute(cmd)
    -- os.execute returns 0 (Lua 5.1) or true (Lua 5.2+) on success
    if result == 0 or result == true then return true end
    -- Windows fallback: PowerShell
    if platform == "windows" then
        cmd = 'powershell -NoProfile -Command "(New-Object Net.WebClient).DownloadFile(\'' .. url .. '\',\'' .. dest .. '\')"' .. null_redirect
        result = os.execute(cmd)
        if result == 0 or result == true then return true end
    end
    return false
end

--- Parse "X.Y.Z" version string into a comparable number (major*10000 + minor*100 + patch)
local function parse_version(str)
    if not str then return 0 end
    local major, minor, patch = str:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return 0 end
    return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

--- Module-level manifest data (populated by sync_from_manifest)
local manifest_saves = nil

--- Fetch manifest.txt from voidtalker. Returns parsed table or nil on failure.
local function fetch_manifest()
    local tmp = "manifest.txt.tmp"
    if not download_file(MANIFEST_URL, tmp) then
        os.remove(tmp)
        return nil
    end
    local f = io.open(tmp, "r")
    if not f then os.remove(tmp) return nil end
    local result = { saves = {} }
    for line in f:lines() do
        local key, val = line:match("^(%S+):(.+)$")
        if key == "SCRIPT_VERSION" then
            result.script_version = val
        elseif key == "EXERCISES_VERSION" then
            result.exercises_version = tonumber(val)
        elseif key == "SAVE" then
            result.saves[#result.saves + 1] = val
        end
    end
    f:close()
    os.remove(tmp)
    return result
end

--- Sync script, exercises, and save state list from manifest. Called once at boot.
local function sync_from_manifest()
    local manifest = fetch_manifest()
    if not manifest then return end
    -- Script update
    if manifest.script_version then
        local remote_num = parse_version(manifest.script_version)
        local local_num = parse_version(SCRIPT_VERSION)
        if remote_num > local_num then
            local tmp_file = "urien_lab.lua.tmp"
            if download_file(GITHUB_RAW_URL .. "urien_lab.lua", tmp_file) then
                os.remove("urien_lab.lua")
                os.rename(tmp_file, "urien_lab.lua")
                print("[Urien Lab] Updated to v" .. manifest.script_version .. " -- reload script to apply")
            else
                os.remove(tmp_file)
            end
        end
    end
    -- Exercise update (decoupled from script updates)
    if manifest.exercises_version and manifest.exercises_version > EXERCISES_VERSION then
        if download_file(GITHUB_RAW_URL .. "urien_lab_exercises.txt", EXERCISE_FILE) then
            print("[Urien Lab] Updated exercises to v" .. manifest.exercises_version)
        end
    end
    -- Store available saves for on-demand download
    if #manifest.saves > 0 then
        manifest_saves = {}
        for _, name in ipairs(manifest.saves) do
            manifest_saves[name] = true
        end
    end
end

--- Download a single .fs save state from voidtalker. Returns true on success.
local function fetch_save_state(filename)
    -- If manifest was loaded, only download files it lists (avoids 404s)
    if manifest_saves and not manifest_saves[filename] then return false end
    if download_file(SAVES_BASE_URL .. filename, filename) then
        print("[Urien Lab] Downloaded save state: " .. filename)
        return true
    end
    return false
end

-- ============================================================================
-- [2] MEMORY ADDRESS MAP
-- ============================================================================

local MEM = {
    -- Game phase (word): 2 = playing
    game_phase      = 0x020154A6,

    -- Player bases
    p1_base         = 0x02068C6C,
    p2_base         = 0x02069104,

    -- P1 state (offsets from p1_base or absolute)
    p1_life         = 0x02068D0B,  -- byte
    p1_action_type  = 0x02068E73,  -- byte
    p1_action_sub   = 0x02068D1B,  -- word (little-endian)
    p1_action_id    = 0x02068E75,  -- word
    p1_x_pos        = 0x02068CD1,  -- word (signed)
    p1_flip         = 0x02068D35,  -- byte (0=right, 1=left)

    -- P2 state
    p2_life         = 0x020691A3,  -- byte
    p2_x_pos        = 0x02069169,  -- word (signed)
    p2_flip         = 0x020691CD,  -- byte (0=facing right, 1=facing left)
    p2_action_type  = 0x0206930B,  -- byte

    -- Round timer
    round_timer     = 0x02011377,  -- byte (write 100 each frame to keep at 99)

    -- Stun
    p2_stun_bar     = 0x02069612,  -- word (big-endian, write 0x0000 to clear)
    p1_stun_timer   = 0x020695FD,  -- byte (write 0x00 to prevent stun lockout)

    -- Combo tracking
    combo_counter   = 0x020696C5,  -- byte

    -- Charge system (P1)
    charge_base     = 0x020259D8,
    -- Urien horizontal charge: charge_base + 0x00
    -- Urien vertical charge:   charge_base + 0x1C AND charge_base + 0x54
    -- Charge display bytes (pattern: value = base+offset+1, timer = base+offset-1)
    charge_h_value  = 0x020259D9,  -- H charge (4-6) value byte
    charge_h_timer  = 0x020259D7,  -- H charge (4-6) timer byte
    charge_v_value  = 0x020259F5,  -- V charge (2-8) value byte
    charge_v_timer  = 0x020259F3,  -- V charge (2-8) timer byte

    -- Meter
    meter_gauge     = 0x020695B5,  -- byte (gauge fill within current bar)
    meter_bars      = 0x020286AD,  -- byte (number of full bars)
    meter_count     = 0x020695BF,  -- byte (number of full bars, authoritative)
    meter_update    = 0x020157C8,  -- byte (write 0x01 to sync meter changes)
    max_meter_gauge = 0x020695B3,  -- byte (max gauge per bar, SA-dependent)
    max_meter_count = 0x020695BD,  -- byte (max bars for selected SA)

    -- Projectile / object system
    obj_list_base   = 0x02068A96,  -- linked list head indices
    obj_data_base   = 0x02028990,  -- object data array
    obj_stride      = 0x800,       -- bytes per object

    -- Hit tracking region (for wazaTotalNum)
    hit_region_base = 0x02011000,
    hit_region_size = 0x200,
    hit_reset_addr  = 0x02010CA5,

    -- Character select
    p1_char_id      = 0x02011387,  -- byte (Urien = 14)

    -- Character select screen (game's native menu)
    char_select_timer = 0x020154FB,  -- byte: freeze to prevent timeout
    p1_locked         = 0x020154C6,  -- byte: 0xFF = character locked in
    p2_locked         = 0x020154C8,  -- byte: 0xFF = character locked in
    p1_select_state   = 0x0201553D,  -- byte: 0-4=selecting, >4=locked (SA chosen)
    p2_select_state   = 0x02015545,  -- byte: 0-4=selecting, >4=locked (SA chosen)
}

-- Charge gauge offsets (from charge_base)
local CHARGE_OFFSETS = { 0x00, 0x1C, 0x38, 0x54, 0x70 }

-- ============================================================================
-- [2b] CHARACTER ROSTER
-- ============================================================================

local CHARACTERS = {
    { id = 1,  name = "Alex" },
    { id = 12, name = "Akuma" },
    { id = 16, name = "Chun-Li" },
    { id = 4,  name = "Dudley" },
    { id = 8,  name = "Elena" },
    { id = 6,  name = "Hugo" },
    { id = 7,  name = "Ibuki" },
    { id = 15, name = "Ken" },
    { id = 10, name = "Makoto" },
    { id = 5,  name = "Necro" },
    { id = 9,  name = "Oro" },
    { id = 18, name = "Q" },
    { id = 19, name = "Remy" },
    { id = 2,  name = "Ryu" },
    { id = 11, name = "Sean" },
    { id = 17, name = "Twelve" },
    { id = 14, name = "Urien" },
    { id = 13, name = "Yang" },
    { id = 3,  name = "Yun" },
}

local CHAR_GRID_COLS = 4
local CHAR_GRID_ROWS = 5

-- App state
local app_state = APP_CHARSELECT
local charselect_visible = true -- toggle with P1 Start
local char_cursor = 1
local selected_opponent = nil   -- reference to CHARACTERS entry
local char_states = {}          -- { [char_id] = { saved = bool } }
local pending_home_load = true  -- auto-load first available save on startup
local charselect_seq = 0  -- game character select sequence state
local all_exercises_sorted = {}    -- indices into exercises[], category-sorted, no opponent filter
local filtered_exercises = {}      -- indices into exercises[] for current opponent (tagged + untagged)
local filter_active = false     -- true when filtering by opponent

-- Secret: Konami code enables turbo charge (continuous charge fill during exercises)
local konami = {
    active = false,
    flash_timer = 0,
    index = 1,
    sequence = {
        "P1 Up", "P1 Up", "P1 Down", "P1 Down",
        "P1 Left", "P1 Right", "P1 Left", "P1 Right",
        "P1 Weak Kick", "P1 Weak Punch", "P1 Start",
    },
}

-- Temp slot used for all save/load operations (file gets renamed to descriptive name)
local TEMP_SLOT = 99999

--- Get the named save file path for a character
local function char_save_path(char)
    return "vs_" .. char.name .. ".fs"
end

-- ============================================================================
-- [3] URIEN MOVE DATABASE
-- ============================================================================

local MOVES = {
    -- Normal attacks (A prefix)
    ["cr.HP"]      = { action_ids = {"A00180018"}, type = "normal", sf = "d+HP",    numpad = "2HP" },
    ["st.LP_close"]= { action_ids = {"A00000000"}, type = "normal", sf = "LP",      numpad = "5LP" },
    ["st.LP_far"]  = { action_ids = {"A00010001"}, type = "normal", sf = "LP",      numpad = "5LP" },
    ["st.LP"]      = { action_ids = {"A00000000","A00010001"}, type = "normal", sf = "LP", numpad = "5LP" },
    ["st.MP_close"]= { action_ids = {"A0000009e","A0001009e"}, type = "normal", sf = "MP", numpad = "5MP" },
    ["st.MP_far"]  = { action_ids = {"A00030003"}, type = "normal", sf = "f+MP",   numpad = "6MP" },
    ["st.MP"]      = { action_ids = {"A0000009e","A0001009e","A00030003"}, type = "normal", sf = "MP", numpad = "5MP" },
    ["cr.LK"]      = { action_ids = {"A001b001b"}, type = "normal", sf = "d+LK",    numpad = "2LK" },
    ["j.HP"]       = { action_ids = {"A00400028","A00280028","A00340028"}, type = "normal", sf = "j.HP", numpad = "j.HP" },
    ["j.HK"]       = { action_ids = {"A0046002e","A002e002e","A003a002e"}, type = "normal", sf = "j.HK", numpad = "j.HK" },

    -- Special moves (S prefix)
    ["L.Tackle"]   = { action_ids = {"S003a003a"}, type = "special", sf = "b~f+LK",    numpad = "[4]6LK" },
    ["M.Tackle"]   = { action_ids = {"S003b003b"}, type = "special", sf = "b~f+MK",    numpad = "[4]6MK" },
    ["H.Tackle"]   = { action_ids = {"S003c003c"}, type = "special", sf = "b~f+HK",    numpad = "[4]6HK" },
    ["EX.Tackle"]  = { action_ids = {"S003d003d"}, type = "special", sf = "b~f+KK",    numpad = "[4]6KK" },
    ["L.Headbutt"] = { action_ids = {"S00290029"}, type = "special", sf = "d~u+LP",    numpad = "[2]8LP" },
    ["M.Headbutt"] = { action_ids = {"S002a002a"}, type = "special", sf = "d~u+MP",    numpad = "[2]8MP" },
    ["H.Headbutt"] = { action_ids = {"S002b002b"}, type = "special", sf = "d~u+HP",    numpad = "[2]8HP" },
    ["EX.Headbutt"]= { action_ids = {"S002c002c"}, type = "special", sf = "d~u+PP",    numpad = "[2]8PP" },
    ["L.Knee"]     = { action_ids = {"S00190019"}, type = "special", sf = "d~u+LK(air)", numpad = "[2]8LK(air)" },
    ["M.Knee"]     = { action_ids = {"S001a001a"}, type = "special", sf = "d~u+MK(air)", numpad = "[2]8MK(air)" },
    ["H.Knee"]     = { action_ids = {"S001b001b"}, type = "special", sf = "d~u+HK(air)", numpad = "[2]8HK(air)" },
    ["Taunt"]      = { action_ids = {"S00370037"}, type = "other",   sf = "Taunt",      numpad = "Taunt" },

    -- Projectiles / supers (F prefix)
    ["EX.Sphere"]  = { action_ids = {"F0084"},     type = "special", sf = "qcf+PP",     numpad = "236PP" },
    ["L.Aegis"]    = { action_ids = {"F077b"},     type = "super",   sf = "qcf+LP (SA3)", numpad = "236LP(SA3)" },
    ["M.Aegis"]    = { action_ids = {"F077c"},     type = "super",   sf = "qcf+MP (SA3)", numpad = "236MP(SA3)" },
    ["Temporal"]   = { action_ids = {"F0068"},     type = "super",   sf = "qcf+P (SA2)",  numpad = "236P(SA2)" },

    -- Metallic Sphere character animations (throw motion, S-prefix)
    ["L.Sphere_throw"] = { action_ids = {"S003e003e"}, type = "special", sf = "qcf+LP", numpad = "236LP" },
    ["M.Sphere_throw"] = { action_ids = {"S003f003f"}, type = "special", sf = "qcf+MP", numpad = "236MP" },
    ["H.Sphere_throw"] = { action_ids = {"S00400040"}, type = "special", sf = "qcf+HP", numpad = "236HP" },

    -- Metallic Sphere projectile hits (F-prefix)
    ["L.Sphere"]   = { action_ids = {"F0053"},     type = "special", sf = "qcf+LP",    numpad = "236LP" },
    ["H.Sphere"]   = { action_ids = {"F0055"},     type = "special", sf = "qcf+HP",    numpad = "236HP" },

    -- Aegis Reflector (SA3) - H.Aegis completes the set
    ["H.Aegis"]    = { action_ids = {"F077d"},     type = "super",   sf = "qcf+HP (SA3)", numpad = "236HP(SA3)" },

    -- Tyrant Slaughter (SA1) has multiple hit IDs
    ["Tyrant"]     = { action_ids = {"S00460046","S00470047","S00480048"}, type = "super", sf = "qcf+K (SA1)", numpad = "236K(SA1)" },

    -- Unidentified specials (rename once identified)
    ["Unk_0021"]   = { action_ids = {"S00210021"}, type = "special", sf = "Unk_0021",  numpad = "Unk_0021" },
    ["Unk_0023"]   = { action_ids = {"S00230023"}, type = "special", sf = "Unk_0023",  numpad = "Unk_0023" },
}

-- ============================================================================
-- [4] EXERCISE DEFINITIONS
-- ============================================================================

local exercises = {}
-- Exercises populated via record-to-exercise (Coin) and loaded from urien_lab_exercises.txt

-- ============================================================================
-- [5] PROGRESSION STATE
-- ============================================================================

local progression = {}  -- { [exercise_id] = { completions = N, attempts = N, mastered = bool } }
local current_streak = 0
local best_streak = 0
local exercise_sides = {}  -- { [exercise_id] = "L" or "R" }

local function get_exercise_side(exercise_id)
    return exercise_sides[exercise_id] or "L"
end

local function toggle_exercise_side(exercise_id)
    if exercise_sides[exercise_id] == "R" then
        exercise_sides[exercise_id] = "L"
    else
        exercise_sides[exercise_id] = "R"
    end
end

local function init_progression()
    for _, exercise in ipairs(exercises) do
        if not progression[exercise.id] then
            progression[exercise.id] = {
                completions = 0,
                attempts = 0,
                mastered = false,
            }
        end
    end
end

local function save_progression()
    local f = io.open(SAVE_FILE, "w")
    if not f then return end
    f:write("-- Urien Lab Save Data\n")
    f:write("-- Version: " .. SCRIPT_VERSION .. "\n")
    for id, data in pairs(progression) do
        local side = exercise_sides[id] or "L"
        f:write(string.format("%s,%d,%d,%s,%s\n",
            id, data.completions, data.attempts,
            data.mastered and "1" or "0", side))
    end
    f:close()
end

local function load_progression()
    local f = io.open(SAVE_FILE, "r")
    if not f then
        init_progression()
        return
    end
    for line in f:lines() do
        if line:sub(1, 2) ~= "--" and line ~= "" then
            local id, comp, att, mast, side = line:match("^(.+),(%d+),(%d+),(%d+),?([LR]?)$")
            if id then
                progression[id] = {
                    completions = tonumber(comp) or 0,
                    attempts = tonumber(att) or 0,
                    mastered = (mast == "1"),
                }
                if side == "R" then
                    exercise_sides[id] = "R"
                end
            end
        end
    end
    f:close()
    init_progression()  -- fill in any new exercises not in save file
end

-- ============================================================================
-- [6] UTILITY FUNCTIONS
-- ============================================================================

--- Read N bytes from memory as little-endian value (ported from trial script)
local function read_mem(addr, bytes)
    local value = 0
    for i = 1, bytes do
        value = value + (memory.readbyte(addr + i - 1) * (0x100 ^ (i - 1)))
    end
    return value
end

--- Read a signed word from memory
local function read_word_signed(addr)
    local v = memory.readword(addr)
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end

--- Build action detail string from type/sub/id (matches trial format)
local function build_action_string(action_type, action_sub, action_id)
    -- Strip 0x2000 hit-state flag (set by game during connected hits)
    action_id = action_id % 0x2000
    local prefix = "N"
    if action_type == 1 then
        prefix = "G"      -- guard
    elseif action_type == 2 then
        prefix = "T"      -- throw
    elseif action_type == 4 then
        prefix = "A"      -- attack (normal)
    elseif action_type == 5 then
        prefix = "S"      -- special
    elseif action_type == 7 then
        prefix = "M"      -- misc
    end
    return prefix .. string.format("%04x", action_sub) .. string.format("%04x", action_id)
end

--- Normalize a stored action string by stripping 0x2000 hit-state flag from ID portion.
--- Handles both 9-char (S/A/T/G/M/N prefix) and 5-char (F prefix) formats.
local function normalize_action_string(str)
    if #str == 9 then
        local prefix = str:sub(1, 1)
        local sub_hex = str:sub(2, 5)
        local id_num = tonumber(str:sub(6, 9), 16)
        if id_num and id_num >= 0x2000 then
            return prefix .. sub_hex .. string.format("%04x", id_num % 0x2000)
        end
    end
    return str
end

--- Check if a value exists in a table
local function table_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

--- Clamp a value between min and max
local function clamp(val, min_val, max_val)
    if val < min_val then return min_val end
    if val > max_val then return max_val end
    return val
end

--- Check if a position is near a stage corner
local function is_near_corner(x_pos)
    return x_pos <= (STAGE_LEFT + CORNER_THRESHOLD) or x_pos >= (STAGE_RIGHT - CORNER_THRESHOLD)
end

--- Reverse-lookup a move name from the MOVES table by action_id
--- Returns name, sf, numpad, type or nil if not found
local function lookup_move_name(action_id)
    for name, move in pairs(MOVES) do
        for _, aid in ipairs(move.action_ids) do
            if aid == action_id then
                return name, move.sf, move.numpad, move.type
            end
        end
    end
    return nil
end

-- ============================================================================
-- [7] GAME STATE READER
-- ============================================================================

local game_state = {
    phase = 0,
    playing = false,

    p1 = {
        life = 0,
        action_type = 0,
        action_sub = 0,
        action_id = 0,
        action_string = "",
        x_pos = 0,
        flip = 0,
    },
    p2 = {
        life = 0,
        x_pos = 0,
        action_type = 0,
    },

    combo_counter = 0,
    combo_counter_prev = 0,

    waza_total = 0,
    waza_total_prev = 0,

    meter_gauge = 0,
    meter_bars = 0,
    meter_bars_prev = 0,

    frame_count = 0,
}

local function read_game_state()
    local gs = game_state

    gs.phase = memory.readword(MEM.game_phase)
    gs.playing = (gs.phase == 2)

    if not gs.playing then return end

    -- P1 state
    gs.p1.life = memory.readbyte(MEM.p1_life)
    gs.p1.action_type = memory.readbyte(MEM.p1_action_type)
    gs.p1.action_sub = read_mem(MEM.p1_action_sub, 2)
    gs.p1.action_id = read_mem(MEM.p1_action_id, 2)
    gs.p1.action_string = build_action_string(gs.p1.action_type, gs.p1.action_sub, gs.p1.action_id)
    gs.p1.x_pos = read_word_signed(MEM.p1_x_pos)
    gs.p1.flip = memory.readbyte(MEM.p1_flip)

    -- P2 state
    gs.p2.life = memory.readbyte(MEM.p2_life)
    gs.p2.x_pos = read_word_signed(MEM.p2_x_pos)
    gs.p2.action_type = memory.readbyte(MEM.p2_action_type)

    -- Combo tracking
    gs.combo_counter_prev = gs.combo_counter
    local raw_combo = memory.readbyte(MEM.combo_counter)
    if raw_combo ~= gs.combo_counter and raw_combo > 0 then
        gs.combo_counter = raw_combo
    elseif raw_combo == 0 then
        gs.combo_counter = 0
    end

    -- Waza total (sum of hit tracking region)
    gs.waza_total_prev = gs.waza_total
    local wt = 0
    for i = 0, MEM.hit_region_size do
        wt = wt + memory.readbyte(MEM.hit_region_base + i)
    end
    gs.waza_total = wt

    -- Meter
    gs.meter_bars_prev = gs.meter_bars
    gs.meter_gauge = memory.readbyte(MEM.meter_gauge)
    gs.meter_bars = memory.readbyte(MEM.meter_bars)

    gs.frame_count = gs.frame_count + 1
end

-- ============================================================================
-- [8] DUMMY CONTROLLER
-- ============================================================================

local function set_player_pos(player, x)
    if player == 1 then
        memory.writeword(MEM.p1_x_pos, x)
    else
        memory.writeword(MEM.p2_x_pos, x)
    end
end

local function set_life(player, val)
    if player == 1 then
        memory.writebyte(MEM.p1_life, val)
    else
        memory.writebyte(MEM.p2_life, val)
    end
end

local function fill_meter_full()
    local max_g = memory.readbyte(MEM.max_meter_gauge)
    local max_b = memory.readbyte(MEM.max_meter_count)
    if max_g == 0 then max_g = 0x80 end  -- fallback before match starts
    if max_b == 0 then max_b = 2 end
    memory.writebyte(MEM.meter_gauge, max_g)
    memory.writebyte(MEM.meter_count, max_b)
    memory.writebyte(MEM.meter_update, 0x01)
end

local function fill_h_charge()
    -- Urien horizontal charge: charge_base + 0x00
    memory.writeword(MEM.charge_base + CHARGE_OFFSETS[1], 0xFFFF)
end

local function fill_v_charge()
    -- Urien vertical charge: charge_base + 0x1C and + 0x54
    memory.writeword(MEM.charge_base + CHARGE_OFFSETS[2], 0xFFFF)
    memory.writeword(MEM.charge_base + CHARGE_OFFSETS[4], 0xFFFF)
end

local function lock_dummy()
    -- Zero all P2 inputs to prevent CPU from acting
    joypad.set({
        ["P2 Up"] = false,
        ["P2 Down"] = false,
        ["P2 Left"] = false,
        ["P2 Right"] = false,
        ["P2 Weak Punch"] = false,
        ["P2 Medium Punch"] = false,
        ["P2 Strong Punch"] = false,
        ["P2 Weak Kick"] = false,
        ["P2 Medium Kick"] = false,
        ["P2 Strong Kick"] = false,
    })
    -- Refill P2 life so round doesn't end
    set_life(2, 0xA0)
end

-- Forward declaration (reset_stun defined later, but needed by freeze_game)
local reset_stun

-- Forward declarations (input state defined in [12], but needed by swap_inputs)
local input_current = {}
local input_prev = {}

--- Swap P1 and P2 inputs so one controller selects both characters
local function swap_inputs()
    local inp = input_current
    joypad.set({
        ["P1 Up"]    = inp["P2 Up"] or false,    ["P1 Down"]  = inp["P2 Down"] or false,
        ["P1 Left"]  = inp["P2 Left"] or false,  ["P1 Right"] = inp["P2 Right"] or false,
        ["P1 Weak Punch"]   = inp["P2 Weak Punch"] or false,
        ["P1 Medium Punch"] = inp["P2 Medium Punch"] or false,
        ["P1 Strong Punch"] = inp["P2 Strong Punch"] or false,
        ["P1 Weak Kick"]    = inp["P2 Weak Kick"] or false,
        ["P1 Medium Kick"]  = inp["P2 Medium Kick"] or false,
        ["P1 Strong Kick"]  = inp["P2 Strong Kick"] or false,
        ["P2 Up"]    = inp["P1 Up"] or false,    ["P2 Down"]  = inp["P1 Down"] or false,
        ["P2 Left"]  = inp["P1 Left"] or false,  ["P2 Right"] = inp["P1 Right"] or false,
        ["P2 Weak Punch"]   = inp["P1 Weak Punch"] or false,
        ["P2 Medium Punch"] = inp["P1 Medium Punch"] or false,
        ["P2 Strong Punch"] = inp["P1 Strong Punch"] or false,
        ["P2 Weak Kick"]    = inp["P1 Weak Kick"] or false,
        ["P2 Medium Kick"]  = inp["P1 Medium Kick"] or false,
        ["P2 Strong Kick"]  = inp["P1 Strong Kick"] or false,
    })
end

local function freeze_game()
    -- Lock ALL inputs so the game effectively freezes during charselect.
    -- We already read physical inputs via joypad.get() for our own navigation,
    -- so zeroing them here only prevents the game from seeing them.
    joypad.set({
        ["P1 Up"] = false, ["P1 Down"] = false,
        ["P1 Left"] = false, ["P1 Right"] = false,
        ["P1 Weak Punch"] = false, ["P1 Medium Punch"] = false,
        ["P1 Strong Punch"] = false, ["P1 Weak Kick"] = false,
        ["P1 Medium Kick"] = false, ["P1 Strong Kick"] = false,
        ["P1 Start"] = false,
        ["P2 Up"] = false, ["P2 Down"] = false,
        ["P2 Left"] = false, ["P2 Right"] = false,
        ["P2 Weak Punch"] = false, ["P2 Medium Punch"] = false,
        ["P2 Strong Punch"] = false, ["P2 Weak Kick"] = false,
        ["P2 Medium Kick"] = false, ["P2 Strong Kick"] = false,
    })
    -- Keep both players alive and healthy
    set_life(1, LIFE_FULL)
    set_life(2, LIFE_FULL)
    reset_stun()
end

local function reset_hit_tracking()
    for i = 0, MEM.hit_region_size do
        memory.writebyte(MEM.hit_region_base + i, 0)
    end
    memory.writebyte(MEM.hit_reset_addr, 0x00)
    game_state.waza_total = 0
    game_state.waza_total_prev = 0
    game_state.combo_counter = 0
    game_state.combo_counter_prev = 0
end

--- Resource management timers (declared before apply_exercise_setup which uses them)
local res = {
    recovery = 0,       -- counts up after combo drops
    stun_reset = 0,     -- counts up after combo drops, resets stun after delay
    meter_refill = 0,   -- counts up when meter is not full and no combo active
    meter_consumed = false,  -- true after super meter drops, cleared on refill
    prev_bars = 0,      -- previous frame's meter bars (read in on_gui, post-game-logic)
}

local function apply_exercise_setup(exercise)
    local setup = exercise.setup
    set_life(1, setup.p1_life)
    set_life(2, setup.p2_life)
    if setup.meter == "full" then
        fill_meter_full()
        res.meter_consumed = false
        res.meter_refill = 0
        res.prev_bars = 2
    end
    if konami.active then
        if setup.fill_h_charge then fill_h_charge() end
        if setup.fill_v_charge then fill_v_charge() end
    end
    reset_hit_tracking()
end

-- (resource timers moved before apply_exercise_setup)

reset_stun = function()
    -- Zero P2 stun bar so dummy doesn't get dizzy
    memory.writeword(MEM.p2_stun_bar, 0x0000)
    -- Clear P1 stun timer
    memory.writebyte(MEM.p1_stun_timer, 0x00)
end

local function manage_resources(exercise)
    if not exercise then return end
    local setup = exercise.setup

    -- Keep charge ready only if turbo charge secret is active
    if konami.active then
        if setup.fill_h_charge then fill_h_charge() end
        if setup.fill_v_charge then fill_v_charge() end
    end

    -- Note: meter management is handled exclusively in on_gui (writes in on_frame
    -- get overwritten by game logic). HP/stun/charge writes here are also overwritten,
    -- but the always-on on_gui path handles persistent writes for those too.

    -- HP and stun recovery: delayed reset after combo drops
    if game_state.combo_counter == 0 then
        res.recovery = res.recovery + 1
        res.stun_reset = res.stun_reset + 1
        if res.recovery > RECOVERY_DELAY_FRAMES then
            local p1_hp = memory.readbyte(MEM.p1_life)
            local p2_hp = memory.readbyte(MEM.p2_life)
            if p1_hp < LIFE_FULL then
                memory.writebyte(MEM.p1_life, math.min(p1_hp + LIFE_RECOVERY_SPEED, LIFE_FULL))
            end
            if p2_hp < LIFE_FULL then
                memory.writebyte(MEM.p2_life, math.min(p2_hp + LIFE_RECOVERY_SPEED, LIFE_FULL))
            end
        end
        if res.stun_reset > STUN_RESET_DELAY_FRAMES then
            reset_stun()
        end
    else
        res.recovery = 0
        res.stun_reset = 0
        -- But always keep P2 alive during combos so the round doesn't end
        if memory.readbyte(MEM.p2_life) < 0x10 then
            memory.writebyte(MEM.p2_life, 0x10)
        end
    end
end

-- ============================================================================
-- [9] EXERCISE ENGINE (state machine)
-- ============================================================================

local engine = {
    state = STATE_IDLE,
    current_exercise = nil,       -- reference to exercise table
    current_exercise_index = 1,   -- index in exercises array
    combo_index = 1,           -- current step in sequence (1-based)
    setup_timer = 0,
    result_timer = 0,
    attempt_started = false,
    fail_reason = "",
    last_hit_waza = "",
    projectile_hit_id = nil,

    -- Timing tracking
    step_frames = {},          -- frame when each step was hit
    active_start_frame = 0,    -- frame when ACTIVE began
    last_hit_frame = 0,        -- frame of most recent hit

    -- Hit deduplication: prevent multi-frame counter/waza noise from
    -- double-counting consecutive moves with the same action ID
    last_match_action = "",        -- action string at last matched step
    action_changed_since_match = true,  -- has action string changed since last match?

    -- Same-action step advancement: when consecutive steps share an action_id,
    -- use new button press detection instead of action-string-change detection
    next_expects_same_action = false,   -- next step has same action_id as current
    new_input_since_match = false,      -- new attack button pressed since last match
    last_match_buttons = {},            -- joypad snapshot at last match

    -- Fail diagnostics
    fail_step_index = 0,       -- which step failed
    fail_type = "",            -- "drop" | "timeout"
    fail_gap = 0,              -- actual frame gap at failure point
    fail_ref_gap = 0,          -- reference gap (0 if unknown)
    fail_last_action = "",     -- what move player was in at fail

    -- Stats for current session
    session_attempts = 0,
    session_completions = 0,
}

-- Combo tracker: live display of moves as they land (independent of exercise engine)
local combo_tracker = {
    moves = {},            -- array of move name strings
    display_string = "",   -- pre-built display text
    last_action_id = nil,  -- deduplicate same-frame hits
    fade_timer = 0,        -- countdown after combo drops
    active = false,        -- true while combo counter > 0
}
local COMBO_FADE_FRAMES = 120  -- 2 seconds at 60fps

--- Scan projectile objects for hits (ported from trial script)
local function scan_projectile_hits(expected_ids)
    local list = 3
    local obj_index = read_word_signed(MEM.obj_list_base + (list * 2))
    local count = 0

    while count < MAX_GAME_OBJECTS and obj_index ~= -1 do
        local obj_addr = MEM.obj_data_base + (obj_index * MEM.obj_stride)
        local tobi_id = read_mem(obj_addr + 0x04, 2)
        local p_hb_addr = memory.readdword(obj_addr + 0x2A0)
        local tobi_player = memory.readbyte(obj_addr + 0x3BF)

        if tobi_player == 0 and p_hb_addr ~= 0 then
            local hit_flg = memory.readbyte(obj_addr + 0x189)
            local hit_flg_prev = memory.readbyte(obj_addr + 0x189 + 0x04)

            if hit_flg ~= hit_flg_prev then
                local proj_string = "F" .. string.format("%04x", tobi_id)

                -- Check if this projectile hit matches any expected ID
                if expected_ids then
                    for _, eid in ipairs(expected_ids) do
                        if proj_string == eid then
                            -- Mark as logged so we don't double-count
                            if memory.readbyte(obj_addr + 0x189 + 0x06) == 0 then
                                memory.writebyte(obj_addr + 0x189 + 0x06, 1)
                                engine.projectile_hit_id = proj_string
                                return proj_string
                            end
                        end
                    end
                end

                -- Update prev for next frame comparison
                memory.writebyte(obj_addr + 0x189 + 0x04, hit_flg)
            end
        end

        -- Follow linked list
        obj_index = read_word_signed(obj_addr + 0x1C)
        count = count + 1
    end

    return nil
end

-- Sphere_throw and Aegis Reflector share the same P1 activation animation.
-- When meter was consumed, remap Sphere_throw action_id → Aegis action_id.
local SPHERE_TO_AEGIS = {
    ["S003e003e"] = "F077b",  -- L.Sphere_throw → L.Aegis
    ["S003f003f"] = "F077c",  -- M.Sphere_throw → M.Aegis
    ["S00400040"] = "F077d",  -- H.Sphere_throw → H.Aegis
}

local function select_exercise(index)
    index = clamp(index, 1, #exercises)
    engine.current_exercise_index = index
    engine.current_exercise = exercises[index]
    engine.state = STATE_SETUP
    engine.combo_index = 1
    engine.setup_timer = SETUP_DELAY_FRAMES
    engine.attempt_started = false
    engine.fail_reason = ""
    engine.last_hit_waza = ""
    engine.projectile_hit_id = nil
    engine.step_frames = {}
    engine.active_start_frame = 0
    engine.last_hit_frame = 0
    engine.last_match_action = ""
    engine.action_changed_since_match = true
    engine.next_expects_same_action = false
    engine.new_input_since_match = false
    engine.last_match_buttons = {}
    engine.fail_step_index = 0
    engine.fail_type = ""
    engine.fail_gap = 0
    engine.fail_ref_gap = 0
    engine.fail_last_action = ""
    engine.session_attempts = 0
    engine.session_completions = 0
end

local function reset_exercise()
    if not engine.current_exercise then return end
    engine.state = STATE_SETUP
    engine.combo_index = 1
    engine.setup_timer = SETUP_DELAY_FRAMES
    engine.attempt_started = false
    engine.fail_reason = ""
    engine.last_hit_waza = ""
    engine.projectile_hit_id = nil
    engine.step_frames = {}
    engine.active_start_frame = 0
    engine.last_hit_frame = 0
    engine.last_match_action = ""
    engine.action_changed_since_match = true
    engine.next_expects_same_action = false
    engine.new_input_since_match = false
    engine.last_match_buttons = {}
    engine.fail_step_index = 0
    engine.fail_type = ""
    engine.fail_gap = 0
    engine.fail_ref_gap = 0
    engine.fail_last_action = ""
end

local function engine_setup_update()
    if not game_state.playing then return end
    if not engine.current_exercise then
        engine.state = STATE_IDLE
        return
    end

    apply_exercise_setup(engine.current_exercise)

    engine.setup_timer = engine.setup_timer - 1
    if engine.setup_timer <= 0 then
        engine.state = STATE_ACTIVE
        engine.active_start_frame = game_state.frame_count
        engine.last_hit_frame = game_state.frame_count
        reset_hit_tracking()
    end
end

local function engine_active_update()
    if not game_state.playing then return end
    if not engine.current_exercise then
        engine.state = STATE_IDLE
        return
    end

    local ex = engine.current_exercise
    local seq = ex.sequence

    -- Manage HP/stun/meter/charge with delayed recovery
    manage_resources(ex)

    -- Timeout check: fail if exercise has been active too long
    local timeout = (ex.fail and ex.fail.timeout_frames) or 900
    if game_state.frame_count - engine.active_start_frame > timeout then
        engine.state = STATE_FAIL
        engine.result_timer = FAIL_DISPLAY_FRAMES
        engine.fail_step_index = engine.combo_index
        engine.fail_type = "timeout"
        engine.fail_gap = 0
        engine.fail_ref_gap = 0
        engine.fail_last_action = ""
        engine.fail_reason = "Timeout"
        return
    end

    -- Current step we're looking for
    if engine.combo_index > #seq then
        -- Already completed all steps (shouldn't get here normally)
        return
    end

    local current_step = seq[engine.combo_index]

    -- Check for combo drops: if combo counter was > 0 and resets to 0, and we haven't
    -- finished the sequence, that's a drop (skip for multi-combo exercises like Aegis setups)
    if not ex.allow_combo_reset and engine.combo_index > 1 and game_state.combo_counter == 0 and game_state.combo_counter_prev > 0 then
        engine.state = STATE_FAIL
        engine.result_timer = FAIL_DISPLAY_FRAMES

        -- Structured fail diagnostics
        engine.fail_step_index = engine.combo_index
        engine.fail_type = "drop"
        engine.fail_gap = game_state.frame_count - engine.last_hit_frame
        engine.fail_ref_gap = (ex.ref_timing and ex.ref_timing[engine.combo_index]) or 0
        engine.fail_last_action = lookup_move_name(game_state.p1.action_string) or game_state.p1.action_string

        -- Backward-compat fail_reason
        engine.fail_reason = "Combo dropped at: " .. current_step.name
        return
    end

    -- Check for projectile hits (F-type moves)
    if current_step.hit_type == "F" then
        local proj_hit = scan_projectile_hits(current_step.action_ids)
        if proj_hit and table_contains(current_step.action_ids, proj_hit) then
            engine.step_frames[engine.combo_index] = game_state.frame_count
            engine.last_hit_frame = game_state.frame_count
            engine.combo_index = engine.combo_index + 1
            if engine.combo_index == 2 and not engine.attempt_started then
                engine.attempt_started = true
                engine.session_attempts = engine.session_attempts + 1
                local prog = progression[ex.id]
                if prog then prog.attempts = prog.attempts + 1 end
            end
        end
    else
        -- Check for normal/special hits (H-type moves)
        -- Track whether the action string has changed since the last matched
        -- step.  Multi-hit normals (cr.HP = 2 hits) and multi-frame counter/
        -- waza noise can cause spurious new_hit signals while the player is
        -- still in the same move.  Requiring the action to change first
        -- ensures each step corresponds to a genuinely new move input.
        if game_state.p1.action_string ~= engine.last_match_action then
            engine.action_changed_since_match = true
        end

        -- Same-action step advancement: when consecutive steps share an
        -- action_id, detect new button presses instead of action-string changes
        if engine.next_expects_same_action and not engine.new_input_since_match then
            local attack_buttons = {
                "P1 Weak Punch", "P1 Medium Punch", "P1 Strong Punch",
                "P1 Weak Kick", "P1 Medium Kick", "P1 Strong Kick",
            }
            for _, key in ipairs(attack_buttons) do
                if input_current[key] and not engine.last_match_buttons[key] then
                    engine.new_input_since_match = true
                    break
                end
            end
        end

        local new_hit = false
        if game_state.combo_counter > game_state.combo_counter_prev and game_state.combo_counter > 0 then
            new_hit = true
        end

        if new_hit and (engine.action_changed_since_match or (engine.next_expects_same_action and engine.new_input_since_match)) then
            local hit_waza = game_state.p1.action_string
            engine.last_hit_waza = hit_waza

            -- Check if this hit matches any of the expected action IDs
            for _, expected_id in ipairs(current_step.action_ids) do
                if hit_waza == expected_id then
                    engine.step_frames[engine.combo_index] = game_state.frame_count
                    engine.last_hit_frame = game_state.frame_count
                    engine.last_match_action = hit_waza
                    engine.action_changed_since_match = false

                    -- Snapshot buttons and check if next step shares action_id
                    engine.last_match_buttons = {}
                    for k, v in pairs(input_current) do
                        engine.last_match_buttons[k] = v
                    end
                    engine.new_input_since_match = false
                    engine.next_expects_same_action = false
                    local next_idx = engine.combo_index + 1
                    if next_idx <= #seq then
                        for _, cur_id in ipairs(current_step.action_ids) do
                            for _, nxt_id in ipairs(seq[next_idx].action_ids) do
                                if cur_id == nxt_id then
                                    engine.next_expects_same_action = true
                                end
                            end
                        end
                    end

                    engine.combo_index = next_idx
                    if engine.combo_index == 2 and not engine.attempt_started then
                        engine.attempt_started = true
                        engine.session_attempts = engine.session_attempts + 1
                        local prog = progression[ex.id]
                        if prog then prog.attempts = prog.attempts + 1 end
                    end
                    break
                end
            end
        end
    end

    -- Check if all steps completed
    if engine.combo_index > #seq then
        local min_combo = ex.success.min_combo
        if min_combo and game_state.combo_counter < min_combo then
            -- Combo dropped before completing — don't count as success
            engine.combo_index = #seq
        else
            engine.state = STATE_SUCCESS
            engine.result_timer = SUCCESS_DISPLAY_FRAMES
            engine.session_completions = engine.session_completions + 1
            current_streak = current_streak + 1
            if current_streak > best_streak then
                best_streak = current_streak
            end

            -- Update progression
            local prog = progression[ex.id]
            if prog then
                prog.completions = prog.completions + 1
                if prog.completions >= MASTERY_THRESHOLD then
                    prog.mastered = true
                end
                save_progression()
            end
        end
    end
end

local function engine_result_update()
    engine.result_timer = engine.result_timer - 1
    if engine.result_timer <= 0 then
        if engine.state == STATE_FAIL then
            current_streak = 0
        end
        reset_exercise()
    end
end

local function engine_update()
    if engine.state == STATE_SETUP then
        engine_setup_update()
    elseif engine.state == STATE_ACTIVE then
        engine_active_update()
    elseif engine.state == STATE_SUCCESS or engine.state == STATE_FAIL then
        engine_result_update()
        -- Keep resources managed during result display
        if game_state.playing and engine.current_exercise then
            manage_resources(engine.current_exercise)
        end
    end
end

--- Compute timing summary for completed steps
--- Returns array of {name, actual_gap, ref_gap, delta, rating} per completed step
local function compute_timing_summary()
    local ex = engine.current_exercise
    if not ex then return {} end

    local seq = ex.sequence
    local summary = {}

    for i = 1, math.min(engine.combo_index - 1, #seq) do
        local entry = { name = seq[i].name, actual_gap = 0, ref_gap = 0, delta = 0, rating = "tight" }

        if i == 1 then
            -- First step has no predecessor gap
            entry.actual_gap = 0
            entry.ref_gap = 0
            entry.delta = 0
            entry.rating = "tight"
        elseif engine.step_frames[i] and engine.step_frames[i - 1] then
            entry.actual_gap = engine.step_frames[i] - engine.step_frames[i - 1]
            entry.ref_gap = (ex.ref_timing and ex.ref_timing[i]) or 0

            if entry.ref_gap > 0 then
                entry.delta = entry.actual_gap - entry.ref_gap
                local abs_delta = math.abs(entry.delta)
                if abs_delta <= TIMING_TIGHT then
                    entry.rating = "tight"
                elseif abs_delta <= TIMING_OK then
                    entry.rating = "ok"
                else
                    entry.rating = "loose"
                end
            else
                entry.delta = 0
                entry.rating = "tight"  -- no reference = no judgment
            end
        end

        table.insert(summary, entry)
    end

    return summary
end

--- Get color for a timing rating
local function timing_color(rating)
    if rating == "tight" then return COLOR.timing_tight end
    if rating == "ok" then return COLOR.timing_ok end
    return COLOR.timing_loose
end

--- Combo tracker update: runs every frame, independent of exercise engine and capture
local function combo_tracker_update()
    if not game_state.playing then return end

    local gs = game_state

    -- Detect combo start (counter went from 0 to >0)
    if gs.combo_counter > 0 and gs.combo_counter_prev == 0 then
        combo_tracker.moves = {}
        combo_tracker.display_string = ""
        combo_tracker.last_action_id = nil
        combo_tracker.active = true
        combo_tracker.fade_timer = 0
    end

    -- Detect new hit (counter or waza increased)
    if combo_tracker.active and gs.combo_counter > 0 then
        local new_hit = false
        if gs.combo_counter > gs.combo_counter_prev and gs.combo_counter_prev >= 0 then
            new_hit = true
        elseif gs.waza_total ~= gs.waza_total_prev and gs.waza_total > 0 then
            new_hit = true
        end

        if new_hit then
            local action_id = gs.p1.action_string
            -- Aegis activation shares action_id with Sphere_throw; remap when meter was consumed
            if res.meter_consumed and SPHERE_TO_AEGIS[action_id] then
                action_id = SPHERE_TO_AEGIS[action_id]
            end
            -- Deduplicate: don't add the same action_id consecutively (multi-hit moves)
            if action_id ~= combo_tracker.last_action_id then
                combo_tracker.last_action_id = action_id
                local move_name = lookup_move_name(action_id)
                if not move_name then
                    -- Build readable fallback: "spc?0021" instead of raw "S00210021"
                    local prefix_names = {
                        A = "atk", S = "spc", T = "throw", G = "guard", M = "misc", N = ""
                    }
                    local p = action_id:sub(1, 1)
                    move_name = (prefix_names[p] or "") .. "?" .. action_id:sub(6)
                end
                table.insert(combo_tracker.moves, move_name)

                -- Rebuild display string
                combo_tracker.display_string = table.concat(combo_tracker.moves, " > ")
                -- Truncate from left if too long
                if #combo_tracker.display_string > 90 then
                    combo_tracker.display_string = "..." .. combo_tracker.display_string:sub(-87)
                end
            end
        end
    end

    -- Detect combo drop (counter went from >0 to 0)
    if gs.combo_counter == 0 and gs.combo_counter_prev > 0 and combo_tracker.active then
        combo_tracker.active = false
        combo_tracker.fade_timer = COMBO_FADE_FRAMES
    end

    -- Fade countdown
    if not combo_tracker.active and combo_tracker.fade_timer > 0 then
        combo_tracker.fade_timer = combo_tracker.fade_timer - 1
        if combo_tracker.fade_timer <= 0 then
            combo_tracker.moves = {}
            combo_tracker.display_string = ""
            combo_tracker.last_action_id = nil
        end
    end
end

-- ============================================================================
-- [10] INPUT DISPLAY
-- ============================================================================

local notation_mode = NOTATION_SF

local function get_notation(exercise)
    if notation_mode == NOTATION_NUMPAD then
        return exercise.numpad
    else
        return exercise.notation
    end
end

local function toggle_notation()
    if notation_mode == NOTATION_SF then
        notation_mode = NOTATION_NUMPAD
    else
        notation_mode = NOTATION_SF
    end
end

-- ============================================================================
-- [11a] MATCHUP SAVE STATES
-- ============================================================================

local matchup_slots = {}  -- { [slot] = { name = "vs Chun", saved = true } }

local function init_matchup_slots()
    for i = 1, MAX_MATCHUP_SLOTS do
        matchup_slots[i] = { name = "Slot " .. i, saved = false }
    end
end

local function save_matchup_metadata()
    local f = io.open(MATCHUP_FILE, "w")
    if not f then return end
    for i = 1, MAX_MATCHUP_SLOTS do
        local slot = matchup_slots[i]
        f:write(string.format("%d,%s,%s\n", i, slot.name, slot.saved and "1" or "0"))
    end
    f:close()
end

local function load_matchup_metadata()
    init_matchup_slots()
    local f = io.open(MATCHUP_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local idx, name, saved = line:match("^(%d+),(.+),(%d+)$")
        if idx then
            local i = tonumber(idx)
            if i and i >= 1 and i <= MAX_MATCHUP_SLOTS then
                matchup_slots[i].name = name
                matchup_slots[i].saved = (saved == "1")
            end
        end
    end
    f:close()
end

local function save_matchup(slot_num)
    if slot_num < 1 or slot_num > MAX_MATCHUP_SLOTS then return false end
    local state = savestate.create(MATCHUP_SLOT_BASE + slot_num)
    savestate.save(state)
    matchup_slots[slot_num].saved = true
    save_matchup_metadata()
    print("[Urien Lab] Saved matchup to slot " .. slot_num .. ": " .. matchup_slots[slot_num].name)
    return true
end

local function load_matchup(slot_num)
    if slot_num < 1 or slot_num > MAX_MATCHUP_SLOTS then return false end
    if not matchup_slots[slot_num].saved then
        print("[Urien Lab] Slot " .. slot_num .. " is empty")
        return false
    end
    local state = savestate.create(MATCHUP_SLOT_BASE + slot_num)
    savestate.load(state)
    print("[Urien Lab] Loaded matchup from slot " .. slot_num .. ": " .. matchup_slots[slot_num].name)
    return true
end

-- ============================================================================
-- [11a2] CHARACTER SAVE STATES
-- ============================================================================

local function init_char_states()
    for _, char in ipairs(CHARACTERS) do
        if not char_states[char.id] then
            char_states[char.id] = { saved = false }
        end
    end
end

--- Check if a file exists (opens and closes cleanly)
local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

--- Load the character select save state
local function load_charselect_save()
    if not file_exists(CHARSELECT_SAVE) then
        -- Try downloading from server
        if not fetch_save_state(CHARSELECT_SAVE) then
            print("[Urien Lab] No character select save found: " .. CHARSELECT_SAVE)
            return false
        end
    end
    local temp = tostring(TEMP_SLOT)
    os.remove(temp)
    if not os.rename(CHARSELECT_SAVE, temp) then
        print("[Urien Lab] Could not access: " .. CHARSELECT_SAVE)
        return false
    end
    local state = savestate.create(TEMP_SLOT)
    savestate.load(state)
    os.rename(temp, CHARSELECT_SAVE)
    return true
end

--- Start the game character select sequence
local function start_character_select()
    if not load_charselect_save() then return false end
    charselect_seq = 1  -- P1 selecting
    app_state = APP_CHARSELECT
    charselect_visible = false  -- hide script overlay, show game's native screen
    print("[Urien Lab] Character select -- pick your fighters!")
    return true
end

local function save_char_metadata()
    local f = io.open(CHAR_SAVE_FILE, "w")
    if not f then return end
    for _, char in ipairs(CHARACTERS) do
        local st = char_states[char.id]
        f:write(string.format("%d,%s,%s\n", char.id, char.name, st and st.saved and "1" or "0"))
    end
    f:close()
end

local function load_char_metadata()
    init_char_states()
    -- First check the metadata file
    local f = io.open(CHAR_SAVE_FILE, "r")
    if f then
        for line in f:lines() do
            local id_str, name, saved = line:match("^(%d+),(.+),(%d+)$")
            if id_str then
                local id = tonumber(id_str)
                if char_states[id] then
                    char_states[id].saved = (saved == "1")
                end
            end
        end
        f:close()
    end
    -- Also verify named files actually exist on disk
    for _, char in ipairs(CHARACTERS) do
        local path = char_save_path(char)
        local sf = io.open(path, "rb")
        if sf then
            sf:close()
            char_states[char.id] = { saved = true }
        end
    end
end

-- Forward declaration (defined in [11b], needed by load_char_state below)
local rebuild_filtered_exercises

local function save_char_state(char_index)
    local char = CHARACTERS[char_index]
    if not char then return false end
    local path = char_save_path(char)
    local temp = tostring(TEMP_SLOT)
    -- Save to temp slot, then rename to named file
    local state = savestate.create(TEMP_SLOT)
    savestate.save(state)
    -- Remove existing named file if present, then rename temp
    os.remove(path)
    os.rename(temp, path)
    char_states[char.id] = { saved = true }
    save_char_metadata()
    print("[Urien Lab] Saved state: " .. path)
    return true
end

local function load_char_state(char_index)
    local char = CHARACTERS[char_index]
    if not char then return false end
    local path = char_save_path(char)
    -- Try downloading if file doesn't exist locally
    if not file_exists(path) then
        if fetch_save_state("vs_" .. char.name .. ".fs") then
            char_states[char.id] = { saved = true }
        else
            print("[Urien Lab] No save state for vs " .. char.name)
            return false
        end
    end
    if not char_states[char.id] or not char_states[char.id].saved then
        print("[Urien Lab] No save state for vs " .. char.name)
        return false
    end
    local temp = tostring(TEMP_SLOT)
    -- Rename named file to temp slot, load, then rename back
    os.remove(temp)
    if not os.rename(path, temp) then
        print("[Urien Lab] Could not find save file: " .. path)
        return false
    end
    local state = savestate.create(TEMP_SLOT)
    savestate.load(state)
    os.rename(temp, path)
    -- Immediately freeze round timer so it doesn't tick after loading
    memory.writebyte(MEM.round_timer, 100)
    -- Fill meter immediately on next on_gui frame
    res.meter_refill = METER_REFILL_DELAY_FRAMES + 1
    charselect_seq = 0  -- stop native select sequence so it doesn't clear opponent
    selected_opponent = char
    rebuild_filtered_exercises()
    print("[Urien Lab] Loaded state: " .. path)
    return true
end

--- Auto-load the first available saved character state on script start
local function load_home_state()
    for i, char in ipairs(CHARACTERS) do
        if char_states[char.id] and char_states[char.id].saved then
            if load_char_state(i) then
                -- Stay in charselect with overlay visible so user sees the grid
                app_state = APP_CHARSELECT
                charselect_visible = true
                char_cursor = i
                print("[Urien Lab] Auto-loaded home state: vs " .. char.name)
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- [11b] HUD & MENU
-- ============================================================================

-- Menu modes
local MENU_ALL_EXERCISES = 1   -- All exercises (unfiltered)
local MENU_CHAR_EXERCISES = 2  -- Character-filtered exercises
local MENU_OPPONENT = 3

local menu = {
    show = false,
    cursor_all = 1,        -- cursor for All tab
    cursor_char = 1,       -- cursor for Character tab
    mode = MENU_ALL_EXERCISES,
    matchup_cursor = 1,
    naming_slot = nil,     -- set to slot number when naming a matchup
    naming_buffer = "",
    debug = false,
    delete_id = nil,       -- exercise ID pending delete confirmation
    sort_mode = "category",
}

-- Sort modes for exercise list (cycled with HP)
local SORT_MODES = {"category", "difficulty", "name"}
local SORT_LABELS = { category = "Category", difficulty = "Diff", name = "Name" }

--- Rebuild both exercise index lists (all + character-filtered)
--- Sorts by category order (combo → unblockable → sequence → parry)
rebuild_filtered_exercises = function()
    filtered_exercises = {}
    all_exercises_sorted = {}
    filter_active = (selected_opponent ~= nil)

    -- Build category priority lookup
    local cat_order = {}
    for i, cat in ipairs(EXERCISE_CATEGORIES) do
        cat_order[cat] = i
    end

    -- Multi-mode comparator
    local sorter
    if menu.sort_mode == "difficulty" then
        sorter = function(a, b)
            local da = exercises[a].difficulty or 1
            local db = exercises[b].difficulty or 1
            if da ~= db then return da < db end
            return a < b
        end
    elseif menu.sort_mode == "name" then
        sorter = function(a, b)
            local na = (exercises[a].name or ""):lower()
            local nb = (exercises[b].name or ""):lower()
            if na ~= nb then return na < nb end
            return a < b
        end
    else -- "category" (default)
        sorter = function(a, b)
            local cat_a = exercises[a].category or "combo"
            local cat_b = exercises[b].category or "combo"
            local order_a = cat_order[cat_a] or 99
            local order_b = cat_order[cat_b] or 99
            if order_a ~= order_b then return order_a < order_b end
            return a < b
        end
    end

    -- Build all-exercises list (unfiltered, sorted by current mode)
    local all = {}
    for i = 1, #exercises do
        table.insert(all, i)
    end
    table.sort(all, sorter)
    all_exercises_sorted = all

    -- Build character-filtered list
    local matching = {}
    for i, exercise in ipairs(exercises) do
        local dominated = false
        if filter_active then
            if exercise.characters and #exercise.characters > 0 then
                dominated = true
                for _, char_name in ipairs(exercise.characters) do
                    if char_name == selected_opponent.name then
                        dominated = false
                        break
                    end
                end
            end
        end
        if not dominated then
            table.insert(matching, i)
        end
    end
    table.sort(matching, sorter)
    filtered_exercises = matching

    -- Clamp cursors
    if menu.cursor_all > #all_exercises_sorted then
        menu.cursor_all = math.max(1, #all_exercises_sorted)
    end
    if menu.cursor_char > #filtered_exercises then
        menu.cursor_char = math.max(1, #filtered_exercises)
    end
end

-- Forward declaration (capture table defined in [11b], referenced by draw_header)
local capture

--- Draw a filled box with optional border
local function draw_box(x, y, w, h, bg_color, border_color)
    gui.box(x, y, x + w, y + h, bg_color, border_color or bg_color)
end

--- Draw a vertical gradient box (top_color to bottom_color) with optional border
local function draw_gradient_box(x, y, w, h, top_color, bottom_color, border_color)
    -- Extract RGBA components (FBNeo uses RRGGBBAA format)
    local tr = math.floor(top_color / 0x01000000) % 256
    local tg = math.floor(top_color / 0x00010000) % 256
    local tb = math.floor(top_color / 0x00000100) % 256
    local ta = top_color % 256

    local br = math.floor(bottom_color / 0x01000000) % 256
    local bg = math.floor(bottom_color / 0x00010000) % 256
    local bb = math.floor(bottom_color / 0x00000100) % 256
    local ba = bottom_color % 256

    -- Draw horizontal strips (every 2 pixels for performance)
    local step = 2
    for row = 0, h - 1, step do
        local t = row / math.max(h - 1, 1)
        local r = math.floor(tr + (br - tr) * t + 0.5)
        local g = math.floor(tg + (bg - tg) * t + 0.5)
        local b = math.floor(tb + (bb - tb) * t + 0.5)
        local a = math.floor(ta + (ba - ta) * t + 0.5)
        local c = r * 0x01000000 + g * 0x00010000 + b * 0x00000100 + a
        local row_h = math.min(step, h - row)
        gui.box(x, y + row, x + w, y + row + row_h - 1, c, c)
    end

    -- Draw border on top
    if border_color then
        gui.box(x, y, x + w, y + h, COLOR.transparent, border_color)
    end
end

--- Draw text with a dark outline for readability
local function draw_text(x, y, text, color)
    gui.text(x, y, text, color, COLOR.text_outline)
end

--- Draw the two charge meters (4-6 horizontal, 2-8 vertical)
local function draw_charge_meters()
    local bar_w, bar_h = 42, 2
    local function gauge(label, x, y, value_addr, timer_addr)
        draw_text(x - 16, y, label, COLOR.text_gray)
        local charge = memory.readbyte(value_addr)
        local timer = memory.readbyte(timer_addr)
        -- Charge bar
        if charge ~= 0xFF then
            gui.box(x, y, x + bar_w, y + bar_h, COLOR.transparent, COLOR.charge_border)
            local fill = math.min(charge, bar_w)
            if fill > 0 then
                gui.box(x, y, x + fill, y + bar_h, COLOR.charge_fill, COLOR.charge_border)
            end
        else
            gui.box(x, y, x + bar_w, y + bar_h, COLOR.transparent, COLOR.charge_full_border)
        end
        -- Timer bar (shows charge decay countdown)
        y = y + 3
        if timer ~= 0xFF then
            gui.box(x, y, x + bar_w, y + bar_h, COLOR.transparent, COLOR.charge_border)
            local fill = math.min(timer, bar_w)
            if fill > 0 then
                gui.box(x, y, x + fill, y + bar_h, COLOR.charge_timer, COLOR.charge_border)
            end
        else
            gui.box(x, y, x + bar_w, y + bar_h, COLOR.transparent, COLOR.charge_border)
        end
    end
    local side_r = engine.current_exercise and get_exercise_side(engine.current_exercise.id) == "R"
    local x, y = side_r and 20 or 320, 170
    local h_label = notation_mode == NOTATION_NUMPAD and "4-6" or "b-f"
    local v_label = notation_mode == NOTATION_NUMPAD and "2-8" or "d-u"
    gauge(h_label, x, y, MEM.charge_h_value, MEM.charge_h_timer)
    gauge(v_label, x, y + 8, MEM.charge_v_value, MEM.charge_v_timer)
end

--- Draw the character select screen
local function draw_charselect()
    local panel_x = 10
    local panel_y = 5
    local panel_w = SCREEN_W - 20
    local panel_h = SCREEN_H - 10

    draw_gradient_box(panel_x, panel_y, panel_w, panel_h, COLOR.menu_top, COLOR.menu_bottom, COLOR.border_light)

    -- Title
    draw_text(panel_x + 4, panel_y + 4, "SELECT OPPONENT", COLOR.text_cyan)
    draw_text(panel_x + panel_w - 100, panel_y + 4, "URIEN LAB v" .. SCRIPT_VERSION, COLOR.text_gray)

    -- Grid
    local grid_x = panel_x + 12
    local grid_y = panel_y + 18
    local cell_w = 84
    local cell_h = 28

    for i, char in ipairs(CHARACTERS) do
        local col = (i - 1) % CHAR_GRID_COLS
        local row = math.floor((i - 1) / CHAR_GRID_COLS)
        local cx = grid_x + col * cell_w
        local cy = grid_y + row * cell_h

        local is_cursor = (i == char_cursor)
        local has_state = char_states[char.id] and char_states[char.id].saved

        -- Cell background — always draw a visible box so tiles are apparent
        local bg = 0x181822FF
        local border = 0x333344FF
        if is_cursor then
            bg = 0x282848FF
            border = COLOR.highlight
        elseif has_state then
            bg = 0x182218FF
            border = 0x335533FF
        end
        draw_box(cx, cy, cell_w - 4, cell_h - 4, bg, border)

        -- Character name
        local name_color = COLOR.text_white
        if has_state then
            name_color = COLOR.text_green
        elseif not is_cursor then
            name_color = COLOR.text_gray
        end

        local text_y = cy + (cell_h - 4) / 2 - 4
        draw_text(cx + 4, text_y, char.name, name_color)

        -- Saved indicator
        if has_state then
            draw_text(cx + cell_w - 14, text_y, "*", COLOR.text_green)
        end
    end

    -- Bottom instructions
    local help_y = panel_y + panel_h - 36
    local char = CHARACTERS[char_cursor]
    if char then
        local has_state = char_states[char.id] and char_states[char.id].saved
        if has_state then
            draw_text(panel_x + 4, help_y, "Jab = Load  vs " .. char.name, COLOR.text_white)
            draw_text(panel_x + 4, help_y + 10, "Fierce = Re-save current state", COLOR.text_white)
        else
            draw_text(panel_x + 4, help_y, "No state saved for vs " .. char.name, COLOR.text_yellow)
            draw_text(panel_x + 4, help_y + 10, "Fierce = Save current game state", COLOR.text_white)
        end
    end
end

--- Draw the top header bar (always visible in training mode)
local function draw_header()
    draw_box(0, 0, SCREEN_W, 16, COLOR.bg_header, COLOR.border)

    -- Line 1 (y=2): "URIEN LAB" on left, status on right
    draw_text(4, 2, "URIEN LAB", COLOR.text_cyan)

    -- Right side of line 1: recording status or opponent name
    if capture.active then
        local elapsed = game_state.frame_count - capture.start_frame
        -- Flash every 30 frames
        if math.floor(elapsed / 15) % 2 == 0 then
            draw_text(SCREEN_W - 100, 2,
                string.format("[REC] %d hits %ds", capture.hit_count, math.floor(elapsed / 60)),
                COLOR.text_red)
        end
    elseif selected_opponent then
        draw_text(SCREEN_W - 60, 2, "vs " .. selected_opponent.name, COLOR.text_white)
    end

    -- Line 2 (y=8): exercise name or instructions on left, exercise count on right
    if engine.current_exercise then
        local exercise_label = engine.current_exercise.name
        if get_exercise_side(engine.current_exercise.id) == "R" then
            exercise_label = exercise_label .. " [R]"
        end
        draw_text(4, 8, exercise_label, COLOR.text_yellow)
    else
        draw_text(4, 8, "Start=Menu  Coin=Record", COLOR.text_gray)
    end

    draw_text(SCREEN_W - 50, 8, #exercises .. " exercises", COLOR.text_gray)
end

--- Draw the live combo tracker (below header)
local function draw_combo_tracker()
    if #combo_tracker.moves == 0 then return end

    local hit_count = #combo_tracker.moves
    local text = hit_count .. " hits: " .. combo_tracker.display_string

    if combo_tracker.active then
        -- Active combo: solid white
        draw_text(4, 18, text, COLOR.text_white)
    elseif combo_tracker.fade_timer > 0 then
        -- Fading out after combo drop
        local alpha = math.floor((combo_tracker.fade_timer / COMBO_FADE_FRAMES) * 0xFF)
        alpha = clamp(alpha, 0, 0xFF)
        local fade_color = 0xBBBBBB00 + alpha
        draw_text(4, 18, text, fade_color)
    end
end

--- Draw the bottom info bar during active exercise
local function draw_info_bar()
    if not engine.current_exercise then return end
    if engine.state == STATE_IDLE or engine.state == STATE_MENU then return end

    local ex = engine.current_exercise
    local seq = ex.sequence
    local bar_y = SCREEN_H - 30

    draw_box(0, bar_y, SCREEN_W, 30, COLOR.bg_panel, COLOR.border)

    -- Pre-compute timing summary for completed steps
    local summary = compute_timing_summary()

    -- Pre-compute attempt counter to know available width
    local att_str = string.format("Attempt: %d  OK: %d/%d",
        engine.session_attempts,
        engine.session_completions,
        engine.session_attempts)

    -- Step indicator with scrolling viewport for long combos
    local step_label = "Step: "
    local label_x = 4
    draw_text(label_x, bar_y + 2, step_label, COLOR.text_gray)
    local content_x = label_x + #step_label * 4
    local visible_w = SCREEN_W - #att_str * 4 - 8 - content_x

    -- Pass 1: calculate positions and widths for each step
    local step_positions = {}
    local cursor = 0
    for i, step in ipairs(seq) do
        local bl = (i == engine.combo_index) and "[" or ""
        local br = (i == engine.combo_index) and "]" or ""
        local timing = ""
        if i < engine.combo_index and i > 1 and summary[i] and summary[i].ref_gap > 0 then
            local delta = summary[i].delta
            local sign = delta >= 0 and "+" or ""
            timing = "(" .. sign .. delta .. "f)"
        end
        local sep = (i < #seq) and " > " or ""
        local name_w = (#bl + #step.name + #br) * 4
        local time_w = #timing * 4
        local sep_w = #sep * 4
        step_positions[i] = {
            x = cursor, name_w = name_w, time_w = time_w, sep_w = sep_w,
            bl = bl, br = br, timing = timing, sep = sep,
        }
        cursor = cursor + name_w + time_w + sep_w
    end

    -- Scroll to keep current step visible, pushing completed steps off left
    local scroll = 0
    if step_positions[engine.combo_index] then
        local cp = step_positions[engine.combo_index]
        local current_end = cp.x + cp.name_w + cp.time_w
        if current_end > visible_w then
            scroll = cp.x - 20  -- keep 20px peek at previous step
        end
    end
    if scroll < 0 then scroll = 0 end

    -- Pass 2: draw only steps within the viewport
    for i, step in ipairs(seq) do
        local sp = step_positions[i]
        local dx = content_x + sp.x - scroll
        local total_w = sp.name_w + sp.time_w + sp.sep_w
        if dx + total_w >= content_x and dx < content_x + visible_w then
            local color
            if i < engine.combo_index then
                color = COLOR.step_done
            elseif i == engine.combo_index then
                color = COLOR.step_current
            else
                color = COLOR.step_pending
            end
            draw_text(dx, bar_y + 2, sp.bl .. step.name .. sp.br, color)
            dx = dx + sp.name_w
            if sp.timing ~= "" then
                draw_text(dx, bar_y + 2, sp.timing, timing_color(summary[i].rating))
                dx = dx + sp.time_w
            end
            if sp.sep ~= "" then
                draw_text(dx, bar_y + 2, sp.sep, color)
            end
        end
    end

    -- Attempt counter (right-aligned)
    draw_text(SCREEN_W - #att_str * 4 - 4, bar_y + 2, att_str, COLOR.text_white)

    -- Hint line
    if ex.hints and #ex.hints > 0 then
        -- Show first hint, or cycle hints on repeated failures
        local hint_idx = 1
        local prog = progression[ex.id]
        if prog and prog.attempts > 3 and #ex.hints > 1 then
            hint_idx = ((prog.attempts - 1) % #ex.hints) + 1
        end
        draw_text(4, bar_y + 14, "Hint: " .. ex.hints[hint_idx], COLOR.text_orange)
    end
end

--- Build timing strip string for completed steps (used in both success and fail banners)
local function draw_timing_strip(x, y, summary, fail_step)
    local sx = x
    for i, s in ipairs(summary) do
        local name_color = COLOR.step_done
        draw_text(sx, y, s.name, name_color)
        sx = sx + #s.name * 4

        -- Show timing delta for steps after the first (if reference exists)
        if i > 1 and s.ref_gap > 0 then
            local sign = s.delta >= 0 and "+" or ""
            local delta_str = "(" .. sign .. s.delta .. "f)"
            draw_text(sx, y, delta_str, timing_color(s.rating))
            sx = sx + #delta_str * 4
        end

        -- Separator
        if i < #summary or fail_step then
            draw_text(sx, y, " > ", COLOR.text_gray)
            sx = sx + 12
        end
    end

    -- Show failed step if provided
    if fail_step then
        local fail_mark = "X" .. fail_step
        draw_text(sx, y, fail_mark, COLOR.text_red)
    end
end

-- Category selector after exercise capture
local cat_sel = { active = false, cursor = 1, exercise = nil }

--- Draw category selector popup after exercise capture
local function draw_category_selector()
    if not cat_sel.active then return end
    local num_cats = #EXERCISE_CATEGORIES
    local row_h = 10
    local popup_w = 100
    local popup_h = 14 + num_cats * row_h + 12  -- title + rows + footer
    local popup_x = (SCREEN_W - popup_w) / 2
    local popup_y = (SCREEN_H - popup_h) / 2

    draw_box(popup_x, popup_y, popup_w, popup_h, COLOR.bg_dark, COLOR.border_light)
    draw_text(popup_x + 4, popup_y + 4, "SELECT CATEGORY:", COLOR.text_cyan)

    for i, cat in ipairs(EXERCISE_CATEGORIES) do
        local y = popup_y + 14 + (i - 1) * row_h
        local label = CATEGORY_LABELS[cat] or cat:upper()
        if i == cat_sel.cursor then
            draw_text(popup_x + 6, y, "> " .. label, COLOR.text_yellow)
        else
            draw_text(popup_x + 14, y, label, COLOR.text_white)
        end
    end

    draw_text(popup_x + 4, popup_y + popup_h - 10, "Jab: Confirm", COLOR.text_gray)
end

--- Draw success/fail banner
local function draw_result_banner()
    if engine.state == STATE_SUCCESS then
        local ex = engine.current_exercise
        local summary = compute_timing_summary()
        local has_timing = false
        for _, s in ipairs(summary) do
            if s.ref_gap > 0 then has_timing = true; break end
        end

        -- Banner height: base 30 + timing line if available + streak line
        local banner_h = 30
        if has_timing then banner_h = banner_h + 12 end
        if current_streak > 1 then banner_h = banner_h + 10 end

        local banner_y = SCREEN_H / 2 - banner_h / 2
        local bx = SCREEN_W / 4
        local bw = SCREEN_W / 2
        draw_box(bx, banner_y, bw, banner_h, COLOR.bg_success, COLOR.step_done)

        -- Line 1: CLEAR!
        draw_text(SCREEN_W / 2 - 20, banner_y + 4, "CLEAR!", COLOR.text_green)

        -- Line 2: Progression
        local line_y = banner_y + 16
        local prog = progression[ex.id]
        if prog then
            local comp_str = prog.completions .. "/" .. MASTERY_THRESHOLD
            if prog.mastered then
                comp_str = comp_str .. " MASTERED!"
            end
            draw_text(SCREEN_W / 2 - 24, line_y, comp_str, COLOR.text_white)
            line_y = line_y + 12
        end

        -- Line 3: Timing deltas (if reference timing exists)
        if has_timing then
            local timing_x = bx + 4
            draw_text(timing_x, line_y, "Timing: ", COLOR.text_gray)
            local tx = timing_x + 32
            for i, s in ipairs(summary) do
                if i > 1 and s.ref_gap > 0 then
                    local sign = s.delta >= 0 and "+" or ""
                    local delta_str = sign .. s.delta .. "f"
                    draw_text(tx, line_y, delta_str, timing_color(s.rating))
                    tx = tx + (#delta_str + 1) * 4
                end
            end
            line_y = line_y + 10
        end

        -- Line 4: Streak
        if current_streak > 1 then
            draw_text(SCREEN_W / 2 - 20, line_y, "Streak: " .. current_streak, COLOR.text_yellow)
        end

    elseif engine.state == STATE_FAIL then
        local ex = engine.current_exercise
        local summary = compute_timing_summary()

        -- Calculate banner height based on content
        local banner_h = 14  -- Line 1: dropped message
        banner_h = banner_h + 10  -- Line 2: timing info
        if #summary > 0 then banner_h = banner_h + 10 end  -- Line 3: step strip
        banner_h = banner_h + 4  -- padding

        local banner_y = SCREEN_H / 2 - banner_h / 2
        local bx = SCREEN_W / 4 - 20
        local bw = SCREEN_W / 2 + 40
        draw_box(bx, banner_y, bw, banner_h, COLOR.bg_fail, COLOR.text_red)

        local line_y = banner_y + 4

        -- Line 1: DROPPED/TIMEOUT at step N: [move_name]
        local step_name = ""
        if ex and ex.sequence and engine.fail_step_index > 0 and engine.fail_step_index <= #ex.sequence then
            step_name = ex.sequence[engine.fail_step_index].name
        end
        local fail_label = engine.fail_type == "timeout" and "TIMEOUT" or "DROPPED"
        local drop_msg = string.format("%s at step %d: %s", fail_label, engine.fail_step_index, step_name)
        draw_text(bx + 4, line_y, drop_msg, COLOR.text_red)
        line_y = line_y + 10

        -- Line 2: Timing delta or raw gap
        if engine.fail_ref_gap > 0 then
            local delta = engine.fail_gap - engine.fail_ref_gap
            local direction = delta >= 0 and "LATE" or "EARLY"
            local abs_delta = math.abs(delta)
            local delta_color
            if abs_delta <= TIMING_TIGHT then delta_color = COLOR.timing_tight
            elseif abs_delta <= TIMING_OK then delta_color = COLOR.timing_ok
            else delta_color = COLOR.timing_loose end
            draw_text(bx + 4, line_y, direction .. " by " .. abs_delta .. "f", delta_color)
        else
            draw_text(bx + 4, line_y, "Gap: " .. engine.fail_gap .. "f", COLOR.text_yellow)
        end
        -- Show what move player was doing
        if engine.fail_last_action ~= "" then
            draw_text(bx + 100, line_y, "(was: " .. engine.fail_last_action .. ")", COLOR.text_gray)
        end
        line_y = line_y + 10

        -- Line 3: Step timing strip
        if #summary > 0 then
            draw_timing_strip(bx + 4, line_y, summary, step_name)
        end
    end
end

--- Draw setup countdown
local function draw_setup_overlay()
    -- Intentionally empty: no "Ready" countdown overlay
end

--- Draw the exercise selection menu
--- @param ex_list table  — index list (all_exercises_sorted or filtered_exercises)
--- @param cursor number  — current cursor position within ex_list
--- @param is_all boolean — true when drawing the All tab (shows tag count indicator)
local function draw_exercise_list(menu_x, menu_y, menu_w, row_h, visible_rows, menu_h, ex_list, cursor, is_all)
    -- Column positions (right-aligned region)
    local col_hits = menu_x + menu_w - 96
    local col_diff = menu_x + menu_w - 68
    local col_side = menu_x + menu_w - 44
    local col_prog = menu_x + menu_w - 24

    -- Count display with sort indicator
    local count_str
    if is_all then
        count_str = #exercises .. " exercises"
    elseif filter_active then
        count_str = #ex_list .. "/" .. #exercises
    else
        count_str = #exercises .. " exercises"
    end
    if menu.sort_mode ~= "category" then
        count_str = count_str .. "  by " .. SORT_LABELS[menu.sort_mode]
    end
    draw_text(menu_x + menu_w - #count_str * 4, menu_y + 2, count_str,
        menu.sort_mode ~= "category" and COLOR.text_yellow or COLOR.text_gray)

    -- Empty state
    if #ex_list == 0 then
        if #exercises > 0 and filter_active and not is_all then
            local opp_name = selected_opponent and selected_opponent.name or "opponent"
            draw_text(menu_x + 4, menu_y + 40,
                "No exercises for " .. opp_name .. ". Press Coin to record.", COLOR.text_yellow)
        else
            draw_text(menu_x + 4, menu_y + 40, "No exercises. Press Coin to record a combo.", COLOR.text_yellow)
        end
        return
    end

    -- Header row
    local header_y = menu_y + 14
    draw_text(menu_x + 20, header_y, "Name",
        menu.sort_mode == "name" and COLOR.text_yellow or COLOR.text_gray)
    draw_text(col_hits, header_y, "Hits",
        COLOR.text_gray)
    draw_text(col_diff, header_y, "Diff",
        menu.sort_mode == "difficulty" and COLOR.text_yellow or COLOR.text_gray)
    draw_text(col_side, header_y, "Side", COLOR.text_gray)

    -- Content rows start below header; one fewer visible row
    local content_rows = visible_rows - 1
    local content_y_start = header_y + row_h

    -- Build display rows: list of {type="header"|"exercise", ...}
    -- Category headers only in category sort mode
    local display_rows = {}
    local last_category = nil
    for i = 1, #ex_list do
        if menu.sort_mode == "category" then
            local ex = exercises[ex_list[i]]
            local cat = ex.category or "combo"
            if cat ~= last_category then
                local label = CATEGORY_LABELS[cat] or cat:upper()
                table.insert(display_rows, { type = "header", label = label })
                last_category = cat
            end
        end
        table.insert(display_rows, { type = "exercise", filtered_idx = i })
    end

    -- Find which display row the current cursor maps to
    local cursor_display_row = 1
    for dr_i, dr in ipairs(display_rows) do
        if dr.type == "exercise" and dr.filtered_idx == cursor then
            cursor_display_row = dr_i
            break
        end
    end

    -- Scrolling: determine start display row based on cursor position
    local start_dr = 1
    if cursor_display_row > content_rows then
        start_dr = cursor_display_row - content_rows + 1
    end

    local drawn = 0
    local cursor_row_y = nil
    for dr_i = start_dr, #display_rows do
        if drawn >= content_rows then break end

        local dr = display_rows[dr_i]
        local row_y = content_y_start + drawn * row_h

        if dr.type == "header" then
            -- Category header: dim yellow, non-selectable
            draw_text(menu_x + 4, row_y, "-- " .. dr.label .. " --", COLOR.text_yellow)
        else
            local i = dr.filtered_idx
            local ex = exercises[ex_list[i]]
            local prog = progression[ex.id]

            if i == cursor then
                cursor_row_y = row_y
                draw_box(menu_x + 2, row_y - 1, menu_w - 4, row_h, 0xFFFFFF40, COLOR.transparent)
                draw_text(menu_x + 4, row_y, ">", COLOR.highlight)
            end

            local status = "  "
            local name_color = COLOR.text_white
            if prog and prog.mastered then
                status = "* "
                name_color = COLOR.text_green
            elseif prog and prog.completions > 0 then
                status = "~ "
                name_color = COLOR.text_yellow
            end

            -- Status + Name
            draw_text(menu_x + 12, row_y, status, name_color)
            draw_text(menu_x + 20, row_y, ex.name, name_color)

            -- Hits
            local hits = #ex.sequence
            draw_text(col_hits + 8, row_y, tostring(hits), COLOR.text_gray)

            -- Difficulty
            draw_text(col_diff + 4, row_y, tostring(ex.difficulty), COLOR.text_orange)

            -- Side
            local side = get_exercise_side(ex.id)
            local side_color = (side == "R") and COLOR.text_cyan or COLOR.text_gray
            draw_text(col_side, row_y, "[" .. side .. "]", side_color)

            -- Progress
            if prog and prog.completions > 0 then
                draw_text(col_prog, row_y,
                    prog.completions .. "/" .. MASTERY_THRESHOLD, COLOR.text_gray)
            end
        end
        drawn = drawn + 1
    end

    -- Description and button hints for selected exercise
    if ex_list[cursor] and exercises[ex_list[cursor]] then
        local desc_y = menu_y + menu_h - 10
        local sel = exercises[ex_list[cursor]]
        if menu.delete_id == sel.id then
            draw_text(menu_x + 4, desc_y, "Press HK again to DELETE this exercise", COLOR.text_red)
        else
            draw_text(menu_x + 4, desc_y, sel.description or sel.name, COLOR.text_gray)
            local hints_x = menu_x + menu_w - 180
            if engine.state ~= STATE_IDLE then
                draw_text(hints_x - 50, desc_y, "MP=Stop", COLOR.text_yellow)
            end
            draw_text(hints_x, desc_y, "HP=Sort", COLOR.text_orange)
            draw_text(hints_x + 40, desc_y, "LK=Side", COLOR.text_cyan)
            draw_text(hints_x + 80, desc_y, "MK=Tag", COLOR.text_yellow)
            draw_text(hints_x + 120, desc_y, "HK=Del", COLOR.text_red)
        end

        -- Character tag popup below cursor row
        if cursor_row_y and sel.characters and #sel.characters > 0
            and menu.delete_id ~= sel.id then
            local popup_y = cursor_row_y + row_h + 1
            local popup_x = menu_x + 4
            local max_chars_per_line = math.floor((menu_w - 12) / 4)
            -- Wrap character names into lines
            local lines = {}
            local line = "vs:"
            for ci, cn in ipairs(sel.characters) do
                local sep = (ci == 1) and " " or ", "
                if #line + #sep + #cn > max_chars_per_line then
                    table.insert(lines, line)
                    line = "    " .. cn
                else
                    line = line .. sep .. cn
                end
            end
            table.insert(lines, line)
            local popup_h = #lines * row_h + 4
            local popup_bottom = popup_y + popup_h
            local menu_bottom = menu_y + menu_h - 12
            if popup_bottom > menu_bottom then
                popup_h = menu_bottom - popup_y
            end
            if popup_h > row_h then
                draw_box(popup_x - 2, popup_y - 1, menu_w - 8, popup_h,
                    0x000000E0, COLOR.text_cyan)
                for li, ln in ipairs(lines) do
                    local ly = popup_y + (li - 1) * row_h
                    if ly + row_h > menu_bottom then break end
                    draw_text(popup_x, ly, ln, COLOR.text_cyan)
                end
            end
        end
    end
end

--- Draw the opponent tab in the menu
local function draw_opponent_tab(menu_x, menu_y, menu_w, row_h, visible_rows, menu_h)
    local opp_name = selected_opponent and selected_opponent.name or "(none)"
    local center_y = menu_y + 30

    draw_text(menu_x + 4, center_y, "Current opponent:", COLOR.text_gray)
    draw_text(menu_x + 80, center_y, opp_name, COLOR.text_yellow)

    draw_text(menu_x + 4, center_y + 20, "Jab = Change opponent", COLOR.text_white)
    draw_text(menu_x + 4, center_y + 32, "Returns to character select screen", COLOR.text_gray)

    draw_text(menu_x + 4, center_y + 56, "Fierce = Re-save current state for " .. opp_name, COLOR.text_white)
end

local function draw_menu()
    if not menu.show then return end

    -- Position below player portraits (y~48) and above super meter (y~200)
    local menu_x = 20
    local menu_y = 50
    local menu_w = SCREEN_W - 40
    local row_h = 12
    local visible_rows = 9
    local menu_h = visible_rows * row_h + 30

    draw_gradient_box(menu_x, menu_y, menu_w, menu_h, COLOR.menu_top, COLOR.menu_bottom, COLOR.border_light)

    -- Tab bar
    local tab_all_color = (menu.mode == MENU_ALL_EXERCISES) and COLOR.text_yellow or COLOR.text_gray
    local char_label = selected_opponent and ("vs " .. selected_opponent.name) or "Character"
    local tab_char_color = (menu.mode == MENU_CHAR_EXERCISES) and COLOR.text_yellow or COLOR.text_gray
    local tab_opp_color = (menu.mode == MENU_OPPONENT) and COLOR.text_yellow or COLOR.text_gray
    local all_label = "[All]"
    local char_label_full = "[" .. char_label .. "]"
    local opp_label = "[Select Opponent]"
    local tab_cw = 4
    local tab_gap = 4
    local x_all = menu_x + 4
    local x_char = x_all + #all_label * tab_cw + tab_gap
    local x_opp = x_char + #char_label_full * tab_cw + tab_gap
    draw_text(x_all, menu_y + 2, all_label, tab_all_color)
    draw_text(x_char, menu_y + 2, char_label_full, tab_char_color)
    draw_text(x_opp, menu_y + 2, opp_label, tab_opp_color)

    if menu.mode == MENU_ALL_EXERCISES then
        draw_exercise_list(menu_x, menu_y, menu_w, row_h, visible_rows, menu_h,
            all_exercises_sorted, menu.cursor_all, true)
    elseif menu.mode == MENU_CHAR_EXERCISES then
        draw_exercise_list(menu_x, menu_y, menu_w, row_h, visible_rows, menu_h,
            filtered_exercises, menu.cursor_char, false)
    else
        draw_opponent_tab(menu_x, menu_y, menu_w, row_h, visible_rows, menu_h)
    end
end

--- Draw debug info
local function draw_debug()
    if not menu.debug then return end
    local gs = game_state
    local y = 34
    draw_text(4, y,      "Phase: " .. gs.phase, COLOR.text_gray)
    draw_text(4, y + 8,  "P1 Action: " .. gs.p1.action_string, COLOR.text_gray)
    draw_text(4, y + 16, "Combo: " .. gs.combo_counter, COLOR.text_gray)
    draw_text(4, y + 24, "Waza: " .. gs.waza_total, COLOR.text_gray)
    draw_text(4, y + 32, "Engine: " .. engine.state, COLOR.text_gray)
    draw_text(4, y + 40, "Step: " .. engine.combo_index, COLOR.text_gray)
    draw_text(4, y + 48, "LastHit: " .. engine.last_hit_waza, COLOR.text_gray)
    draw_text(4, y + 56, "P1 X: " .. string.format("0x%04x", gs.p1.x_pos), COLOR.text_gray)
    draw_text(4, y + 64, "P2 X: " .. string.format("0x%04x", gs.p2.x_pos), COLOR.text_gray)
    draw_text(4, y + 72, "Meter: " .. gs.meter_bars .. " bars + " .. gs.meter_gauge, COLOR.text_gray)
end

-- ============================================================================
-- [11b] EXERCISE CAPTURE TOOL
-- ============================================================================

-- Forward declarations (defined later, called from capture_stop below)
local build_exercise_from_capture
local save_exercises

capture = {
    active = false,
    log = {},          -- array of frame data
    start_frame = 0,
    start_p1_x = 0,
    start_p2_x = 0,
    hit_count = 0,
    sequence = {},     -- built sequence entries
    input_log = {},    -- per-frame joypad snapshots indexed by frame offset
    setup_snapshot = nil,  -- positions, flip, meter, charges, corner at recording start
}

-- Result banner for exercise creation feedback
local capture_result = nil       -- string message to display
local capture_result_timer = 0   -- countdown frames

local function capture_start()
    capture.active = true
    capture.log = {}
    capture.sequence = {}
    capture.input_log = {}
    capture.start_frame = game_state.frame_count
    capture.start_p1_x = game_state.p1.x_pos
    capture.start_p2_x = game_state.p2.x_pos
    capture.hit_count = 0

    -- Snapshot current setup state
    capture.setup_snapshot = {
        p1_x = game_state.p1.x_pos,
        p2_x = game_state.p2.x_pos,
        p1_flip = game_state.p1.flip,
        meter_bars = game_state.meter_bars,
        meter_gauge = game_state.meter_gauge,
        corner = is_near_corner(game_state.p2.x_pos),
    }

    -- Pause any active exercise
    if engine.state == STATE_ACTIVE or engine.state == STATE_SETUP then
        engine.state = STATE_IDLE
    end

    print("[Capture] Recording started")
end

local function capture_stop()
    capture.active = false
    print("[Capture] Recording stopped -- " .. capture.hit_count .. " hits over " ..
        (game_state.frame_count - capture.start_frame) .. " frames")

    -- Build output (legacy raw capture format)
    local out = {}
    table.insert(out, string.format("-- Captured: %s, %d hits over %d frames",
        os.date("%Y-%m-%d"),
        capture.hit_count,
        game_state.frame_count - capture.start_frame))
    table.insert(out, "{")
    table.insert(out, "    sequence = {")
    for _, entry in ipairs(capture.sequence) do
        local ids_str = '"' .. entry.action_id .. '"'
        table.insert(out, string.format('        { name = "%s", hit_type = "%s", action_ids = {%s} },  -- frame %d',
            entry.action_id, entry.hit_type, ids_str, entry.frame))
    end
    table.insert(out, "    },")
    table.insert(out, string.format("    setup = { p1_x = 0x%04X, p2_x = 0x%04X },",
        capture.start_p1_x, capture.start_p2_x))
    table.insert(out, string.format("    success = { min_combo = %d },", capture.hit_count))
    table.insert(out, "}")

    local output_text = table.concat(out, "\n")
    print(output_text)

    -- Also save raw capture to file
    local f = io.open(CAPTURE_FILE, "a")
    if f then
        f:write(output_text .. "\n\n")
        f:close()
    end

    -- Build a playable exercise from the capture
    local new_exercise = build_exercise_from_capture()
    if new_exercise then
        table.insert(exercises, new_exercise)
        init_progression()
        rebuild_filtered_exercises()
        -- Open category selector instead of saving immediately
        cat_sel.active = true
        cat_sel.cursor = 1
        cat_sel.exercise = new_exercise
        print("[Capture] Created exercise: " .. new_exercise.id .. " - " .. new_exercise.name)
    else
        capture_result = nil
        capture_result_timer = 0
    end
end

local function capture_toggle()
    if capture.active then
        capture_stop()
    else
        capture_start()
    end
end

local function capture_frame_update()
    if not capture.active then return end
    if not game_state.playing then return end

    local gs = game_state
    local frame_num = gs.frame_count - capture.start_frame

    -- Record this frame's joypad state for input notation detection
    capture.input_log[frame_num] = joypad.get() or {}

    -- Detect normal/special hits
    local new_hit = false
    if gs.combo_counter > gs.combo_counter_prev and gs.combo_counter > 0 then
        new_hit = true
    elseif gs.waza_total ~= gs.waza_total_prev and gs.waza_total > 0 then
        new_hit = true
    end

    if new_hit then
        local action_id = gs.p1.action_string
        local hit_type = "H"
        -- Aegis activation shares action_id with Sphere_throw; remap when meter was consumed
        if res.meter_consumed and SPHERE_TO_AEGIS[action_id] then
            action_id = SPHERE_TO_AEGIS[action_id]
            hit_type = "F"
        end
        capture.hit_count = capture.hit_count + 1
        table.insert(capture.sequence, {
            action_id = action_id,
            hit_type = hit_type,
            frame = frame_num,
        })
    end

    -- Detect projectile hits
    local list = 3
    local obj_index = read_word_signed(MEM.obj_list_base + (list * 2))
    local count = 0
    while count < MAX_GAME_OBJECTS and obj_index ~= -1 do
        local obj_addr = MEM.obj_data_base + (obj_index * MEM.obj_stride)
        local tobi_id = read_mem(obj_addr + 0x04, 2)
        local p_hb_addr = memory.readdword(obj_addr + 0x2A0)
        local tobi_player = memory.readbyte(obj_addr + 0x3BF)

        if tobi_player == 0 and p_hb_addr ~= 0 then
            local hit_flg = memory.readbyte(obj_addr + 0x189)
            local hit_flg_prev = memory.readbyte(obj_addr + 0x189 + 0x04)
            if hit_flg ~= hit_flg_prev then
                local proj_string = "F" .. string.format("%04x", tobi_id)
                if memory.readbyte(obj_addr + 0x189 + 0x06) == 0 then
                    capture.hit_count = capture.hit_count + 1
                    table.insert(capture.sequence, {
                        action_id = proj_string,
                        hit_type = "F",
                        frame = frame_num,
                    })
                    memory.writebyte(obj_addr + 0x189 + 0x06, 1)
                end
                memory.writebyte(obj_addr + 0x189 + 0x04, hit_flg)
            end
        end

        obj_index = read_word_signed(obj_addr + 0x1C)
        count = count + 1
    end
end

-- ============================================================================
-- [11c2] INPUT NOTATION DETECTOR
-- ============================================================================
-- Converts raw joypad input logs into human-readable move notation.
-- Used by the record-to-exercise system as a fallback when MOVES lookup fails.
do -- scope 11c2+11c3 helpers to free main-chunk local slots

--- Convert directional booleans to numpad value (1-9)
--- flip: 0 = facing right (right=forward), 1 = facing left (left=forward)
local function dirs_to_numpad(up, down, left, right, flip)
    -- Raw physical directions to numpad (no flip adjustment)
    local raw
    if up and left then raw = 7
    elseif up and right then raw = 9
    elseif down and left then raw = 1
    elseif down and right then raw = 3
    elseif up then raw = 8
    elseif down then raw = 2
    elseif left then raw = 4
    elseif right then raw = 6
    else raw = 5
    end

    -- If facing left (flip=1), mirror horizontal: 4<->6, 1<->3, 7<->9
    if flip == 1 then
        local mirror = { [4]=6, [6]=4, [1]=3, [3]=1, [7]=9, [9]=7 }
        raw = mirror[raw] or raw
    end
    return raw
end

--- Search for an ordered sequence of numpad values in direction history
local function find_sequence(dir_history, pattern)
    local pi = 1
    for i = 1, #dir_history do
        if dir_history[i] == pattern[pi] then
            pi = pi + 1
            if pi > #pattern then return true end
        end
    end
    return false
end

--- Detect a charge pattern: sustained hold of charge_dirs for min_frames, then release_dir
local function find_charge_pattern(dir_history, charge_dirs, release_dir, min_frames)
    local charge_count = 0
    local found_charge = false
    for i = 1, #dir_history do
        local d = dir_history[i]
        local is_charge = false
        for _, cd in ipairs(charge_dirs) do
            if d == cd then is_charge = true; break end
        end
        if is_charge then
            charge_count = charge_count + 1
            if charge_count >= min_frames then
                found_charge = true
            end
        else
            if found_charge and d == release_dir then
                return true
            end
            -- Reset if not a charge direction and we haven't released yet
            if not is_charge then
                charge_count = 0
                found_charge = false
            end
        end
    end
    return false
end

--- Detect a dash pattern: tap→release→tap of the same direction within a window
--- dir_history: array of numpad directions, tap_dir: 6 (forward) or 4 (back)
--- Returns true if a dash pattern is found
local function find_dash_pattern(dir_history, tap_dir, max_gap)
    max_gap = max_gap or 12
    -- Scan backward: find last tap, then release, then earlier tap
    local second_tap = nil
    for i = #dir_history, 1, -1 do
        if dir_history[i] == tap_dir then
            second_tap = i
            break
        end
    end
    if not second_tap then return false end

    -- Find release (not tap_dir) before the second tap
    local release = nil
    for i = second_tap - 1, math.max(1, second_tap - max_gap), -1 do
        if dir_history[i] ~= tap_dir then
            release = i
            break
        end
    end
    if not release then return false end

    -- Find first tap before the release
    for i = release - 1, math.max(1, second_tap - max_gap), -1 do
        if dir_history[i] == tap_dir then
            return true
        end
    end
    return false
end

--- Detect the motion component of a move from input history
--- input_log: table indexed by frame number -> joypad snapshot
--- button_frame: frame number when button was pressed
--- p1_flip: 0=facing right, 1=facing left
--- Returns sf_motion, numpad_motion (e.g. "qcf+", "236")
local function detect_motion(input_log, button_frame, p1_flip)
    -- Build numpad direction history from ~30 frames before button press
    local dir_history = {}
    local lookback = 30
    local start_frame = button_frame - lookback
    if start_frame < 0 then start_frame = 0 end

    for f = start_frame, button_frame do
        local inp = input_log[f]
        if inp then
            local np = dirs_to_numpad(
                inp["P1 Up"], inp["P1 Down"],
                inp["P1 Left"], inp["P1 Right"],
                p1_flip
            )
            table.insert(dir_history, np)
        end
    end

    if #dir_history == 0 then return "", "5" end

    -- Pattern match in priority order
    -- Charge moves checked first: down-back→forward passes through 2→3→6,
    -- so QCF would false-match on tackle/headbutt inputs if checked first
    -- 1. Charge back→forward (tackle)
    if find_charge_pattern(dir_history, {4, 1}, 6, 10) then
        return "b~f+", "[4]6"
    end
    -- 2. Charge down→up (headbutt)
    if find_charge_pattern(dir_history, {2, 1}, 8, 10) then
        return "d~u+", "[2]8"
    end
    -- 3. Forward dash: f→neutral→f
    if find_dash_pattern(dir_history, 6, 12) then
        return "f,f+", "66"
    end
    -- 4. Back dash: b→neutral→b
    if find_dash_pattern(dir_history, 4, 12) then
        return "b,b+", "44"
    end
    -- 5. QCF: 2→3→6
    if find_sequence(dir_history, {2, 3, 6}) then
        return "qcf+", "236"
    end
    -- 6. QCB: 2→1→4
    if find_sequence(dir_history, {2, 1, 4}) then
        return "qcb+", "214"
    end
    -- 7. Crouching: last direction is 1, 2, or 3
    local last_dir = dir_history[#dir_history]
    if last_dir == 2 or last_dir == 1 or last_dir == 3 then
        return "d+", "2"
    end
    -- 8. Jump: 7, 8, or 9 in recent history
    for i = math.max(1, #dir_history - 10), #dir_history do
        local d = dir_history[i]
        if d == 7 or d == 8 or d == 9 then
            return "j.", "j."
        end
    end
    -- 9. Standing (default)
    return "", "5"
end

--- Detect which button was pressed near a hit frame
--- input_log: table indexed by frame number -> joypad snapshot
--- hit_frame: frame number when hit was detected
--- Returns button string ("LP", "HP", "KK", etc.) and the frame it was found
local function detect_button(input_log, hit_frame)
    local button_map = {
        { key = "P1 Weak Punch",   name = "LP" },
        { key = "P1 Medium Punch", name = "MP" },
        { key = "P1 Strong Punch", name = "HP" },
        { key = "P1 Weak Kick",    name = "LK" },
        { key = "P1 Medium Kick",  name = "MK" },
        { key = "P1 Strong Kick",  name = "HK" },
    }

    -- Scan ±5 frames around hit for button press edges
    local best_btn = nil
    local best_frame = nil
    local best_dist = 999
    local simultaneous = {}

    for offset = -5, 5 do
        local f = hit_frame + offset
        local curr = input_log[f]
        local prev = input_log[f - 1]
        if curr and prev then
            for _, btn in ipairs(button_map) do
                if curr[btn.key] and not prev[btn.key] then
                    local dist = math.abs(offset)
                    if dist < best_dist then
                        best_dist = dist
                        best_btn = btn.name
                        best_frame = f
                        simultaneous = { btn.name }
                    elseif dist == best_dist then
                        table.insert(simultaneous, btn.name)
                    end
                end
            end
        end
    end

    -- Detect simultaneous presses (PP/KK)
    if #simultaneous >= 2 then
        local punches = 0
        local kicks = 0
        for _, name in ipairs(simultaneous) do
            if name == "LP" or name == "MP" or name == "HP" then punches = punches + 1 end
            if name == "LK" or name == "MK" or name == "HK" then kicks = kicks + 1 end
        end
        if punches >= 2 then return "PP", best_frame end
        if kicks >= 2 then return "KK", best_frame end
    end

    if best_btn then return best_btn, best_frame end

    -- Fallback: check which button is held at the hit frame
    local curr = input_log[hit_frame]
    if curr then
        for _, btn in ipairs(button_map) do
            if curr[btn.key] then
                return btn.name, hit_frame
            end
        end
    end

    return "?", hit_frame
end

--- Combine motion + button into full notation strings
--- Returns sf_str, numpad_str (e.g. "d+HP", "2HP" or "qcf+LP", "236LP")
local function build_notation(motion_sf, motion_numpad, button)
    local sf_str = motion_sf .. button
    local numpad_str
    if motion_numpad == "5" then
        numpad_str = "5" .. button
    else
        numpad_str = motion_numpad .. button
    end
    return sf_str, numpad_str
end

-- ============================================================================
-- [11c3] EXERCISE BUILDER (Record-to-Exercise)
-- ============================================================================
-- Converts a captured combo recording into a complete, playable exercise definition.

--- Build a complete exercise table from capture data
--- Returns an exercise table or nil if capture is invalid
build_exercise_from_capture = function()
    -- Check if any attack button was newly pressed between two frames
    -- Used to distinguish multi-hit moves (one input) from same-move links (two inputs)
    local function has_new_button_press(input_log, from_frame, to_frame)
        local buttons = {
            "P1 Weak Punch", "P1 Medium Punch", "P1 Strong Punch",
            "P1 Weak Kick", "P1 Medium Kick", "P1 Strong Kick",
        }
        for f = from_frame, to_frame do
            local curr = input_log[f]
            local prev = input_log[f - 1]
            if curr and prev then
                for _, key in ipairs(buttons) do
                    if curr[key] and not prev[key] then
                        return true
                    end
                end
            end
        end
        return false
    end
    if #capture.sequence == 0 then
        print("[Capture] No hits recorded -- no exercise created")
        return nil
    end

    exercise_counter = exercise_counter + 1
    local exercise_id = string.format("c_%02d", exercise_counter)

    local sequence = {}
    local notations_sf = {}
    local notations_np = {}
    local move_names = {}
    local final_frames = {}  -- frame timestamps for surviving entries (for ref_timing)
    local has_h_charge = false
    local has_v_charge = false
    local has_combo_reset = false
    local last_frame = 0

    local prev_action_id = nil  -- for collapsing multi-hit moves
    local prev_hit_frame = 0   -- frame of previous hit

    for _, entry in ipairs(capture.sequence) do
        -- Collapse multi-hit moves (same action, no new button press = one input, multiple hits)
        -- But keep same-move links (same action with a new button press = re-input)
        local same_action = (entry.action_id == prev_action_id)
        local is_multi_hit = same_action and not has_new_button_press(capture.input_log, prev_hit_frame + 1, entry.frame)
        prev_hit_frame = entry.frame

        if not is_multi_hit then
            -- Skip non-attack entries (N=neutral, M=misc, G=guard, T=throw)
            -- These appear during combo counter resets in multi-combo Aegis setups
            local entry_prefix = entry.action_id:sub(1, 1)
            if entry_prefix == "N" or entry_prefix == "M" or entry_prefix == "G" or entry_prefix == "T" then
                has_combo_reset = true
            else
                prev_action_id = entry.action_id

                -- Try MOVES lookup first (authoritative source of truth)
                local move_name, sf, numpad, move_type = lookup_move_name(entry.action_id)

                if move_name then
                    -- Known move: use database notation
                    table.insert(sequence, {
                        name = move_name,
                        hit_type = entry.hit_type,
                        action_ids = { entry.action_id },
                    })
                    table.insert(final_frames, entry.frame)
                    table.insert(notations_sf, sf)
                    table.insert(notations_np, numpad)
                    table.insert(move_names, move_name)

                    -- Infer charge from notation
                    if sf:find("b~f") or numpad:find("%[4%]6") then has_h_charge = true end
                    if sf:find("d~u") or numpad:find("%[2%]8") then has_v_charge = true end
                elseif entry.hit_type == "H" then
                    -- Unknown H-type hit: detect from input log
                    local button, btn_frame = detect_button(capture.input_log, entry.frame, nil)
                    btn_frame = btn_frame or entry.frame
                    local p1_flip = capture.setup_snapshot and capture.setup_snapshot.p1_flip or 0
                    local motion_sf, motion_np = detect_motion(capture.input_log, btn_frame, p1_flip)
                    local sf_str, np_str = build_notation(motion_sf, motion_np, button)

                    -- Infer charge from detected motion
                    if motion_sf == "b~f+" then has_h_charge = true end
                    if motion_sf == "d~u+" then has_v_charge = true end

                    local display_name = sf_str
                    table.insert(sequence, {
                        name = display_name,
                        hit_type = "H",
                        action_ids = { entry.action_id },
                    })
                    table.insert(final_frames, entry.frame)
                    table.insert(notations_sf, sf_str)
                    table.insert(notations_np, np_str)
                    table.insert(move_names, display_name)
                else
                    -- Unknown F-type (projectile): use raw action_id
                    local display_name = entry.action_id
                    table.insert(sequence, {
                        name = display_name,
                        hit_type = "F",
                        action_ids = { entry.action_id },
                    })
                    table.insert(final_frames, entry.frame)
                    table.insert(notations_sf, display_name)
                    table.insert(notations_np, display_name)
                    table.insert(move_names, display_name)
                end

                last_frame = entry.frame
            end
        end
    end

    if #sequence == 0 then
        print("[Capture] All hits collapsed (multi-hit move) -- no exercise created")
        return nil
    end

    -- Build exercise name (truncate to 40 chars)
    local full_name = table.concat(move_names, " > ")
    if #full_name > 40 then
        full_name = full_name:sub(1, 37) .. "..."
    end

    -- Build notation strings
    local notation_sf_str = table.concat(notations_sf, ", ")
    local notation_np_str = table.concat(notations_np, ", ")

    -- Build hints from notation
    local hint_str = table.concat(notations_sf, " -> ")

    -- Setup from snapshot
    local snap = capture.setup_snapshot or {}
    local setup = {
        p1_x = snap.p1_x or 0x0100,
        p2_x = snap.p2_x or 0x0180,
        p1_life = 0xA0,
        p2_life = 0xA0,
        meter = "full",
        fill_h_charge = has_h_charge,
        fill_v_charge = has_v_charge,
        p2_state = "stand",
        corner = snap.corner or false,
    }

    -- Difficulty: clamped sequence length
    local difficulty = clamp(#sequence, 1, 5)

    local new_exercise = {
        id = exercise_id,
        name = full_name,
        notation = notation_sf_str,
        numpad = notation_np_str,
        difficulty = difficulty,
        category = "combo",
        setup = setup,
        sequence = sequence,
        success = { min_combo = #sequence },
        fail = {},
        hints = { hint_str },
    }

    -- Auto-set allow_combo_reset for multi-combo sequences (e.g. Aegis setups)
    if has_combo_reset then
        new_exercise.allow_combo_reset = true
    end

    -- Auto-populate reference timing from captured frame data
    if #final_frames >= 2 then
        local ref_timing = {0}
        for i = 2, #final_frames do
            ref_timing[i] = final_frames[i] - final_frames[i - 1]
        end
        new_exercise.ref_timing = ref_timing
    end

    -- Auto-tag with current opponent
    if selected_opponent then
        new_exercise.characters = { selected_opponent.name }
    end

    return new_exercise
end

end -- scope 11c2+11c3

-- ============================================================================
-- [11c4] EXERCISE PERSISTENCE
-- ============================================================================

--- Write a single exercise to an open file handle
local function write_exercise(f, exercise)
    f:write("---\n")
    f:write("ID:" .. exercise.id .. "\n")
    f:write("NAME:" .. exercise.name .. "\n")
    f:write("NOTATION_SF:" .. (exercise.notation or "") .. "\n")
    f:write("NOTATION_NP:" .. (exercise.numpad or "") .. "\n")
    f:write("DIFFICULTY:" .. (exercise.difficulty or 1) .. "\n")
    f:write("CATEGORY:" .. (exercise.category or "combo") .. "\n")
    -- Character tags (optional)
    if exercise.characters and #exercise.characters > 0 then
        f:write("CHARS:" .. table.concat(exercise.characters, ",") .. "\n")
    end

    -- Setup: p1_x,p2_x,p1_life,p2_life,meter,h_charge,v_charge,p2_state,corner
    local s = exercise.setup
    f:write(string.format("SETUP:%04X,%04X,%02X,%02X,%s,%d,%d,%s,%d\n",
        s.p1_x, s.p2_x, s.p1_life, s.p2_life,
        s.meter or "full",
        s.fill_h_charge and 1 or 0,
        s.fill_v_charge and 1 or 0,
        s.p2_state or "stand",
        s.corner and 1 or 0))

    -- Sequence: name,hit_type,action_id1;action_id2|name,hit_type,...
    local seq_parts = {}
    for _, step in ipairs(exercise.sequence) do
        local ids = table.concat(step.action_ids, ";")
        table.insert(seq_parts, step.name .. "," .. step.hit_type .. "," .. ids)
    end
    f:write("SEQ:" .. table.concat(seq_parts, "|") .. "\n")

    f:write("SUCCESS:" .. (exercise.success.min_combo or #exercise.sequence) .. "\n")
    -- Timeout (if set)
    if exercise.fail and exercise.fail.timeout_frames then
        f:write("TIMEOUT:" .. exercise.fail.timeout_frames .. "\n")
    end
    -- Multi-combo reset flag (Aegis setups)
    if exercise.allow_combo_reset then
        f:write("RESETOK:1\n")
    end
    -- Reference timing (frame gaps between steps)
    if exercise.ref_timing and #exercise.ref_timing > 0 then
        local timing_parts = {}
        for _, t in ipairs(exercise.ref_timing) do
            table.insert(timing_parts, tostring(t))
        end
        f:write("TIMING:" .. table.concat(timing_parts, ",") .. "\n")
    end
    -- Hints
    if exercise.hints and #exercise.hints > 0 then
        f:write("HINT:" .. exercise.hints[1] .. "\n")
    end

    f:write("---\n")
end

--- Save custom (non-shipped) exercises to the custom file
save_exercises = function()
    local f = io.open(CUSTOM_EXERCISE_FILE, "w")
    if not f then
        print("[Urien Lab] Could not write custom exercises file")
        return
    end

    f:write("# Urien Lab Custom Exercises\n")
    f:write("# Your captured and custom exercises (not overwritten by updates)\n")
    f:write("# CATEGORY: combo | unblockable | sequence | parry\n")

    for _, exercise in ipairs(exercises) do
        if not exercise.shipped then
            write_exercise(f, exercise)
        end
    end

    f:close()
end

--- Load exercises from a single file, marking each with shipped flag
local function load_exercises_from_file(path, shipped_flag)
    local f = io.open(path, "r")
    if not f then return 0 end

    local current = nil
    local count = 0
    local max_counter = 0

    for line in f:lines() do
        if line == "---" then
            if current then
                -- Finalize and add exercise
                if current.id and current.sequence and #current.sequence > 0 then
                    if not current.category then
                        current.category = "combo"  -- default category
                    end
                    current.shipped = shipped_flag
                    table.insert(exercises, current)
                    count = count + 1

                    -- Track max counter for ID generation
                    local num = tonumber(current.id:match("c_(%d+)"))
                    if num and num > max_counter then
                        max_counter = num
                    end
                end
            end
            current = nil
        else
            if not current then current = {} end

            local key, value = line:match("^(.-):(.*)")
            if key and value then
                if key == "ID" then
                    current.id = value
                elseif key == "NAME" then
                    current.name = value
                elseif key == "NOTATION_SF" then
                    current.notation = value
                elseif key == "NOTATION_NP" then
                    current.numpad = value
                elseif key == "DIFFICULTY" then
                    current.difficulty = tonumber(value) or 1
                elseif key == "CATEGORY" then
                    current.category = value
                elseif key == "CHARS" then
                    current.characters = {}
                    for char_name in value:gmatch("[^,]+") do
                        local trimmed = char_name:match("^%s*(.-)%s*$")
                        if trimmed and trimmed ~= "" then
                            table.insert(current.characters, trimmed)
                        end
                    end
                elseif key == "SETUP" then
                    local p1x, p2x, p1l, p2l, meter, hc, vc, p2s, corner =
                        value:match("^(%x+),(%x+),(%x+),(%x+),(%w+),(%d+),(%d+),(%w+),(%d+)")
                    if p1x then
                        current.setup = {
                            p1_x = tonumber(p1x, 16),
                            p2_x = tonumber(p2x, 16),
                            p1_life = tonumber(p1l, 16),
                            p2_life = tonumber(p2l, 16),
                            meter = meter,
                            fill_h_charge = (hc == "1"),
                            fill_v_charge = (vc == "1"),
                            p2_state = p2s,
                            corner = (corner == "1"),
                        }
                    end
                elseif key == "SEQ" then
                    current.sequence = {}
                    for part in value:gmatch("[^|]+") do
                        local name, hit_type, ids_str = part:match("^(.-),(.-),(.*)")
                        if name then
                            local action_ids = {}
                            for aid in ids_str:gmatch("[^;]+") do
                                table.insert(action_ids, normalize_action_string(aid))
                            end
                            table.insert(current.sequence, {
                                name = name,
                                hit_type = hit_type,
                                action_ids = action_ids,
                            })
                        end
                    end
                elseif key == "SUCCESS" then
                    current.success = { min_combo = tonumber(value) or 1 }
                elseif key == "TIMEOUT" then
                    current.fail = { timeout_frames = tonumber(value) or 600 }
                elseif key == "RESETOK" then
                    current.allow_combo_reset = (value == "1")
                elseif key == "TIMING" then
                    current.ref_timing = {}
                    for num_str in value:gmatch("[^,]+") do
                        table.insert(current.ref_timing, tonumber(num_str) or 0)
                    end
                elseif key == "HINT" then
                    current.hints = { value }
                end
            end
        end
    end

    f:close()

    -- Update exercise_counter from max c_ ID seen
    if max_counter > exercise_counter then
        exercise_counter = max_counter
    end

    return count
end

--- Load exercises from both shipped and custom files
local function load_exercises()
    local shipped_count = load_exercises_from_file(EXERCISE_FILE, true)
    local custom_count = load_exercises_from_file(CUSTOM_EXERCISE_FILE, false)
    local total = shipped_count + custom_count
    if total > 0 then
        print("[Urien Lab] Loaded " .. total .. " exercises (" .. shipped_count .. " shipped, " .. custom_count .. " custom)")
    end
end

--- Reload exercises from file (after user edits names, etc.)
local function reload_exercises()
    -- Clear all exercises
    exercises = {}
    exercise_counter = 0
    -- Re-read from both files
    load_exercises()
    -- Sync progression with updated exercise list
    init_progression()
    rebuild_filtered_exercises()
    print("[Urien Lab] Reloaded " .. #exercises .. " exercises")
end

-- ============================================================================
-- [12] MAIN LOOP CALLBACKS
-- ============================================================================

-- Input state tracking: read joypad ONCE per frame to avoid inconsistency
-- (input_current and input_prev are forward-declared in [6])

local function read_input()
    input_prev = input_current
    input_current = joypad.get() or {}
end

local function is_pressed(btn)
    return input_current[btn] and not input_prev[btn]
end

local function is_held(btn)
    return input_current[btn]
end

local function check_konami()
    local expected = konami.sequence[konami.index]
    if is_pressed(expected) then
        konami.index = konami.index + 1
        if konami.index > #konami.sequence then
            konami.active = not konami.active
            konami.flash_timer = 180
            konami.index = 1
        end
    else
        -- Any other button press resets the sequence
        for _, btn in ipairs(konami.sequence) do
            if is_pressed(btn) and btn ~= expected then
                konami.index = 1
                break
            end
        end
    end
end

--- Handle character select input (app-level)
local function handle_charselect_input()
    -- Start: hide overlay and enter training mode (if a match is loaded)
    if is_pressed("P1 Start") then
        if charselect_visible then
            charselect_visible = false
            if game_state.playing then
                app_state = APP_TRAINING
                engine.state = STATE_IDLE
            end
        else
            charselect_visible = true
        end
        return
    end

    -- Only process grid input when overlay is visible
    if not charselect_visible then return end

    -- Grid navigation
    if is_pressed("P1 Up") then
        char_cursor = char_cursor - CHAR_GRID_COLS
        if char_cursor < 1 then
            char_cursor = char_cursor + #CHARACTERS
        end
    elseif is_pressed("P1 Down") then
        char_cursor = char_cursor + CHAR_GRID_COLS
        if char_cursor > #CHARACTERS then
            char_cursor = char_cursor - #CHARACTERS
        end
    elseif is_pressed("P1 Left") then
        char_cursor = char_cursor - 1
        if char_cursor < 1 then char_cursor = #CHARACTERS end
    elseif is_pressed("P1 Right") then
        char_cursor = char_cursor + 1
        if char_cursor > #CHARACTERS then char_cursor = 1 end
    elseif is_pressed("P1 Weak Punch") then
        -- Load character state
        if load_char_state(char_cursor) then
            app_state = APP_TRAINING
            engine.state = STATE_IDLE
        end
    elseif is_pressed("P1 Strong Punch") then
        -- Save current game state for this character
        if game_state.playing then
            save_char_state(char_cursor)
        else
            print("[Urien Lab] Cannot save -- game phase is " .. game_state.phase .. " (need 2 = playing)")
            print("[Urien Lab] Start a match as Urien vs your opponent first, then save once the round begins")
        end
    end
end

--- Handle category selector input after exercise capture
local function handle_category_selector_input()
    if not cat_sel.active then return end
    local num_cats = #EXERCISE_CATEGORIES

    if is_pressed("P1 Up") then
        cat_sel.cursor = cat_sel.cursor - 1
        if cat_sel.cursor < 1 then cat_sel.cursor = num_cats end
    elseif is_pressed("P1 Down") then
        cat_sel.cursor = cat_sel.cursor + 1
        if cat_sel.cursor > num_cats then cat_sel.cursor = 1 end
    elseif is_pressed("P1 Weak Punch") then
        -- Confirm: apply selected category
        cat_sel.exercise.category = EXERCISE_CATEGORIES[cat_sel.cursor]
        save_exercises()
        save_progression()
        capture_result = "EXERCISE CREATED: " .. cat_sel.exercise.name
        capture_result_timer = 180
        cat_sel.active = false
        cat_sel.exercise = nil
        rebuild_filtered_exercises()
    elseif is_pressed("P1 Start") or is_pressed("P1 Coin") then
        -- Cancel: keep default "combo", save and close
        save_exercises()
        save_progression()
        capture_result = "EXERCISE CREATED: " .. cat_sel.exercise.name
        capture_result_timer = 180
        cat_sel.active = false
        cat_sel.exercise = nil
    end
end

--- Handle menu navigation input
local function handle_menu_input()
    if not menu.show then return end

    -- Tab switching: Left/Right cycles All → Character → Opponent → All
    if is_pressed("P1 Right") then
        if menu.mode == MENU_ALL_EXERCISES then menu.mode = MENU_CHAR_EXERCISES
        elseif menu.mode == MENU_CHAR_EXERCISES then menu.mode = MENU_OPPONENT
        else menu.mode = MENU_ALL_EXERCISES end
        menu.delete_id = nil
        return
    elseif is_pressed("P1 Left") then
        if menu.mode == MENU_ALL_EXERCISES then menu.mode = MENU_OPPONENT
        elseif menu.mode == MENU_OPPONENT then menu.mode = MENU_CHAR_EXERCISES
        else menu.mode = MENU_ALL_EXERCISES end
        menu.delete_id = nil
        return
    end

    if menu.mode == MENU_ALL_EXERCISES or menu.mode == MENU_CHAR_EXERCISES then
        -- Determine active list and cursor based on tab
        local ex_list, cur
        if menu.mode == MENU_ALL_EXERCISES then
            ex_list = all_exercises_sorted
            cur = menu.cursor_all
        else
            ex_list = filtered_exercises
            cur = menu.cursor_char
        end

        -- Exercise menu navigation
        if is_pressed("P1 Up") then
            if #ex_list > 0 then
                cur = cur - 1
                if cur < 1 then cur = #ex_list end
            end
            menu.delete_id = nil
        elseif is_pressed("P1 Down") then
            if #ex_list > 0 then
                cur = cur + 1
                if cur > #ex_list then cur = 1 end
            end
            menu.delete_id = nil
        elseif is_pressed("P1 Weak Punch") then
            menu.delete_id = nil
            if ex_list[cur] then
                select_exercise(ex_list[cur])
                menu.show = false
            end
        elseif is_pressed("P1 Medium Punch") then
            menu.delete_id = nil
            if engine.state ~= STATE_IDLE then
                engine.state = STATE_IDLE
                engine.current_exercise = nil
            else
                menu.show = false
            end
        elseif is_pressed("P1 Strong Kick") then
            -- Delete exercise (requires double-press to confirm)
            local real_idx = ex_list[cur]
            local sel = real_idx and exercises[real_idx]
            if sel then
                if sel.shipped then
                    print("[Urien Lab] Shipped exercises can't be deleted")
                    menu.delete_id = nil
                elseif menu.delete_id == sel.id then
                    table.remove(exercises, real_idx)
                    progression[sel.id] = nil
                    rebuild_filtered_exercises()
                    save_exercises()
                    save_progression()
                    menu.delete_id = nil
                    print("[Urien Lab] Deleted exercise: " .. sel.name)
                else
                    menu.delete_id = sel.id
                end
            end
        elseif is_pressed("P1 Strong Punch") then
            -- Cycle sort mode: category → difficulty → name → category
            menu.delete_id = nil
            local saved_ex_idx = ex_list[cur]  -- remember which exercise is selected
            for si, sm in ipairs(SORT_MODES) do
                if sm == menu.sort_mode then
                    menu.sort_mode = SORT_MODES[(si % #SORT_MODES) + 1]
                    break
                end
            end
            rebuild_filtered_exercises()
            -- Restore cursor to same exercise in new sort order
            if saved_ex_idx then
                local new_list = (menu.mode == MENU_ALL_EXERCISES) and all_exercises_sorted or filtered_exercises
                for ni, idx in ipairs(new_list) do
                    if idx == saved_ex_idx then
                        cur = ni
                        break
                    end
                end
            end
        elseif is_pressed("P1 Weak Kick") then
            -- Toggle side (L/R) for highlighted exercise
            local real_idx = ex_list[cur]
            if real_idx and exercises[real_idx] then
                toggle_exercise_side(exercises[real_idx].id)
                save_progression()
            end
        elseif is_pressed("P1 Medium Kick") then
            -- Toggle current opponent tag on highlighted exercise
            local real_idx = ex_list[cur]
            local sel = real_idx and exercises[real_idx]
            if sel and selected_opponent then
                local opp = selected_opponent.name
                if not sel.characters then sel.characters = {} end
                local found = false
                for j, char_name in ipairs(sel.characters) do
                    if char_name == opp then
                        table.remove(sel.characters, j)
                        found = true
                        print("[Urien Lab] Untagged " .. opp .. " from " .. sel.name)
                        break
                    end
                end
                if not found then
                    table.insert(sel.characters, opp)
                    print("[Urien Lab] Tagged " .. sel.name .. " for " .. opp)
                end
                if sel.shipped then
                    print("[Urien Lab] Tag change is session-only for shipped exercises")
                else
                    save_exercises()
                end
                rebuild_filtered_exercises()
            end
        end

        -- Write cursor back to the correct variable
        if menu.mode == MENU_ALL_EXERCISES then
            menu.cursor_all = cur
        else
            menu.cursor_char = cur
        end
    else
        -- Opponent tab
        if is_pressed("P1 Weak Punch") then
            app_state = APP_CHARSELECT
            charselect_visible = true
            engine.state = STATE_IDLE
            engine.current_exercise = nil
            menu.show = false
        elseif is_pressed("P1 Strong Punch") then
            if selected_opponent and game_state.playing then
                for i, char in ipairs(CHARACTERS) do
                    if char.id == selected_opponent.id then
                        save_char_state(i)
                        break
                    end
                end
            end
        elseif is_pressed("P1 Medium Punch") then
            if engine.state ~= STATE_IDLE then
                engine.state = STATE_IDLE
                engine.current_exercise = nil
            else
                menu.show = false
            end
        end
    end
end

--- Handle general input
local function handle_input()
    -- Category selector blocks all other input while active
    if cat_sel.active then
        handle_category_selector_input()
        return
    end

    -- Start button toggles menu
    if is_pressed("P1 Start") then
        if menu.show then
            menu.show = false
        else
            menu.show = true
            -- Pause exercise when opening menu
            if engine.state == STATE_ACTIVE then
                engine.state = STATE_SETUP
                engine.setup_timer = SETUP_DELAY_FRAMES
            end
        end
    end

    -- Coin = Toggle record-to-exercise capture
    if is_pressed("P1 Coin") then
        capture_toggle()
    end

    if menu.show then
        handle_menu_input()
    end
end

--- Update the game character select sequence (called from on_frame)
local function update_charselect_sequence()
    local p1_state = memory.readbyte(MEM.p1_select_state)
    local p2_state = memory.readbyte(MEM.p2_select_state)

    if charselect_seq == 1 then  -- P1 selecting
        if p1_state > 4 then
            charselect_seq = 2  -- P2 debounce
            print("[Urien Lab] P1 locked -- release inputs to select P2")
        end
    elseif charselect_seq == 2 then  -- P2 debounce
        -- Wait for player to release all buttons before P2 selection
        local any_held = false
        for _, val in pairs(input_current) do
            if val == true then any_held = true; break end
        end
        if not any_held then
            charselect_seq = 3  -- P2 selecting
            print("[Urien Lab] Selecting P2 opponent...")
        end
    elseif charselect_seq == 3 then  -- P2 selecting
        if p1_state > 4 and p2_state > 4 then
            charselect_seq = 4  -- transitioning
            emu.speedmode("turbo")
            print("[Urien Lab] Characters locked -- fast-forwarding to match...")
        end
    elseif charselect_seq == 4 then  -- transitioning
        local phase = memory.readword(MEM.game_phase)
        if phase == 2 then
            emu.speedmode("normal")
            charselect_seq = 0  -- none
            app_state = APP_TRAINING
            charselect_visible = false
            selected_opponent = nil
            rebuild_filtered_exercises()
            memory.writebyte(MEM.round_timer, 100)
            print("[Urien Lab] Match started -- training mode active")
        end
    end
end

--- Main per-frame callback (before emulation)
local function on_frame()
    -- Game character select: fast-forward phase skips everything
    if charselect_seq == 4 then  -- transitioning
        update_charselect_sequence()
        return
    end

    -- Game character select: P1 selecting (1), P2 debounce (2), or P2 selecting (3)
    if charselect_seq >= 1 and charselect_seq <= 3 then
        read_input()
        update_charselect_sequence()
        if is_pressed("P1 Coin") then
            charselect_visible = not charselect_visible
        end
        if charselect_visible then
            handle_charselect_input()
        end
        if charselect_seq == 3 then  -- P2 selecting: swap P1↔P2
            swap_inputs()
        elseif charselect_seq == 2 then  -- debounce: zero P1 inputs
            joypad.set({
                ["P1 Up"] = false, ["P1 Down"] = false,
                ["P1 Left"] = false, ["P1 Right"] = false,
                ["P1 Weak Punch"] = false, ["P1 Medium Punch"] = false,
                ["P1 Strong Punch"] = false, ["P1 Weak Kick"] = false,
                ["P1 Medium Kick"] = false, ["P1 Strong Kick"] = false,
            })
        end
        return
    end

    -- Auto-load first available save state on startup
    if pending_home_load then
        pending_home_load = false
        if file_exists(CHARSELECT_SAVE) or fetch_save_state(CHARSELECT_SAVE) then
            start_character_select()
        else
            load_home_state()
        end
        return  -- skip this frame to let loaded state settle
    end

    -- ALWAYS read input first, even when not playing, so prev stays in sync
    read_input()
    check_konami()
    read_game_state()

    if app_state == APP_CHARSELECT then
        handle_charselect_input()
        -- If we just transitioned to training, skip this frame so Start
        -- doesn't also toggle the exercise menu
        if app_state ~= APP_CHARSELECT then return end
        if game_state.playing then
            -- Freeze game inputs while the charselect overlay is visible
            if charselect_visible then
                freeze_game()
            end
        end
        if charselect_visible then return end
    end

    -- APP_TRAINING
    if not game_state.playing then return end

    handle_input()

    if not menu.show then
        engine_update()
        capture_frame_update()
    end
    combo_tracker_update()

    -- Keep dummy locked when exercise is active
    if engine.state == STATE_SETUP or engine.state == STATE_ACTIVE then
        lock_dummy()
    end
end

--- GUI drawing callback (runs AFTER game logic, so memory writes here stick)
local function on_gui()
    -- Game character select sequence: freeze timer and draw HUD
    if charselect_seq >= 1 and charselect_seq <= 3 then
        memory.writebyte(MEM.char_select_timer, 0x69)
        if charselect_visible then
            draw_charselect()
        else
            local msg = charselect_seq == 1
                and "Select your character"
                or "Select opponent"
            draw_text(4, 4, "URIEN LAB -- " .. msg, COLOR.text_cyan)
            draw_text(4, 14, "Coin = Quick-load matchup", COLOR.text_gray)
        end
        return
    elseif charselect_seq == 4 then  -- transitioning
        draw_text(4, 4, "Loading match...", COLOR.text_cyan)
        return
    end

    if game_state.playing then
        -- Freeze round timer (infinite time)
        memory.writebyte(MEM.round_timer, 100)

        -- Meter: refill to max after inactivity (no P1 input, no combo)
        local actual_bars = memory.readbyte(MEM.meter_count)
        if actual_bars < res.prev_bars then
            res.meter_consumed = true
            res.meter_refill = 0
        end
        local any_input = false
        for _, val in pairs(input_current) do
            if val == true then any_input = true; break end
        end
        if game_state.combo_counter > 0 or any_input then
            res.meter_refill = 0
        elseif actual_bars < (memory.readbyte(MEM.max_meter_count) or 2) then
            res.meter_refill = res.meter_refill + 1
            if res.meter_refill > METER_REFILL_DELAY_FRAMES then
                fill_meter_full()
                res.meter_consumed = false
            end
        end
        res.prev_bars = actual_bars

        -- Always-on training resources: delayed HP/stun recovery
        if game_state.combo_counter == 0 then
            res.recovery = res.recovery + 1
            res.stun_reset = res.stun_reset + 1
            if res.recovery > RECOVERY_DELAY_FRAMES then
                local p1_hp = memory.readbyte(MEM.p1_life)
                local p2_hp = memory.readbyte(MEM.p2_life)
                if p1_hp < LIFE_FULL then
                    memory.writebyte(MEM.p1_life, math.min(p1_hp + LIFE_RECOVERY_SPEED, LIFE_FULL))
                end
                if p2_hp < LIFE_FULL then
                    memory.writebyte(MEM.p2_life, math.min(p2_hp + LIFE_RECOVERY_SPEED, LIFE_FULL))
                end
            end
            if res.stun_reset > STUN_RESET_DELAY_FRAMES then
                reset_stun()
            end
        else
            res.recovery = 0
            res.stun_reset = 0
            -- Keep P2 alive during combos
            if memory.readbyte(MEM.p2_life) < 0x10 then
                memory.writebyte(MEM.p2_life, 0x10)
            end
        end
    end

    if app_state == APP_CHARSELECT then
        if charselect_visible then
            draw_charselect()
        else
            draw_text(4, 4, "URIEN LAB -- Press Start for menu", COLOR.text_cyan)
        end
        return
    end

    -- APP_TRAINING
    if not game_state.playing then
        draw_text(4, 4, "URIEN LAB v" .. SCRIPT_VERSION .. " -- Waiting for match...", COLOR.text_cyan)
        return
    end

    draw_header()
    draw_combo_tracker()
    draw_charge_meters()
    draw_info_bar()
    draw_result_banner()
    draw_setup_overlay()
    draw_menu()
    draw_debug()

    -- Category selector or exercise creation banner
    if cat_sel.active then
        draw_category_selector()
    elseif capture_result and capture_result_timer > 0 then
        capture_result_timer = capture_result_timer - 1
        local banner_y = 32
        draw_box(20, banner_y, SCREEN_W - 40, 16, 0x003366D0, COLOR.text_cyan)
        draw_text(24, banner_y + 4, capture_result, COLOR.text_cyan)
    end

    -- Turbo charge flash message
    if konami.flash_timer > 0 then
        konami.flash_timer = konami.flash_timer - 1
        local msg = konami.active and "TURBO CHARGE ON" or "TURBO CHARGE OFF"
        local color = konami.active and COLOR.text_green or COLOR.text_gray
        draw_text(SCREEN_W / 2 - 30, SCREEN_H - 16, msg, color)
    end
end

--- Savestate load callback: reset engine state to avoid desync
local function on_savestate_load()
    if engine.state == STATE_ACTIVE then
        reset_exercise()
    end
    reset_hit_tracking()
    -- Reset combo tracker to prevent stale display
    combo_tracker.moves = {}
    combo_tracker.display_string = ""
    combo_tracker.last_action_id = nil
    combo_tracker.fade_timer = 0
    combo_tracker.active = false
end

--- Emulator start callback
local function on_start()
    game_state.frame_count = 0
    reset_hit_tracking()
end

-- ============================================================================
-- [13] HOOK REGISTRATION
-- ============================================================================

-- Sync content from manifest (script updates, exercises, save state list)
sync_from_manifest()

-- Load exercises FIRST (before progression, so init_progression sees exercise IDs)
load_exercises()
-- Load saved progress, matchup slots, and character states
load_progression()
rebuild_filtered_exercises()
load_matchup_metadata()
load_char_metadata()

-- Register FBNeo callbacks
emu.registerbefore(on_frame)
gui.register(on_gui)
emu.registerstart(on_start)
savestate.registerload(on_savestate_load)

-- Register hotkeys
-- Alt+1 = Return to character select / save character select state
input.registerhotkey(1, function()
    if start_character_select() then
        menu.show = false
    end
end)

-- Alt+2 = Toggle numpad notation
input.registerhotkey(2, function()
    toggle_notation()
    print("[Urien Lab] Notation: " .. (notation_mode == NOTATION_SF and "SF" or "Numpad"))
end)

-- Alt+3 = Reset current exercise progress
input.registerhotkey(3, function()
    if engine.current_exercise then
        local id = engine.current_exercise.id
        progression[id] = { completions = 0, attempts = 0, mastered = false }
        save_progression()
        print("[Urien Lab] Reset progress for: " .. engine.current_exercise.name)
    end
end)

-- Alt+4 = Toggle debug display
input.registerhotkey(4, function()
    menu.debug = not menu.debug
end)

-- Alt+5 = Toggle menu (reliable fallback if Start conflicts with game)
input.registerhotkey(5, function()
    menu.show = not menu.show
    if menu.show and engine.state == STATE_ACTIVE then
        engine.state = STATE_SETUP
        engine.setup_timer = SETUP_DELAY_FRAMES
    end
end)

-- Alt+6 = Quick save matchup to current slot
input.registerhotkey(6, function()
    save_matchup(menu.matchup_cursor)
end)

-- Alt+7 = Rename current matchup slot (via console)
input.registerhotkey(7, function()
    local slot = matchup_slots[menu.matchup_cursor]
    print("[Urien Lab] Current slot " .. menu.matchup_cursor .. " name: " .. slot.name)
    print("[Urien Lab] To rename, edit " .. MATCHUP_FILE .. " directly")
end)

-- Alt+9 = Reload exercises (after editing file)
input.registerhotkey(9, function()
    reload_exercises()
end)

-- Startup message
print("===========================================")
print("  BLUEABS URIEN LAB v" .. SCRIPT_VERSION)
print("  Training Mode for SF3:3rd Strike")
print("===========================================")
print("  CHARACTER SELECT:")
print("    D-Pad     = Navigate characters")
print("    Jab       = Load opponent state")
print("    Fierce    = Save current state")
print("  TRAINING:")
print("    Start     = Open exercise menu")
print("    Left/Right= Switch tabs (Exercises/Opponent)")
print("    LK        = Toggle exercise side (L/R)")
print("    MK        = Tag/untag opponent on exercise")
print("    MP        = Stop exercise (in menu)")
print("  Coin        = Toggle capture mode")
print("  Alt+1       = Return to character select")
print("  Alt+2       = Toggle notation (SF/Numpad)")
print("  Alt+3       = Reset current exercise progress")
print("  Alt+4       = Toggle debug display")
print("  Alt+5       = Toggle menu (backup)")
print("  Alt+9       = Reload exercises (after editing file)")
print("===========================================")
