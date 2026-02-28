# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Blueabs Urien Lab** is a Lua training script for **Street Fighter III: 3rd Strike** running on **FBNeo (FinalBurn Neo)** emulator. It teaches Urien combos progressively through a curriculum-driven drill system — from basic normals through tackle loops to advanced Aegis Reflector unblockable setups.

### Flow

1. Script loads → auto-loads first available save state → **character select grid** appears (19 characters, 4×5 grid)
2. **Start** toggles the overlay — hide it to play, show it to save/load
3. **Fierce** saves the current match state for the selected opponent
4. **Jab** loads a saved state → transitions to training mode
5. **Start** opens the drill menu to select which combo to practice
6. Drill engine manages setup, detection, and progression

## Running the Script

Load `urien_lab.lua` via FBNeo's Lua console (`Game > Lua Scripting`). The ROM must be SF3: 3rd Strike (`sfiii3`). No build step — single Lua file, no `require`.

## Architecture

### Main File: `urien_lab.lua` (~2800 lines)

Two-level state machine:
- **App level:** `APP_CHARSELECT` ↔ `APP_TRAINING` — controls whether the character select grid or the training HUD is shown
- **Drill level:** `IDLE` → `SETUP` → `ACTIVE` → `SUCCESS`/`FAIL` — manages individual drill execution

Organized into numbered sections:

| Section | Purpose |
|---------|---------|
| [1] Constants | Screen dims (384×224), timing, colors, drill/app state enums |
| [2] Memory Map | CPS3 RAM addresses (game phase, P1/P2 base, charge, meter, combos) |
| [2b] Character Roster | 19 SF3:3S characters (alphabetical, no Gill), grid layout constants, app state vars |
| [3] Move Database | Urien moves with action IDs, dual notation (SF + Numpad) |
| [4] Drill Definitions | Tier-organized drills with sequences, setup requirements, success/fail criteria, hints |
| [5] Progression | Save/load to `urien_lab_save.txt`, mastery tracking (3 completions) |
| [6] Utilities | Memory reads (little-endian), action string builders, action ID normalization |
| [7] Game State Reader | Per-frame polling of positions, actions, combo counter, hit region, meter |
| [8] Dummy Controller | P2 position/life/meter/stun management, input locking, delayed HP recovery |
| [9] Drill Engine | State machine: SETUP → ACTIVE → SUCCESS/FAIL, combo detection, timeout |
| [10] Input Display | Toggleable SF/Numpad notation |
| [11a] Matchup States | Legacy 5-slot save state system (slots 8001–8005) |
| [11a2] Character States | Named save files (`vs_CharName.fs`), metadata in `urien_lab_characters.txt`, auto-load on startup |
| [11b] HUD & Menu | Character select grid, two-tab drill menu (Drills / Opponent), result banners |
| [11c] Drill Capture | Records combos to `captured_drills.txt` in Lua table format |
| [11c2] Input Notation Detector | Converts joypad input logs to human-readable notation (numpad, SF format) |
| [11c3] Drill Builder | Record-to-Drill — converts captured combos into playable drill definitions |
| [11c4] Custom Drill Persistence | Save/load custom drills to `urien_lab_custom_drills.txt` |
| [12] Controls | Input handlers: charselect navigation, menu nav, drill selection |
| [13] Hooks | FBNeo callbacks, hotkeys, file migration, initialization |

## Key Technical Details

### FBNeo Lua API Used
- **Memory:** `memory.readbyte()`, `memory.readword()`, `memory.writebyte()`, `memory.writeword()`
- **Input:** `joypad.set()` (P2 dummy), `joypad.get()` (P1 input), `input.registerhotkey()` (Alt+N dev keys). Button names use fighting game notation: `"P1 Weak Punch"`, `"P1 Medium Punch"`, `"P1 Strong Punch"`, `"P1 Weak Kick"`, `"P1 Medium Kick"`, `"P1 Strong Kick"`, `"P1 Start"`, `"P1 Up/Down/Left/Right"` (same pattern for P2)
- **Savestates:** `savestate.create()`, `savestate.save()`, `savestate.load()` — uses temp slot + `os.rename()` to produce named files (`vs_CharName.fs`)
- **Hooks:** `emu.registerbefore()` (pre-frame logic/input), `gui.register()` (draw overlay + memory writes that must persist after game logic)
- **Drawing:** `gui.text()`, `gui.box()`

**Important:** Memory writes that need to stick (timer, HP, meter) must happen in `gui.register()` (runs after game logic), not `emu.registerbefore()` (runs before, so the game overwrites them).

### Action ID System

Action strings are built by `build_action_string()` as `prefix + sub(4hex) + id(4hex)`:
- Prefixes: `A` (attack/normal), `S` (special), `F` (projectile, 5-char format: `F` + id(4hex)), `G` (guard), `T` (throw), `M` (misc), `N` (neutral)
- The game sets a `0x2000` flag on `action_id` during connected hits. `build_action_string()` strips this with `action_id % 0x2000` so IDs always match the clean values in the MOVES database.
- `normalize_action_string()` strips the same flag from stored strings (for backward compatibility with custom drill files saved before normalization was added).

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

### Always-On Training Resources (in `gui.register`)
These run every frame when the game is playing, regardless of drill state:
- **Round timer** — frozen at 99
- **Super meter** — always full
- **Stun** — always cleared (both players)
- **HP recovery** — delayed rejuvenate after combo drops (configurable delay + speed)
- **P2 survival** — kept alive during combos (min 0x10 HP)

### Combo Detection
1. Monitor combo counter at `0x020696C5`
2. Sum hit region `0x02011000–0x020110C8` for waza total
3. When either increases, compare P1's action string against the expected move in the drill sequence
4. Combo counter drop (>0 → 0) triggers FAIL, unless `drill.allow_combo_reset` is set (for multi-combo Aegis setups)

