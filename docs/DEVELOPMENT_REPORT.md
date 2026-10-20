# Little Bot, Big World: Development Report

Engine: Godot 4.7.2 (Forward+, GDScript, Jolt physics). Target: Windows desktop.

## Player character

The robot is the original rig from `pink_ball_robot_with_THE_BALL_v2.blend` (`RIG_PinkRobot`,
48 bones). Nothing was remodelled.

- `tools/blender/export_robots.py` exports a GLB with all 12 actions baked, so the IK and
  copy-rotation constraints survive.
- The custom `eye_glow` property (which drives eye emission through a driver) is exported as
  curves. At runtime they become animation tracks, so the eyes flicker exactly as authored.
- The animations have no root motion, so there is no risk of double movement. All movement
  is scripted (`CharacterBody3D`).

How the authored animations are used:

| Animation | Used for |
|---|---|
| Idle_Hover, Hover_Move_Forward | idle/forward blend space (faster playback while boosting) |
| Hover_Move_Left / Right | leaning into turns |
| Hover_Jump | hover hop |
| Attack | poke/activate gesture |
| Boost | scanning (its eye-glow ramp fits a scan) |
| Victory | discoveries, wake-up, restorations |
| Take_Damage | bumping a wall at full boost |
| Dodge_Left / Right | idle fidgets |
| Shutdown | asleep pose at the start; played in reverse as the wake-up; quick power cycle after a dunk in the ravine |

Procedural layers on top of the animations:

- extra hover bob;
- body tilt from acceleration and turning;
- eye display that drifts toward the focused interactable;
- blinking;
- spring-damped antennas.

The other two robots in the .blend appear as sleeping NPCs, with an eye flicker on "Say
hello". They wake at the finale:

- *The Ball*, the caretaker in the forest;
- *The Ball V2*, the wheeled courier in the shrine.

## What is implemented

**Movement**
- Camera-relative movement with acceleration and deceleration, plus smooth turning.
- Boost, and a gentle hover hop (hold for a higher hop) with coyote time and input buffering.
- The robot glides across ponds.

**Camera**
- Smoothed follow of the interpolated player position, with mouse/stick orbit and pitch limits.
- Scroll zoom and sphere-cast collision (fast pull-in, slow ease-out).
- Gentle auto-follow, which can be turned off in Settings.
- Cinematic shot sequences for scripted moments.

**World**
- One persistent world, about 320 x 600 m, generated from a hand-designed layout:
  - the winding path, four area basins and a shrine plateau with a paved plaza;
  - a ravine with a stream, five ponds, and boundary hills covered in giant grass;
  - flat zones under the light-beam puzzles.
- Terrain collision is a `HeightMapShape3D`. The height grid is cached in `resources/terrain_cache.bin`.
- An invisible marching-squares boundary wall follows the foot of the hills, so the robot
  can't climb out of the world or around a gate.

**Art**
- 69 props are modelled by a Blender script, with vertex data for AO, wind sway and petal folding.
- Custom shaders: terrain, foliage, environment, crystals, machine glow, water, waterfall,
  sky, plaza, light beams and the scan pulse.
- Grass and scatter use chunked MultiMeshes with distance fades.
- Plants dissolve when they come between the camera and the robot.

**Areas**
- **The Quiet Meadow.** Wake-up at the dock, 7 fragments (one on a boulder, one hidden, one
  inside a giant watering can), and the gate pylon that needs 3 energy.
- **The Mushroom Forest.**
  - giant trunks under a leaf canopy, a glowing pool, a hollow log into a fairy-ring glade;
  - three scan-hidden valve switches linked to the bridge machine by cables;
  - an animated bridge over the ravine.
- **The Forgotten Shrine.** Four power nodes:
  - energy (10);
  - a sunlight beam bounced off two rotating mirrors;
  - a scanner-revealed glyph that opens a hidden chamber;
  - three rotating conduit tiles.

  The core's activation cinematic lights the lanterns, starts the waterfall and opens the
  great door.
- **The Crystal Garden.** Three resonators:
  - a prism beam puzzle;
  - one hidden in a humming grotto;
  - a melody puzzle shown with both sound and glyph shapes, not color alone.

  The Crystal Heart (20 energy) triggers the finale: the whole world wakes, followed by an
  aerial flyover, a completion screen and free roam.

