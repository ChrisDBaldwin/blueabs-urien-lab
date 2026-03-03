# Current State

## User Flow

1. Script loads → loads `character_select.fs` (downloads from voidtalker.com if missing) → game's native character select screen
2. Player picks P1 and P2 characters, both lock in → fast-forwards to match start
3. In training mode, press Start to open exercise menu, select a combo to practice
4. Alt+1 returns to character select at any time

## What Works

- Exercise system with built-in curriculum, record-to-exercise capture, mastery tracking
- Four exercise categories: combo, unblockable, sequence, parry
- Always-on training environment (timer, meter, health, stun, dummy management)
- Charge meters for horizontal and vertical charge with decay timers (labels follow notation mode)
- Per-opponent save states with visual character select grid
- Game character select integration (native char select screen with timer freeze and fast-forward)
- Three-tab menu (All / Character / Opponent), dual notation, live combo tracker
- Opponent tagging, exercise side toggle (L/R), timing feedback on cancel windows (color-coded: green/yellow/orange)
- Exercise deletion from menu, editable exercise files with hot-reload (Alt+9)
- Manifest-based content sync from voidtalker.com (`manifest.txt` checked on boot for script version, exercise version, and available save states)
- Auto-update from GitHub (downloads script and exercises only when manifest indicates newer versions)
- Save state distribution from voidtalker.com (downloads `character_select.fs` and `vs_*.fs` on demand, validated against manifest)
- Custom exercise file separation (`urien_lab_custom.txt` — never overwritten by updates)
- Konami code easter egg (enables turbo charge — continuous charge fill during exercises)

## What's Missing

- **Content:** Curriculum is thin; no defensive exercises (parry category exists but no attack playback); move database has gaps
- **Matchup-specific content:** Opponent tagging exists, punish exercises per character are missing
- **Community exercises:** No submit/review/distribute pipeline yet

## Invariants (must not break)

These are regression-critical behaviors. Violating any of these will silently break training.

1. **Memory writes in `gui.register()`, never `emu.registerbefore()`.** The game overwrites memory between `registerbefore` and `gui.register`. Timer, HP, meter, and stun writes must go in `on_gui()`.

2. **Always-on training resources run every frame** when game phase = playing, regardless of exercise state:
   - Round timer frozen at 99 (write `100` to `0x02011377`)
   - Super meter refills to max after 90 frames of no input and no active combo (`METER_REFILL_DELAY_FRAMES`)
   - Stun cleared after 40-frame delay once combo drops (`STUN_RESET_DELAY_FRAMES`)
   - P2 kept alive during combos (min `0x10` HP)
   - HP recovers after combo drops with configurable delay (20 frames) and speed (+8/frame)

3. **Combo counter drop triggers FAIL.** When combo counter goes from >0 to 0, the exercise fails — unless `allow_combo_reset` is set (for multi-combo Aegis setups where the counter legitimately resets between sequences).

4. **Action ID `0x2000` flag always stripped.** `build_action_string()` strips the connected-hit flag with `action_id % 0x2000`. IDs must match the clean values in the MOVES database. `normalize_action_string()` does the same for stored strings.

5. **Multi-hit moves collapse to single sequence step** in the exercise builder. Dedup by action string — consecutive hits with the same action ID become one entry.

6. **N/M/G/T-prefix entries filtered out** of built exercises. These are state transitions (neutral, misc, guard, throw), not player moves. The builder auto-sets `allow_combo_reset` when it filters these.

7. **Custom exercises live in `urien_lab_custom.txt`**, shipped exercises in `urien_lab_exercises.txt`. Auto-update replaces the shipped file only. Custom file is never overwritten.

8. **Exercise file format is backward compatible.** New fields (TIMING, RESETOK, CHARS) are optional on parse. Old exercise files still load fine.

9. **Save state rename dance.** FBNeo requires numeric slot IDs. Save: create temp slot 99999 → `savestate.save()` → `os.rename()` to `vs_CharName.fs`. Load: `os.rename()` to temp → `savestate.load()` → rename back. Both directions use this pattern. Metadata tracked in `urien_lab_characters.txt` (CSV: `id,name,saved`).

10. **`input_current` read once per frame** via `read_input()` at top of `on_frame()`. All input checks (`is_pressed`, `is_held`) use the snapshot. Never call `joypad.get()` directly elsewhere.

11. **Exercises from both files merge into one list.** Custom exercises use `c_XX` ID prefix, shipped use `t_XX`. The exercise counter tracks the max custom ID to avoid collisions.

12. **Exercise categories as group headers.** Categories (`combo`, `unblockable`, `sequence`, `parry`) appear as section dividers in the menu. Category defaults to `combo` if omitted.

## Controls

### Character Select (on script load)

| Input | Action |
|-------|--------|
| D-Pad | Navigate character grid |
| Jab (P1 Weak Punch) | Load saved state for selected opponent |
| Fierce (P1 Strong Punch) | Save current game state for selected opponent |

### Training Mode

| Input | Action |
|-------|--------|
| Start | Open/close exercise menu |
| Left/Right | Switch menu tabs (All / Character / Opponent) |
| Up/Down | Navigate exercises |
| Jab (P1 Weak Punch) | Select exercise (Opponent tab: return to character select) |
| Strong (P1 Medium Punch) | Stop exercise / Close menu |
| Fierce (P1 Strong Punch) | Cycle sort mode (Category / Difficulty / Name) |
| Roundhouse (P1 Strong Kick) | Delete exercise (press twice to confirm) |
| Weak Kick | Toggle exercise side (L/R) |
| Medium Kick | Tag/untag current opponent on highlighted exercise |
| Coin | Toggle record-to-exercise capture |

The menu displays a button guide at the bottom: **MP=Stop, HP=Sort, LK=Side, MK=Tag, HK=Del**.

### Hotkeys (Alt+N)

| Key | Action |
|-----|--------|
| Alt+1 | Return to character select at any time |
| Alt+2 | Toggle numpad notation |
| Alt+3 | Reset current exercise progress |
| Alt+4 | Toggle debug display |
| Alt+5 | Toggle menu (reliable backup for Start) |
| Alt+6 | Quick save matchup to current slot (legacy) |
| Alt+7 | Show current matchup slot name (legacy) |
| Alt+9 | Reload exercises (after editing file) |

### Secret

Konami code (Up Up Down Down Left Right Left Right Weak Kick Weak Punch Start on P1) toggles turbo charge — continuous charge fill during exercises.

## Record-to-Exercise Flow

1. Press **Coin** during a match to start recording (pauses any active exercise)
2. Perform a combo — the capture system records hits and joypad inputs each frame
3. Press **Coin** again to stop — the system automatically builds a playable exercise:
   - Known moves identified via `lookup_move_name()` against the MOVES database
   - Unknown moves get notation inferred from joypad edge detection (`detect_motion` + `detect_button`)
   - Multi-hit moves collapsed into a single sequence step
   - N/M/G/T-prefix entries filtered out (state transitions, not player moves)
4. A category selector popup appears (COMBO / UNBLOCKABLE / SEQUENCE / PARRY) — Up/Down to pick, Jab to confirm, Start or Coin to cancel (defaults to COMBO)
5. Exercises persist to `urien_lab_custom.txt` and reload on script restart
6. To rename: edit the `NAME:` line in `urien_lab_custom.txt` and press **Alt+9** to reload
7. Delete: highlight in menu, press Roundhouse (HK) twice to confirm
