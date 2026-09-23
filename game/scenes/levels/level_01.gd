extends Level

## Level 01 — "Service Deck".
##
## A teaching course, not an assortment of obstacles. Every beat introduces one
## idea, gives it a safe repetition, then combines it with what came before:
##
##   run → gap → low vault → gap+rise → high vault → slide → drop
##   → wide gap → mantle ×2 → wall run → ledge catch → committed gap → roll
##
## ### Distances are computed, not eyeballed
##
## At full speed (11.5 m/s) a running jump peaks at ~3.0 m and stays airborne
## ~0.77 s, covering about 8.8 m of ground. Gaps are therefore sized:
## comfortable ≤ 5 m, demanding 6–7 m, committed 7–7.5 m. Nothing here needs more
## than 7 m, so the course is always clearable without frame-perfect input.
##
## ### The course is the traversal test
##
## The autopilot only ever presses *right*, *jump for gaps*, and *slide when
## falling fast*. Every vault, slide, mantle, wall run and ledge catch below has to
## be chosen by `TraversalPlanner` on its own. If the bot completes the course, the
## contextual system genuinely works; if it stops at a crate, it does not. That is
## why the level deliberately contains geometry for each move rather than only the
## shapes plain jumping can handle.
##
## ### Dressing never changes gameplay
##
## Obstacles are placed with `furniture()`, which pairs a coarse collision box with
## a detailed kit mesh. The numbers passed to it are the numbers the movement
## system sees; the art follows them. Everything placed with `scenery()` has no
## collision at all and lives behind the play plane. When this level was dressed,
## not one gameplay dimension changed — the autopilot's route and timing were
## identical before and after, which is the whole point of the split.

## Surface height of the opening deck.
const START_Y: float = 0.0


func build_course() -> void:
	spawn(SkylineBackdrop.new())

	# --- Act I: teaching. Each move introduced alone, then combined. ------------
	_beat_run_up()
	_beat_first_gap_and_vaults()
	_beat_rise_and_slide()
	_beat_drop_and_wide_gap()
	_beat_mantles_and_wall()
	_beat_committed_gap_and_roll()

	# --- Act II: rhythm. Everything taught, now at pace and in combination. -----
	_beat_vault_chain()
	_beat_stagger_climb()
	_beat_duct_run()
	_beat_descent()

	# --- Act III: pressure. The hardest shapes, then the run home. --------------
	_beat_tight_sequence()
	_beat_wall_ladder()
	_beat_final_sprint()


# === Beat 1: run-up =========================================================
# Long enough to reach top speed before anything else happens.
func _beat_run_up() -> void:
	deck(-14.0, 34.0, START_Y)
	parapet(-14.0, 34.0, START_Y)

	# A kerb the run state absorbs silently. Present so the step-up path runs on
	# every single attempt — silent features rot otherwise.
	obstacle(24.0, 2.4, START_Y, 0.34, SurfaceLibrary.Kind.CONCRETE)

	# Dressing. The door housing gives the opening a reason to exist: this is where
	# the runner came from.
	scenery("roof_door", -6.0, START_Y, 4.6)
	scenery("vent_stack", 8.0, START_Y, 3.6)
	scenery("pipe_run", 15.0, START_Y, 3.2)
	scenery("water_tank", 29.0, START_Y, 9.0)
	scenery("antenna_mast", 2.0, START_Y, 14.0)
	_rail_run(-12.0, 33.0, START_Y)


# === Beats 2–3: first gap, then vaults ======================================
# The 5 m gap is clearable even from a standing jump, so the first gap can never be
# the thing that stops a new player. The vaults then arrive on flat ground with
# clear run-up either side, so the move is learned in isolation.
func _beat_first_gap_and_vaults() -> void:
	deck(39.0, 62.0, START_Y)
	parapet(39.0, 62.0, START_Y)
	_rail_run(40.0, 61.0, START_Y)

	# Hip height (0.95 m) and thin (1.3 m): hurdled at full speed with no loss.
	furniture("ac_unit", 48.65, START_Y, 0.95, 1.3)
	# A second, immediately after, so the player sees it was not a fluke.
	furniture("crate", 55.55, START_Y, 0.8, 1.1, SurfaceLibrary.Kind.CONCRETE)

	scenery("scaffold", 44.0, START_Y, 6.5)
	scenery("vent_stack", 59.0, START_Y, 3.4)
	scenery("billboard", 52.0, START_Y + 1.0, 17.0)


