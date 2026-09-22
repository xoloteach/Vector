# Changelog

All notable progress, recorded per playable demo. Newest first.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/).
Every entry corresponds to a commit on `main` that produced a working build.

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
