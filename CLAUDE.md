# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Blueabs Urien Lab** is a Lua training script for **Street Fighter III: 3rd Strike** running on **FBNeo (FinalBurn Neo)** emulator. It teaches Urien combos progressively through a curriculum-driven exercise system.

For user flow, controls, behavioral invariants, and feature details see `intent/CURRENT_STATE.md`.

## Running the Script

Load `urien_lab.lua` via FBNeo's Lua console (`Game > Lua Scripting`). The ROM must be SF3: 3rd Strike (`sfiii3`). No build step — single Lua file, no `require`.

## Architecture

### Main File: `urien_lab.lua` (~3900 lines)

Two-level state machine:
- **App level:** `APP_CHARSELECT` ↔ `APP_TRAINING` — controls whether the character select screen or the training HUD is shown
- **Exercise level:** `IDLE` → `SETUP` → `ACTIVE` → `SUCCESS`/`FAIL` — manages individual exercise execution

Organized into numbered sections:

| Section | Purpose |
|---------|---------|
| [1] Constants & Config | Screen dims (384×224), timing, colors, exercise/app state enums, category constants |
| [1b] Update & Distribution | Auto-update from GitHub, save state download from voidtalker.com |
| [2] Memory Address Map | CPS3 RAM addresses (game phase, P1/P2 base, charge, meter, combos) |
| [2b] Character Roster | 19 SF3:3S characters (alphabetical, no Gill), grid layout constants, app state vars |
| [3] Urien Move Database | Urien moves with action IDs, dual notation (SF + Numpad) |
| [4] Exercise Definitions | Exercises loaded from file with sequences, setup requirements, success/fail criteria, hints |
| [5] Progression State | Save/load to `urien_lab_save.txt`, mastery tracking (3 completions) |
| [6] Utility Functions | Memory reads (little-endian), action string builders, action ID normalization |
| [7] Game State Reader | Per-frame polling of positions, actions, combo counter, hit region, meter |
| [8] Dummy Controller | P2 position/life/meter/stun management, input locking, delayed HP recovery |
| [9] Exercise Engine | State machine: SETUP → ACTIVE → SUCCESS/FAIL, combo detection, timeout |
| [10] Input Display | Toggleable SF/Numpad notation |
| [11a] Matchup Save States | Legacy 5-slot save state system (slots 8001–8005) |
| [11a2] Character Save States | Named save files (`vs_CharName.fs`), metadata in `urien_lab_characters.txt`, auto-load on startup |
| [11b] HUD & Menu | Character select grid, three-tab exercise menu (All / Character / Opponent), result banners |
| [11b]* Exercise Capture | Records combos to `captured_exercises.txt` — note: duplicate label, should be [11c] |
| [11c2] Input Notation Detector | Converts joypad input logs to human-readable notation (numpad, SF format) |
| [11c3] Exercise Builder | Record-to-Exercise — converts captured combos into playable exercise definitions |
| [11c4] Exercise Persistence | Save/load exercises to `urien_lab_exercises.txt` and `urien_lab_custom.txt` |
| [12] Main Loop Callbacks | `on_frame()` (input + state machines), `on_gui()` (draw + memory writes) |
| [13] Hook Registration | FBNeo callbacks, hotkeys, initialization |

### Frame Callback Split (critical)

- `emu.registerbefore()` → `on_frame()`: Before game logic. Input reading, state machines, dummy control.
- `gui.register()` → `on_gui()`: After game logic. Drawing, memory writes that must persist (timer, HP, meter, stun).

**Memory writes in `on_frame()` get overwritten by the game.** Anything that needs to stick must go in `on_gui()`.

### FBNeo Lua API Used
- **Memory:** `memory.readbyte()`, `memory.readword()`, `memory.writebyte()`, `memory.writeword()`
- **Input:** `joypad.set()` (P2 dummy), `joypad.get()` (P1 input), `input.registerhotkey()` (Alt+N dev keys). Button names: `"P1 Weak Punch"`, `"P1 Medium Punch"`, `"P1 Strong Punch"`, `"P1 Weak Kick"`, `"P1 Medium Kick"`, `"P1 Strong Kick"`, `"P1 Start"`, `"P1 Up/Down/Left/Right"` (same pattern for P2)
- **Savestates:** `savestate.create()`, `savestate.save()`, `savestate.load()` — temp slot (99999) + `os.rename()` to named files
- **Hooks:** `emu.registerbefore()`, `gui.register()`
- **Drawing:** `gui.text()`, `gui.box()`

### Action ID System

