# Demo 0.1 — milestone review

Build: first successful web export of the Demo 0.1 movement prototype.
Captures: `captures/demo01-first/` (13 frames, real Chromium + WebGL2).

Five critics reviewed the captures independently against distinct briefs, then
findings were merged and ranked by gameplay impact. Raw independent notes are
condensed here; the synthesis is what drives the work.

---

## Independent findings

### Critic A — Visual quality

- **The value structure is inverted.** Distant buildings are rendered *darker*
  than the sky, so the furthest masses are the highest-contrast shapes on
  screen and read as foreground. Real aerial perspective converges distant
  geometry toward the sky/haze colour. The depth ramp is currently fighting the
  composition instead of building it.
- Window quads read as detached beige rectangles floating in front of the
  buildings rather than as apertures in them — too bright, too warm, too large,
  and sitting on masses that are far darker than they are.
- The rooftop deck surface is blown out to near-white. Combined ambient (1.1)
  and directional (1.45) energy over a 0.30 albedo has no headroom left.
- Scene reads as assembled primitives, not as a place. Expected at this stage,
  but the value ramp is the thing blocking it, not the geometry.

### Critic B — Animation and movement

- Gait is plausible: limbs cycle, the figure leans, contacts are distance-locked
  so there is no visible skating.
- Cannot properly assess transitions from these frames — most captures after
  frame 09 are of a *dead* runner, so airborne, landing and drop poses were
  never actually photographed. **The capture methodology is the defect here,
  not the animation.**
- At this character size on screen, limb articulation is nearly invisible. Any
  animation quality work is wasted until framing is fixed.

### Critic C — Gameplay readability

- **Critical: the runner is barely findable in the frame.** A near-black figure
  (~90 px) sits against a dark navy backdrop mass. The single most important
  object in a side-view parkour game does not read.
- The deck's top surface is visible as a wide bright plateau because decks are
  5.7 m deep and the camera sits 1.5 m above the feet. The roof reads as a
  plain seen from above rather than an edge seen from the side, which makes
  judging where a surface *ends* harder than it should be.
- Height differences between decks are legible thanks to the dark fascia band —
  that part works.
- Upcoming obstacles are visible but low-contrast; the pale step block at x=24
  is brighter than the deck it sits on, which inverts the expected "furniture
  is lighter than floor" cue inconsistently.

### Critic D — Reference feel (genre-level only)

- Momentum is there in the numbers (full speed sustained across the whole
  course per the autopilot log) but the *image* does not communicate speed: no
  motion cue, no camera response visible, character too small to convey effort.
- Silhouette discipline is the genre's core asset and it is currently
  unreadable. This is the gap between "a platformer prototype" and the target.
- Framing is too wide and too neutral to feel cinematic.

### Critic E — Browser and technical quality

- Build boots reliably in Chromium on WebGL2 via SwiftShader; first frame
  renders; no page errors; no failed requests; no missing assets.
- Canvas scales correctly to the 1280×720 viewport; no UI overlap; HUD stays
  clear of the action band.
- No-threads export confirmed, so GitHub Pages hosting will work.
- `index.wasm` is 39 MB uncompressed. Acceptable served gzipped (~10 MB) but it
  must not be re-committed on every push.
- **Bug: the debug overlay shows `pos 71.2, -237.0` with `state Death`.** The
  runner keeps accelerating downward forever after dying. Harmless to play but
  it is a dead state that never settles.

---

## Synthesis — ranked by impact

