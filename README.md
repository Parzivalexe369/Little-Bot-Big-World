# Little Bot, Big World

A cozy third-person exploration game built in **Godot 4.7** (GDScript, Forward+).
You play the small pink hover robot from `pink_ball_robot_with_THE_BALL_v2.blend`. It wakes
in an enormous, sleeping garden and brings it back to life, one old machine at a time.

## Running the game

1. Install **Godot 4.7.2** (standard build) from https://godotengine.org. The editor is not
   stored in the repository.
2. Open the project folder in Godot, or run it directly. The repo's helper scripts in
   `tools/` (tests, playtests, captures, exports) expect the Windows editor at
   `tools/Godot_v4.7.2-stable_win64.exe` and `tools/Godot_v4.7.2-stable_win64_console.exe`,
   so copy both there if you use them:

```bash
tools/Godot_v4.7.2-stable_win64.exe --path .
```

The main scene is `scenes/ui/main_menu.tscn`. Godot's import cache (`.godot/`) and exported
builds (`build/`) are not committed, so the first launch imports every asset, which takes a
few minutes.

## Browser version (GitHub Pages, Vercel)

```bash
python tools/build_web.py
```

This builds the game for browsers into `build/web/`, about 200 MB in total with no file over
GitHub's 100 MB limit:
- `index.wasm` (38 MB) is the engine.
- `index.pck` (82 MB) holds the game data with desktop texture formats (S3TC/BPTC).
- `index.mobile.pck` (82 MB) holds the same data with the formats iPad, iPhone and Android
  graphics read (ETC2/ASTC). `index.html` loads the pack the device can read, so each player
  downloads only one; add `?pack=mobile` or `?pack=desktop` to the address to force a choice.

The script works on a temporary copy of the project, so the desktop game keeps its
full-quality assets. The copy gets lighter textures (sci-fi scans 1024 px, garden scans
512 px, terrain layers 768 px) and a few fixes for the browser renderer (WebGL 2); the
script's header lists them all. The build is single-threaded, so it needs no special server
headers. `build/web/` also gets `.nojekyll` (GitHub Pages) and `vercel.json` (Vercel: static
site, no build step).

On an iPad, the game plays with the touch controls (see Controls). In Safari, Share → "Add
to Home Screen" starts it full screen from the home screen, without the browser bars.

To try it locally, serve the folder over HTTP. Opening `index.html` as a file does not work.

```bash
python -m http.server 8060 --directory build/web
```

Then open http://localhost:8060. `python tools/build_web.py --test` also exports test builds
into `build/web_test/` that start directly in the garden or the facility, plus a browser
benchmark (`build/web_test/bench/index.html?scene=world` or `?scene=facility`, from
`tools/web_bench.gd`). The benchmark visits fixed spots and prints frame times and draw calls
to the browser console; add `&exp=shadow,GrassField` to also measure with those switched off.
These builds are for checking only; never deploy them.

**Deploying.** Publish the *contents* of `build/web/` as the site root. This repository
keeps them on a `gh-pages` branch. To update it after a new build:

```bash
git worktree add build/gh-pages gh-pages
cp -r build/web/. build/gh-pages/
git -C build/gh-pages add -A
git -C build/gh-pages commit -m "Update web build"
git -C build/gh-pages push
git worktree remove build/gh-pages
```

Hosting that branch:

- **GitHub Pages:** in the repository's Settings → Pages, choose "Deploy from a branch",
  then select `gh-pages` / root.
- **Vercel:** import the GitHub repository, set the production branch to `gh-pages`, and
  choose the framework preset "Other" with no build command. Deploy through the GitHub
  integration rather than `vercel deploy`, because the CLI upload limit on the Hobby plan
  is smaller than this build.

**What to expect in a browser**

- The browser version uses the Low graphics preset. Volumetric fog, bounce light, SSAO and
  shadows from lamps and glowing devices are off; only the sun casts shadows.
