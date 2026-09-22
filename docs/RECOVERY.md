# RECOVERY — resuming this project from nothing

You are a new agent. The build sandbox that produced this repository is gone.
This document plus the repository is everything you need.

## 0. What this project is

**Roofline** — an original browser-playable 2.5D cinematic side-view parkour
runner in Godot 4. Gameplay is on a 2D plane (X/Y; Z locked); rendering uses
Godot's 3D renderer for real lighting, fog, depth parallax, and skeletal
animation from Blender.

Legal boundary: the project draws on the *genre* of cinematic parkour runners
for feel only. It contains no copyrighted assets, art, animation, audio, level
layouts, UI, characters, or code from any commercial game, and must never
acquire any. Original or permissively licensed (CC0/PD/MIT/BSD/Apache-2.0)
content only, with every third-party asset recorded in `ATTRIBUTION.md`.

## 1. Reconstitute the toolchain

Follow `docs/ENVIRONMENT.md` exactly — it has copy-pasteable install commands
and the list of traps (Blender mirror, `xz`, mesa libs, Playwright `--with-deps`,
export-template directory naming).

Minimum viable set: **Godot 4.7.2 + its web export templates**. That alone lets
you build, validate, and ship. Blender is needed only to regenerate art;
Chromium only to review it.

## 2. Reconstitute the repository

```bash
git clone https://github.com/xoloteach/Vector.git
cd Vector
git branch --show-current     # must be: main
./scripts/validate.sh         # confirm the project imports clean
./scripts/export_web.sh       # confirm the browser build still produces
./scripts/serve_web.sh        # then open http://localhost:8080
```

**Single-branch rule:** all work happens on `main`. Do not create feature,
temp, review, or `gh-pages` branches. GitHub Pages deploys from `main` through
`.github/workflows/pages.yml`.

## 3. Orient yourself, in this order

1. `TODO.md` — current milestone, blockers, known bugs, next features. **Start here.**
2. `CHANGELOG.md` — what each demo actually delivered.
3. `AGENTS.md` — conventions, commands, pitfalls, architecture rules.
4. `docs/reviews/` — the most recent multi-critic review. Its highest-ranked
   unfixed issue is almost certainly your next task.
5. `README.md` — directory map and controls.

## 4. How to work

Operate the loop, never skipping the middle:

```
BUILD → VALIDATE → WEB EXPORT → CAPTURE SCREENSHOTS → MULTI-CRITIC REVIEW
      → SYNTHESIZE → FIX HIGHEST-VALUE ISSUE → RETEST → COMMIT → PUSH → DEPLOY
```

Rules that matter most:

- **Push constantly.** The sandbox is disposable. Any slice of work that exists
  only locally is work you are about to lose.
- **Never judge the game by whether it compiles.** Export it, open it in a real
  browser, screenshot it, and have at least three critics with *different roles*
  review the captures independently before you believe it works.
- **Fix the biggest weakness before adding scope.** Broken gameplay and
  traversal/collision bugs outrank any amount of visual polish.
- **Quality of movement over volume of content.** One excellent level beats ten
  mediocre ones. Do not add worlds, multiplayer, stories, shops, or cosmetics.

## 5. Where things live

| Path | Contains |
| --- | --- |
| `game/` | The Godot project. Open with `godot --path game`. |
| `game/project.godot` | Renderer, input map, autoloads, window settings. |
| `game/export_presets.cfg` | Web preset. `thread_support=false` — do not change. |
| `game/src/player/` | Controller; `states/` = state machine, `sensors/` = parkour probes. |
| `game/src/camera/` | Framing rig. |
| `game/src/level/` | Level runtime, kit pieces, checkpoints, triggers. |
| `game/src/chase/` | Pursuer and chase-pressure director. |
| `game/src/ui/` | Title, HUD, pause, death, level complete. |
| `game/assets/` | Generated/imported meshes, textures, audio, fonts. |
| `blender/scripts/` | Headless Blender Python that *generates* all art. |
| `scripts/` | validate / build_assets / export_web / serve_web / test_web / capture. |
| `exports/web/` | Committed browser build. What Pages serves. |
| `docs/reviews/` | Milestone critic reports and self-critiques. |

## 6. If something is broken

| Symptom | Cause / fix |
| --- | --- |
| Export fails: "no export template found" | Templates missing or the directory is not named `4.7.2.stable`. See `docs/ENVIRONMENT.md`. |
| Browser build shows a black screen, console mentions `SharedArrayBuffer` | Thread support got re-enabled. Set `variant/thread_support=false` in `game/export_presets.cfg`. |
| Browser build fails to load from disk | You opened `file://`. Serve over HTTP (`./scripts/serve_web.sh`). |
| Shaders/effects look wrong only on web | A Forward+-only feature is in use. The web target is `gl_compatibility` (WebGL2). |
| Resources fail to load on a fresh clone | Cold import cache. Run `./scripts/validate.sh` (it imports twice). |
| Blender: `libGL.so.1` not found | Install mesa libs — see `docs/ENVIRONMENT.md`. |
| Chromium refuses to start as root | Add `--no-sandbox`. |

## 7. Definition of done

Not done until: the browser build loads reliably; a full level is completable;
controls feel responsive; all core parkour moves work consistently; animation
transitions are smooth; collision bugs are rare; no softlocks or dead states;
the chase mechanic works; visuals have a coherent original identity; audio is
integrated; performance is acceptable on integrated-GPU-class hardware;
deployment is reproducible; documentation is complete; every third-party asset
is attributed; and the latest stable build is pushed to `main`.
