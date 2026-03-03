# Architecture Intent

## Single File

FBNeo Lua has no `require`. One file is the constraint and the distribution model.

## Section Organization

Numbered sections form a dependency chain — later sections depend on earlier ones, never the reverse.

| Layer | Sections | Role |
|-------|----------|------|
| Data | [1], [1b], [2]-[4] | Constants, update/distribution, memory map, moves, exercise definitions |
| Infrastructure | [5]-[8] | Progression, utilities, game state, dummy controller |
| Engine | [9]-[10] | Exercise state machine, input display |
| Application | [11a]-[11c4] | Save states, HUD/menu, capture/builder/persistence |
| Glue | [12]-[13] | Main loop callbacks, hook registration |

Note: the source has a duplicate `[11b]` label — the first is HUD & Menu, the second is Exercise Capture (should be `[11c]`).

## Frame Callback Split

- `emu.registerbefore()` → `on_frame()`: Before game logic. Input, state machines, dummy control.
- `gui.register()` → `on_gui()`: After game logic. Drawing, memory writes that must persist.

This split is load-bearing. Memory writes in `on_frame()` get overwritten by the game.

## Exercise Data Format

Exercises are pure data — the engine is generic. Hand-authored and machine-captured exercises use the same format and the same file. This is what makes record-to-exercise and content sync possible.

## Save State Architecture

FBNeo requires numeric slot IDs. The script uses a temp slot (99999), then renames to descriptive names (`vs_Ken.fs`). Load: rename to temp → API load → rename back.
