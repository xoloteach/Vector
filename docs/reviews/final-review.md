# Final milestone review — Roofline 1.0

Build: 640 m course, full movement set, chase, audio, UI. Web export verified in
Chromium/WebGL2.

Evidence reviewed:
- `captures/final/` — 17 frames of live gameplay, autopilot driving, real browser
- `captures/final-mobile/` — 5 phone/tablet profiles, genuine multi-touch
- `captures/ui_sheet/final/` — 20 interface screens across 4 viewports
- `captures/shots/extended/` — 23 deterministic frames + render-cost telemetry
- Autopilot logs: completion run and chase counter-test

Five critics reviewed independently against separate briefs before findings were
merged.

---

## Independent findings

### Critic A — Visual quality

**Works.** The value structure is now correct and measurable: walking surfaces are
the brightest large area (0.445), backdrop masses sit 0.20–0.38 and fade toward haze
with distance, and only ~0.4% of the frame falls below 0.1 luminance so near-black
belongs to the runner alone. The warm/cool split reads — sunlit faces warm, shadowed
faces cool — which is what stops a limited palette looking merely desaturated. The
prop kit gives the roofs a genuine sense of place; railings in particular turned flat
slabs into rooftops.

**Weak.** Backdrop buildings are still large flat quadrilaterals. They separate
correctly by value but have no silhouette interest — no setbacks, roof structures or
variation in profile. Billboard panels are big enough that a runner at jump apex can
pass across one; contrast keeps the silhouette readable, but the hard edge is
distracting. Fog is doing very little at current density.

### Critic B — Animation and movement

**Works.** Every state has a distinct authored pose and the rig blends toward it at a
per-state rate, so nothing snaps. Poses are verifiable rather than impressionistic:
bone landmarks confirm standing has feet at 0.06 m and hands at 0.84 m, the jump tuck
lifts feet to 0.32 m and hands to 1.83 m, the slide puts feet 0.82 m forward, and the
ledge hang puts hands at 2.03 m overhead. The gait is distance-locked so there is no
foot sliding at any speed. Landing compression scales with impact.

**Weak.** Feet are not IK-planted, so on the few sloped or stepped surfaces a foot can
intersect geometry slightly. Arm poses during vaults are stylised rather than
contact-accurate — the hand does not actually meet the obstacle it is supposedly
planting on. No transitional animation between slide and stand; the blend covers it,
but a dedicated recovery pose would read better.

### Critic C — Gameplay readability

**Works.** The runner is unmistakably the darkest object in frame at all times, which
is the single property the whole design protects. Deck heights read instantly from the
fascia lines. Obstacle furniture is reliably lighter than the floor it stands on, so
"this is a thing I interact with" is a consistent visual rule rather than a
case-by-case decision. Gaps are legible well before the takeoff point. The camera's
speed-scaled look-ahead gives real reaction time, and the chase widening is genuinely
functional — without it the pursuer sits off the left edge exactly when it matters.

**Weak.** Overhead ducts are visible but their *clearance* is not obvious until close;
a player's first duct is usually a surprise rather than a read. The threat meter is
bottom-centre and easy to miss while concentrating on the next obstacle — the drone's
own light and audio carry more of that load than the HUD does.

### Critic D — Reference feel (genre level only)

**Works.** Momentum is the game's core and it shows: the autopilot holds ~11.5 m/s
across 640 m, vaults cost nothing, mantles cost half, and rolls recover what a hard
landing would take. That cost structure is what makes route choice meaningful rather
than cosmetic. Chained traversal genuinely flows — the Act II vault chain reads as one
continuous movement rather than four discrete events. The chase creates sustained
pressure without unfairness, verified from both sides.

**Weak.** It is still one environment and one palette; a mid-level change of setting
would do a lot for the sense of a journey. There is no camera event language — no
slow-down, framing change or emphasis on a spectacular traversal, which is where this
genre usually earns its "cinematic" description.

### Critic E — Browser and technical quality

**Works.** Boots reliably in Chromium on WebGL2, no page errors, no failed requests,
correct canvas scaling at every tested size, no UI overlap. No-threads export
confirmed, so static hosting works. **Peak render cost across the whole level is 51
draw calls and 7,544 primitives** — a 640 m course with 13 prop types, a skinned
character, a drone and a 4-layer parallax skyline. That is enormous headroom, earned by
shared materials and MultiMesh backdrop layers. Audio is 812 KB and the total build is
39 MB, essentially all of it engine WASM.

**Weak.** Frame rate has still never been measured on real GPU hardware; SwiftShader
numbers are not a signal and were deliberately not treated as one. GitHub Pages remains
disabled at the repository level, so the public deployment is untested end to end.

---

## Synthesis — ranked