# === Beats 4–6: gap plus rise, high vault, slide ============================
func _beat_rise_and_slide() -> void:
	# 5.5 m across and 1.5 m up at once — two known quantities combined.
	deck(67.5, 96.0, START_Y + 1.5)
	parapet(67.5, 96.0, START_Y + 1.5)
	_rail_run(68.5, 95.0, START_Y + 1.5)

	# Chest height (1.45 m), thin: a hand-plant vault. Costs a little speed, which
	# is the first time a traversal has a price.
	furniture("transformer", 77.8, START_Y + 1.5, 1.45, 1.6)

	# 1.0 m of clearance — impossible to stand under, so the slide is entered
	# automatically. The player is taught the move by being given no alternative,
	# which is the cheapest possible tutorial.
	overhead(87.7, START_Y + 1.5, 1.0, 3.4)

	scenery("skylight", 72.0, START_Y + 1.5, 3.2)
	scenery("pipe_run", 82.0, START_Y + 1.5, 3.4)
	scenery("water_tank", 93.0, START_Y + 1.5, 8.0)
	scenery("antenna_mast", 66.0, START_Y + 1.5, 12.0)


# === Beats 7–8: the drop, then a wide gap ==================================
func _beat_drop_and_wide_gap() -> void:
	# 5 m down. Fast enough to feel committed, comfortably under the 26 m/s
	# hard-landing threshold, so it reads as exhilarating rather than punishing.
	deck(96.0, 122.0, START_Y - 3.5)
	parapet(96.0, 122.0, START_Y - 3.5)
	_rail_run(97.0, 121.0, START_Y - 3.5)

	# 6 m — needs real speed, hence the long deck before it.
	deck(128.0, 150.0, START_Y - 3.5)
	parapet(128.0, 150.0, START_Y - 3.5)
	_rail_run(129.0, 149.0, START_Y - 3.5)

	scenery("ac_unit", 104.0, START_Y - 3.5, 3.6)
	scenery("scaffold", 112.0, START_Y - 3.5, 7.0)
	scenery("vent_stack", 118.0, START_Y - 3.5, 3.4)
	scenery("roof_door", 134.0, START_Y - 3.5, 4.8)
	scenery("skylight", 142.0, START_Y - 3.5, 3.2)
	scenery("billboard", 124.0, START_Y - 2.0, 19.0)
	scenery("antenna_mast", 146.0, START_Y - 3.5, 13.0)


# === Beats 9–10: mantles, then a wall run into a ledge catch ===============
func _beat_mantles_and_wall() -> void:
	# Two 1.5 m flush risers, back to back, with no gap in front of them.
	#
	# Flush risers were removed from this level during Demo 0.1 because they were
	# unplayable: a step taller than the step-up allowance is a wall to a capsule,
	# collision zeroed horizontal velocity, and the runner arrived on top with
	# nothing left. They are back deliberately, because `ClimbState` is exactly the
	# fix, and their presence is what proves the mantle works.
	#
	# Thickness reaches below the deck each riser stands against, so the face is
	# genuinely flush. Left at the default, a 0.4 m void opened under each riser.
	deck(150.0, 161.0, START_Y - 2.0, 2.0)
	deck(161.0, 172.0, START_Y - 0.5, 2.0)
	_rail_run(151.0, 160.0, START_Y - 2.0)
	_rail_run(162.0, 171.0, START_Y - 0.5)

	# A 3.0 m flush face — too tall to mantle, so it must be run up. The top comes
	# within the hands' reach partway up, handing over to a ledge catch. Approach
	# speed decides whether it works, which is the point.
	#
	# 3.6 m thick so the face reaches from +2.5 down past the -0.5 deck below it. At
	# the default thickness this was a 1.9 m void with an overhang, and the runner
	# ran straight off into it.
	deck(172.0, 196.0, START_Y + 2.5, 3.6)
	parapet(172.0, 196.0, START_Y + 2.5)
	_rail_run(176.0, 195.0, START_Y + 2.5)

	# A vent on top, to reward arriving with speed intact.
	furniture("ac_unit", 182.6, START_Y + 2.5, 0.85, 1.2)

	scenery("water_tank", 189.0, START_Y + 2.5, 7.5)
	scenery("pipe_run", 166.0, START_Y - 0.5, 3.2)
	scenery("antenna_mast", 193.0, START_Y + 2.5, 11.0)
	scenery("scaffold", 156.0, START_Y - 2.0, 6.5)


