extends Level

## Level 01 — "Service Deck". Demo 0.1 test course.
##
## The course is a teaching sequence, not a random assortment. Every beat
## introduces exactly one idea, gives it a safe repetition, then combines it:
##
##   run-up → step → short gap → obstacle → longer gap → step up
##   → raised obstacle → drop → wide gap → staircase → committed gap → finish
##
## Distances are chosen against the movement profile rather than by eye. At full
## speed (11.5 m/s) a running jump peaks at ~3.0 m and stays airborne ~0.77 s,
## which covers about 8.8 m of ground. Gaps are therefore sized:
##   comfortable ≤ 5 m, demanding 6–7 m, committed 7–7.5 m.
## Nothing in this level requires more than 7.5 m, so the course is always
## clearable without frame-perfect input.

## Surface height of the opening deck.
const START_Y: float = 0.0


func build_course() -> void:
	spawn(SkylineBackdrop.new())

	# --- Beat 1: run-up. Long enough to reach top speed before anything else. --
	deck(-14.0, 34.0, START_Y)
	# A kerb the run state absorbs silently. Present so the step-up path is
	# exercised every single run — silent features rot otherwise.
	obstacle(24.0, 2.4, START_Y, 0.34, SurfaceLibrary.Kind.CONCRETE)
	parapet(-14.0, 34.0, START_Y)

	# --- Beat 2: first gap. 5 m — clearable even from a standing start jump. ---
	deck(39.0, 62.0, START_Y)
	parapet(39.0, 62.0, START_Y)
	# --- Beat 3: an obstacle on flat ground. Hip height, thin: this becomes the
	# first vault once Demo 0.2 lands. For now it is a jump. ---------------------
	obstacle(48.0, 1.3, START_Y, 0.95, SurfaceLibrary.Kind.METAL)

	# --- Beat 4: gap + rise together. 5.5 m across, 1.5 m up. ------------------
	deck(67.5, 92.0, START_Y + 1.5)
	parapet(67.5, 92.0, START_Y + 1.5)
	# Chest-high block on the raised deck — the future high vault.
	obstacle(77.0, 1.6, START_Y + 1.5, 1.45, SurfaceLibrary.Kind.METAL)
	# An overhead duct. Clearance is 1.95 m for now — enough to sprint under,
	# because Demo 0.1 has no slide and an impassable duct would be a softlock.
	# Demo 0.2 lowers it to ~1.0 m once sliding exists. The geometry is placed now
	# so the beat's spacing can be tuned before the mechanic arrives.
	duct(85.0, 3.0, START_Y + 1.5, 1.95)

	# --- Beat 5: the drop. 5 m down. Fast enough to feel committed, well under
	# the 26 m/s hard-landing threshold, so it reads as exhilarating not punishing.
	deck(92.0, 118.0, START_Y - 3.5)
	parapet(92.0, 118.0, START_Y - 3.5)

	# --- Beat 6: wide gap. 6 m — needs real speed, hence the long deck before it.
	deck(124.0, 146.0, START_Y - 3.5)
	parapet(124.0, 146.0, START_Y - 3.5)

	# --- Beat 7: the ascent. Three 1.5 m rises, each reached across a 2 m gap. --
	#
	# Separated by gaps rather than stacked as flush steps, deliberately. A flush
	# riser taller than the step-up allowance is a *wall*: the runner's capsule
	# hits its face mid-jump, collision zeroes horizontal velocity, and it slides
	# up the face and arrives on top with no speed. That turned this beat into
	# three dead stops. A gap in front of each riser means the takeoff happens in
	# open air and all momentum carries onto the next level.
	#
	# Flush risers become desirable again in Demo 0.2, once a mantle state can
	# convert that wall contact into a climb instead of a collision.
	deck(148.0, 157.0, START_Y - 2.0)
	deck(159.0, 168.0, START_Y - 0.5)
	deck(170.0, 179.0, START_Y + 1.0)
	parapet(170.0, 179.0, START_Y + 1.0, false)

	# --- Beat 8: the committed gap. 7 m at speed — the widest jump in the level.
	# Placed last, so failing the hardest thing costs the least progress.
	deck(186.0, 212.0, START_Y + 1.0)
	parapet(186.0, 212.0, START_Y + 1.0)

	# --- Beat 9: finish. Set well back from the gap so landing and finishing are
	# two separate moments rather than one confusing one. -----------------------
	finish(204.0, START_Y + 1.0)


# ---------------------------------------------------------------- kit shorthand

## Roof-edge detailing that makes each deck's height read instantly from the
## side. Without it, flat-lit decks at different heights are genuinely hard to
## tell apart at speed.
##
## **None of it collides, and none of it sits in the play plane.** An earlier
## version put a 0.55 m parapet across the leading edge of every deck; it looked
## right and it pinned the runner against a wall at every single takeoff point.
## The lesson is the rule in AGENTS.md: decoration may never compete with
## traversal. Readability is bought with value contrast, not with geometry.
##
##  - a dark fascia strip on the front face, just under the walking surface,
##    which outlines the deck's top edge without ever occluding the runner,
##  - a parapet set *behind* the play plane, reading as the far roof edge.
func parapet(from_x: float, to_x: float, top_y: float, _both_ends: bool = true) -> void:
	var width: float = to_x - from_x

	# Front fascia: a dark band hugging the underside of the leading edge. This is
	# the single strongest height cue in the whole scene.
	#
	# Standing clear of the deck's front face on purpose. An earlier version put it
	# at +0.07 with 0.14 depth, so its back face landed exactly on the deck face
	# and the two z-fought into a flickering sawtooth along the entire deck edge.
	var fascia: BoxBlock = block(
		Vector3(from_x + width * 0.5, top_y - 0.2, SURFACE_FRONT_Z + 0.14),
		Vector3(width, 0.4, 0.1),
		SurfaceLibrary.Kind.DARK
	)
	fascia.solid = false

	# Rear parapet, behind the runner. Gives the roof a real silhouette top line.
	#
	# Kept low (0.4 m, below hip height) and mid-valued rather than dark. A tall
	# dark parapet sits exactly behind the runner's torso, which is the worst
	# possible place to put a near-black element: the character's body merged into
	# it and only the accent stripe remained visible.
	var rear: BoxBlock = block(
		Vector3(from_x + width * 0.5, top_y + 0.2, -2.5),
		Vector3(width, 0.4, 0.22),
		SurfaceLibrary.Kind.TRIM
	)
	rear.solid = false

	# End posts, so deck ends are punctuated rather than fading out — the eye
	# needs to know exactly where the surface stops.
	for post_x: float in [from_x + 0.2, to_x - 0.2]:
		var post: BoxBlock = block(
			Vector3(post_x, top_y + 0.36, -2.5),
			Vector3(0.24, 0.72, 0.28),
			SurfaceLibrary.Kind.TRIM
		)
		post.solid = false


## An overhead duct leaving `clearance` metres of headroom above `ground_y`.
## Visual-only in Demo 0.1; becomes a slide-under obstacle in Demo 0.2.
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
