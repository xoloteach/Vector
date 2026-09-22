"""Generates the pursuer: an original autonomous security drone.

    blender --background --factory-startup \
        --python blender/scripts/build_drone.py -- --out game/assets/characters

Why a drone rather than a humanoid pursuer
------------------------------------------
Three reasons, in order of how much they mattered:

1. **Readability.** The player never looks directly at the thing chasing them —
   it lives at the edge of vision while their attention is on the next obstacle.
   A drone can carry one bright emissive eye that says "I am here and this is how
   close" in peripheral vision. A second dark humanoid silhouette would compete
   with the runner's, which is the one shape the whole game depends on reading.

2. **Fairness is legible.** A flying pursuer visibly ignores terrain, so when it
   gains ground the player can see *why*. A running pursuer that keeps pace over
   obstacles invites the suspicion that it is cheating — and in most games it is.

3. **Cost.** No gait, no skinning, no second animation set. The whole thing is
   rigid-body motion plus spinning rotors, which is a handful of triangles and a
   few lines of code, and none of that budget is taken from the runner.

The design is original: a flattened delta hull, two outboard rotor pods, a single
forward sensor eye, and a ventral antenna rake. Nothing here references any
existing character.

Built nose-forward along +X so it faces the direction it travels, base at Z = 0
and hull centred on the origin, matching the kit's placement convention.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from kit_common import (  # noqa: E402
    MAT_ACCENT,
    MAT_DARK,
    MAT_METAL,
    MAT_TRIM,
    Prop,
    ensure_materials,
    export_glb,
    parse_out_dir,
    recalculate_normals,
    reset_scene,
)

# Rotors are exported as separate objects so the game can spin them. Everything
# else is one static hull.
ROTOR_OFFSETS = (
    ("RotorL", (-0.1, -0.52)),
    ("RotorR", (-0.1, 0.52)),
    ("RotorFL", (0.52, -0.34)),
    ("RotorFR", (0.52, 0.34)),
)
ROTOR_RADIUS = 0.26


def hull() -> Prop:
    p = Prop("DroneHull")

    # --- central body: a flattened wedge, nose toward +X ---------------------
    p.box((0.0, 0.0, 0.0), (1.05, 0.44, 0.2), MAT_TRIM)
    p.box((0.42, 0.0, -0.01), (0.34, 0.3, 0.15), MAT_METAL)
    # Nose taper.
    p.cylinder((0.6, 0.0, 0.0), 0.22, 0.11, MAT_METAL, sides=6, top_radius=0.045, axis="X")
    # Dorsal spine housing, so the top is not a blank plate.
    p.box((-0.1, 0.0, 0.11), (0.6, 0.2, 0.06), MAT_DARK)

    # --- sensor eye ----------------------------------------------------------
    # The single most important element on the model: the one thing the player
    # tracks in peripheral vision. Deliberately the only accent surface, and set
    # into a dark recess so it reads as a lit aperture rather than a painted dot.
    p.cylinder((0.68, 0.0, 0.0), 0.05, 0.095, MAT_DARK, sides=10, axis="X")
    p.cylinder((0.72, 0.0, 0.0), 0.04, 0.072, MAT_ACCENT, sides=10, axis="X")

    # --- outboard arms -------------------------------------------------------
    for _, (ax, ay) in ROTOR_OFFSETS:
        # Arm from the hull out to the pod.
        mid_x, mid_y = ax * 0.5, ay * 0.5
        length = max(abs(ax), abs(ay)) * 1.05
        if abs(ay) > abs(ax):
            p.box((mid_x, mid_y, 0.0), (0.12, length, 0.07), MAT_DARK)
        else:
            p.box((mid_x, mid_y, 0.0), (length, 0.12, 0.07), MAT_DARK)
        # Pod: a short barrel with a guard ring, so the rotor reads as shrouded.
        p.cylinder((ax, ay, -0.05), 0.12, 0.1, MAT_TRIM, sides=8)
        p.cylinder((ax, ay, 0.055), 0.03, ROTOR_RADIUS, MAT_DARK, sides=12,
                   top_radius=ROTOR_RADIUS)

    # --- ventral antenna rake ------------------------------------------------
    # Breaks the underside silhouette, which is the side the player usually sees.
    for x in (-0.3, 0.0, 0.3):
        p.box((x, 0.0, -0.16), (0.05, 0.05, 0.14), MAT_DARK)
    p.box((0.0, 0.0, -0.23), (0.8, 0.05, 0.05), MAT_DARK)

    # --- tail fin ------------------------------------------------------------
    p.box((-0.56, 0.0, 0.1), (0.2, 0.05, 0.28), MAT_TRIM)

    return p


def rotor(name: str) -> Prop:
    """A two-blade rotor, centred on its own origin so the game can spin it."""
    p = Prop(name)
    p.cylinder((0.0, 0.0, -0.02), 0.05, 0.05, MAT_DARK, sides=6)
    for blade_y in (-1.0, 1.0):
        p.box(
            (0.0, blade_y * ROTOR_RADIUS * 0.5, 0.0),
            (0.07, ROTOR_RADIUS, 0.014),
            MAT_METAL,
        )
    return p


def main() -> None:
    out_dir = os.path.abspath(parse_out_dir("game/assets/characters"))
    path = os.path.join(out_dir, "drone.glb")
    print(f"[build_drone] generating -> {path}")

    reset_scene()
    materials = ensure_materials()

    hull_prop = hull()
    hull_obj = hull_prop.to_object(materials)
    recalculate_normals(hull_obj)

    total = hull_prop.triangle_count()
    rotor_objects = []
    for name, (ax, ay) in ROTOR_OFFSETS:
        blade = rotor(name)
        obj = blade.to_object(materials)
        recalculate_normals(obj)
        obj.location = (ax, ay, 0.085)
        # Parented to the hull so the whole drone exports and moves as one unit,
        # while each rotor keeps its own transform for spinning.
        obj.parent = hull_obj
        rotor_objects.append(obj)
        total += blade.triangle_count()

    import bpy  # type: ignore

    bpy.ops.object.select_all(action="DESELECT")
    hull_obj.select_set(True)
    for obj in rotor_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = hull_obj
    export_glb(hull_obj, path)

    print(f"[build_drone] triangles: {total}")
    print(f"[build_drone] rotors   : {len(rotor_objects)}")
    print(f"[build_drone] wrote    : {path}")
    print("BUILD_DRONE: DONE")


if __name__ == "__main__":
    main()
