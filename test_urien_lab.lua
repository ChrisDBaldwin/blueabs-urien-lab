-- ============================================================================
-- TEST HARNESS FOR URIEN LAB
-- ============================================================================
-- Run: lua test_urien_lab.lua
-- No emulator needed. Tests engine state machine behaviors.
--
-- Design principles:
--   - Test BEHAVIORS not implementation ("blocking triggers success",
--     not "engine.state == some string after calling some function")
--   - Each test sets up a scenario, runs frames, checks the outcome
--   - Tests break when behavior changes, not when code is refactored
--   - No test framework dependency — plain Lua asserts with clear messages
-- ============================================================================

-- ============================================================================
-- FBNEO API MOCKS
-- ============================================================================
-- Minimal stubs so urien_lab.lua loads without crashing.
-- Memory is a flat byte array; tests write values here to simulate game state.

local mock_memory = {}
local mock_joypad_state = {}
local mock_joypad_sets = {}  -- captures what lock_dummy/dummy_attack write

memory = {
    readbyte = function(addr) return mock_memory[addr] or 0 end,
    readword = function(addr)
        local lo = mock_memory[addr] or 0
        local hi = mock_memory[addr + 1] or 0
        return lo + hi * 256
    end,
    writebyte = function(addr, val) mock_memory[addr] = val end,
    writeword = function(addr, val)
        mock_memory[addr] = val % 256
        mock_memory[addr + 1] = math.floor(val / 256) % 256
    end,
}

