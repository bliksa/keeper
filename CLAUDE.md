# Keeper of the Cycle — working on the Godot port

The game is developed **by prompts, without the Godot editor**. Everything is
plain text (GDScript, JSON, level text). Every push builds the game for the
web and deploys it to GitHub Pages, so changes are tested in a browser.

## Layout

```
godot/                     Godot 4.4.1 project (GL Compatibility, 1066×600)
  project.godot            minimal engine config (autoloads, window)
  scenes/main.tscn         the only real scene — everything else is built in code
  scripts/main.gd          game flow / state machine (boot → title → forest → cave → boss → garden)
  scripts/autoload/        Game (state + input actions), Text (strings, dialogs, fonts), Audio
  scripts/screens/         boot, title, forest_intro, platformer (cave + boss; garden + LH wave)
  scripts/minigames/       breathing, choco_puzzle (mg2), pipes (mg3), prices (mg4),
                           iron_plate (mg5), rhythm (mg6), signals (mg7) — level 2
  scripts/ui/              dialog_box, platformer_hud, player_art (sprite anim), draw helpers
  scripts/dev/             dev_menu + level_editor (in-game, DEV button on the first/boot screen)
  scripts/level_data.gd    level text → platforms/entities (THE LEGEND lives here)
  data/levels/cave.txt     the cave level, one text row per 120 px band, 25 columns
  data/levels/garden.txt   level 2 (climbed upwards: spawn at the bottom, summit E at the top)
  docs/                    GDD drafts (gdd_levely_fazy_cyklu.md = level 2 design, implemented)
  data/dialogs.json        dialog nodes (parts, speaker, buttons), voice overrides, letter→dialog map
  data/i18n/{en,sk,pt}.json  all strings; <KB>…</KB> keyboard-only, <GP>…</GP> gamepad-only
  assets/                  images, audio, font (from the web prototype)
  tests/test_runner.gd     headless end-to-end test — plays the whole game
web-export/                the original vibe-coded web build (reference only — do not edit)
tools/                     setup_godot.sh, test.sh, export_web.sh
.github/workflows/web.yml  test → export → deploy to GitHub Pages (site/ + site/original/)
```

## Common edits

- **Level**: edit `godot/data/levels/cave.txt` (or `garden.txt`). `.` = empty.
  Legend is in the header of `scripts/level_data.gd` (`=` platform, `O` iron,
  `^` spike, `S/F/J/C` cramps, `P` spawn, `2/3/4` minigames, `5` boss, `a–z`
  dialogs; level 2: `@` bubble, `%` popping bubble, `~` updraft, `N` distraction,
  `6/7/8` minigames, `9` LH wave, `E` summit). Keep 25 columns. Minigame / boss /
  wave / summit triggers span the whole row. `Game.LEVELS` maps level id → file.
- **Dialog text**: change the string in `data/i18n/*.json` (all three languages).
  New dialog = add node in `data/dialogs.json` + keys in every i18n file;
  voice = `assets/audio/<KEY>.wav` (or `voice_overrides`).
- **Dialog trigger in the level**: put a lowercase letter in the level and map it
  in `letter_dialogs` in `data/dialogs.json`.
- **Physics / feel**: constants at the top of `scripts/screens/platformer.gd`
  (gravity, jump, speed). Values match the web build, scaled per frame by `dt60`.
- **Flow** (what happens after a trigger/minigame): `scripts/main.gd`.
- **Input**: actions are created in code in `scripts/autoload/game.gd`.

## Conventions

- Don't add nodes to `.tscn` files; build nodes in `_ready()` like the existing scripts.
  New screen = new script with `class_name`, instantiated from `main.gd`.
- GDScript is typed. `:=` on a Variant value is a **compile error** in this
  project (e.g. `var x := dict.value` → use `var x: float = dict.value`;
  use `floorf/absf/minf/maxf/clampf` instead of `floor/abs/min/max/clamp`).
- Textures wider than 8192 px don't load in some browsers — keep
  `process/size_limit=4096` in their `.import` file (see `back.png.import`).
- Coordinates are in the 1066×600 virtual screen (same as the web build).
- Keep `web-export/` untouched; it is the reference implementation.

## Verify every change

```
tools/test.sh         # imports the project, fails on script errors, runs tests/test_runner.gd
tools/export_web.sh   # builds build/web (serve with: python3 -m http.server -d build/web 8000)
```

`tools/setup_godot.sh` installs Godot 4.4.1 + web templates into the user's cache
(the SessionStart hook runs it automatically). If you change game flow, extend
`tests/test_runner.gd` so the new path is played through. For visual changes, export
and look at the page in Chromium (Playwright is preinstalled in cloud sessions).

After push, GitHub Actions deploys to `https://bliksa.github.io/keeper/`
(original prototype at `/original/`).

## Animation lab (Developer mode → Animations)

`scripts/dev/anim_lab.gd` previews every player animation (`PlayerArt.ANIMS`: idle,
walk, run, jump, sidejump, doublejump, fall, lookdown, sit, pain, dead, hang) on the
real renderer (`PlayerArt.overrides`).

The UI has three parts:
- an animation dropdown;
- a variant dropdown with new / duplicate / rename / delete;
- a frame list with pick-from-assets / upload / move / remove per frame, plus
  "Upload frames…" and "From assets…".

The asset browser (`open_assets`) lists repo images via
`ResourceLoader.list_directory` (`assets/images`, `assets/anim_test/**`) plus
uploads in `user://anim_uploads/`. Picked repo files are referenced by `res://`
path, not copied. Space toggles pause in Animation mode. The icon at the top right
of the preview picks a preview background from the same browser (`stage_bg`, kept
in the browser only).

