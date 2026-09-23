# TODO

## Current state

**All twelve build phases are complete and pushed.** The game is playable end to end
in a browser on desktop and on touch devices: 640 m course, full parkour vocabulary
chosen contextually, an original pursuer, synthesised audio, and a complete
title → play → pause → results flow.

Read [`docs/reviews/final-review.md`](docs/reviews/final-review.md) before starting
anything new — its ranked table is the work queue.

| Phase | Status |
| --- | --- |
| 0 · Environment, repo scaffold, recovery docs | done |
| 1 · Demo 0.1 — minimum playable movement | done |
| 2 · Demo 0.2 — parkour vocabulary | done |
| 3 · Blender character pipeline | done |
| 4 · Demo 0.3 — skeletal animation | done |
| 5 · Contextual traversal | done |
| 6 · Demo 0.4 — environment kit, dressed level | done |
| 7 · Demo 0.5 — chase system | done |
| 8 · Demo 0.6 — visual polish, FX | done |
| 9 · Demo 0.7 — synthesised audio | done |
| 10 · UI and game flow | done |
| 11 · Browser export reliability | done |
| 12 · Pages workflow | done (deployment blocked — see below) |
| — · Touch controls | done |
| — · Level extended to 2–4 min playtime | done |

## Blockers

**GitHub Pages is not enabled on the repository.** The workflow validates, runs the
gameplay tests, exports and uploads the artifact correctly, but `actions/deploy-pages`
returns 404 because Pages has never been turned on. This cannot be done from a
workflow, and the REST call needs admin (`POST /repos/.../pages` returns 403).

*One-time manual step:* **Settings → Pages → Build and deployment → Source → GitHub
Actions**, then re-run the workflow. **No code changes are needed.**

Until then the playable build is available two other ways: the `roofline-web-build`
artifact on any successful run, and the committed copy in `exports/web/` (serve over
HTTP, not `file://`). The deploy step is `continue-on-error` so this settings issue
cannot mask real regressions — the build job still fails hard on those.

## Open work, in priority order

1. **Measure the frame rate on real GPU hardware.** The only claim in the review that
   rests on inference. Render cost is excellent by proxy — peak 51 draw calls and
   7,544 primitives across the whole level — but SwiftShader frame rates are not a
   signal and were not treated as one. Needs a real device or a GPU-backed runner.
2. **Camera language.** The cheapest remaining route to "cinematic": a brief
   time-dilation and wider lens on a high vault or a long drop, and an impact-framed
   beat on a hard landing. Every moment is currently framed identically.
3. **Backdrop silhouette variety.** Distant buildings separate correctly by value but
   are featureless quadrilaterals. Setbacks, roof structures and varied profiles would
   cost almost nothing — the backdrop is already MultiMesh.
4. **Duct clearance readability.** A player's first slide-under is a surprise rather
   than a read. Needs a visual cue on the approach, not a tutorial message.
5. **Foot IK.** Feet occasionally intersect stepped geometry. A two-bone solver on the
   existing rig would fix it.
6. **Animation expressiveness.** No anticipation before a vault, no follow-through
   after a landing, and hands do not truly contact the obstacles they plant on.
7. A second environment or time of day. 640 m in one palette is the main reason the
   game reads as a strong prototype rather than a finished one.

## Known bugs

None open. Nineteen were found and fixed across the build; each is recorded in
`CHANGELOG.md` against the milestone that fixed it, with the cause rather than just
the symptom.

## Deliberately not done

- More levels. One excellent course beats several mediocre ones, and the brief is
  explicit that movement quality outranks content volume.
- Multiplayer, stories, shops, cosmetics, progression. Out of scope by instruction and
  by judgement.
- Ogg Vorbis audio compression. The bundled ffmpeg in this environment has no Vorbis
  encoder, so source-rate reduction was used instead. `build_audio.py` already prefers
  Vorbis when a capable ffmpeg is present.
