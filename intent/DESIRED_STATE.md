# Desired State

## Vision: The Golden Road

Urien Lab is a guided path from "I picked Urien" to "I can play Urien." Not a reference tool, not a sandbox — a tutorial that teaches you everything in the right order.

The goal is progressive accretion. Each exercise builds on the last. The player learns game systems and mechanics *in the order they need them* to execute Urien's combos. If the progression is clear and the ordering is right, a player who follows the road comes out the other side able to play.

Baby mode to illuminated. Early lessons hold your hand. Things get harder. The endpoint isn't "completed" — it's understanding *why* each piece works.

The curriculum draws heavily from **"Urien Vs. The World"** by Dr. Steelhammer — the definitive Urien guide covering 18 matchups with corner combos, unblockable setups, Aegis strategies, post-throw pressure, and character-specific knowledge. Credit to Dan, RX, RB, rKf, and Kuroda for the match footage and strategies that inform the guide.

Three new systems compose to make this work: **recordings** capture how a combo is performed, **playback** demonstrates it, and **rhythm** visualizes the timing. Each system is useful alone; together they let the player see, hear, and feel a combo before attempting it.

---

## The Road (Five Tiers)

1. **Fundamentals** — What is charge? What is canceling? What is linking? Exercises that isolate each mechanic before combining them.
2. **Basic Confirms** — Simple hit-confirms into specials. cr.HP xx Tackle, low confirms, jump-in combos. One cancel window, one charge direction.
3. **Intermediate** — Multi-hit sequences, tackle loops, toward-throw-headbutt (TTH), corner carry, charge partitioning.
4. **Aegis** — Setups, unblockables, sweet spot positioning, midscreen Aegis, multi-bar sequences.
5. **Matchup Application** — What works on who, and when. Character-specific combos, punishes, and setups from UVSTW. Urien's punishes are layered — what connects on one character whiffs on another, and the situations where each combo applies don't line up the way you'd expect.

---

## Systems

### Input Recordings

Shared primitive enabling demo playback and rhythm visualization.