| # | Issue | Sev | Critics | Likely cause | Fix | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Screenshot capture drives blind timed key presses, so most frames show a dead runner and the later course was never reviewed | **blocker** | B, C | Capture plan is a fixed timeline; it cannot actually play the game | Run the already-proven autopilot *inside* the web build via `?bot=1`, and capture while it plays | Re-capture; every frame shows live gameplay past x=70 |
| 2 | Runner does not read against the backdrop | **critical** | C, D, A, B | Near-black character over dark navy masses; no enforced value separation | Invert the depth ramp so distance converges toward haze; guarantee the nearest backdrop layer is well above character luminance | Before/after at the same course position |
| 3 | Character too small to read or animate meaningfully | **critical** | C, D, B | `view_distance` 15 m at 42° FOV | Pull the camera in and re-tune look-ahead so anticipation is preserved | Character occupies ≥20% of frame height |
| 4 | Deck reads as a plateau from above, not an edge from the side | major | C, A | Decks 5.7 m deep, camera 1.5 m above feet | Shallower decks, lower camera height offset | Roof reads as a line with visible front face |
| 5 | Rooftop surfaces blown out | major | A | Ambient + directional energy too high for the albedos | Rebalance exposure; darken concrete | Deck luminance mid-range, sky brightest |
| 6 | Windows read as floating rectangles | minor | A | Too bright/warm against too-dark masses | Cooler, dimmer, smaller; fixed largely by #2 | Windows read as part of the mass |
| 7 | No visual speed cue | minor | D | Nothing communicates velocity but position change | Deferred to Phase 8 (motion streaks, FOV response, dust) | — |
| 8 | Death state falls forever | minor | E | `DeathState` applies gravity unconditionally | Settle the body and stop integrating | Debug overlay shows a bounded Y |

Items 1–5 are being fixed now. 6 and 8 are cheap and ride along. 7 is Phase 8.

---

## Required questions

- **Does movement feel responsive?** Numerically yes — full speed sustained,
  coyote time and jump buffering in place, and two genuine responsiveness bugs
  were found and fixed before this review (compounding jump-cut, input sampled
  on the wrong clock). Cannot be confirmed by feel until framing is fixed.
- **Does momentum feel believable?** The autopilot holds 11.5 m/s across the
  entire course with no unintended stalls, and the one place that *did* kill
  momentum (flush 2 m risers) was rebuilt as gap-separated risers.
- **Are animation transitions smooth?** Blended, not snapped, by construction —
  but not yet verifiable from captures. Re-assess after #1 and #3.
- **Can the player understand obstacles immediately?** Partly. Heights read;
  contrast does not.
- **Does the silhouette read clearly?** **No.** This is the headline failure.
- **Does the camera frame upcoming obstacles properly?** Too wide, but the
  look-ahead logic behaves.
- **Does it resemble a cinematic parkour game rather than a generic platformer?**
  Not yet. Framing and value structure are why.
- **Visual bugs?** Inverted depth ramp, blown highlights, floating windows.
- **Collision problems?** None observed after the parapet and riser fixes.
- **Softlocks?** One found by the autopilot (pinned against a leading-edge
  parapet) and fixed. None remaining.
- **Dead states?** One: the infinitely falling corpse.
- **Is the browser build playable?** Yes — boots, renders, accepts input.
- **Is performance acceptable?** Unmeasured on real hardware; SwiftShader is not
  a useful signal. Needs a real-GPU check later.
- **Did ≥3 independent critics inspect real output?** Yes, five, against
  13 Chromium/WebGL2 screenshots.

---

## Self-critique

**What works.** The engineering spine is sound: the state machine is clean, the
sensor is the single source of world knowledge, the autopilot is a genuinely
strong test that caught three real bugs (compounding jump cut, input sampled in
`_process` instead of `_physics_process`, parapet softlock) plus two level
design faults (momentum-killing flush risers, a sensor blind spot that made a
5 m drop look bottomless). The web pipeline works end to end.

**What feels weak.** It does not look like the game yet. Every visual decision
so far was made in the dark, and the first time it was actually *looked at*, the
most basic requirement of the genre — the silhouette reads — was not met. The
lesson is that the capture loop should have come before the art direction, not
after.

**Bugs found.** Five, listed above, four already fixed.

**Performance.** Untested meaningfully. 39 MB WASM is the main size concern.

**Highest-value next improvement.** Fix the capture loop (#1) so the critics can
see real gameplay, then fix silhouette readability and framing (#2, #3). Nothing
else matters until the character reads.
