# Project Intent: Blueabs Urien Lab

## What This Is

A training tool for Urien in Street Fighter III: 3rd Strike. It runs as a Lua script inside the FBNeo emulator and teaches combos, unblockables, and other techniques through a structured, progressive exercise system.

## Who It's For

Players who want to learn Urien to play in Street Fighter III: Third Strike.

## Core Design Principles

1. **Single file, zero setup.** The script is one Lua file. No build step, no dependencies, no `require`. Drop it in, load it, go.

2. **The script manages everything.** Timer, meter, health, positioning, dummy behavior — the player never touches training mode settings. The tool handles the boring parts so the player focuses on execution.

3. **Progressive curriculum.** Exercises are ordered by difficulty. The system tracks completions and mastery so you can see improvement.

4. **Record anything, grind it.** Any combo can become a replayable exercise.

## Current Architecture

Two-level state machine in a single, large Lua file:

- **App level:** `APP_CHARSELECT` (pick opponent) / `APP_TRAINING` (practice combos)
- **Exercise level:** `IDLE` / `SETUP` / `ACTIVE` / `SUCCESS` / `FAIL`

The script hooks into FBNeo's frame callbacks:
- `emu.registerbefore()` — input handling, state machine logic
- `gui.register()` — drawing, memory writes that must persist (timer, HP, meter)

Exercises are defined as data (sequences of moves with setup requirements and success criteria), loaded from a text file, and executed by a generic engine. The exercise format is the same whether hand-authored or machine-captured.

## What Makes It Different

Most FGC training tools are either:
- Frame data apps (passive reference)
- Full training mode replacements (complex, multi-character, config-heavy)

Urien Lab is neither. It's a **guided practice tool** — tells you what to do, watches you do it, tracks your progress. The value is in the exercise set and the order you do them in.