joypad = {
    get = function() return mock_joypad_state end,
    set = function(t)
        mock_joypad_sets[#mock_joypad_sets + 1] = t
        for k, v in pairs(t) do mock_joypad_state[k] = v end
    end,
}

gui = {
    text = function() end,
    box = function() end,
    register = function() end,
}

emu = {
    registerbefore = function() end,
    registerstart = function() end,
    speedmode = function() end,
}

savestate = {
    create = function() return {} end,
    save = function() end,
    load = function() end,
    registerload = function() end,
}

input = {
    registerhotkey = function() end,
}

-- Stub io.open to return nil (no save files during test)
local real_io_open = io.open
io.open = function(path, mode)
    -- Allow the test harness itself to be read, block game save files
    if path and path:match("urien_lab") and not path:match("test_urien_lab") then
        return nil
    end
    return real_io_open(path, mode)
end

-- Stub os.execute / os.remove for download_file
local real_os_remove = os.remove
os.execute = function() return true end
os.remove = function(path)
    if path and path:match("%.tmp$") then return true end
    return real_os_remove(path)
end

-- ============================================================================
-- LOAD THE SCRIPT
-- ============================================================================

TESTING = true
local lab = assert(loadfile("urien_lab.lua"))()

-- Restore io.open
io.open = real_io_open

-- ============================================================================
-- TEST RUNNER
-- ============================================================================

local tests_run = 0
local tests_passed = 0
local tests_failed = 0
local failed_names = {}

local function test(name, fn)
    tests_run = tests_run + 1
    local ok, err = pcall(fn)
    if ok then
        tests_passed = tests_passed + 1
        io.write("  PASS  " .. name .. "\n")
    else
        tests_failed = tests_failed + 1
        failed_names[#failed_names + 1] = name
        io.write("  FAIL  " .. name .. "\n")
        io.write("        " .. tostring(err) .. "\n")
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "assert_eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Reset engine and game state to a clean baseline for a test
local function reset()
    lab.engine.state = lab.STATE_IDLE
    lab.engine.current_exercise = nil
    lab.engine.current_exercise_index = nil
    lab.engine.combo_index = 1
    lab.engine.attempt_started = false
    lab.engine.block_detected = false
    lab.engine.session_attempts = 0
    lab.engine.session_completions = 0
    lab.engine.result_timer = 0
    lab.engine.active_start_frame = 0
    lab.engine.last_hit_frame = 0
    lab.engine.last_match_action = ""
    lab.engine.action_changed_since_match = true
    lab.engine.step_frames = {}
    lab.engine.fail_reason = ""
    lab.engine.last_hit_waza = ""
    lab.engine.setup_timer = 0

    lab.game_state.playing = true
    lab.game_state.phase = 2
    lab.game_state.frame_count = 100
    lab.game_state.combo_counter = 0
    lab.game_state.combo_counter_prev = 0
    lab.game_state.waza_total = 0
    lab.game_state.meter_bars = 2
    lab.game_state.meter_gauge = 0
    lab.game_state.p1.action_string = "N00000000"
    lab.game_state.p1.life = 0xA0
    lab.game_state.p1.action_type = 0
    lab.game_state.p1.action_sub = 0
    lab.game_state.p1.action_id = 0
    lab.game_state.p1.x_pos = 0x0100
    lab.game_state.p2.x_pos = 0x0180

    mock_joypad_sets = {}
end

--- Find a tutorial lesson by ID
local function find_lesson(id)
    for _, chapter in ipairs(lab.TUTORIAL_CHAPTERS) do
        for _, lesson in ipairs(chapter.lessons) do
            if lesson.id == id then return lesson end
        end
    end
    error("Lesson not found: " .. id)
end

--- Start a tutorial lesson and advance to ACTIVE state
local function start_lesson(id)
    local lesson = find_lesson(id)
    lab.select_tutorial_lesson(lesson)
    -- Advance past SETUP (setup_timer = 0 means instant)
    lab.engine_setup_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "lesson should be ACTIVE after setup")
    return lesson
end

-- ============================================================================
-- TUTORIAL DATA STRUCTURE TESTS
-- ============================================================================
print("\n--- Tutorial Data ---")

test("all chapters have names and lessons", function()
    assert(#lab.TUTORIAL_CHAPTERS > 0, "no chapters")
    for i, chapter in ipairs(lab.TUTORIAL_CHAPTERS) do
        assert(chapter.name, "chapter " .. i .. " missing name")
        assert(chapter.lessons and #chapter.lessons > 0,
            "chapter " .. chapter.name .. " has no lessons")
    end
end)

test("all lessons have required fields", function()
    for _, chapter in ipairs(lab.TUTORIAL_CHAPTERS) do
        for _, lesson in ipairs(chapter.lessons) do
            assert(lesson.id, chapter.name .. ": lesson missing id")
            assert(lesson.name, chapter.name .. ": lesson missing name")
            assert(lesson.tutorial_type, lesson.id .. ": missing tutorial_type")
            assert(lesson.sequence, lesson.id .. ": missing sequence")
            assert(lesson.setup, lesson.id .. ": missing setup")
        end
    end
end)

test("all lesson IDs are unique", function()
    local seen = {}
    for _, chapter in ipairs(lab.TUTORIAL_CHAPTERS) do
        for _, lesson in ipairs(chapter.lessons) do
            assert(not seen[lesson.id], "duplicate ID: " .. lesson.id)
            seen[lesson.id] = true
        end
    end
end)

test("all lesson IDs registered in progression", function()
    for _, chapter in ipairs(lab.TUTORIAL_CHAPTERS) do
        for _, lesson in ipairs(chapter.lessons) do
            assert(lab.progression[lesson.id],
                lesson.id .. " not in progression table")
        end
    end
end)

-- ============================================================================
-- ACTION DETECTION TESTS (Special/EX/Aegis moves)
-- ============================================================================
print("\n--- Action Detection ---")

test("performing a tackle triggers success", function()
    reset()
    start_lesson("tut_3_01")  -- Chariot Tackle
    lab.game_state.p1.action_string = "S003a003a"
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "should succeed on tackle action")
end)

test("wrong action does not trigger success", function()
    reset()
    start_lesson("tut_3_01")  -- Chariot Tackle
    lab.game_state.p1.action_string = "S00290029"  -- headbutt instead
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "should stay active on wrong action")
end)

test("idle action does not trigger success", function()
    reset()
    start_lesson("tut_3_01")
    lab.game_state.p1.action_string = "N00000000"
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "idle should not trigger")
end)

test("EX move detection works", function()
    reset()
    start_lesson("tut_4_01")  -- EX Tackle
    lab.game_state.p1.action_string = "S003d003d"
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "EX tackle should succeed")
end)

test("Aegis activation detection works", function()
    reset()
    start_lesson("tut_5_01")  -- Activate Aegis
    lab.game_state.p1.action_string = "S003e003e"
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "Aegis should succeed")
end)