# === Beats 11–13: committed gap, the roll, finish ==========================
func _beat_committed_gap_and_roll() -> void:
	# 7 m, the widest in the level, at height. Everything learned so far, at once.
	deck(203.0, 224.0, START_Y + 2.5)
	parapet(203.0, 224.0, START_Y + 2.5)
	_rail_run(204.0, 223.0, START_Y + 2.5)

	# An 8.5 m drop. Above the roll threshold (22 m/s) and above the hard-landing
	# threshold (26 m/s), so it costs most of the player's speed unless they go low
	# on contact. The last lesson is that height is survivable if you time it.
	deck(224.0, 252.0, START_Y - 6.0)
	parapet(224.0, 252.0, START_Y - 6.0)
	_rail_run(230.0, 251.0, START_Y - 6.0)

	scenery("skylight", 210.0, START_Y + 2.5, 3.2)
	scenery("vent_stack", 218.0, START_Y + 2.5, 3.4)
	scenery("scaffold", 234.0, START_Y - 6.0, 7.0)
	scenery("water_tank", 240.0, START_Y - 6.0, 9.0)
	scenery("billboard", 228.0, START_Y - 4.0, 18.0)


# ===========================================================================
# ACT II — rhythm
# ===========================================================================
#
# Everything is taught by now. This act stops explaining and starts asking for
# execution: the same moves arrive closer together, in combinations, with less room
# to recover between them. The pursuer is also fully established by here, so the cost
# of hesitating has become concrete rather than theoretical.


## Three vaults in quick succession, then a gap taken straight out of the third.
##
## Spacing is the whole design. 7 m between obstacles is just enough to re-accelerate
## after a high vault's speed cost, so the chain is survivable but punishes stalling —
## and the gap immediately after means the third vault has to be carried, not recovered
## from.
func _beat_vault_chain() -> void:
	deck(252.0, 296.0, START_Y - 6.0)
	parapet(252.0, 296.0, START_Y - 6.0)
	_rail_run(253.0, 295.0, START_Y - 6.0)

	furniture("ac_unit", 262.0, START_Y - 6.0, 0.95, 1.3)
	furniture("crate", 269.5, START_Y - 6.0, 0.8, 1.1, SurfaceLibrary.Kind.CONCRETE)
	furniture("transformer", 277.5, START_Y - 6.0, 1.45, 1.6)
	furniture("ac_unit", 286.0, START_Y - 6.0, 0.9, 1.25)

	scenery("scaffold", 258.0, START_Y - 6.0, 6.5)
	scenery("vent_stack", 274.0, START_Y - 6.0, 3.4)
	scenery("water_tank", 292.0, START_Y - 6.0, 8.5)
	scenery("billboard", 280.0, START_Y - 4.0, 18.0)
	scenery("antenna_mast", 266.0, START_Y - 6.0, 12.5)

	# 6.5 m, taken out of the last vault.
	deck(302.5, 330.0, START_Y - 6.0)
	parapet(302.5, 330.0, START_Y - 6.0)
	_rail_run(303.5, 329.0, START_Y - 6.0)
	scenery("roof_door", 312.0, START_Y - 6.0, 4.8)
	scenery("skylight", 322.0, START_Y - 6.0, 3.2)