Action strings are built by `build_action_string()` as `prefix + sub(4hex) + id(4hex)`:
- Prefixes: `A` (attack/normal), `S` (special), `F` (projectile, 5-char format: `F` + id(4hex)), `G` (guard), `T` (throw), `M` (misc), `N` (neutral)
- The game sets a `0x2000` flag on `action_id` during connected hits. `build_action_string()` strips this with `action_id % 0x2000` so IDs always match the clean values in the MOVES database.
- `normalize_action_string()` strips the same flag from stored strings (backward compatibility).

### Critical Memory Addresses
- Game phase: `0x020154A6` (word, 2 = playing)
- Round timer: `0x02011377` (byte, write `100` each frame to keep at 99)
- P1 life: `0x02068D0B` (byte), P2 life: `0x020691A3` (byte), full = `0xA0`
- P1 base: `0x02068C6C`, P2 base: `0x02069104`
- Combo counter: `0x020696C5`
- Hit tracking region: `0x02011000` (200 bytes, summed for waza total)
- Charge system: `0x020259D8` + offsets (0x00, 0x1C, 0x38, 0x54, 0x70)
- Meter gauge: `0x020695B5`, bars: `0x020286AD`
- P2 stun bar: `0x02069612` (word), P1 stun timer: `0x020695FD` (byte)
- P1 character ID: `0x02011387` (byte, Urien = 14)

### Exercise Definition Format
```lua
{ id = "t1_03", name = "cr.HP xx L.Tackle",
  category = "combo",
  sequence = {
      { name = "cr.HP",    hit_type = "H", action_ids = {"A00180018"} },
      { name = "L.Tackle", hit_type = "H", action_ids = {"S003a003a"} },
  },
  setup = { p1_x = 0x0100, p2_x = 0x0180, p1_life = 0xA0, p2_life = 0xA0,
            meter = "full", fill_h_charge = true, fill_v_charge = false,
            p2_state = "stand", corner = false },
  success = { min_combo = 2 },
  fail = { timeout_frames = 600 },
  ref_timing = { 12, 8 },
  hints = { "Hold down-back, press d+HP, then tap f+LK during the cancel window" },
  difficulty = 2,
  allow_combo_reset = false,
  characters = {"Ken", "Yun"} }
```

### Exercise File Format
Line-oriented key:value blocks in `urien_lab_exercises.txt` / `urien_lab_custom.txt`:
```
---
ID:c_01
NAME:cr.HP > L.Tackle
NOTATION_SF:d+HP, b~f+LK
NOTATION_NP:2HP, [4]6LK
DIFFICULTY:2
CATEGORY:combo
CHARS:Ken,Yun
SETUP:0100,0180,A0,A0,full,1,0,stand,0
SEQ:cr.HP,H,A00180018|L.Tackle,H,S003a003a
SUCCESS:2
TIMEOUT:900
RESETOK:1
TIMING:12,8
HINT:d+HP -> b~f+LK
---
```

All fields after ID and NAME are optional on parse (backward compatible).

## Data Files

| File | Tracked | Purpose |
|------|---------|---------|
| `urien_lab.lua` | Yes | Main script |
| `urien_lab_exercises.txt` | Yes | Shipped exercise definitions (updated automatically) |
| `urien_lab_custom.txt` | No | User's captured/custom exercises (never overwritten by updates) |
| `CLAUDE.md` | Yes | Dev guidance (this file) |
| `README.md` | Yes | User-facing docs |
| `intent/` | Yes | Design docs: overview, architecture, current/desired state |
| `urien_lab_save.txt` | No | User progression (completions, attempts, mastery) |
| `urien_lab_characters.txt` | No | Character save state metadata |
| `character_select.fs` | No | Character select screen save state (downloaded on first boot) |
| `captured_exercises.txt` | No | Raw capture logs |
| `vs_*.fs` | No | Binary FBNeo save states (user-specific, ROM-dependent) |
| `reference/` | No | Prior art scripts (gitignored) |

## Conventions
- All colors are RRGGBBAA 32-bit hex (FBNeo convention, e.g. `0xFF0000FF` = red, full opacity)
- Move IDs are built as `prefix .. sub(4hex) .. id(4hex)` strings (or `prefix .. id(4hex)` for F-type)
- Screen coordinates: 384×224 native CPS3 resolution
- Character IDs match the game's internal numbering (0=Gill through 19=Remy)
- Save state files: `vs_CharName.fs` (e.g., `vs_Yun.fs`, `vs_Ken.fs`)
- Single-file architecture by design (FBNeo Lua has no `require`)
- Shipped exercise IDs use `t_XX` prefix, custom use `c_XX`
