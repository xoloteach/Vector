# Changelog

All notable progress, recorded per playable demo. Newest first.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/).
Every entry corresponds to a commit on `main` that produced a working build.

## Demo 0.4 — modular environment kit — 2026-09-22

Level 01 is dressed. 13 procedural props, 1492 triangles total, 140 KB — and not
one gameplay dimension changed in the process.

### Added

- `blender/scripts/kit_common.py` — mesh primitives (box, tapered cylinder, open
  frame) built from raw vertex/face lists rather than `bpy.ops`, because operator
  modelling depends on selection state and makes a long generation script fragile
  in exactly the way a reproducible pipeline must not be.
- `blender/scripts/build_kit.py` — 13 props, each a separate GLB:
  - **furniture**, sized against the movement profile so the kit and the
    controller agree by construction: AC unit (0.9 m low vault), crate (0.8 m),
    transformer cabinet (1.45 m high vault), duct section (slide-under).
  - **scenery**: vent stack, pipe run, railing, scaffold bay, water tank, antenna
    mast, billboard, roof door, skylight.
  - Open frames rather than panels for railings, scaffolding and masts, so they
    read as structure and not as walls the runner might have to deal with.
- `PropLibrary` — loads the kit, maps its intent-named materials onto
  `SurfaceLibrary` so props share the level palette and batch with block geometry,
  and **fades every prop toward the haze colour in proportion to its depth**.
- `Level.scenery()`, `Level.furniture()` and `Level.overhead()`.
- Panel seams on tall riser faces. A flush riser's front face is a large flat
  rectangle aimed at the camera; undressed it read as a blank slab with no sense of
  scale, which also made its height hard to judge.

### Design notes

**Props are decoration; `BoxBlock` is collision.** `furniture()` places a coarse
axis-aligned collision box and a detailed mesh over it, and hides the box's own
visual. Gameplay collision stays predictable and a prop can be re-modelled without
retesting traversal. The proof this held: after dressing the entire level, the
autopilot's completion time was **23.13 s — identical to the frame, with identical
state counts**, before and after.

**Depth fade is a gameplay rule, not an art flourish.** A prop pushed back for
visual depth automatically *becomes* background, so it can never compete with the
runner's silhouette. There is also a hard floor (`MINIMUM_SCENERY_FADE`) applied to
any prop behind the play plane however close, because a depth-proportional fade
barely touched a railing two metres back — and a near-black railing running
horizontally through the runner's torso at body height merged with the figure.
Scenery is never part of the foreground palette.

### Fixed

- Skylight glazing read as a glowing pool of water; emission energy more than
  halved. A bright saturated patch on the walking surface competes with the
  obstacles the player is trying to pick out.
- Scenery no longer casts shadows: at this sun angle props behind the play plane
  threw long shadows across the walking surface, adding noise exactly where the
  ground needs to be readable.

### Verified

- Measured value structure: walking surface 0.475 — the brightest band in frame;
  sky, backdrop and scenery 0.20–0.31; only 0.4% of pixels below 0.1 luminance, so
  near-black belongs to the runner alone. Contrast range 0.84.
- Autopilot: 244 m, 23.13 s, all states exercised, unchanged by dressing.
- Web export clean, total build unchanged at 39 MB.

## Demo 0.3 — procedural character + skeletal animation — 2026-09-22

The placeholder box rig is gone. The runner is now a skinned mesh generated
headlessly by Blender and posed through a real `Skeleton3D`.

### Added

**Character pipeline (Phase 3)**
- `blender/scripts/rig_spec.py` — every proportion and the whole 20-bone skeleton
  in one file, imported by the mesh builder. Nothing about the character's
  dimensions is written down twice.
- `blender/scripts/build_runner.py` — generates mesh, armature, skin weights and
  exports GLB, entirely headlessly. **586 vertices, 1088 triangles, 76 KB.**
  - Original minimalist courier: tapering limbs so the outline reads as athletic
    rather than tubular, an accent shoulder yoke that makes orientation and lean
    legible at ~150 px, and a low backpack that breaks the torso outline so front
    and back are distinguishable in pure silhouette.
  - Skinning is deliberate, not automatic. Each mesh ring binds to its own bone
    and only the rings flanking a joint blend 50/50. Blender's automatic weights
    are softer but blobbier; predictable deformation is worth more when the same
    rig has to hold up in a vault, a slide and a hang.
