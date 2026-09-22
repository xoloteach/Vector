# ROOFLINE

**A cinematic side-view parkour runner for the browser.**

Roofline is an original 2.5D parkour action game built in Godot 4. You play a
courier sprinting across the rooftops and service decks of a rain-slicked
industrial skyline, chained together by momentum: vault the ducts, slide the
gaps, kick off the walls, catch the ledges, and never stop moving — because
something is behind you.

> Roofline is an **original work**. It takes inspiration from the genre of
> cinematic side-view parkour games at a conceptual level only (fluid
> momentum traversal, rooftop environments, readable silhouettes). It contains
> no assets, art, animation, audio, level layouts, UI, or code from any
> commercial game.

---

## Play

| Where | Link |
| --- | --- |
| Browser (GitHub Pages) | https://xoloteach.github.io/Vector/ |
| Local export | `exports/web/index.html` (serve over HTTP, see below) |

---

## Controls

| Action | Keyboard |
| --- | --- |
| Run left / right | `A` / `D` or `←` / `→` |
| Jump | `Space` / `W` / `↑` |
| Slide / roll | `S` / `↓` / `Shift` |
| Interact / parkour assist | `E` (contextual — normally automatic) |
| Restart run | `R` |
| Pause | `Esc` / `P` |

Movement is **contextual**: you do not press a "vault" button. Run at an
obstacle and the character picks the traversal that fits its height, your
speed, and the landing space on the far side. Jump is forgiving — it has
coyote time and input buffering.

### Touch controls

Phones and tablets are a supported way to play, not an afterthought. On-screen
controls appear automatically on any touch device — and also the moment a real
touch arrives, which covers touch-capable laptops whose browsers under-report
their capabilities. They disappear again on keyboard input.

| Control | Position | Notes |
| --- | --- | --- |
| Run left / right | Left thumb, side by side | Hold to run |
| Jump | Right thumb, outermost | **Hold for a full jump, tap for a hop** — variable height works exactly as on keyboard |
| Slide / roll | Right thumb, inboard and above | Placed along the arc a thumb naturally travels |
| Restart, pause | Top right, small | Out of the action band |

- **Full multi-touch.** Each finger is tracked independently, so holding a
  direction while jumping and sliding works. This is table stakes for a parkour
  game and is verified automatically — see `scripts/test_mobile.sh`.
- **Sliding between buttons works.** Dragging a thumb off one control and onto
  another releases the first and presses the second, so fast direction changes
  and jump→slide chains do not drop inputs.
- **Hit areas are larger than the artwork**, because fingers are imprecise and
  hidden under your own hand.
- **Layout scales with the screen**, sized from the viewport's short edge, and
  rearranges between portrait and landscape.
- Losing focus mid-hold (a call, a notification, a tab switch) releases
  everything, so the runner never gets stuck sprinting into a wall.

Landscape is the intended orientation — a side-view runner needs horizontal room
to read what is coming. Portrait is fully playable: the camera automatically
pulls back to preserve horizontal coverage and lifts its aim clear of the thumb
zone, and a quiet hint suggests rotating. It never blocks play.

---

## Architecture overview

```
game/                     Godot 4 project (the game itself)
  project.godot
  export_presets.cfg      Web export preset (checked in, reproducible)
  src/
    autoload/             Singletons: run state, audio bus, settings
    player/               CharacterBody3D controller
      states/             One file per movement state (state machine)
      sensors/            Raycast/shapecast parkour probes
    camera/               Framing rig (look-ahead, speed zoom, shake)
    level/                Level runtime, checkpoints, triggers, kit pieces
    chase/                Pursuer AI and chase pressure director
    fx/                   Particles, motion streaks, post effects
    ui/                   Title, HUD, pause, death, level complete
  scenes/                 Composed scenes and levels
  assets/                 Imported meshes, textures, audio, fonts

blender/scripts/          Headless Blender Python asset generators
                          (character, rig, environment kit) — the art is
                          reproducible from source, not hand-saved .blend files
exports/web/              Committed browser build (what GitHub Pages serves)
scripts/                  Dev tooling: validate, export, screenshot, test
docs/                     Environment, recovery, design and review notes
tools/                    Local-only helpers (not required to build)
```

**Key design decision — why 3D:** the game plays on a 2D plane (movement is
locked to X/Y, Z is fixed) but renders in Godot's 3D renderer. That buys real
lighting, fog, depth-sorted parallax layers, and Blender-authored skeletal
animation, while keeping platforming collision simple and predictable.

**Renderer:** `gl_compatibility` (WebGL2). The web export is built with
**thread support off** so it runs on static hosts like GitHub Pages that
cannot send the `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`
headers that `SharedArrayBuffer` requires.

---

## Run locally

Requires Godot 4.7.x. See [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) for the
exact toolchain and install commands.

```bash
# Play in the editor
godot --path game

# Run the game directly
godot --path game res://scenes/Main.tscn

# Headless validation (imports assets, reports script/scene errors, exits)
./scripts/validate.sh
```

## Build the browser export

```bash
./scripts/export_web.sh          # validates, exports to exports/web/, fails loudly
./scripts/serve_web.sh           # serves exports/web/ on http://localhost:8080
./scripts/test_web.sh            # headless Chromium smoke test + screenshots
```

The export **must** be served over HTTP — opening `index.html` from `file://`
will not work because browsers block WASM module loading from that origin.

## Deployment

GitHub Pages deploys from the single canonical `main` branch via
[`.github/workflows/pages.yml`](.github/workflows/pages.yml). The workflow
builds the web export from source with the pinned Godot version and publishes
it, so the live build always corresponds to a commit on `main`. A prebuilt
copy is also committed under `exports/web/` so the game is immediately
deployable even without CI.

If Pages has not been enabled on the repository yet: **Settings → Pages →
Source → GitHub Actions**. No code changes are needed.

---

## Documentation

| File | Purpose |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Conventions, commands, pitfalls, current priorities |
| [`docs/RECOVERY.md`](docs/RECOVERY.md) | How to resume this project from scratch |
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | Exact tool versions and setup |
| [`TODO.md`](TODO.md) | Current milestone, blockers, bugs, next features |
| [`CHANGELOG.md`](CHANGELOG.md) | Progress per playable demo |
| [`ATTRIBUTION.md`](ATTRIBUTION.md) | Licenses for every external asset |

## License

Project code and original assets: MIT (see [`LICENSE`](LICENSE)).
Third-party assets retain their own licenses — see
[`ATTRIBUTION.md`](ATTRIBUTION.md).