**Restoration**
- Each milestone tweens a global `restore_levels` vector, which all world shaders read:
  - petals open and grass saturates;
  - moss greens and mushrooms and crystals glow.
- Lights come on, ambience "life" layers fade in (birds, insects, chimes), fireflies and
  butterflies appear, and the fog lifts.

**Systems**
- **Interaction:** proximity, facing and line-of-sight checks, with locked prompts that say
  what's missing.
- **Scanner:** an expanding shell plus a ground ring, with reveals timed to the wavefront.
- **Objectives:** data-driven (`resources/quests.json`), recomputed from state so
  out-of-order progress is always correct.
- **Journal:** per-area fragment counts and the discoveries list.
- **Checkpoints:** each one autosaves when reached.

**Save**
- Versioned JSON in `user://`, with temp-file writes, a backup fallback, v1 migration, and
  rejection of foreign or future saves.
- The player position is saved and validated on load.
- Settings live in a separate file, so New Game never touches them.

**UI**
- Theme resource with system fonts, a minimal HUD, and contextual one-time control hints.
- Main menu over a live diorama: Continue (with a save summary), New Game (with confirmation
  if a save exists), Settings, Quit.
- Pause menu with a frosted backdrop: Resume, Journal, Restart from checkpoint, Settings,
  Save and return to menu, Quit.
- Settings:
  - volumes: master, music, SFX, ambience;
  - controls: look sensitivity, invert X/Y, camera assist;
  - graphics: quality, fullscreen, window size, render scale, V-Sync, FOV.
- Completion screen.

**Audio**
- Everything is synthesized by `tools/audio/generate_audio.py`: 35 SFX, 8 ambience beds,
  5 loops and 6 music tracks.
- Buses: Master (with limiter), Music, SFX (with reverb), Ambient and UI.
- Music crossfades by area. Ambience layers are weighted by area and restoration.
- Repeat limiting keeps bursts from getting loud.

## How it was tested

- **Compile check:** `tools/check.sh` imports the project and compiles all 78 scripts (0 failures).
- **Logic tests:** `tests/test_runner.tscn` runs 94 checks, 0 failures. They cover:
  - fragments, duplicates and sets;
  - objective order and out-of-order completion;
  - save round-trip, corrupt-file backup fallback, v1 migration, future/foreign save rejection;
  - settings surviving New Game;
  - level data (30 unique fragment ids, every discovery placed, enough energy for every gate);
  - conduit tile logic.
- **End-to-end playthrough:** `tools/playtest.sh` boots the real main menu and starts a New
  Game. From there it wakes the robot and walks with real input, then collects all 30
  fragments and makes all 8 discoveries. Along the way it:
  - scans hidden objects;
  - does a real hover hop onto a stepping stone;
  - solves every puzzle through the actual Interactor focus and interact input;
  - crosses the bridge on foot;
  - round-trips the save before the finale;
  - plays the finale and checks the completion screen and free exploration.

  The last full run passed (results in the session log); screenshots of each step are in
  `docs/captures/`.
- **Visual checks:** dormant/restored screenshot pairs for each area, plus robot animation
  states while idling, moving, turning, boosting and scanning.
- **Performance:** measured at Medium quality, 1600x900, on an RTX 2050 laptop GPU. Every
  area holds a steady 60 FPS (vsync-capped):

| Area | GPU time | CPU time |
|---|---|---|
| Meadow | 7.3 ms | 4.5 ms |
| Forest | 10.2 ms | 2.1 ms |
| Shrine | 6.8 ms | 3.9 ms |
| Garden | 6.6 ms | 4.7 ms |

## Visual upgrade (cinematic environments)

The maps were upgraded in place: same layout, routes, landmarks, collision and gameplay.
A full backup from before the upgrade is in `backups/pre_visual_upgrade_2026-10-16_2236.zip`.
Before/after screenshots from identical camera positions are in `docs/captures/`
(`before_v0*.png`, `after_v0*.png`, side by side in `comparison_1.png` and `comparison_2.png`).