test("action detection increments progression", function()
    reset()
    local lesson = find_lesson("tut_3_02")
    lab.progression[lesson.id] = { completions = 0, attempts = 0, mastered = false }
    start_lesson("tut_3_02")  -- Headbutt
    lab.game_state.p1.action_string = "S00290029"
    lab.engine_active_update()
    assert_eq(lab.progression[lesson.id].completions, 1, "completions should be 1")
    assert_eq(lab.progression[lesson.id].attempts, 1, "attempts should be 1")
end)

-- ============================================================================
-- BLOCK DETECTION TESTS
-- ============================================================================
print("\n--- Block Detection ---")

test("standing block triggers success after dummy attacks", function()
    reset()
    start_lesson("tut_2_01")  -- Block a Punch, dummy_attack.delay = 40
    -- Advance frame_count past the dummy attack delay
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0xA0  -- full HP = blocked, not hit
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "standing block should succeed")
end)

test("block before dummy attacks does not trigger", function()
    reset()
    start_lesson("tut_2_01")
    -- Frame count before dummy delay (delay=40, only 10 frames in)
    lab.game_state.frame_count = lab.engine.active_start_frame + 10
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "should not succeed before dummy attacks")
end)

test("getting hit does not trigger block success", function()
    reset()
    start_lesson("tut_2_01")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0x80  -- lost HP = got hit, not a real block
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "damaged P1 should not count as block")
end)

test("any G-prefix matches broad block_match", function()
    reset()
    start_lesson("tut_2_01")  -- block_match = "G"
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "G00020002"  -- crouch block
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "crouch block should match G prefix")
end)

test("crouch block lesson requires exact match", function()
    reset()
    start_lesson("tut_2_02")  -- block_match = "G00020002"
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "G00010001"  -- standing block, not crouch
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "standing block should NOT match crouch lesson")
end)

test("crouch block with correct action succeeds", function()
    reset()
    start_lesson("tut_2_02")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "G00020002"
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "crouch block should succeed")
end)

test("non-guard action does not trigger block detection", function()
    reset()
    start_lesson("tut_2_01")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50
    lab.game_state.p1.action_string = "A00180018"  -- cr.HP, not a block
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "attack should not trigger block")
end)

-- ============================================================================
-- BLOCK-PUNISH DETECTION TESTS
-- ============================================================================
print("\n--- Block then Punish ---")

test("block then hit with correct move succeeds", function()
    reset()
    start_lesson("tut_2_03")  -- Block then Punish, dummy_attack.delay = 40
    lab.game_state.frame_count = lab.engine.active_start_frame + 50

    -- Phase 1: block (full HP = not hit)
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "should stay active after block phase")
    assert_eq(lab.engine.block_detected, true, "block should be detected")

    -- Phase 2: punish with cr.MK
    lab.game_state.p1.action_string = "A001e001e"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "punish should succeed")
end)

test("hit without blocking first does not succeed", function()
    reset()
    start_lesson("tut_2_03")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50

    -- Skip block, go straight to hit
    lab.game_state.p1.action_string = "A001e001e"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "should not succeed without blocking first")
end)

test("block then wrong punish move does not succeed", function()
    reset()
    start_lesson("tut_2_03")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50

    -- Block
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0xA0
    lab.engine_active_update()

    -- Wrong punish (cr.HP instead of cr.MK)
    lab.game_state.p1.action_string = "A00180018"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "wrong punish should not succeed")
end)

test("getting hit then punishing does not count as block_punish", function()
    reset()
    start_lesson("tut_2_03")
    lab.game_state.frame_count = lab.engine.active_start_frame + 50

    -- P1 in guard state but lost HP (got hit, not blocked)
    lab.game_state.p1.action_string = "G00010001"
    lab.game_state.p1.life = 0x80
    lab.engine_active_update()
    assert_eq(lab.engine.block_detected, false, "should not detect block when HP dropped")
end)

-- ============================================================================
-- HIT DETECTION TESTS (Normals)
-- ============================================================================
print("\n--- Hit Detection (Normals) ---")

test("landing st.MP triggers success", function()
    reset()
    start_lesson("tut_1_01")  -- Standing Strong (st.MP)

    -- Simulate a hit: combo counter goes from 0 to 1, action matches
    lab.game_state.p1.action_string = "A0001009e"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "st.MP hit should succeed")