## A staggered ascent: mantle, gap, mantle, gap. Alternating move types so neither
## becomes automatic.
func _beat_stagger_climb() -> void:
	deck(330.0, 342.0, START_Y - 4.5, 2.0)
	_rail_run(331.0, 341.0, START_Y - 4.5)

	deck(348.0, 360.0, START_Y - 3.0)
	_rail_run(349.0, 359.0, START_Y - 3.0)

	deck(360.0, 372.0, START_Y - 1.5, 2.0)
	_rail_run(361.0, 371.0, START_Y - 1.5)

	deck(378.5, 398.0, START_Y)
	parapet(378.5, 398.0, START_Y)
	_rail_run(379.5, 397.0, START_Y)

	scenery("pipe_run", 336.0, START_Y - 4.5, 3.2)
	scenery("vent_stack", 355.0, START_Y - 3.0, 3.4)
	scenery("scaffold", 366.0, START_Y - 1.5, 6.5)
	scenery("water_tank", 390.0, START_Y, 9.0)
	scenery("antenna_mast", 384.0, START_Y, 13.0)


## Two ducts with a vault between them: slide, stand, vault, slide. The transitions
## are the difficulty, not any single move.
func _beat_duct_run() -> void:
	overhead(384.0, START_Y, 1.0, 3.4)
	furniture("crate", 390.5, START_Y, 0.85, 1.1, SurfaceLibrary.Kind.CONCRETE)

	deck(398.0, 432.0, START_Y)
	parapet(398.0, 432.0, START_Y)
	_rail_run(399.0, 431.0, START_Y)
	overhead(404.0, START_Y, 1.0, 4.2)
	furniture("ac_unit", 413.0, START_Y, 0.9, 1.25)
	overhead(421.0, START_Y, 1.05, 3.6)

	scenery("billboard", 410.0, START_Y + 1.0, 17.0)
	scenery("skylight", 427.0, START_Y, 3.2)
	scenery("roof_door", 400.0, START_Y, 5.0)


## A long descent in three stages, each landing faster than the last. The final drop
## crosses the roll threshold, so the act ends on the skill it taught last.
func _beat_descent() -> void:
	deck(438.0, 462.0, START_Y - 3.0)
	parapet(438.0, 462.0, START_Y - 3.0)
	_rail_run(439.0, 461.0, START_Y - 3.0)

	deck(468.0, 490.0, START_Y - 7.5)
	parapet(468.0, 490.0, START_Y - 7.5)
	_rail_run(469.0, 489.0, START_Y - 7.5)

	# 8.5 m: above the roll threshold. Roll it or lose most of your speed.
	deck(490.0, 520.0, START_Y - 16.0)
	parapet(490.0, 520.0, START_Y - 16.0)
	_rail_run(496.0, 519.0, START_Y - 16.0)

	scenery("scaffold", 446.0, START_Y - 3.0, 7.0)
	scenery("vent_stack", 458.0, START_Y - 3.0, 3.4)
	scenery("water_tank", 480.0, START_Y - 7.5, 8.0)
	scenery("antenna_mast", 474.0, START_Y - 7.5, 12.0)
	scenery("roof_door", 504.0, START_Y - 16.0, 4.8)
	scenery("billboard", 512.0, START_Y - 14.0, 19.0)


# ===========================================================================
# ACT III — pressure
# ===========================================================================


## The tightest sequence in the level: vault, immediate gap, immediate mantle. There is
## no recovery room, which is the point — this is the difficulty peak.
func _beat_tight_sequence() -> void:
	furniture("transformer", 508.0, START_Y - 16.0, 1.45, 1.6)
	furniture("ac_unit", 515.5, START_Y - 16.0, 0.95, 1.3)

	# 5.5 m gap straight into a 1.5 m riser.
	deck(525.5, 536.0, START_Y - 14.5, 2.0)
	_rail_run(526.5, 535.0, START_Y - 14.5)

	deck(542.0, 556.0, START_Y - 13.0, 2.0)
	_rail_run(543.0, 555.0, START_Y - 13.0)
	furniture("crate", 551.0, START_Y - 13.0, 0.8, 1.1, SurfaceLibrary.Kind.CONCRETE)

	scenery("pipe_run", 530.0, START_Y - 14.5, 3.2)
	scenery("scaffold", 548.0, START_Y - 13.0, 6.5)


