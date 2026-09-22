# TODO

## Current milestone

**Demo 0.2 — parkour movement vocabulary.** Next up.

## Milestone ladder

| # | Milestone | Status |
| --- | --- | --- |
| 0 | Environment, repo scaffold, recovery docs, push safety | **done** |
| 1 | **Demo 0.1** — run, jump, gravity, floor, camera, reset, web export | **done** |
| 2 | GitHub Pages workflow deploying from `main` | **done** (needs Pages enabled — see blockers) |
| — | Touch controls — multi-touch, phone + tablet, verified in-browser | **done** |
| 3 | **Demo 0.2** — slide, vault, climb, wall-run, ledge grab, roll | in progress |
| 4 | Blender headless character pipeline (mesh + rig + GLB) | planned |
| 5 | **Demo 0.3** — animation families and blended transitions | planned |
| 6 | Contextual traversal tuning across hundreds of repeats | planned |
| 7 | **Demo 0.4** — modular environment kit, one polished 2–4 min level | planned |
| 8 | Chase system (original pursuer, pressure director, fail state) | planned |
| 9 | Visual polish — parallax depth, fog, particles, motion streaks | planned |
| 10 | Audio — footsteps, impacts, ambience, music, mixing | planned |
| 11 | UI and game flow — title, pause menu, retry, level complete, settings | planned |
| 12 | Browser export reliability hardening | planned |
| 13 | Final polish pass against the definition of done | planned |

## Blockers

**GitHub Pages is not enabled on the repository.** The workflow builds, tests and
uploads the artifact correctly, but `actions/deploy-pages` returns 404 because
Pages has never been turned on. This cannot be fixed from a workflow or with the
default token (`POST /repos/.../pages` returns 403 — it needs admin).

*One-time manual step:* **Settings → Pages → Build and deployment → Source →
GitHub Actions**, then re-run the workflow. No code changes are needed.

Until then the playable build is available from the `roofline-web-build` artifact
on any successful run, and from the committed copy in `exports/web/`. The deploy
step is marked `continue-on-error` so this settings issue does not mask real
regressions — the build job still fails hard on those.

## Known bugs

None open. Everything found so far is fixed and recorded in `CHANGELOG.md`.

## Next features (immediate queue)

1. `SlideState` — crouch collision shape, momentum-preserving, sustained while
   held and under low ceilings; lower the level 01 duct back to ~1.0 m once it
   exists.
2. `VaultState` (low and high variants) — momentum-preserving hurdle over thin
   obstacles, driven by `ParkourSensor` classification that already exists.
3. `ClimbState` / mantle — converts a wall-contact-at-speed into a climb instead
   of the current dead stop, which is what will let flush risers back into level
   design.
4. `LedgeGrabState` + ledge climb — catch a missed jump instead of falling.
5. `WallRunState` / wall kick for walls too tall to mantle.
6. `RollState` — convert a hard landing into a roll when timed, rewarding
   deliberate play over hoping.
7. Extend the autopilot to exercise the new moves so traversal regressions keep
   failing the build.
8. Re-tune level 01 to teach each new move, and add `shots.sh` stations for them.

## Deferred, deliberately

- Motion streaks, landing dust, slide sparks — Phase 9, once movement is final.
- Real character model and skeletal animation — Phases 4 and 5. The placeholder
  box rig is good enough to judge movement and is not worth polishing.
- Performance measurement on real GPU hardware. SwiftShader numbers are
  meaningless; needs a real device or a GPU runner.