- The 3D view renders at about 1.4 million pixels by default (80% on a 1080p screen). On
  touch screens (iPad, tablets, phones) it is about 1 million pixels (around 40-50% on an
  iPad's high-density screen), the grass is a little thinner, and only the robot casts a sun
  shadow. Menus and text stay sharp, and Settings → Graphics → Render scale changes it.
- "Quit" is hidden in browsers, because a web page cannot close its own tab.
- Browsers are limited by draw calls (each drawn object goes through JavaScript and WebGL),
  so the browser version draws less at a time:
  - level objects stop drawing beyond a distance that grows with their size
    (`scripts/systems/web_draw_distance.gd`);
  - the sleeping robots are merged into one mesh per material, and so are the facility's
    walls and floors (per room in the lab, which powers its rooms on one by one);
  - the sun uses one shadow map over the nearest 30 m, tiny parts cast no shadows, and
    lamps cast none (an omni lamp's shadow redraws everything near it six times, even off
    screen: three of them cost the garden 170-350 draw calls a frame);
  - the facility draws only the area you are in;
  - there is no depth pre-pass.
  This took the garden from about 2,500 draw calls a frame to 340–560.
- Browsers compile each shader on the page's only thread the first time something uses it:
  on a first visit (or after an update that changes shaders) one material takes several
  seconds, and a whole scene at once froze the page for over two minutes, long enough for
  Chrome to call it unresponsive (it does so after 15 s without a break). So the browser
  version spreads that work out (`scripts/systems/shader_warmup.gd`):
  - the main menu's first frame draws only the menu; its 3D scene is then built and shown one
    new material per frame behind a plain backdrop, with a "Preparing graphics" count;
  - levels load in separate steps (file, scene, the garden's four areas and its grass each in
    a frame of their own), then the loading screen reveals the whole level from above, one
    new material per frame (with the same count), so nothing compiles later during play;
  - the terrain's cliff moss and the robot shell's orange-peel wobble are simplified in the
    browser build, because their shaders alone took 15-18 s to compile.

  On the development PC a cold first visit takes about two minutes for the menu and three to
  four for each of the garden and the facility, with no frame over about 15 s. Later visits
  start quickly, because the browser caches compiled shaders.

## Controls

| Action | Keyboard / Mouse | Gamepad | Touch (iPad, phones) |
|---|---|---|---|
| Move | WASD / Arrow keys | Left stick | Stick on the left half of the screen |
| Look | Mouse | Right stick | Drag anywhere else |
| Zoom | Mouse wheel | LB / RB | Pinch |
| Hover hop (hold for higher) | Space | A | HOP button |
| Boost | Shift | RT / L3 | BOOST button, or push the stick past its rim |
| Interact | E (or F) | X | USE button, or tap the prompt |
| Scan | Q | Y | SCAN button (shows its cooldown) |
| Journal | J / Tab | Back | Book button (top) |
| Pause | Esc | Start | Pause button (top) |

The touch controls (`scripts/ui/touch_controls.gd`, part of the HUD) appear on touch screens
and hide as soon as a keyboard, mouse or gamepad is used. Settings → Controls has
"Touch controls" (Auto / Always / Off) and "Touch button size". `tools/touch_test_runner.tscn`
drives them with injected touch events (add `facility` after `--` for the sci-fi areas).

## The journey

1. **The Quiet Meadow.** Wake at the abandoned charging dock and gather energy fragments.
   Then power the old gate's pylon to raise its shutter. The meadow's flowers open and its
   colors return.
2. **The Mushroom Forest.** Giant trunks, glowing mushrooms, a hollow log into a hidden
   fairy ring. Follow old cables to three switches hidden under moss (the scanner reveals
   them), then raise the bridge over the ravine.
3. **The Forgotten Shrine.** Wake four power nodes:
   - one needs 10 energy;
   - one needs sunlight bounced off two rotating mirrors;
   - one sits behind a wall only the scanner can read;
   - one needs a broken conduit repaired by rotating stone tiles.

   Then awaken the core. Lanterns light, a waterfall starts and the great door opens.
4. **The Crystal Garden.** Wake three resonators:
   - a prism light puzzle;
   - one hidden in a humming crystal grotto;
   - a melody puzzle with singing crystals.

   Then restore the Crystal Heart (20 energy). The whole world wakes up, and a research lift
   rises beside the Heart.
5. **Abandoned Space Research Facility.** An orbital lab running on emergency power after
   Experiment Seven. Restore power in three steps:
   - re-energize five conduits with couplers that each flip the conduits their pipes touch;
   - push mirror carts along floor rails to route a laser to the receiver;
   - restart four terminals in the reverse of the logged shutdown order.

   A loose vent, found with the scanner, hides a secret laboratory.
6. **Alien Energy Reactor.** A vast cavern around a living alien core. Stabilize it:
   - lock two swinging bridge arms at the moment they line up;
   - balance energy between cores of capacity 8, 5 and 3 until two hold 4 each;
   - wake four nodes, on pads reached by a moving lift and timed hard-light bridges, in
     the rhythm the heart beats.

   Plasma vents and the pit are the hazards.
7. **Quantum Space-Time Laboratory.** A white, impossible lab floating in a nebula:
   - low gravity to float up a well;
   - shifting between dimensions A and B, where only one set of platforms is solid;
   - freezing time to slip past spinning blades.

   The exit core needs all three at once. Then a portal takes you home.

The pause menu's **Travel** screen returns you to any area you have reached. In total
there are 42 energy fragments and 14 discoveries.

## Project layout

```
assets/characters/   robot GLBs exported from the .blend (+ eye-glow curves)
assets/environment/  props.glb: every environment prop, modelled by a Blender script
assets/textures/     photoscanned PBR sets (Poly Haven, CC0; see CREDITS.txt) + terrain arrays;
                     scifi/ holds the six 2k sets used only by the sci-fi areas
assets/fonts/        Fredoka + Nunito (SIL OFL) for the main menu
scenes/facility/     the three sci-fi areas (facility.tscn + one level scene each)
scripts/facility/    facility world, sci-fi kit (props/materials/lights), puzzle parts, areas/
assets/audio/        synthesized SFX (wav), ambience/loops/music (ogg)
scenes/              world, player, levels (one per area), interactables, ui
scripts/systems/     autoloads: GameState, SaveSystem, Settings, Quests, Audio, SceneRouter, Events
scripts/player/      player controller, robot visual + AnimationTree, camera rig, interactor
scripts/gameplay/    fragments, checkpoints, devices and puzzles
scripts/world/       terrain generator, layout, grass, water, area decoration, atmosphere, director
shaders/             terrain (PBR layers), props (triplanar PBR), foliage, water, crystal, sky, devices, UI
resources/           quests.json (data-driven objectives), ui_theme.tres, terrain cache
tests/               logic tests (progression, quests, save/load, level data)
tools/               asset pipeline + dev tools (see below)
```

Key ideas:

- The **robot** is the original rig. All 12 baked actions run through an AnimationTree:
  - idle, forward and lean blend space;
  - one-shot actions (poke, scan, hop, victory, bump, fidgets);
  - Shutdown played in reverse as the wake-up.

  The Blender `eye_glow` custom property is converted into an animation track, so the eyes
  flicker exactly as authored. Procedural layers add blinking, eye gaze toward interactables,
  springy antennas and body tilt.
- The **world** is one persistent scene. `WorldLayout` holds the hand-designed macro layout
  (path, areas, ravine, ponds). `WorldTerrain` generates the ground from it, with collision
  from a `HeightMapShape3D`. Area scenes place gameplay objects; their decoration scripts add
  landmarks plus rule-based scatter, batched into chunked MultiMeshes.
- **Restoration** is state-driven:
  - flags in `GameState` drive a global shader vector (`restore_levels`), so grass, flowers
    (petals fold shut while dormant), moss, mushrooms and crystals respond everywhere;
  - devices restore their own state on load.
- **Surfaces** use photoscanned PBR sets (albedo, OpenGL normal, AO/roughness/metal):
  - the terrain blends 8 layers from compressed texture arrays, with two-scale
    anti-tiling, height-aware transitions and triplanar rock on slopes;
  - props get object-space triplanar scans (so moving parts don't swim), with textured
    moss on upward faces;
  - water refracts and absorbs light by depth, with a soft shoreline.
- **Lighting** comes from `AtmosphereController`:
  - per-area moods with indirect light (SSIL), volumetric fog with sun shafts, and mist
    volumes over water;
  - a gentle per-channel color grade on AgX;
  - all scaled by the Low/Medium/High preset.
- **Saving** is a versioned JSON file in `user://` with temp-file writes, a backup copy,
  migration and validation. Settings are stored separately in `user://settings.cfg`.

## Tools

| Command | What it does |
|---|---|
| `blender -b <file>.blend --python tools/blender/export_robots.py` | Re-export the robots from the source .blend |
| `blender -b --python tools/blender/build_props.py` | Rebuild `assets/environment/props.glb` |
| `godot --headless --path . --script res://tools/build_texture_arrays.gd` | Rebuild the terrain texture arrays from `assets/textures/terrain_src` |
| `godot --headless --path . --script res://tools/compare_props.gd -- old.glb new.glb` | Check that a props rebuild kept every prop's dimensions |
| `python tools/gen_levels.py` | Regenerate the four level scenes from their layout tables |
| `python tools/audio/generate_audio.py` | Re-synthesize all audio (uses ffmpeg for ogg if present) |
| `tools/check.sh` | Import + compile-check every script |
| `godot --headless --path . res://tests/test_runner.tscn` | Logic tests |
| `tools/playtest.sh` | Automated end-to-end playthrough of the garden (windowed), screenshots in `docs/captures/` |
| `tools/facility_playtest.sh` | Automated playthrough of the three sci-fi areas (every puzzle, hazard, save, travel) |
| `blender -b --python tools/blender/build_scifi_props.py` | Rebuild `assets/environment/scifi_props.glb` |
| `tools/web_bench.tscn` | Browser benchmark (exported by `build_web.py --test` as `build/web_test/bench`) |
| `tools/facility_perf.sh` | GPU/CPU frame time at six spots in the sci-fi areas (`quality=N` optional) |
| `godot --headless --path . --export-release "macOS" build/macos/LittleBotBigWorld.zip` | Universal macOS app (Intel + Apple Silicon, ad-hoc signed); see `build/macos/HOW_TO_RUN_ON_MAC.txt` |
| `python tools/build_web.py [--test]` | Browser build with lighter textures in `build/web/` (see "Browser version" above) |
| `godot --path . res://tools/touch_test_runner.tscn -- [shot_dir] [facility]` | Touch controls test: injected taps, stick, look, pinch, buttons, menus (windowed) |
| `python tools/gen_facility_levels.py` | Regenerate the facility scenes (checkpoints, fragments, discoveries) |
| `python tools/audio/generate_scifi_audio.py` | Synthesize the sci-fi sounds (leaves the original audio untouched) |
| `tools/capture.sh <shots.json>` | Screenshots from scripted viewpoints (`docs/captures/baseline.json` = the before/after views) |
| `godot --path . res://tools/perf_runner.tscn -- x z yaw [quality=N] [profile]` | Frame timing at a spot; `profile` measures each effect's cost |

`gen_levels.py` overwrites the level scenes. If you prefer editing the levels in the Godot
editor, stop using the generator after that point.
