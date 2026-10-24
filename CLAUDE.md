# Keeper of the Cycle — working on the Godot port

The game is developed **by prompts, without the Godot editor**. Everything is
plain text (GDScript, JSON, level text). Every push builds the game for the
web and deploys it to GitHub Pages, so changes are tested in a browser.

## Layout

```
godot/                     Godot 4.4.1 project (GL Compatibility, 1066×600)
  project.godot            minimal engine config (autoloads, window)
  scenes/main.tscn         the only real scene — everything else is built in code
  scripts/main.gd          game flow / state machine (boot → title → forest → cave → boss)
  scripts/autoload/        Game (state + input actions), Text (strings, dialogs, fonts), Audio
  scripts/screens/         boot, title, forest_intro, platformer (cave + boss)
  scripts/minigames/       breathing, choco_puzzle (mg2), pipes (mg3), prices (mg4)
  scripts/ui/              dialog_box, platformer_hud, player_art (sprite anim), draw helpers
  scripts/dev/             dev_menu + level_editor (in-game, Developer mode on the title)
  scripts/level_data.gd    level text → platforms/entities (THE LEGEND lives here)
  data/levels/cave.txt     the cave level, one text row per 120 px band, 25 columns
  data/dialogs.json        dialog nodes (parts, speaker, buttons), voice overrides, letter→dialog map
  data/i18n/{en,sk,pt}.json  all strings; <KB>…</KB> keyboard-only, <GP>…</GP> gamepad-only
  assets/                  images, audio, font (from the web prototype)
  tests/test_runner.gd     headless end-to-end test — plays the whole game
web-export/                the original vibe-coded web build (reference only — do not edit)
tools/                     setup_godot.sh, test.sh, export_web.sh
.github/workflows/web.yml  test → export → deploy to GitHub Pages (site/ + site/original/)
```

## Common edits

- **Level**: edit `godot/data/levels/cave.txt`. `.` = empty. Legend is in the
  header of `scripts/level_data.gd` (`=` platform, `O` iron, `^` spike,
  `S/F/J/C` cramps, `P` spawn, `2/3/4` minigames, `5` boss, `a–z` dialogs).
  Keep 25 columns. Minigame/boss triggers span the whole row.
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

`scripts/dev/anim_lab.gd` previews run/jump frame variants listed in
`data/anim_variants.json` on the real renderer (`PlayerArt.overrides`). When the
user sends new PNGs, add them with:

```
tools/add_anim_variant.py run  "<variant name>" path/to/*.png
tools/add_anim_variant.py jump "<variant name>" jump*.png sidejump*.png doublejump*.png fall*.png
```

(copies into `assets/anim_test/<anim>/<slug>/`, updates the manifest), then run
`tools/test.sh` and push. Frames are scaled to the same on-screen height as the
originals (85 px × scale), so canvas size doesn't matter, but the feet should sit
at the same place in the canvas as in `run1.png`.

## Pause menu

`Esc` / gamepad Start during play (forest, cave, minigames) opens
`scripts/ui/pause_menu.gd`: Continue, Restart game (fresh run from the forest),
Main menu. It uses `get_tree().paused`; the menu itself runs with
`PROCESS_MODE_ALWAYS`. Async steps in `main.gd` check `_run_id` so a fade
started before a restart can't act on the new run.

## Debug shortcuts (in the cave)

`1–4` restart at checkpoint · `Shift+2…5` jump to minigame/boss trigger · `5` boss ·
`C` breathing + 20 iron · `X` skip a minigame. Developer mode (title screen) has
checkpoints, skip-to-boss and the level editor (paint, test with Enter, export/import).