### Drill Definition Format
```lua
{ id = "t1_03", name = "cr.HP xx L.Tackle",
  sequence = {
      { name = "cr.HP",    hit_type = "H", action_ids = {"A00180018"} },
      { name = "L.Tackle", hit_type = "H", action_ids = {"S003a003a"} },
  },
  setup = { p1_x = 0x0100, p2_x = 0x0180, p1_life = 0xA0, p2_life = 0xA0,
            meter = "full", fill_h_charge = true, fill_v_charge = false,
            p2_state = "stand", corner = false },
  success = { min_combo = 2 },
  fail = { timeout_frames = 600 },
  hints = { "Hold down-back, press d+HP, then tap f+LK during the cancel window" },
  difficulty = 2 }
```

Custom drills have additional fields: `custom = true`, `tier = 0`, and optionally `allow_combo_reset = true` for multi-combo sequences.

### Multi-Combo Drills (Aegis Setups)
Drills with `allow_combo_reset = true` tolerate the combo counter resetting to 0 mid-sequence. The drill builder auto-sets this flag when it filters out N/M/G/T-prefix entries (neutral/misc state transitions that appear during combo resets). Persisted as `RESETOK:1` in the custom drill file.

### Record-to-Drill Flow
1. Press **Coin** during a match to start recording (pauses any active drill)
2. Perform a combo — the capture system records hits and joypad inputs each frame
3. Press **Coin** again to stop — the system automatically builds a playable drill:
   - Known moves are identified via `lookup_move_name()` against the MOVES database
   - Unknown moves get notation inferred from joypad edge detection (`detect_motion` + `detect_button`)
   - Multi-hit moves (e.g., Tyrant Slaughter) are collapsed into a single sequence step
   - N/M/G/T-prefix entries are filtered out (state transitions, not player moves)
4. The new drill appears at the bottom of the drill menu with a `[C]` prefix in cyan
5. Custom drills persist to `urien_lab_custom_drills.txt` and reload on script restart
6. To rename a custom drill, edit the `NAME:` line in `urien_lab_custom_drills.txt` and press **Alt+9** to reload
7. Delete custom drills: highlight in menu, press Fierce twice to confirm

### Custom Drill File Format
Line-oriented key:value blocks in `urien_lab_custom_drills.txt`:
```
---
ID:c_01
NAME:cr.HP > L.Tackle
NOTATION_SF:d+HP, b~f+LK
NOTATION_NP:2HP, [4]6LK
DIFFICULTY:2
SETUP:0100,0180,A0,A0,full,1,0,stand,0
SEQ:cr.HP,H,A00180018|L.Tackle,H,S003a003a
SUCCESS:2
TIMEOUT:900
RESETOK:1
HINT:d+HP -> b~f+LK
---
```

### Character Save State System
Save states use named files (`vs_CharName.fs`) stored next to the script. A temp FBNeo slot (99999) is used for the API call, then the file is renamed. Metadata persisted to `urien_lab_characters.txt` (CSV: `id,name,saved`). Legacy numbered files are auto-migrated to named format on startup.

## Data Files

| File | Tracked | Purpose |
|------|---------|---------|
| `urien_lab.lua` | Yes | Main script |
| `urien_lab_custom_drills.txt` | Yes | Curated drill curriculum (the shipped content) |
| `CLAUDE.md` | Yes | Dev guidance |
| `README.md` | Yes | User-facing docs |
| `urien_lab_save.txt` | No | User progression (completions, attempts, mastery) |
| `urien_lab_characters.txt` | No | Character save state metadata |
| `captured_drills.txt` | No | Raw capture logs |
| `vs_*.fs` | No | Binary FBNeo save states (user-specific, ROM-dependent) |
| `reference/` | No | Prior art scripts (gitignored) |

## Controls

### Character Select (on script load)
- **D-Pad** — Navigate character grid (4×5)
- **Start** — Toggle character select overlay (hide to play, show to save/load)
- **Jab (P1 Weak Punch)** — Load saved state for selected opponent
- **Fierce (P1 Strong Punch)** — Save current game state for selected opponent

### Training Mode
- **Start** — Open/close drill menu
- **Left/Right** — Switch tabs (Drills / Opponent)
- **Up/Down** — Navigate drills
- **Jab (P1 Weak Punch)** — Select drill / Change opponent (in Opponent tab)
- **Strong (P1 Medium Punch)** — Back / Close menu
- **Fierce (P1 Strong Punch)** — Delete custom drill (in Drills tab, press twice to confirm)
- **Weak Kick** — Toggle drill side (L/R)
- **Coin** — Toggle record-to-drill capture (records combo → creates playable drill)
- **Alt+2** — Toggle numpad notation
- **Alt+3** — Reset current drill progress
- **Alt+4** — Toggle debug display
- **Alt+5** — Toggle menu (reliable backup for Start)
- **Alt+9** — Reload custom drills (after editing `urien_lab_custom_drills.txt`)

## Conventions
- All colors are RRGGBBAA 32-bit hex (FBNeo convention, e.g. `0xFF0000FF` = red, full opacity)
- Move IDs are built as `prefix .. sub(4hex) .. id(4hex)` strings (or `prefix .. id(4hex)` for F-type)
- Screen coordinates: 384×224 native CPS3 resolution
- Character IDs match the game's internal numbering (0=Gill through 19=Remy)
- Save state files: `vs_CharName.fs` (e.g., `vs_Yun.fs`, `vs_Ken.fs`)
- Single-file architecture by design (FBNeo Lua has no `require`)
