# TODO

## Current milestone

**Phase 0 — environment + repository safety.** In progress.

## Milestone ladder

| # | Milestone | Status |
| --- | --- | --- |
| 0 | Environment, repo scaffold, recovery docs, push safety | in progress |
| 1 | **Demo 0.1** — minimum playable: run, jump, gravity, floor, camera, reset, web export | next |
| 2 | GitHub Pages workflow deploying `exports/web/` from `main` | next |
| 3 | **Demo 0.2** — parkour movement state machine, coyote time, jump buffer | planned |
| 4 | Blender headless character pipeline (mesh + rig + GLB) | planned |
| 5 | **Demo 0.3** — animation families and blended transitions | planned |
| 6 | Contextual traversal detection and obstacle classification | planned |
| 7 | **Demo 0.4** — modular environment kit and one polished 2–4 min level | planned |
| 8 | Chase system (original pursuer, pressure director, fail state) | planned |
| 9 | Visual polish — parallax, fog, lighting, particles, motion streaks | planned |
| 10 | Audio — footsteps, impacts, ambience, music, mixing | planned |
| 11 | UI and game flow — title, pause, retry, level complete, settings | planned |
| 12 | Browser export reliability hardening | planned |
| 13 | Final polish pass against the definition of done | planned |

## Blockers

None.

## Known bugs

None recorded yet.

## Next features (immediate queue)

1. Godot project skeleton: `project.godot`, input map, `gl_compatibility`
   renderer, web export preset with `thread_support=false`.
2. `scripts/validate.sh` and `scripts/export_web.sh` that fail loudly.
3. Playable `CharacterBody3D` runner on a primitive test level.
4. Camera follow rig with look-ahead.
5. Fall/death detection and instant restart.
6. First web export, browser smoke test, screenshot capture.
