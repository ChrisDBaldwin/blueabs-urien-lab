# Desired State

## Content Sync from voidtalker.com

One Lua file. Download it, load it in FBNeo, the script fetches everything it needs on launch. No zips, no repos, no manual file management.

### Approach

1. Script fetches a manifest from `voidtalker.com/urien-lab/manifest.json`
2. Compares against local files, downloads what's new or missing
3. Works offline from cached files if network is unavailable

### Technical

FBNeo Lua has `os.execute`. Windows: PowerShell `Invoke-WebRequest`. Linux/Mac: `curl`.

### Outcomes

- Save state distribution (new users never touch `.fs` files)
- Updated curriculum — push exercise updates, everyone gets them
- Script auto-update
- Community exercises: submit, review, ship
- Character expansion (same infrastructure for future labs)

### First Step

On first launch, if `character_select.fs` is missing, fetch it from voidtalker.com.

---

## Future Features

- **Defensive exercises** — parry category exists, but needs recorded attack playback so the dummy performs a sequence for the player to parry
- **Matchup-specific curriculum** — punish exercises per opponent (opponent tagging is in place, content is missing)
- **Multi-character support** — abstract character-specific parts (moves, exercises, charge meters)
- **Community exercise exchange** — submit, curate, distribute
