# Desired State

## Content Sync from voidtalker.com

One Lua file. Download it, load it in FBNeo, the script fetches everything it needs on launch. No zips, no repos, no manual file management.

### Status: Manifest implemented

`manifest.txt` at `voidtalker.com/urien-lab/manifest.txt` — fetched once on boot, drives all sync decisions:
- Script version check (downloads from GitHub only when manifest says newer)
- Exercise version check (decoupled from script updates)
- Save state availability list (avoids blind 404s on download)

### Remaining

- Community exercises: submit, review, ship
- Character expansion (same infrastructure for future labs)

---

## Future Features

- **Defensive exercises** — parry category exists, but needs recorded attack playback so the dummy performs a sequence for the player to parry
- **Matchup-specific curriculum** — punish exercises per opponent (opponent tagging is in place, content is missing)
- **Multi-character support** — abstract character-specific parts (moves, exercises, charge meters)
- **Community exercise exchange** — submit, curate, distribute