## Two wall runs back to back, the second taller than the first. Only reachable with
## speed intact, so it is the level's final test of whether the player has been
## carrying momentum or merely surviving.
func _beat_wall_ladder() -> void:
	deck(556.0, 572.0, START_Y - 10.0, 3.6)
	parapet(556.0, 572.0, START_Y - 10.0)
	_rail_run(560.0, 571.0, START_Y - 10.0)

	deck(572.0, 592.0, START_Y - 6.4, 3.9)
	parapet(572.0, 592.0, START_Y - 6.4)
	_rail_run(576.0, 591.0, START_Y - 6.4)
	furniture("ac_unit", 585.0, START_Y - 6.4, 0.9, 1.25)

	scenery("antenna_mast", 566.0, START_Y - 10.0, 11.0)
	scenery("water_tank", 588.0, START_Y - 6.4, 7.5)
	scenery("billboard", 578.0, START_Y - 4.0, 18.0)


## The run home: a wide gap, a long clear deck, and the finish. Deliberately generous
## after the wall ladder — a level should end on a sprint the player wins, not on one
## last chance to fail.
func _beat_final_sprint() -> void:
	deck(599.0, 648.0, START_Y - 6.4)
	parapet(599.0, 648.0, START_Y - 6.4)
	_rail_run(600.0, 647.0, START_Y - 6.4)

	furniture("ac_unit", 612.0, START_Y - 6.4, 0.9, 1.25)
	overhead(624.0, START_Y - 6.4, 1.05, 3.4)

	scenery("roof_door", 606.0, START_Y - 6.4, 5.0)
	scenery("skylight", 618.0, START_Y - 6.4, 3.2)
	scenery("scaffold", 634.0, START_Y - 6.4, 7.0)
	scenery("water_tank", 643.0, START_Y - 6.4, 9.0)
	scenery("antenna_mast", 630.0, START_Y - 6.4, 13.0)
	scenery("billboard", 640.0, START_Y - 4.5, 17.0)

	finish(640.0, START_Y - 6.4)


# ---------------------------------------------------------------- kit shorthand

## Roof-edge detailing that makes each deck's height read instantly from the side.
## Without it, flat-lit decks at different heights are genuinely hard to tell apart
## at speed.
##
## **None of it collides, and none of it sits in the play plane.** An earlier
## version put a 0.55 m parapet across the leading edge of every deck; it looked
## right and it pinned the runner against a wall at every single takeoff point. The
## rule in AGENTS.md comes from here: decoration may never compete with traversal.
## Readability is bought with value contrast, not with geometry.
func parapet(from_x: float, to_x: float, top_y: float, _both_ends: bool = true) -> void:
	var width: float = to_x - from_x

	# Front fascia: a dark band hugging the underside of the leading edge. The
	# single strongest height cue in the scene.
	#
	# Thin on purpose, and standing clear of the deck's front face. At 0.4 m it
	# projected as a ~37 px near-black band across every frame and swallowed anything
	# low to the ground; placed flush, it z-fought into a flickering sawtooth along
	# the entire deck edge.
	var fascia: BoxBlock = block(
		Vector3(from_x + width * 0.5, top_y - 0.13, SURFACE_FRONT_Z + 0.14),
		Vector3(width, 0.26, 0.1),
		SurfaceLibrary.Kind.DARK
	)
	fascia.solid = false

	# End posts, so deck ends are punctuated rather than fading out — the eye needs
	# to know exactly where a surface stops.
	for post_x: float in [from_x + 0.2, to_x - 0.2]:
		var post: BoxBlock = block(
			Vector3(post_x, top_y + 0.36, -2.5),
			Vector3(0.24, 0.72, 0.28),
			SurfaceLibrary.Kind.TRIM
		)
		post.solid = false


## A run of kit railing along the back edge of a deck.
##
## Replaces the solid rear parapet block: an open railing gives the same roof-edge
## silhouette while letting the backdrop show through, which keeps the depth
## reading and stops the band immediately behind the runner from becoming a solid
## mass. Non-colliding, and far enough back to be pure scenery.
func _rail_run(from_x: float, to_x: float, top_y: float) -> void:
	const SECTION: float = 2.0
	var x: float = from_x + SECTION * 0.5
	while x < to_x:
		scenery("railing", minf(x, to_x - SECTION * 0.5), top_y, 2.6)
		x += SECTION