- `scripts/build_assets.sh` — regenerates all Blender art and reimports it.

**Animation (Phase 4)**
- `RunnerAnimator` now drives the real skeleton. The pose data and blending
  carried over from the box rig untouched, which was the point of keeping them
  separate from the mesh.
- Poses authored in *character space* ("swing this limb forward") and converted
  per bone at bind time. Torso lean splits across the spine chain so the back
  curves instead of hinging at one joint.

**Tooling**
- `scripts/pose_sheet.sh` — renders the runner alone, large, on neutral grey, one
  frame per pose, **with numeric bone landmarks printed alongside**. Reading a
  pose off a 150 px dark shape in a busy scene cannot distinguish "the pose is
  wrong" from "the model is rotated" from "you are misreading it"; this does.
- `game/tests/rig_report.gd` — dumps the imported hierarchy and every bone's rest
  orientation.

### Fixed

- **Bone poses discarded the rest orientation.** `set_bone_pose_rotation` sets a
  bone's *absolute* local rotation — it does not compose with the rest — so
  passing the delta alone snapped every limb to the skeleton's default axis and
  pointed them straight up. The foot bone sat at y ≈ 1.82 instead of 0.06, level
  with the head. From the outside this looked like a broken model or a bad glTF
  export. What identified it was printing landmark positions instead of looking at
  renders: "FootL y=1.82" is unambiguous where the image was not.
- `Pose.get()` shadowed `Object.get` and failed to compile; renamed `angle_for`.
- `mathutils.Vector` takes one sequence, not separate components.
- Props were still mirroring the dark sky on camera-facing faces; metallic reduced
  further.

### Verified

- Every pose's landmarks are anatomically sensible: standing has feet at 0.06 and
  hands at 0.84; the jump tuck lifts feet to 0.32 and hands to 1.83; the slide
  puts feet 0.82 m forward; the ledge hang puts hands at 2.03, overhead.
- Autopilot still completes 244 m in 23.1 s with every state exercised.
- Web export clean.

## Demo 0.2 — parkour vocabulary — 2026-09-22

The full movement set, chosen contextually. Course extended to 244 m and rebuilt
to teach each move. Completed end to end by the autopilot in 23.1 s.

### Added

**Movement**
- Six new states: `Slide`, `Vault` (low and high), `Climb` (mantle),
  `LedgeGrab`, `WallRun`, `Roll`. One file each, all under 150 lines.
- `TraversalPlanner` — the single place that decides *which* move an obstacle
  calls for. States ask it; they never decide for themselves, so the same
  obstacle produces the same decision whether the runner arrives on the ground or
  out of the air. Priority is ranked by momentum preserved, and thresholds lean
  toward *doing* the move, because vaulting something you meant to jump is a much
  cheaper error than stopping dead at a crate.
- `TraversalArc` — timed positional arcs for the scripted moves. The sensor has
  already verified height, depth and landing space before one starts, so an
  authored path gives the same clean action every time where a physics jump
  varies with approach frame.
- Sensor gained a `SLIDE_UNDER` obstacle class and a ledge probe.
- Movement profile gained tuning groups for every new move.
- Player can resize its collision capsule (pinned at the feet, so shrinking never
  registers as leaving the ground) and refuses to stand up without headroom.
- Six traversal signals for animation, audio and effects to hang off.

**Feel**
- **Roll** converts a heavy landing into a cheap one if the player goes low near
  contact: ~92% speed kept versus ~45%. This is the justification for hard
  landings existing at all — a landing penalty with no skilful counter is just a
  tax on playing fast, which teaches players to avoid height.
- **Slide-jump** cancels a slide at full speed.
- **Ledge catch** converts near-miss jumps into recoveries without making any
  jump easier. Hangs briefly then pulls up automatically — a hang with no timeout
  is a state the player can sit in forever, and on touch it is not obvious what
  to press.
- **Wall run** is vertical, not lateral. Running along a wall does not exist in a
  strict side view, and kicking off backwards sends the runner away from the goal.
  An up-run trades horizontal momentum for height, so arriving fast is the answer
  to obstacles too tall to mantle.

**Animation** — `RunnerAnimator`, replacing the old placeholder
- Every state declares a target pose; the rig *blends* toward it at a per-state
  rate. Blend rates differ by move because one global rate cannot serve both: fast
  enough for a vault to read as decisive makes a landing look twitchy.
