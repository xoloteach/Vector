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
## shapes that plain jumping can handle.

## Surface height of the opening deck.
const START_Y: float = 0.0


func build_course() -> void:
	spawn(SkylineBackdrop.new())

	# === Beat 1: run-up ======================================================
	# Long enough to reach top speed before anything else happens.
	deck(-14.0, 34.0, START_Y)
	# A kerb the run state absorbs silently. Present so the step-up path runs on
	# every single attempt — silent features rot otherwise.
	obstacle(24.0, 2.4, START_Y, 0.34, SurfaceLibrary.Kind.CONCRETE)
	parapet(-14.0, 34.0, START_Y)

	# === Beat 2: first gap ===================================================
	# 5 m — clearable even from a standing jump, so the first gap cannot be the
	# thing that stops a new player.
	deck(39.0, 62.0, START_Y)
	parapet(39.0, 62.0, START_Y)

	# === Beat 3: low vault ===================================================
	# Hip height (0.95 m) and thin (1.3 m). Hurdled at full speed with no loss.
	# Placed on flat ground with clear run-up either side so the move is learned
	# in isolation.
	obstacle(48.0, 1.3, START_Y, 0.95, SurfaceLibrary.Kind.METAL)
	# A second, immediately after, so the player sees it was not a fluke.
	obstacle(55.0, 1.1, START_Y, 0.8, SurfaceLibrary.Kind.METAL)

	# === Beat 4: gap plus rise ===============================================
	# 5.5 m across and 1.5 m up at once — two known quantities combined.
	deck(67.5, 96.0, START_Y + 1.5)
	parapet(67.5, 96.0, START_Y + 1.5)

	# === Beat 5: high vault ==================================================
	# Chest height (1.45 m), thin: a hand-plant vault. Costs a little speed, which
	# is the first time a traversal has a price.
	obstacle(77.0, 1.6, START_Y + 1.5, 1.45, SurfaceLibrary.Kind.METAL)

	# === Beat 6: slide =======================================================
	# 1.0 m of clearance — impossible to stand under, so the slide is entered
	# automatically. The player is taught the move by being given no alternative,
	# which is the cheapest possible tutorial.
	duct(86.0, 3.4, START_Y + 1.5, 1.0)

	# === Beat 7: the drop ====================================================
	# 5 m down. Fast enough to feel committed, comfortably under the 26 m/s
	# hard-landing threshold, so it reads as exhilarating rather than punishing.
	deck(96.0, 122.0, START_Y - 3.5)
	parapet(96.0, 122.0, START_Y - 3.5)

	# === Beat 8: wide gap ====================================================
	# 6 m — needs real speed, hence the long deck before it.
	deck(128.0, 150.0, START_Y - 3.5)
	parapet(128.0, 150.0, START_Y - 3.5)

	# === Beat 9: mantles =====================================================
	# Two 1.5 m flush risers, back to back, with no gap in front of them.
	#
	# Flush risers were removed from this level during Demo 0.1 because they were
	# unplayable: a step taller than the step-up allowance is a wall to a capsule,
	# collision zeroed horizontal velocity, and the runner arrived on top with
	# nothing left. They are back deliberately, because `ClimbState` is exactly the
	# fix, and their presence is what proves the mantle works.
	# Thickness reaches below the deck each riser stands against, so the face is
	# genuinely flush. Left at the default, a 0.4 m void opened under each riser.
	deck(150.0, 161.0, START_Y - 2.0, 2.0)
	deck(161.0, 172.0, START_Y - 0.5, 2.0)

	# === Beat 10: wall run into a ledge catch ================================
	# A 3.0 m flush face — too tall to mantle, so it must be run up. The top comes
	# within the hands' reach partway up, handing over to a ledge catch.
	# Approach speed decides whether it works, which is the point.
	#
	# 3.6 m thick so the face reaches from +2.5 down past the -0.5 deck below it. At
	# the default thickness this was a 1.9 m void with an overhang, and the runner
	# ran straight off into it.
	deck(172.0, 196.0, START_Y + 2.5, 3.6)
	parapet(172.0, 196.0, START_Y + 2.5)
	# A vent on top, to reward arriving with speed intact.
	obstacle(182.0, 1.2, START_Y + 2.5, 0.85, SurfaceLibrary.Kind.METAL)

	# === Beat 11: committed gap =============================================
	# 7 m, the widest in the level, at height. Everything learned so far, at once.
	deck(203.0, 224.0, START_Y + 2.5)
	parapet(203.0, 224.0, START_Y + 2.5)

	# === Beat 12: the roll ==================================================
	# An 8.5 m drop. Above the roll threshold (22 m/s) and above the hard-landing
	# threshold (26 m/s), so it costs most of the player's speed unless they go low
	# on contact. The last lesson is that height is survivable if you time it.
	deck(224.0, 252.0, START_Y - 6.0)
	parapet(224.0, 252.0, START_Y - 6.0)

	# === Beat 13: finish ====================================================
	# Set well back from the drop, so landing and finishing are two separate
	# moments rather than one confusing one.
	finish(244.0, START_Y - 6.0)


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
	# Standing clear of the deck's front face on purpose — an earlier version put it
	# flush, and the two surfaces z-fought into a flickering sawtooth along the
	# entire deck edge.
	# Thin on purpose. At 0.4 m it projected as a ~37 px near-black band across the
	# full width of every frame, and a sliding or rolling runner disappeared into it.
	# A line is enough to define the edge.
	var fascia: BoxBlock = block(
		Vector3(from_x + width * 0.5, top_y - 0.13, SURFACE_FRONT_Z + 0.14),
		Vector3(width, 0.26, 0.1),
		SurfaceLibrary.Kind.DARK
	)
	fascia.solid = false

	# Rear parapet, behind the runner. Gives the roof a real silhouette top line.
	#
	# Kept low (0.4 m, below hip height) and mid-valued rather than dark. A tall
	# dark parapet sits exactly behind the runner's torso, which is the worst place
	# for a near-black element: the body merged into it and only the accent stripe
	# stayed visible.
	var rear: BoxBlock = block(
		Vector3(from_x + width * 0.5, top_y + 0.2, -2.5),
		Vector3(width, 0.4, 0.22),
		SurfaceLibrary.Kind.TRIM
	)
	rear.solid = false

	# End posts, so deck ends are punctuated rather than fading out — the eye needs
	# to know exactly where a surface stops.
	for post_x: float in [from_x + 0.2, to_x - 0.2]:
		var post: BoxBlock = block(
			Vector3(post_x, top_y + 0.36, -2.5),
			Vector3(0.24, 0.72, 0.28),
			SurfaceLibrary.Kind.TRIM
		)
		post.solid = false


## An overhead duct leaving `clearance` metres of headroom above `ground_y`.
##
## At 1.0 m this cannot be run under, which is the point: the traversal planner
## enters the slide automatically, and the player learns the move by doing it.
func duct(from_x: float, length: float, ground_y: float, clearance: float) -> void:
	var thickness: float = 0.7
	var depth: float = PROP_FRONT_Z - PROP_BACK_Z
	block(
		Vector3(
			from_x + length * 0.5,
			ground_y + clearance + thickness * 0.5,
			(PROP_FRONT_Z + PROP_BACK_Z) * 0.5
		),
		Vector3(length, thickness, depth),
		SurfaceLibrary.Kind.METAL,
		true
	)
	# Support legs behind the play plane, so the duct reads as built rather than
	# floating without putting collision where the runner passes.
	for side_x: float in [from_x + 0.3, from_x + length - 0.3]:
		var leg: BoxBlock = block(
			Vector3(side_x, ground_y + (clearance + thickness) * 0.5, -2.4),
			Vector3(0.2, clearance + thickness, 0.22),
			SurfaceLibrary.Kind.DARK
		)
		leg.solid = false