- Captured during the record-to-exercise flow (the capture system already logs per-frame joypad input)
- Stored in `urien_lab_recordings.txt`, separate from exercise definitions
- Joined to exercises by ID (one recording per exercise)
- Delta-encoded hex bitmask format: each frame stores only changes from the previous frame
- Keeping recordings in a separate file preserves exercise file readability and hand-editability
- Recordings are optional — exercises work without them (they just can't demo or show rhythm)

### Playback Engine (Demo Mode)

Plays back a recording to demonstrate a combo.

- State machine: `IDLE` → `SETUP` → `RUNNING` → `DONE`
- Reads recording frame-by-frame, drives P1 inputs via `joypad.set()` each frame
- Exercise engine runs concurrently — validates the demo just like a human attempt
- "DEMO" indicator displayed on screen
- Press any button to exit demo and switch to practice mode
- Demo option grayed out when exercise has no recording; player sees text hint instead
- Recordings added over time as content is captured — not a blocker for exercise authoring

### Rhythm Timeline

Visual timing guide displayed at the bottom of the info bar.

- Replaces the hint line when active (toggleable, Alt+8 or similar)
- Two tracks: direction arrows (stick/d-pad) and button indicators (colored abbreviations)
- NOW marker at ~25% from left edge
- Past inputs dimmed, current input bright, future inputs visible ahead
- Auto-scrolls in demo mode (synced to playback frame)
- Progress-synced in practice mode (advances as player hits sequence steps)
- Requires a recording to display — no recording means hint text shown instead

### Multi-Phase Exercises

Enables combos that span multiple combo-counter sequences.

- `||` delimiter in SEQ field separates phases
- Combo counter is allowed to reset between phases without triggering failure
- Supports position-check phases for Aegis spacing verification
- Enables exercise types that the current single-phase engine can't express:
  - Unblockable setups (combo → Aegis placement → second combo)
  - Post-throw meaty sequences (throw → dash → meaty attack)
  - Multi-bar Aegis sequences (first Aegis combo → second Aegis combo)
- Backward compatible: exercises without `||` behave exactly as today

### Dummy Enhancements

Extended dummy behavior for setup exercises.

- `DUMMY_SEQ` field for multi-input P2 sequences (beyond single-button `DUMMY_ATTACK`)
- Knockdown state tracking for meaty timing exercises
- Position hold for Aegis setup exercises (dummy stays put during placement)

### Unblockable Validation

Verifies that unblockable setups are truly unblockable and that the follow-through connects.

- Dummy set to block during validation — if the setup is correctly unblockable, the attack lands despite block input
- Two-stage validation: setup phase (Aegis placement + positioning) and follow-through phase (the attack that hits)
- Feedback distinguishes setup failures (wrong spacing, wrong Aegis strength) from follow-through failures (mistimed attack, wrong combo route)
- Works with multi-phase exercises — setup is phase 1, follow-through is phase 2
- Character-specific pass/fail: some setups are unblockable on certain characters only (hitbox/hurtbox differences)

---

## Tutorial Curriculum

### Existing Chapters (1-5)

| Ch | Name | Lessons | Content |
|----|------|---------|---------|
| 1 | Normals | 21 | All standing, crouching, jumping normals + UOH |
| 2 | Blocking | 3 | Stand block, crouch block, block-punish |
| 3 | Special Moves | 4 | Tackle, Headbutt, Sphere, Knee Drop |
| 4 | EX Moves | 4 | EX Tackle, EX Headbutt, EX Knee Drop, EX Sphere |
| 5 | Aegis Reflector | 4 | LP/MP/HP Aegis, cr.HP xx Aegis cancel |

### New Chapters (6-15+)

| Ch | Name | Prereqs | Content |
|----|------|---------|---------|
| 6 | Charge Fundamentals | Ch 3 | Charge timing windows, charge partitioning basics, maintaining charge during movement, back-charge vs down-charge isolation |
| 7 | Cancel Windows | Ch 1, 3 | Normal xx Special timing, visual/audio cancel cues, cr.HP xx Tackle as first cancel, cancel timing color feedback |
| 8 | Basic Confirms | Ch 6, 7 | cr.HP xx L.Tackle, cr.LK xx Headbutt, st.MP xx Tackle, jump-in > st.MP > Tackle |
| 9 | Tackle Loops | Ch 8 | cr.HP xx M.Tackle xx M.Tackle, corner carry, charge partition during tackle recovery, TTH (toward-throw-headbutt) |
| 10 | Charge Partitioning | Ch 6, 9 | Midscreen charge partitions (walk-partition-special), partition during dash/whiffed normals, practical midscreen routes that maintain charge, partition timing drills with visual feedback |
| 11 | Corner Combos | Ch 9 | cr.HP xx Tackle xx Tackle xx Headbutt, character-specific corner variants (UVSTW), TTH corner routes |
| 12 | Aegis Basics | Ch 5, 8 | cr.HP xx Aegis > dash > combo, Aegis placement (LP/MP/HP positioning), Aegis timing after knockdown |
| 13 | Aegis Intermediate | Ch 12 | Sweet spot positioning, midscreen Aegis setups, Aegis > throw > Aegis sequences, tackle into Aegis |
| 14 | Aegis Advanced | Ch 13 | Unblockable setups (requires multi-phase + unblockable validation), two-bar Aegis sequences, character-specific unblockable routes from UVSTW |
| 15 | Post-Throw Pressure | Ch 9 | Meaty timing after throw, dash-up options, throw > Aegis setups, kara-throw range |
| 16+ | Matchup Applications | Ch 11+ | Per-character chapters from UVSTW — what combos work on who, character-specific punishes, matchup-specific Aegis setups, full route trees per character |

### Matchup Chapter Coverage (from UVSTW)

Each matchup chapter is tagged to a specific opponent and covers:
- Which standard combos connect (hitbox/hurtbox differences)
- Character-specific corner combos and full route trees (optimal damage paths per starter)
- Unblockable setups that work on this character's wakeup (validated via unblockable validation system)
- Post-throw pressure timing differences
- Punish combos for character-specific unsafe moves
- Midscreen charge partition routes that work at character-specific spacings

Characters covered in UVSTW: Alex, Akuma, Chun-Li, Dudley, Elena, Hugo, Ibuki, Ken, Makoto, Necro, Oro, Q, Remy, Ryu, Sean, Twelve, Yang, Yun.

---

## Implementation Phases

### Phase 0: Recording Capture & Storage
- Hook into existing capture system to preserve per-frame input logs
- Define `urien_lab_recordings.txt` format (delta-encoded hex bitmask)
- Write recording on exercise save, load recordings on script startup
- Join recordings to exercises by ID

### Phase 1: Playback Engine + Live Input Display
- Demo mode state machine (IDLE → SETUP → RUNNING → DONE)
- `joypad.set()` playback from recording data
- Exercise engine validates demo concurrently
- "DEMO" indicator, any-button exit to practice
- Grayed-out demo option when no recording exists

### Phase 2: Rhythm Timeline
- Bottom-strip renderer in info bar (replaces hint line when active)
- Two-track display: directions + buttons
- NOW marker, dimming, auto-scroll
- Toggle hotkey
- Sync modes: frame-locked (demo), progress-locked (practice)

### Phase 3: Multi-Phase Exercise Engine + Unblockable Validation
- `||` delimiter parsing in SEQ field
- Phase transition logic (combo counter reset allowed between phases)
- Position-check phase type for Aegis spacing
- Unblockable validation: dummy blocks during follow-through, system confirms hit landed despite block input
- Character-specific validation (setup may be unblockable on some characters only)
- Backward compatible: single-phase exercises unchanged

### Phase 4: Tutorial Content Authoring (Chapters 6-16)
- Write exercise definitions for each new chapter
- Record demos for each exercise
- Difficulty curve testing and iteration
- Character-specific variants tagged with CHARS field
- Midscreen charge partition library: curate and package shareable partition setups

### Phase 5: Dummy Enhancements
- DUMMY_SEQ parser and playback
- Knockdown state tracking
- Position hold mode

---

## Priorities

1. **Tutorial Curriculum** — Content is king. More exercises on the golden road matter more than any system feature. Chapters 6-10 can be authored with the current engine.
2. **Demo/Rhythm Systems** — Teach by showing. Recordings → playback → rhythm timeline. These compose and each is useful incrementally.
3. **Matchup Curriculum** — Character-specific content from UVSTW. Requires opponent tagging (exists) and multi-phase exercises (Phase 3) for unblockable setups.
4. **Midscreen Charge Partition Library** — Midscreen partitions are underexplored and undertaught. Curate and share practical midscreen partition setups that players can import. These are the kind of routes that don't show up in guides but win rounds.
5. **Community Exercise Exchange** — Players record combos and share them. Submit → review → distribute pipeline. Needs a curriculum to land in, not just a list to append to.

---

## Not Planned

- **Defensive exercises (parry training)** — Other training mode tools handle this better. Urien Lab isn't trying to replace training mode — it's a guided tutorial for Urien's offense.
- **Multi-character support** — Urien Lab teaches Urien. Fork the repo and build an Alex Lab or a Dudley Lab.
- **AI-driven dummy** — Scripted sequences cover the teaching cases. Reactive AI would make exercises non-deterministic and harder to learn from.