- Poses are authored so the **silhouette alone** identifies the action.
- Three value steps inside the silhouette, so limb positions read against the
  torso instead of merging into one rectangle.
- This is the Phase 4 architecture, built against a placeholder mesh. Swapping in
  a skinned Blender model replaces the rig construction; the state-to-pose mapping
  and the blending survive.

**Tooling**
- `scripts/analyse_frame.py` — measures the value structure of a rendered frame
  (banded luminance, histogram, near-black share). Visual critique kept stalling
  on guesswork; this reports what actually reached the framebuffer. No Pillow
  dependency — PNG decoding via `zlib`.
- Shot harness can now capture **moves in progress**: a station places the runner
  short of an obstacle, holds real input for a fixed tick count, then shoots. Still
  deterministic, so these frames remain valid for regression comparison.

### Fixed

- **Every limb rotated about the wrong axis.** Joints rotated about X, which
  swings a hanging limb along Z — into and out of the screen, where a side-view
  camera cannot see it. Every pose rendered as a vertical stick with foreshortened
  limbs: the vault, slide and hang were all authored with wide distinct
  silhouettes and all three looked like a standing figure. It read as an animation
  *quality* problem for two review cycles when it was an axis typo. Now Z
  throughout, with a documented sign convention.
- **The play surface was darker than its own background.** Measured: rooftop
  ≈0.33 screen luminance against a backdrop ≈0.42. Exactly inverted for a
  side-view game, and the reason the scene looked flat however the lighting was
  adjusted. Retuned against measured targets — rooftop now ≈0.45 and the
  brightest large area, backdrop 0.22–0.38, near-black share down from 4.5% to
  0.9% so the runner's silhouette has that range to itself.
- **Ducts were being mantled instead of slid under.** A duct's top surface sits
  within mantling range, so height-based classification labelled it `CLIMB`. What
  distinguishes the two is whether the space *beneath* is passable, so that is
  what the sensor now measures.
- **Stacked decks did not form flush walls.** `deck()` used a fixed thickness, so
  a 3 m height change left a 1.9 m void with an overhang instead of a wall face.
  The runner ran straight off into it and the wall-run beat was unreachable.
- Fascia trim was a ~37 px near-black band across the bottom of every frame, and
  anything low to the ground vanished into it.
- Crate faces mirrored the dark sky at metallic 0.4, so one prop read as two
  unrelated objects depending on the face.
- Ledge hang sat too high — shoulders above the ledge being gripped.
- Slide pose was anatomically closer to a real slide and completely unreadable at
  ~20 px; readability now wins over accuracy.

### Verified

- Autopilot completes 244 m in 23.1 s with **every** state exercised:
  Vault ×4, Slide ×5, Climb ×2, WallRun, LedgeGrab, Roll, 0 hard landings.
- The bot only presses *right*, *jump at gaps*, and *slide when falling fast*.
  Every vault, slide, mantle, wall run and ledge catch is chosen by the planner —
  so the contextual system is genuinely doing the work, not being papered over by
  plain jumping.
- Browser build: 17 gameplay frames captured in Chromium/WebGL2, no page errors.
- Touch controls: all 5 phone/tablet profiles pass.

## Touch controls + Pages hardening — 2026-09-22

### Added
- **On-screen touch controls** (`src/ui/touch_controls.gd`) — a first-class input
  path, not a fallback. Left thumb runs, right thumb jumps and slides, with pause
  and restart tucked top-right.
  - True multi-touch: every finger is tracked independently, so holding a
    direction while jumping and sliding works.
  - Buttons *hold* their action rather than pulsing it, so variable jump height
    and sustained slides behave exactly as on keyboard.
  - Dragging a thumb between controls releases one and presses the next, so fast
    direction changes and jump-to-slide chains do not drop inputs.
  - Hit areas are 22% larger than the artwork, because fingers are imprecise.
  - Layout derives from the viewport short edge and rearranges between portrait
    and landscape; vector glyphs, so no font asset and no translation needed.
  - Auto-reveals on a touch device or on the first real touch event, and hides
    again on keyboard input.
  - Releases every held action on focus loss, so a call or tab switch cannot
    leave the runner sprinting into a wall.
- `scripts/test_mobile.sh` + `scripts/capture_mobile.mjs` — drives the exported
  build in a real touch-capable browser context across five phone and tablet
  profiles in both orientations, using CDP multi-touch to verify that holding a
  direction *and* jumping works. Playwright's own touchscreen API only supports
  single taps, which would have missed exactly the case most likely to break.
