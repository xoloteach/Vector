class_name SurfaceLibrary
extends RefCounted

## Shared materials for the environment kit.
##
## Two reasons this is centralised rather than per-scene:
##
## 1. **Readability is a gameplay system.** In a silhouette-heavy side view the
##    player reads *what they can stand on* from value contrast alone. Surfaces
##    the runner interacts with are deliberately lighter than the backdrop, and
##    that relationship has to be enforced globally or it drifts scene by scene.
##
## 2. **Draw calls.** Materials are cached and shared, so a level made of two
##    hundred boxes still batches into a handful of material switches — which
##    matters on WebGL2.

enum Kind {
	CONCRETE,   ## default rooftop deck — mid value, the main standing surface
	METAL,      ## ducts, vents, crates — slightly lighter, reads as vaultable
	PAINTED,    ## railings and trim — the accent colour, marks intent
	DARK,       ## structural mass and fascias — only below the walking line
	GLASS,      ## windows — emissive-ish, pure background texture
	HAZARD,     ## anything lethal — unmistakably saturated
	TRIM,       ## railings, parapets — mid-dark, safe to sit behind the runner
}

## Cache keyed by Kind so every block of a kind shares one material instance.
static var _cache: Dictionary[int, StandardMaterial3D] = {}


static func get_material(kind: Kind) -> StandardMaterial3D:
	if _cache.has(int(kind)):
		return _cache[int(kind)]
	var mat: StandardMaterial3D = _build(kind)
	_cache[int(kind)] = mat
	return mat


static func _build(kind: Kind) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Vertex colours let individual blocks tint without breaking material sharing.
	mat.vertex_color_use_as_albedo = true

	match kind:
		Kind.CONCRETE:
			# Kept low so the lit rooftop lands mid-range rather than near-white.
			# Walking surfaces are the brightest *gameplay* element, but they must
			# not out-value the sky or the composition flattens.
			mat.albedo_color = Color(0.185, 0.2, 0.235)
			mat.roughness = 0.88
			mat.metallic = 0.0
		Kind.METAL:
			# Props stay clearly lighter than the deck. That relationship is a
			# gameplay cue — lighter than the floor means "this is furniture you
			# interact with" — so it is maintained deliberately, not by eye.
			mat.albedo_color = Color(0.355, 0.385, 0.435)
			mat.roughness = 0.5
			mat.metallic = 0.4
			mat.metallic_specular = 0.55
		Kind.PAINTED:
			mat.albedo_color = Color(0.78, 0.46, 0.14)
			mat.roughness = 0.62
			mat.metallic = 0.1
		Kind.DARK:
			# Reserved for elements *below* the walking line — fascias, undersides,
			# structural mass. Never used behind the runner at body height: at this
			# value it is as dark as the character and the silhouette disappears
			# into it. Use TRIM for anything the runner passes in front of.
			mat.albedo_color = Color(0.07, 0.082, 0.11)
			mat.roughness = 0.95
			mat.metallic = 0.0
		Kind.TRIM:
			# Mid-dark. Dark enough to draw an edge, light enough that the
			# near-black runner still separates cleanly against it.
			mat.albedo_color = Color(0.145, 0.16, 0.2)
			mat.roughness = 0.9
			mat.metallic = 0.05
		Kind.GLASS:
			mat.albedo_color = Color(0.14, 0.20, 0.28)
			mat.roughness = 0.18
			mat.metallic = 0.75
			mat.emission_enabled = true
			mat.emission = Color(0.30, 0.46, 0.62)
			mat.emission_energy_multiplier = 0.35
		Kind.HAZARD:
			mat.albedo_color = Color(0.72, 0.13, 0.12)
			mat.roughness = 0.7
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.2, 0.15)
			mat.emission_energy_multiplier = 0.45

	return mat


## Drops the cache. Only needed by tooling that rebuilds materials at edit time.
static func clear_cache() -> void:
	_cache.clear()
