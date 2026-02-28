# Blueabs Urien Lab

A Lua training script for **Urien** in **Street Fighter III: 3rd Strike**, running on the [FBNeo](https://github.com/finalburnneo/FBNeo) emulator.

Practice combos through a curriculum-driven exercise system — from basic normals and charge specials through tackle loops to advanced Aegis Reflector unblockable setups. Record your own combos and turn them into replayable exercises with automatic move detection and notation.

## Features

- **Exercise curriculum** — Exercises organized by category (combo, unblockable, sequence, parry) with progression tracking and mastery (3 completions = mastered)
- **Record-to-exercise** — Press Coin during a match to record a combo. The system identifies moves, detects input notation (charge, QCF, etc.), and builds a playable exercise automatically
- **Per-character save states** — Save/load game states for each of the 19 opponents via a visual character select grid
- **Live combo tracker** — Real-time move name display during free practice, independent of the exercise system
- **Always-on training resources** — Infinite round timer, full super meter, stun cleared, delayed HP recovery after combos drop
- **Multi-combo exercise support** — Aegis Reflector setups that involve multiple combo sequences (combo counter resets between parts) are fully supported
- **Dual notation** — Toggle between Street Fighter notation (`b~f+MK`) and numpad notation (`[4]6MK`)
- **Character-specific exercise tagging** — Tag exercises for specific opponents (MK in menu); the exercise list filters by current opponent so you only see relevant combos. Recorded exercises auto-tag with the current opponent
- **Exercise persistence** — Exercises save to a human-editable text file; rename combos or tweak hints in a text editor, then reload in-game with Alt+9

## Requirements

- [FBNeo](https://github.com/finalburnneo/FBNeo) emulator (with Lua scripting support)
- SF3: 3rd Strike ROM (`sfiii3`)

## Installation

1. Clone or download this repository
2. Place `urien_lab.lua` somewhere accessible to FBNeo (e.g., next to the emulator or in a scripts folder)
3. Launch FBNeo and load the `sfiii3` ROM
4. Open the Lua console: **Game > Lua Scripting**
5. Load `urien_lab.lua`

The script will auto-load the first available save state and show the character select grid.

## How to Use

### First-Time Setup (per opponent)

1. Start a match as **Urien** vs your chosen opponent in-game
2. Press **Start** to show the character select overlay
3. Navigate to the opponent in the grid with **D-Pad**
4. Press **Fierce (Strong Punch)** to save the current match state

After saving, you can load that opponent's state any time with **Jab (Weak Punch)**.

### Practicing Exercises

1. With a match loaded, press **Start** to open the exercise menu
2. Use **Up/Down** to browse exercises, **Left/Right** to switch between the Exercises and Opponent tabs
3. Press **Jab** to select an exercise
4. The script positions both characters and waits for you to perform the combo
5. Hit the moves in order — the HUD shows your progress through the sequence
6. On success: "CLEAR!" banner, progression updated. On failure: reason displayed, try again

### Recording Exercises

1. During a match, press **Coin** to start recording
2. Perform any combo
3. Press **Coin** again to stop recording
4. The system automatically builds an exercise — it appears in the exercise menu under the COMBO category
5. Exercises persist across sessions in `urien_lab_exercises.txt`

To rename an exercise, edit the `NAME:` line in `urien_lab_exercises.txt` and press **Alt+9** in-game to reload.

### Controls

#### Character Select

| Input | Action |
|-------|--------|
| D-Pad | Navigate character grid |
| Start | Toggle overlay (hide to play, show to save/load) |
| Jab (Weak Punch) | Load saved state for selected opponent |
| Fierce (Strong Punch) | Save current match state for selected opponent |

#### Training Mode

| Input | Action |
|-------|--------|
| Start | Open/close exercise menu |
| Up / Down | Navigate exercise list |
| Left / Right | Switch tabs (Exercises / Opponent) |
| Jab (Weak Punch) | Select exercise / Change opponent |
| Strong (Medium Punch) | Stop exercise / Close menu |
| Fierce (Strong Punch) | Delete exercise (press twice to confirm) |
| Weak Kick | Toggle exercise side (L/R) |
| Medium Kick | Tag/untag current opponent on highlighted exercise |
| Coin | Toggle record-to-exercise capture |

#### Hotkeys

| Input | Action |
|-------|--------|
| Alt+2 | Toggle notation (SF / Numpad) |
| Alt+3 | Reset current exercise progress |
| Alt+4 | Toggle debug display |
| Alt+5 | Toggle menu (reliable backup for Start) |
| Alt+9 | Reload exercises from file |

## Exercise File Format

Exercises are stored in `urien_lab_exercises.txt` as line-oriented key:value blocks:

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
RESETOK:1
HINT:d+HP -> b~f+LK
---
```

| Key | Description |
|-----|-------------|
| `ID` | Unique exercise identifier (`c_01`, `c_02`, ...) |
| `NAME` | Display name (editable) |
| `NOTATION_SF` / `NOTATION_NP` | Street Fighter / numpad notation strings |
| `DIFFICULTY` | 1-5 rating |
| `CATEGORY` | Exercise category: `combo`, `unblockable`, `sequence`, or `parry` (default: `combo`) |
| `CHARS` | (Optional) Comma-separated opponent names to restrict exercise to (omit = universal) |
| `SETUP` | `p1_x,p2_x,p1_life,p2_life,meter,h_charge,v_charge,p2_state,corner` |
| `SEQ` | Pipe-separated sequence steps: `name,hit_type,action_id[;action_id]` |
| `SUCCESS` | Minimum combo count required |
| `TIMEOUT` | (Optional) Frames before auto-fail |
| `RESETOK` | (Optional) `1` = allow combo counter resets mid-sequence (for Aegis setups) |
| `HINT` | (Optional) Execution hint displayed during exercise |

## Architecture

The script is a single-file Lua program (`urien_lab.lua`, ~3000 lines) organized into numbered sections:

| Section | Purpose |
|---------|---------|
| [1] | Constants, colors, timing configuration, exercise categories |
| [2] | CPS3 memory address map |
| [2b] | Character roster, grid layout, app state |
| [3] | Move database (24 Urien moves with dual notation) |
| [4] | Exercise definitions |
| [5] | Progression tracking, save/load |
| [6] | Utility functions |
| [7] | Game state reader (per-frame memory polling) |
| [8] | Dummy controller (P2 management, resource recovery) |
| [9] | Exercise engine state machine (IDLE/SETUP/ACTIVE/SUCCESS/FAIL) |
| [10] | Input display and notation toggle |
| [11a-c] | Save states, HUD/menu, capture system, exercise builder, persistence |
| [12] | Input handlers |
| [13] | FBNeo hooks, hotkeys, initialization |

Two-level state machine:
- **App level:** `APP_CHARSELECT` / `APP_TRAINING` — controls character select vs training HUD
- **Exercise level:** `IDLE` / `SETUP` / `ACTIVE` / `SUCCESS` / `FAIL` — manages individual exercise execution

## Acknowledgments

This project builds on foundational work from the SF3:3S Lua scripting community:

- [**3rd_training_lua**](https://github.com/Grouflon/3rd_training_lua) by Grouflon — Multi-character training mode framework for FBNeo. Provided the memory address map, drawing conventions, and resource management patterns used throughout this script.
- [**SF3 3rd Strike Trial Script**](https://ameblo.jp/3fv/entry-12747992757.html) by 3fv — Combo trial system that established the action ID format and hit detection approach adapted here for exercise sequence matching.

## How to Contribute

### Reporting Issues

Open an issue on GitHub with:
- What you were doing (which exercise, which opponent, etc.)
- What happened vs what you expected
- Any error messages from the FBNeo Lua console

### Adding Exercises

The easiest way to contribute is to add new exercise definitions:

1. Use the record-to-exercise system (Coin) to capture a combo
2. Test that it works reliably
3. Edit `urien_lab_exercises.txt` to clean up the name, hint, and category
4. Submit a PR adding your exercise definitions

### Adding Moves to the Database

If the combo tracker shows `spc?XXXX` or `atk?XXXX` for a move, that action ID is missing from the `MOVES` table. To add it:

1. Enable debug display (Alt+4) and perform the move
2. Note the action string shown (e.g., `S003e003e`)
3. Add an entry to the `MOVES` table in `urien_lab.lua`:
   ```lua
   ["MoveName"] = { action_ids = {"S003e003e"}, type = "special", sf = "qcf+LP", numpad = "236LP" },
   ```
4. Submit a PR with the new entry

### Code Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes to `urien_lab.lua`
4. Test in FBNeo with the `sfiii3` ROM — verify exercises still work, save/load still works, and your feature behaves correctly
5. Submit a pull request with a description of what changed and why

**Key things to keep in mind:**
- The script is a single file by design (FBNeo Lua limitation — no `require`)
- Memory writes that need to persist must go in `gui.register()`, not `emu.registerbefore()`
- Action IDs use the format `prefix + sub(4hex) + id(4hex)` for S/A types, or `prefix + id(4hex)` for F types
- All colors are RRGGBBAA format (FBNeo convention)
- Test both the character select flow and exercise execution after any change

## License

This project is provided as-is for the fighting game community. See the repository for license details.