- Aspect-adaptive camera framing: distance is now derived from a target
  *horizontal* world width instead of being fixed, so the visible slice of track
  stays consistent from ultrawide to portrait.
- A quiet "rotate for a wider view" hint on cramped screens — never blocking.
- Downloadable `roofline-web-build` CI artifact, so the playable build is
  retrievable even while Pages is disabled.

### Fixed
- **Restart, pause and the debug overlay were unreachable by touch.**
  `Input.action_press()` sets action state without synthesising an `InputEvent`,
  so every handler using `event.is_action_pressed()` was invisible to the touch
  controls. These now poll `Input.is_action_just_pressed()`, which sees keyboard,
  gamepad and touch identically.
- **Portrait framing was unplayable.** Godot's default `KEEP_HEIGHT` aspect
  handling fixes the vertical field of view, so a narrow screen collapsed the
  horizontal view to about two metres with the runner filling the frame.
- HUD speed and route meters sat exactly under the left thumb cluster; they now
  relocate under the timer whenever touch controls are visible.
- Default handheld orientation was portrait; corrected to landscape.
- Pages workflow: bumped to Node 24 action releases (`checkout@v7`, `cache@v6`,
  `upload-pages-artifact@v5`, `deploy-pages@v5`) ahead of GitHub forcing Node 24.
- Pages deploy step is `continue-on-error` with an explanatory job summary. The
  deployment 404s until Pages is enabled on the repository, which cannot be done
  from a workflow; failing the whole run on a repo setting would have trained
  everyone to ignore a red build. The build job still fails hard on regressions.

### Known
- GitHub Pages still needs one manual enable — see `TODO.md` blockers.

## Demo 0.1 — "Service Deck" — 2026-09-22

First playable browser build. Run, jump, fall, land, die, retry, finish — on a
204 m test course, in a real browser, at a stable 11.5 m/s.

### Added

**Game**
- Godot 4.7.2 project targeting the browser, `gl_compatibility` (WebGL2)
  renderer, web export preset with thread support **off** so it runs on static
  hosts that cannot send COOP/COEP headers.
- 2.5D setup: simulation locked to the X/Y plane, rendered in 3D for real
  lighting, fog, depth-layered parallax and skeletal animation later.
- `MovementProfile` resource holding every movement tunable in one place —
  speeds, asymmetric gravity, derived jump velocity, forgiveness windows,
  landing thresholds.
- Player controller as a flat state machine: `Idle`, `Run`, `Jump`, `Fall`,
  `Land`, `HardLanding`, `Death`, one file each, with coyote time, jump
  buffering, variable jump height, speed-scaled jump bonus and silent step-up
  over kerbs.
- `ParkourSensor`: the single source of the runner's world knowledge. Probes
  obstacle height/depth/landing, classifies it (step / low vault / high vault /
  climb / wall), marches forward to find surface edges and gap widths, and
  measures ceiling clearance. States are forbidden from raycasting themselves.
- `ParkourCamera`: speed-scaled look-ahead, vertical deadzone with asymmetric
  smoothing, FOV response to speed, impact shake.
- Procedural level pipeline — courses are authored as a readable table of
  distances (`deck`, `obstacle`, `duct`, `parapet`, `finish`) rather than saved
  scene trees, so a whole level is a few hundred bytes and the spacing that
  makes or breaks the game can be read at a glance.
- Level 01: a 204 m teaching sequence — run-up, kerb, 5 m gap, obstacle,
  gap-plus-rise, overhead duct, 5 m drop, 6 m gap, three-stage ascent, a
  committed 7 m gap, finish. Every distance sized against the movement profile.
- `SkylineBackdrop`: four deterministic parallax layers, one draw call each via
  MultiMesh, with an aerial-perspective value ramp.
- `SceneLighting`: key and rim lights aimed by pitch/yaw in degrees.
- `PlaceholderRunner`: jointed box humanoid with a distance-locked gait, blended
  airborne pose, lean, landing compression and a rim-lit silhouette. Stands in
  until the Blender pipeline lands in Phase 3.
- HUD: run timer, speed and route meters, death/finish banner, `F1` debug
  overlay showing state, velocity, sensor output and FPS.