`data/anim_variants.json` has three keys:
- `anims`: anim → variant → [res:// frame paths];
- `in_game`: anim → variant used by the game, applied at start-up by
  `PlayerArt.load_game_defaults()`;
- `settings`: scale, anim_fps, run_rate.

To add PNGs the user sends in chat:

```
tools/add_anim_variant.py run "<variant name>" path/to/*.png [--in-game]
tools/add_anim_variant.py fall "<variant name>" fall*.png
```

The script copies the files into `assets/anim_test/<anim>/<slug>/` and updates the
manifest. Then run `tools/test.sh` and push. Frames are scaled to the same
on-screen height as the originals (85 px × scale). The feet should sit at the same
place in the canvas as in the original frames.

Uploads in the browser go to `user://anim_uploads/` (IndexedDB, local only) until
the user clicks **Save to repo**.

## Saving from the browser (GitHub commits)

`scripts/dev/github_save.gd` (`GitHubSave`) commits files through the GitHub Git
Data API with a fine-grained token the user pastes once (stored in
`user://github_token`, only in that browser).

There are two callers:
- the animation lab commits PNGs plus a merged `data/anim_variants.json`;
- the level editor header commits `data/levels/cave.txt`.

Commits land on the repo's default branch and trigger the deploy. **Run `git pull`
before editing**, because the branch may contain commits made from the browser.
For a local mock API, set `GitHubSave.api_base`, or use `?gh_api=` on the web.

## Level 2: the meadow (follicular phase, horizontal)

Same `Platformer` with `level_id = 2` (`is_meadow()`, `level.horizontal`): the
camera follows `camera_x`, `level_w` is the row length × `CELL_W`. Mechanics in
`_update_meadow`: the river (`level.water_top`; falling in = `river_timer`, then
back to `last_ground`, −10 water), the vessel (`Game.water`, `water_unlock(name)`:
run 25 / double 50 / thread 75, `_max_jumps()`), light seeds (entity `seed`, `tier`
0–3 by x order; the focus thread: `begin_focus` / `end_focus`, `aim` + `aim_mode`
mouse / keys / stick, `_acquire_seed`, `thread_target`, `CATCH_DIST`), shadows
(`shadows`, spawn while a seed is on the thread, a hit = −15 water and
`Game.gate_shift` += 3 cells, trigger `stress_hit`), the gate (`gate`, locked =
`gate_locked_timer` then re-armed when the player steps away; open = `meadow_end`
sequence → trigger `meadow_done`). HUD: `_draw_meadow` (seeds + vessel). Flow in
`main.gd`: `boss_win` → `_walk_to_meadow` (scripted walk, white fade) →
`_start_meadow`; `_mg8_done`…`_mg10_done`; `meadow_done` → `meadow_end` dialog →
`_start_summit`. Dialog letters b/c/d/e/f → `meadow_*` nodes; speaker `Iskra`
gets a code-drawn portrait (`DialogBox._portrait`). Strings `DIA_M*`,
`MG8_*`–`MG10_*`, `ROOM_*`, `BAG_*`, `MARKET_*`, `SIG_*` / `EXP_*` / `HINT_*`.

## Level 3: the summit (ovulation)

Same `Platformer` with `level_id = 3` (`is_summit()`): an Icy Tower style climb
(`SUMMIT_SPEED` / `SUMMIT_ACCEL`, wall jump via `on_wall` + `WALL_KICK`, `combo`
for landings higher than `last_landing_y`, shown in the HUD; `garden.txt` is
generated as short alternating platforms), climbed upwards, procedural
dusk→morning background (`_draw_garden_bg`, by `_climb()`), bubble platforms
(`Plat.kind` bubble/pop, `_pop_bubble`), updrafts (entity `updraft`), distractions
(enemy behaviour `distract`: slow, no iron loss), power-ups in `Game.upgrades`
(`jump`, `dash` on the `run` action = Shift, `double`; see `_jump_force`), and the
LH wave chase (`start_wave`, `_update_wave`, trigger `wave_lost`; `summit` ends the
level). Checkpoints 1–5 use `LevelData.PROGRESS[3]`; `_stand_at_trigger` puts the
player on the trigger row's platform (or column, in the meadow). Flow in
`main.gd`: `_start_summit(1, iron)` after the meadow; `_mg5_done`…`_mg7_done`;
`garden_end` → title.
Dialog letters g/h/k/m/n → `garden_*` nodes; strings `DIA_G*`, `MG5_*`–`MG7_*`.

## Backup of the game before level 2

Branch `backup/v1-jaskyna` (commit pinned as `V1_SHA` in `.github/workflows/web.yml`)
is built into the site at `/v1/`. Branch `backup/v2-zahrada-hore` holds the first
level-2 draft (the upward garden, now level 3). Tags cannot be pushed from
sessions (403).

## Pause menu

`Esc` / gamepad Start during play (forest, cave, minigames) opens
`scripts/ui/pause_menu.gd`: Continue, Restart game (fresh run from the forest),
Fullscreen on/off, Main menu. It uses `get_tree().paused`; the menu itself runs with
`PROCESS_MODE_ALWAYS`. Async steps in `main.gd` check `_run_id` so a fade
started before a restart can't act on the new run.

## Debug shortcuts (in the cave)

`1–4` restart at checkpoint · `Shift+2…5` jump to minigame / boss / gate / LH wave
trigger · `5` boss (meadow: gate, summit: wave) · `H` meadow with a full vessel ·
`G` summit with all power-ups · `C` breathing + 20 iron · `X` skip a minigame. Developer mode (DEV on the boot screen) has checkpoints
for both levels, skip-to-boss and the level editor (level picker in the header, paint,
test with Enter, export/import, save to repo).