**Materials.** 15 photoscanned PBR sets from Poly Haven (CC0; listed in
`assets/textures/CREDITS.txt`). Each set is albedo, OpenGL normal, and AO/roughness/metal.
- *Terrain:* 8 layers in three BPTC-compressed Texture2DArrays (1024 px). Layers:
  - grass soil;
  - dirt path;
  - forest floor;
  - cliff rock;
  - mossy cobbles on the shrine path;
  - gravel in the garden;
  - wet mud at shores;
  - mossy rock.

  The shader mixes two scales and rotations by macro noise (anti-tiling) and blends by
  height (the incoming layer's bumps poke through first). Steep slopes get triplanar rock,
  graded grey, with moss on ledges. A living-grass hue shift greens the meadow floor, and
  dormant areas stay paler.
- *Props:* object-space triplanar scans:
  - rock, bark and wood use the scan's colors;
  - painted metal, mushroom caps and dark stone keep their palette and borrow the scan's
    detail;
  - rusty metal gets real metalness from the scan's metal channel;
  - moss uses a moss scan and still greens with restoration.
- *Plaza:* each slab samples its own patch of a stone scan, with chamfered edges, uneven
  settling and moss in the joints.
- *Water:* the refracted bed is attenuated per color channel by depth, deeper water picks
  up scattered color, and Fresnel reflection comes from the sky (SSR on High). It has three
  octaves of ripples and fades out softly at the shore, with no hard edge.
- *Crystals:* inclusion veils sampled at several depths along the view ray parallax inside
  the gem.

**Geometry** (`tools/blender/build_props.py`; `tools/compare_props.gd` confirms every
gameplay prop kept its bounding box):
- *Rocks:* rebuilt with 4–16x the triangles. They keep the original silhouette and add
  fine bumps, thin crack grooves and chipped planar faces, smooth-shaded. They are fitted
  to the original bounds, so stepping stones keep their exact heights.
- *Hard-surface boxes* (stone, wood, metal): chamfered edges, no knife-sharp CG corners.
- *Grass:* 8–11 thin blades per clump with a folded midrib, varied lean, twist and droop.
  Tone is per blade, not banded per quad, and some tips are sun-bleached.
- *Mushrooms and trunks:* higher resolution.
- *New ground clutter* (scattered on its own random stream, so existing scatter didn't
  move): pebble clusters, small twigs, fallen leaves.

**Lighting and grading** (`AtmosphereController`):
- SSIL bounce light (cheap mode on Medium).
- Volumetric fog per area, densest in the forest, which carries sun shafts through the
  canopy. Mist volumes hang over the ponds and the ravine.
- Tighter shadow cascades for crisp contact shadows near the robot, and a better shadow
  filter on High.
- A restrained per-channel S-curve grade on AgX (slightly cool shadows, warm highlight
  roll-off; no teal-orange).
- Bloom made more conservative, and saturation peaks reduced (1.1 to 1.04) so color comes
  from materials, not post.
- Far depth of field on High only.
- Sky: self-shadowed three-octave clouds with silver linings and a horizon haze band.

**Performance** (RTX 2050 laptop GPU, 1600x900, GPU time per frame):

| View | Before (Medium) | After: Low | After: Medium | After: High |
|---|---|---|---|---|
| Meadow path | 7.3 ms | 6.6 ms | 12.9 ms | 18.3 ms |
| Forest path | 10.2 ms | – | 10.9 ms | – |
| Forest pool (worst case) | – | 7.1 ms | 14.3 ms | 20.9 ms |
| Shrine | 6.8 ms | – | 11.0 ms | – |
| Garden | 6.6 ms | – | 10.2 ms | – |

Verification after the upgrade:
- all 80 scripts compile;
- the logic tests pass (94 checks, 0 failures);
- the full end-to-end playtest passes (72 of 72 checks, 0 failures): all 30 fragments, all
  8 discoveries, every puzzle, the stepping-stone hop, the bridge crossing, the save
  round-trip and the finale.

Medium (the default on NVIDIA) holds 60 FPS everywhere. High now runs about 48–55 FPS on
this GPU and is meant for stronger cards. Measured costs:
- the sun's shadows cost about 3.2 ms;
- full-quality SSIL costs 2.7 ms (0.9 ms in Medium's cheap mode);
- volumetric fog costs about 0.9 ms.

## Gameplay screen polish (HUD, camera, feedback)

A second pass on the moment-to-moment screen. No controls, gameplay values, models,
animations, collisions or layouts changed. Before/after shots are in `docs/captures/`
(`comparison_hud.png` and `comparison_feedback.png`).

**HUD** (`scripts/ui/hud.gd`, same public API as before):
- Corner panels sit on soft gradient backdrops that fade into the scene instead of hard
  boxes, aligned to a 44 px safe margin.
- The objective has a progress bar for counted goals. The count is removed from the
  sentence, so it isn't shown twice.
- The energy counter also shows the current area's fragments as pips, for example
  "QUIET MEADOW 3/7".
- The interaction prompt floats just above the focused object: a key cap, a pulsing marker
  on the object, and a lock icon when locked. Before the robot wakes, and when the object
  is off-screen, it falls back to the lower middle.
- Scanner: a radar glyph, a cooldown sweep, a breathing glow when ready, and the key as a
  cap on the ring.
- Toasts are compact pills with an icon per kind that slide in.
- The discovery card has a gold accent and an "added to journal" line.
- Area title cards have ruled numerals and drift in.

**Feedback:**
- Collecting energy sends sparks from the robot into the counter; the number ticks over as
  they arrive, the icon pulses, and the screen edges flash cyan.
- Bumping a wall at full boost gives a warm edge flash, sparks and dust.
- A contact shadow and soft hover glow are projected under the robot. They spread and fade
  with height, so hops read clearly.
- Moving kicks up dust tinted per area; boosting leaves an energy trail.
- Hops kick up dust; landings throw a dust ring and a ground ripple, plus a small camera
  dip.
- Interacting fires a ring pulse and sparkles at the object.
- A subtle vignette is always on, and it is aspect-correct.

**Camera** (`camera_rig.gd`):
- Hops are followed more softly vertically than horizontally.
- The camera leads slightly in the direction of travel.
- Running fast adds a small FOV and distance kick for a sense of speed.
- Landings get a damped spring dip.
- Sensitivity, inversion, zoom, collision and auto-follow are unchanged.

**World:**
- Large soft cloud shadows drift across the land, weaker under the forest canopy. They are
  procedural, so no textures were added.
- Flowers and canopy leaves have smooth, cupped petals and leaves with more segments.
  Bounds are within 0.7% of before (checked with `tools/compare_props.gd`).

**Resolutions:** checked at 1600x900, 1280x720, ultrawide 21:9 and 4:3. The HUD scales with
the window (`canvas_items` stretch, `expand` aspect), keeps to the corners and doesn't clip.
`tools/capture_runner.gd` gained `window`, `input`, `toast`, `discovery` and `banner`
options for these checks.

**Performance:** Medium on the RTX 2050 at 1600x900, GPU time per frame:

| Area | GPU time |
|---|---|
| Meadow | 12.2 ms |
| Forest pool | 13.4 ms |
| Shrine | 10.3 ms |
| Garden | 9.5 ms |

All areas hold 60 FPS.

## Pink ball robot polish

The original model, proportions, rig, skeleton and the 12 authored animations are unchanged.
Everything below is material, shader or procedural work layered on top, on the model node
only, so physics, collision and controls are untouched. Comparison images are in
`docs/captures/` (`comparison_robot.png`, `comparison_robot_poses.png`).

**Materials** (`robot_materials.gd`, `robot_candy.gdshader`, `robot_pearl.gdshader`,
`robot_glass.gdshader`):
- *Pink armor:* the candy-pink ramp is kept, nudged slightly warmer so AgX tonemapping keeps
  it candy pink instead of drifting to lilac. Added:
  - a faint orange-peel texture in the clear coat, which breaks up reflections the way real
    paint does;
  - slight molded-plastic tone drift;
  - a light-dependent sheen;
  - a rim that brightens while boosting.
- *White shell:* pearlescent (a faint pink-to-lilac shift toward the edges) under a clear
  coat.
- *Visor:* reflects like glass rather than a mirror, and is slightly more see-through so the
  LED eyes read.
- *Eyes:* brighter, purer green. They also flash on pickups and stutter on bumps.
- *Accents:* vents and lime trim glow per instance and brighten while boosting.

**Lighting and readability:**
- The robot renders on its own layer with a small character light rig. A rim light placed
  opposite the camera touches only the robot and keeps its silhouette readable in shade.
- A faint green spill from the eyes falls on the ground in front.
- A local reflection probe follows the robot, re-captured only after it moves 10 m, so the
  chrome, visor and clear coat reflect the surrounding meadow or forest (Medium and High
  only).
- The contact shadow decal skips the robot.

**Animation and feel** (`robot_visual.gd`, `robot_face_modifier.gd`, `player.gd`):
- *Squash and stretch:* a volume-preserving spring on the model's scale, pivoting at its
  base so it stays planted.
  - hop: a one-frame crouch, then a stretch;
  - in the air: a slight stretch along fast vertical motion;
  - landing: a squash scaled by fall speed, with a quick wobble that settles;
  - at rest: a 1% "breath".
- *Anticipation:* starting to move gives a small crouch and antenna swing; a hard stop swings
  the antennas forward.
- *Antennas* react to hops, landings and bumps.
- *Expressions* reshape the LED eyes:
  - happy on pickups;
  - squint on hard landings and locked objects;
  - wide on interact and scan;
  - focus while boosting;
  - hurt (jitter and power flicker) on bumps.

  When nothing is nearby, the eyes glance around now and then.
- *Smoother playback:* the hover bob settles while moving fast, and actions now cross-fade
  (0.12 s) when one interrupts another instead of snapping.
- *Fixed:* `tools/capture_runner.gd` woke the robot without powering it, so every earlier
  close-up screenshot showed dark eyes. It now uses `RobotVisual.wake_instantly()`. In
  real gameplay the boot sequence always powered the eyes correctly.
- New dev tool: `tools/robot_studio.gd` renders studio close-ups. It can also freeze an
  expression or a squash pose for inspection.

**Not done, by design:** the robot hovers rather than rolls (its face always leads), so there
is no rolling animation. I also tried tilting the LED eyes for expressions, but it shears
the dotted bars because of how the eye bones are oriented, so expressions use size,
position, motion and brightness instead.

**Performance:** the character work costs about 0.2 ms of GPU time (two unshadowed lights
and the materials); the reflection probe costs about 0.25 ms. Medium still holds 60 FPS in
every area.

## Main menu redesign

`scripts/ui/main_menu.gd`, `scripts/ui/menu_widgets.gd` and `shaders/menu_vignette.gdshader`.
Before and after are in `docs/captures/comparison_menu.png`.

**Scene:** the same robot, giant grass, flowers and mushrooms, re-staged:
- The ground uses the game's photoscanned terrain material, with a little dirt path winding
  back into the garden behind the robot.
- Grass is instanced and thinned along the path, so the garden beyond shows through. Giant
  flowers frame the right side and the distance.
- Lighting is golden morning: a low warm side sun, soft warm haze, gentle light shafts and
  restrained saturation.
- Subtle depth of field keeps the robot crisp and softens the far garden and the nearest
  blades.
- The camera now sways gently instead of orbiting, so the robot always sits just right of
  center and is never behind the menu.
- The robot fidgets now and then, sometimes glances at the camera, and has its rim light.
- *Fix:* plants near the camera no longer dither on the menu. The dissolve is now a global
  (`foliage_near_fade`) that the menu turns off and restores on exit, so gameplay behavior is
  unchanged.

**UI:**
- The heavy dark overlay is replaced by a soft left-side gradient that keeps the scene
  visible.
- *Title:* Fredoka SemiBold on two balanced lines.
- *Tagline:* Nunito, softer and smaller.
- A tiny hairline-and-sprout accent separates the tagline from the menu.
- *Continue (primary):* a rounded glass pill with a faint mint tint, a hairline mint border,
  a soft glow and a chevron. It brightens on hover or focus.
- The save info sits beneath Continue in small, quiet text.
- *New Game, Settings, Quit:* plain text items. On hover or focus they brighten and slide
  right, and a mint dot and faint wash appear.
- The menu column is on a 140 px grid, and the items fade in one after another.
- Removed: the outlined translucent button boxes, and the "Made with Godot" footer (the
  brief asked for no extra text).
- The new-game confirmation card uses the same styling.
- Checked at 16:9, 1280x720, 21:9 and 4:3.
- Mouse, keyboard and gamepad all work; hovering moves focus, so the hover and focus looks
  match.

## Sci-fi areas 5–7

Three new areas, built as a separate gameplay scene (`scenes/facility/facility.tscn`) with one
level scene each. The four garden areas are untouched: their level scenes and area scripts
are byte-identical to before this work (checked against the backup).

**Integration:**
- After the Crystal Heart is restored, a lift rises beside it (`ResearchLift` in
  `world.tscn`; the garden level itself is unchanged). Riding it loads the facility.
- `SceneRouter.travel_to()` moves between the two scenes and checkpoints.
- `GameState.location` (garden world or facility) is saved. Older saves default to the
  garden.
- Seven new objectives are inserted before free exploration.
- 12 new fragments (42 in total) and 6 new discoveries (14 in total).
- The journal shows the facility areas once reached.
- A new Travel screen in the pause menu lists all seven areas and unlocks each one once
  visited.

**Area 5, research facility:**
- Arrival hall, breaker room, optics lab, a hidden laboratory and a control room, running on
  emergency power. Red emergency lights flicker, and each room's lighting comes back as its
  power step is done.
- Glass chambers and holographic notes: a turning station map and a hologram blueprint of
  the robot itself.
- Robot arms come to life at full power.
- The puzzles teach by cause and effect. Each coupler visibly flips the conduits its pipes
  touch, and there is a reset lever. The laser is traced live through mirror carts on rails.
  The terminal order is given in the shutdown log, and a wrong press trips every terminal.

**Area 6, alien reactor:**
- A cavern over a plasma sea, giant turning rings and gears, alien pylons, and a pulsing core.
- The arm locks are a skill and timing check, with a green window lamp on each console.
- The core balancing is the classic pouring logic puzzle. Transfers show as energy arcs, and
  there is a purge to restart.
- The node order is decoded from the heart's audible, visible beat groups, which only start
  once the cores are balanced. A wrong node overloads and resets.
- Hazards and timing:
  - plasma vents that charge visibly before firing (knockback, not death);
  - hard-light bridges that flicker before switching off;
  - a moving lift;
  - the pit, which returns the robot to its checkpoint.

**Area 7, quantum lab:**
- Floating white platforms in a nebula, upside-down stairs, drifting fragments of the
  building, and portal rifts that warp the space behind them.
- Each mechanic gets its own stage, then the final one combines them:
  - *gravity:* a field that really lowers the robot's hop gravity;
  - *phase:* collision changes per dimension, and inactive platforms show as holograms;
  - *time:* blades and moving platforms stop, and the colors drain.
- The final exit needs all three at once.

**Assets:** 38 new procedural props (`tools/blender/build_scifi_props.py`). Five new shaders:
- panelled metal with grime, scorch marks and light strips;
- refractive lab glass;
- holograms;
- flowing energy;
- a portal distortion.

There is also a deep-space sky. Audio is all synthesized:
- 19 new sound effects;
- 2 loops;
- 3 ambience beds;
- 3 music tracks.

These come from `tools/audio/generate_scifi_audio.py`, and the original audio files are
checksum-identical.

**Testing:**
- The logic tests now run 160 checks. They cover the new progression and the save location,
  including pre-facility saves. They also brute-force the coupler puzzle, which has exactly
  one solution, and the core balance, which is solvable in 7 transfers.
- `tools/facility_playtest.sh` plays all three areas through the real interact input. It
  covers:
  - wrong presses and resets;
  - the arm-lock timing window;
  - a real hop onto crates;
  - vent knockback;
  - the moving lift;
  - falling through an off bridge;
  - the pit and void respawns;
  - real low-gravity hops (impossible without the field);
  - per-dimension collision;
  - frozen and running blades;
  - the finale and completion screen;
  - save and continue inside the facility (every puzzle restored);
  - the Travel screen;
  - the portal home.
- The garden playtest now also checks that the lift rises after the finale and loads the
  facility.
- Results: logic tests 160/160, facility playtest 104/104, garden playtest 76/76.

**Performance:** about 6 ms of GPU time in the facility at Medium (RTX 2050, 1600x900),
holding 60 FPS.

## Sci-fi graphics upgrade (areas 5–7)

A visual pass on the three sci-fi areas only. The garden's files are untouched: a checksum
manifest taken before the work shows the only changed existing files are the sci-fi scripts,
the sci-fi panel shader, the sci-fi prop builder and its GLB, and the facility playtest. Layouts, routes, puzzles and
collision are unchanged:
- every new piece of geometry is visual only;
- block collision is still the original boxes;
- all 52 original prop meshes compare identical vertex for vertex.

**Surfaces.** Six 2k Poly Haven scans (CC0), used only by these areas, sit in
`assets/textures/scifi`: painted steel, riveted tread plate, worn sheet steel, polished
concrete, ceramic tiles and concrete. `shaders/scifi_panel.gdshader` now layers:
- the scan's albedo detail, normal, AO and roughness;
- panel seams and recessed panels with real depth, using analytic parallax;
- paint worn to bare metal on chamfered edges and panel corners;
- dust on upward faces and in seams;
- streaks running down from seams, and stencilled hazard labels;
- polished patches on floors that pick up reflections.

Each area has its own palette:
- off-white painted steel and coated deck plates in the lab;
- dark alien alloy and tread plate in the reactor;
- glazed white ceramic in the quantum lab.

**Geometry.** Architecture blocks are chamfered, so edges catch the light; collision is still
the box. `ScifiDetail` batches visual-only detail into a few meshes per area:
- *Lab:* ribs, cornices, door and window frames with hazard bands and status lamps, ceiling
  beams, and amber emergency guide strips.
- *Reactor:* buttresses, giant flanged pipes and machinery on the cavern walls, roof trusses
  converging over the heart, and column collars and braces.
- *Quantum lab:* stepped keels with anti-grav emitters under every platform, and edge light
  lines.

22 props have a detail child. Godot builds collision only from a prop's root mesh, and a
Blender comparison shows all 52 original prop meshes are vertex-for-vertex unchanged.
- *Lab:* console, rack, terminal, crate, chamber, door, lift, lab table, laser emitter and
  receiver, conduit couplers, ceiling lamps.
- *Reactor:* core, valves, nodes, bridge arms, pylons.
- *Quantum lab:* platforms, portal rings, consoles, exit core, pillars.

The detail includes vent grilles, bolts, handles, latches, hydraulics, cables, bench
equipment, cooling fins, pipe clamps, a pressure gauge, armour plates, roots, bands, and
trusses under the bridge arms.

Some props change colour with puzzle state, so their detail has no emissive parts. Walkable
props (arms, platforms) only get detail on their sides and undersides, and nothing sits
inside a portal opening.

Two older lamp bugs were fixed along the way:
- *Orientation:* the lab's ceiling lamps were hung upside down, with their light panels
  facing into the ceiling.
- *Colour:* ScifiKit's recolouring skipped the lamp-panel material, so the lamps never went
  dim red under emergency power or white when it returned.

Both now work as the lab intended.

**Lighting.**
- *Bounce light:* SDFGI on Medium and High, so strips, screens and emissives light the rooms.
- *Reflections:* box-projected reflection probes per room, refreshed when the lab's power
  returns.
- *Key light:* faded in per area. It is cold starlight through the arrival-hall windows, and
  the accretion disk backlighting the quantum lab.
- *Lab lamps:* the ceiling lamps are now shadowed downlights that throw pools of light.
- *Reactor:* light shafts from the roof and luminous haze over the plasma.
- *Grade:* per area, under the HUD. It covers split toning, contrast, vignette, fine grain
  and a hint of chromatic aberration, and blends as you move between areas.

**Effects.**
- *Lab:* dust drifting in every room's light, spark bursts with crackling arcs at damaged
  machinery, a broken conduit arcing, and coolant steam.
- *Reactor:* a new plasma sea with rolling swells, drifting currents and glowing veins under
  a cooling crust, plus embers rising from it and energy motes around the heart.
- *Quantum lab:* holographic interfaces at the consoles and the exit core, time dust that
  hangs still while time is frozen, and a distant singularity. The singularity bends the
  nebula behind it, with a photon ring, a swirling accretion disk and three gyroscopic
  chronosphere rings, all of which also stop when time stops.

**Performance.** GPU time at 1600x900 on an RTX 2050, measured at seven spots across the three areas with `tools/facility_perf.sh`:
- Low: about 5 ms.
- Medium: 7.4–14.3 ms.
- High: 7.4–14.1 ms. High skips SSIL here, because its full-resolution bounce light covers what SSIL adds.

Every spot holds 60 FPS. The new scans are VRAM-compressed with mipmaps; as first imported (uncompressed, no mipmaps) they doubled the GPU time.

**Testing.** Logic tests 160/160, facility playtest 104/104 (every puzzle, hazard, save and transition), garden playtest 76/76 (including the lift into the facility).

The facility playtest exposed a real stutter in the time freeze. Paused blade hazards asked for overlapping bodies every physics frame with monitoring off. That printed thousands of errors and pushed frames up to 500 ms. `ScifiParts.Hazard` now skips that query while paused. The bridge check in the playtest now waits for the low-gravity landing instead of a fixed 0.4 s; it had only passed before because of that stutter.

The previous versions of every changed sci-fi file are kept in `backups/scifi_pre_gfx/`.

## Garden prop material fix

The visual upgrade introduced a bug in `tools/blender/build_props.py`:
- Each prop part took "every face from index N onward" as its own faces.
- Chamfering a box (bmesh bevel) and `create_cone` reuse freed face slots, so the next
  part's faces could land before N.
- Some faces kept the previous part's material, and some fell back to the prop's first
  material.

22 garden props rendered partly in the wrong material:
- The stone lanterns' glow box was dark rock, so the lanterns never glowed when the shrine
  was restored.
- The great door's leaves were pale carved stone instead of dark rock.
- The lore tablet's slab was carved stone.
- Moss sat on the root gate's pillar caps.
- Half the dandelion's seed fluff was stem green.
- Junction and conduit housings showed as energy lines.

The fix uses the same idea as the sci-fi builder: a `part_done` face layer marks the faces
each part has claimed, and every part takes exactly the faces it created.

How the fix was checked:
- **Only the intended mesh data changed.** The old and new builders were run in Blender
  and every mesh compared face by face, independent of face order. Only the materials and
  the per-part colour variation changed, in exactly those 22 props. Geometry, smooth flags,
  sharp edges, AO, sway and petal vertex colours, UVs and attributes are identical in all
  87 meshes. The old builder run twice compares identical this way; its raw face order
  varies between runs on its own.
- **Bounds unchanged.** `tools/compare_props.gd` shows a 0.000 bounds change and identical
  triangle counts against the previous build.
- **Visual check.** Before/after shots are in `docs/captures/garden_material_fix.png`.
- **Level layouts, gameplay, collisions and shading are unchanged.**

The previous builder and GLB are kept in `backups/` (`*_pre_material_fix`).

## Known limitations

- The world is one big scene, and loading it (terrain, grass, decor) takes a few seconds
  behind a "Waking up..." caption. Background-threaded loading would hide that.
- Changing the graphics quality applies shadows, AO and MSAA right away. Grass density only
  updates on the next world load.
- A short shader-compilation hitch can happen the first time a new area comes into view.
- The level scenes are generated by `tools/gen_levels.py`. Editing them in the editor works,
  but re-running the generator overwrites those edits.
- The props are generated by script, not hand-sculpted. Rocks, ruins and grass are now much
  more detailed, but flowers, crystals, the canopy leaves and the giant watering can keep
  their stylized shapes. That fits the art direction, but they are not photoreal.
- Surface realism comes from 15 generic CC0 scans, not textures painted for each asset.
  Close up, the same rock or bark scan repeats across props (a per-instance offset hides
  most of it). The terrain uses 1024 px layers to keep memory reasonable, so the ground is
  slightly soft right under the camera.
- The new look is more natural and a little darker and more muted than the original bright,
  cartoon-green palette. A few shader uniforms set the balance (`lush_amount` and
  `lush_tint` in `terrain.gdshader`, the per-area moods in `AtmosphereController`).
- Volumetric fog and mist only show on Medium and High. Low falls back to distance fog.
- The upgrade added shaders, so the first-view shader compilation hitch when entering a new
  area can be longer than before.
- The sci-fi areas are built in code from a procedural prop kit and generic scans. The
  graphics pass added real scans, chamfered and greebled geometry, bounce light, reflections
  and effects, but they are still not hand-modelled AAA environments.
- The research lift beside the Crystal Heart uses the sci-fi prop library, so it shows the
  upgraded sci-fi materials and detail. It is the only sci-fi object in the garden.
- The facility areas were tested by automation. Their puzzle timing has not been tried by a
  person with a gamepad: the arm-lock window, hard-light bridge cycles and the 6-second time
  freeze may need tuning.
- In the garden prop builder, per-face flat shading still follows the old index
  bookkeeping. In 35 props some faces get the wrong flat/smooth flag: for example, crystal
  facets are smooth-shaded. It was left as is so the material fix wouldn't change any
  shading. The angle-based sharp edges (20–40°) hide most of it.
- On Medium and High, quitting prints `WARNING: 7 RIDs of type "Texture" were leaked`. It
  comes from the engine's per-viewport reflection atlas used by the robot's reflection probe.
  Freeing the probe early doesn't stop it, and it doesn't appear on Low (no probe). It only
  happens at shutdown and has no effect during play.
- The game was tested by automation and screenshots, not by a person playing with a mouse and
  gamepad. The feel of movement and camera values (speeds, sensitivity, auto-follow strength)
  may need tuning by hand.
- The generated audio is original but simple synthesis: tasteful, not studio quality.