**Tooling** — the part that made the rest trustworthy
- `scripts/validate.sh` — imports, **parses every GDScript inside a running
  project** (autoloads registered, so no false "Identifier not found"), and boots
  the main scene.
- `scripts/test_headless.sh` + the in-game autopilot — a bot plays the level end
  to end and fails the build on death, softlock or timeout. This is the primary
  gameplay gate.
- `scripts/export_web.sh` — exports and then *verifies the artefacts*, including
  failing loudly if a threads-enabled build sneaks in.
- `scripts/test_web.sh` + `scripts/capture_web.mjs` — drives the exported build
  in real Chromium on WebGL2 with the autopilot at the controls, screenshots the
  run, and fails on page errors or a blank canvas.
- `scripts/shots.sh` — deterministic in-engine screenshots from fixed stations
  in seconds rather than minutes, for visual iteration and regression comparison.
- `.github/workflows/pages.yml` — validates, gameplay-tests, exports and
  publishes to GitHub Pages from `main`. No `gh-pages` branch.

### Fixed

Every one of these was found by the autopilot or by looking at real screenshots,
not by reading code:

- **Jump height collapsed to ~0.3 m.** The variable-jump cut multiplier was
  applied every physics tick instead of once, compounding to `0.45^n`.
- **Input sampled on the wrong clock.** `PlayerInput` polled in `_process` while
  the controller consumed it in `_physics_process`, so presses were lost or
  double-counted depending on frame rate.
- **Softlock at every deck edge.** Leading-edge parapets were solid geometry in
  the play plane; the runner pinned against them and could not get over.
  Roof-edge detail is now non-colliding and out of the play plane.
- **Momentum died at every riser.** Flush 2 m steps are walls: the capsule hits
  the face mid-jump, collision zeroes horizontal velocity and the runner slides
  up with no speed. The ascent is now gap-separated risers.
- **A 5 m drop looked bottomless.** The landing probe only reached 4.6 m, so the
  sensor reported a void and the bot jumped into it for an unearned hard
  landing. Landing scans now reach 26 m, past the lethal fall height.
- **Every up-facing surface rendered black.** A hand-written light basis in the
  scene file pointed the key light almost nowhere. Replaced with pitch/yaw
  angles, which cannot fail silently.
- **Inverted depth ramp.** Distant buildings were darker than the sky, so the
  furthest masses were the highest-contrast shapes and the near-black runner
  disappeared into them. Distance now converges toward haze.
- **Camera fixes had no effect** because the scene file re-specified the same
  values and overrode the script defaults.
- **Sawtooth artefacts along every deck edge** from decorative trim z-fighting
  and shadow-aliasing against the surface it trimmed.
- Step-up lifted the full allowance and dropped back, hopping on every kerb; it
  now lifts the smallest amount that clears.
- Death left the body accelerating downward forever (observed at y = -237).
- Screenshot capture drove blind timed key presses and mostly photographed a
  corpse; the build now plays itself via `?bot=1`.

### Verified

- Autopilot completes the course: 204 m, 18.0 s, 9 jumps, 0 hard landings, no
  stalls, full speed sustained.
- Web export boots in Chromium on WebGL2, renders, accepts input, no page
  errors, no failed requests, correct canvas scaling, no UI overlap.
- 28 scripts parse clean; main scene boots clean headlessly.

### Known gaps

- No vault, slide, climb, wall-run or ledge grab yet (Demo 0.2).
- Character is a placeholder box rig (Phase 3).
- No audio, no chase, no title screen.
- Environment is sparse and the backdrop needs more value spread and silhouette
  variety (Phase 8).
- Performance unmeasured on real GPU hardware — SwiftShader is not a signal.

Full critic review and self-critique: `docs/reviews/demo-0.1-review.md`.

## [Unreleased — Phase 0]

### Added
- Repository scaffold: `README.md`, `AGENTS.md`, `TODO.md`, `CHANGELOG.md`,
  `ATTRIBUTION.md`, `LICENSE`, and the `docs/`, `scripts/`, `game/`,
  `blender/`, `exports/` directory tree.
- `docs/ENVIRONMENT.md` — pinned toolchain (Godot 4.7.2, Blender 4.5.14 LTS,
  Chromium 153, ffmpeg 7.0.1) with reproducible install commands and the
  platform gotchas encountered while installing them.
- `docs/RECOVERY.md` — cold-start instructions so a new agent can resume the
  project from the repository alone after the build sandbox is destroyed.