end)

test("st.MP with alternate action ID also succeeds", function()
    reset()
    start_lesson("tut_1_01")
    lab.game_state.p1.action_string = "A0000009e"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "alternate action ID should match")
end)

test("whiffed normal does not trigger hit type", function()
    reset()
    start_lesson("tut_1_01")
    -- Action matches but no combo counter increase
    lab.game_state.p1.action_string = "A0001009e"
    lab.game_state.combo_counter = 0
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "whiffed normal should not trigger")
end)

-- ============================================================================
-- COMBO DETECTION TESTS
-- ============================================================================
print("\n--- Combo Detection ---")

test("cr.HP into Aegis combo succeeds", function()
    reset()
    start_lesson("tut_5_03")  -- cr.HP into Aegis (combo type)

    -- Step 1: cr.HP hits
    lab.game_state.p1.action_string = "A00180018"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_ACTIVE, "should stay active after first hit")
    assert_eq(lab.engine.combo_index, 2, "should advance to step 2")

    -- Step 2: Aegis connects
    lab.game_state.frame_count = lab.game_state.frame_count + 10
    lab.game_state.p1.action_string = "S003e003e"
    lab.game_state.combo_counter = 2
    lab.game_state.combo_counter_prev = 1
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_SUCCESS, "combo should succeed")
end)

test("combo drops are detected", function()
    reset()
    start_lesson("tut_5_03")

    -- Step 1 hits
    lab.game_state.p1.action_string = "A00180018"
    lab.game_state.combo_counter = 1
    lab.game_state.combo_counter_prev = 0
    lab.engine_active_update()

    -- Combo drops (counter goes back to 0)
    lab.game_state.frame_count = lab.game_state.frame_count + 30
    lab.game_state.combo_counter = 0
    lab.game_state.combo_counter_prev = 1
    lab.engine_active_update()
    assert_eq(lab.engine.state, lab.STATE_FAIL, "dropped combo should fail")
end)

-- ============================================================================
-- MASTERY TRACKING
-- ============================================================================
print("\n--- Mastery ---")

test("mastery triggers after threshold completions", function()
    reset()
    local lesson = find_lesson("tut_3_03")  -- Metallic Sphere
    lab.progression[lesson.id] = { completions = 0, attempts = 0, mastered = false }

    for i = 1, lab.MASTERY_THRESHOLD do
        reset()
        -- Preserve progression across resets
        start_lesson("tut_3_03")
        lab.game_state.p1.action_string = "S00210021"
        lab.engine_active_update()
        assert_eq(lab.engine.state, lab.STATE_SUCCESS, "attempt " .. i .. " should succeed")
    end

    assert_eq(lab.progression[lesson.id].mastered, true, "should be mastered")
    assert_eq(lab.progression[lesson.id].completions, lab.MASTERY_THRESHOLD,
        "completions should equal threshold")
end)

-- ============================================================================
-- EXERCISE RESET
-- ============================================================================
print("\n--- Reset ---")

test("reset clears block_detected state", function()
    reset()
    start_lesson("tut_2_03")
    lab.engine.block_detected = true
    lab.reset_exercise()
    assert_eq(lab.engine.block_detected, false, "block_detected should reset")
    assert_eq(lab.engine.state, lab.STATE_SETUP, "should be back in SETUP")
end)

-- ============================================================================
-- MENU STATE
-- ============================================================================
print("\n--- Menu ---")

test("default tab is Tutorial", function()
    assert_eq(lab.menu.mode, lab.MENU_TUTORIAL, "default tab should be Tutorial")
end)

test("tutorial_expanded starts at chapter 1", function()
    assert_eq(lab.menu.tutorial_expanded, 1, "first chapter should be expanded")
end)

-- ============================================================================
-- RESULTS
-- ============================================================================

print("\n===========================================")
if tests_failed == 0 then
    print(string.format("  ALL %d TESTS PASSED", tests_passed))
else
    print(string.format("  %d/%d PASSED, %d FAILED", tests_passed, tests_run, tests_failed))
    for _, name in ipairs(failed_names) do
        print("    - " .. name)
    end
end
print("===========================================\n")

os.exit(tests_failed == 0 and 0 or 1)