| # | Issue | Sev | Critics | Status |
| --- | --- | --- | --- | --- |
| 1 | Frame rate unmeasured on real hardware | major | E | **Open** — needs a real device or GPU runner; render-cost telemetry added as the best available proxy |
| 2 | Pages not enabled, public deploy untested | major | E | **Blocked** — repository setting, needs one manual action |
| 3 | Backdrop silhouettes are featureless | minor | A, D | Open — next visual work |
| 4 | Duct clearance not readable at a distance | minor | C | Open |
| 5 | No foot IK; occasional foot intersection | minor | B | Open |
| 6 | No camera emphasis on spectacular traversal | minor | D | Open |
| 7 | Vault hand contact is stylised, not accurate | polish | B | Open |

Nothing in the broken-gameplay, traversal, collision or softlock categories remains
open. Every item above is visual polish or an environmental limitation.

---

## Required questions

- **Does movement feel responsive?** Yes, and the mechanisms are explicit: coyote
  time, jump buffering, variable jump height, forgiving contextual thresholds that
  lean toward *doing* the move. Two genuine responsiveness bugs were found and fixed
  along the way — a compounding jump cut that collapsed every jump to 0.3 m, and input
  latched on the wrong clock.
- **Does momentum feel believable?** Yes. Full speed is sustained across 640 m, and
  every traversal has a deliberate momentum price: vault 0%, high vault 12%, mantle
  48%, hard landing 55%, roll 8%.
- **Are animation transitions smooth?** Yes — blended per state, never switched, with
  per-state blend rates because one global rate cannot serve both a vault and a
  landing.
- **Can the player understand obstacles immediately?** Mostly. Heights, gaps and
  furniture read reliably. Duct clearance is the weak case.
- **Does the silhouette read clearly?** Yes, and it is enforced structurally rather
  than by eye: measured value bands, a minimum fade on all scenery, and near-black
  reserved for the runner.
- **Does the camera frame upcoming obstacles properly?** Yes, with speed-scaled
  look-ahead, aspect-adaptive width, and chase-responsive widening.
- **Does it resemble a cinematic parkour game rather than a generic platformer?**
  Largely yes — silhouette, momentum, chained traversal and chase pressure are all
  present. What is missing is camera *language* around big moments.
- **Are there visual bugs?** None outstanding. Four were found and fixed by looking at
  real frames: inverted depth ramp, shadow-acne hatching, z-fighting trim, and a
  character whose head read as a top hat.
- **Are there collision problems?** None observed. The historic ones — parapet
  softlock, momentum-killing flush risers, a void hidden inside stacked decks — are
  fixed and covered by the autopilot.
- **Are there softlocks?** None. The autopilot fails on 3 s of no progress, so a
  softlock cannot reach a commit.
- **Are there dead states?** None. The infinitely-falling corpse and the
  no-timeout ledge hang are both fixed.
- **Is the browser build playable?** Yes — boots, renders, accepts keyboard and touch,
  completable end to end.
- **Is performance acceptable?** By every measurable proxy, comfortably: 51 peak draw
  calls, 7.5 k primitives, 812 KB audio. Unverified on real GPU hardware, and stated as
  such rather than assumed.
- **Did ≥3 independent critics inspect real output?** Yes — five, against 65 captured
  frames from a real browser, a real GL driver and four viewport sizes.

---

## Self-critique

**What works.** The engineering discipline held, and it paid for itself repeatedly.
Separating sensing from deciding from acting meant the contextual traversal system
could be verified by making the bot *dumber* — it presses only right, jump-at-gaps and
slide-when-falling, so the planner has to do everything else, and if it stalls at a
crate the test fails. Separating collision from visuals meant the entire level could be
dressed with 13 prop types and the completion time did not change by a single frame.
Separating pose data from the mesh meant the box rig could be replaced with a skinned
Blender model and the animation system survived untouched.

The measurement tooling mattered more than any individual feature. `analyse_frame.py`
turned "it looks flat" into "the play surface is 0.33 and the backdrop is 0.42, which is
inverted". The pose sheet's numeric landmarks turned "the vault looks wrong" into "the
foot bone is at y=1.82 instead of 0.06". The UI harness turned "the menus seem fine"
into "the smallest text is 4.3 physical pixels on a phone". In every one of those cases
staring at screenshots had already failed.

**What feels weak.** The visual identity is coherent but narrow — one time of day, one
palette, one environment for 640 m. The animation is readable but not expressive; there
is no anticipation frame before a vault, no follow-through after a landing, and the
hands do not truly touch anything. And the game has no camera language: every moment is
framed identically, which is the clearest remaining gap against "cinematic".

**Bugs found.** Nineteen, across nine milestones, essentially all of them found by the
autopilot or by looking at real output rather than by reading code. The two most
expensive to diagnose — limbs rotating about the wrong axis, and bone poses discarding
their rest orientation — were both invisible in screenshots and obvious in numbers.

**Performance.** Excellent by proxy, unmeasured in reality. This is the one claim in
this document that rests on inference rather than observation, and it is flagged rather
than dressed up.

**Highest-value next improvement.** Get a real frame-rate measurement on actual
hardware, then camera language — impact-framed slowdowns and a wider lens on big
traversals — which is the cheapest remaining route to the word "cinematic".
