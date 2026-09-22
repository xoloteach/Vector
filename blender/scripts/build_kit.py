"""Generates the modular rooftop / industrial environment kit as GLB props.

Run headlessly:

    blender --background --factory-startup \
        --python blender/scripts/build_kit.py -- --out game/assets/props

Design rules, all of them consequences of the game being a side-view runner:

**Silhouette first.** Every prop is judged by its outline, because that is all the
player sees of it at speed against a bright sky. Open frames (railings,
scaffolding, antennae) are built as bars rather than panels so they read as
structure instead of as walls the runner might have to deal with.

**Props are decoration; ``BoxBlock`` is collision.** Nothing here is ever the
collision shape. Gameplay collision stays coarse, axis-aligned and predictable,
and the detailed mesh sits on top of it. That separation is what prevents the
"I clearly landed on that" class of complaint, and it means a prop can be
re-modelled freely without retesting traversal.

**Two size classes.** Props tagged *furniture* are sized to the movement profile —
a 0.9 m unit is a low vault, a 1.45 m unit is a high vault — so the kit and the
controller agree by construction. Props tagged *scenery* exist only to sit behind
the play plane and give the roof depth.

**Cheap.** This is a browser game. Everything here is a few hundred triangles,
flat-shaded, with no textures.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # type: ignore

from kit_common import (  # noqa: E402
    MAT_ACCENT,
    MAT_CONCRETE,
    MAT_DARK,
    MAT_GLASS,
    MAT_METAL,
    MAT_TRIM,
    Prop,
    ensure_materials,
    export_glb,
    parse_out_dir,
    recalculate_normals,
    reset_scene,
)

# ---------------------------------------------------------------------------
# furniture — sized against the movement profile
# ---------------------------------------------------------------------------


def ac_unit() -> Prop:
    """Rooftop air handler. 0.9 m — a low vault, taken at full speed."""
    p = Prop("ac_unit")
    body_h = 0.78
    p.slab(0.0, 0.0, 0.0, (1.15, 1.0, body_h), MAT_METAL)
    # Recessed top plate with a fan housing, so the top face is not a blank slab.
    p.slab(0.0, 0.0, body_h, (1.05, 0.9, 0.06), MAT_TRIM)
    p.cylinder((0.0, 0.0, body_h + 0.06), 0.06, 0.32, MAT_DARK, sides=10)
    # Louvre ribs on the leading face — catches the light and gives the prop a
    # direction, so the player can read which way it faces.
    for i in range(4):
        p.box((0.585, 0.0, 0.16 + i * 0.16), (0.04, 0.82, 0.07), MAT_DARK)
    # Feet.
    for sx in (-0.45, 0.45):
        for sy in (-0.38, 0.38):
            p.slab(sx, sy, -0.06, (0.1, 0.1, 0.07), MAT_DARK)
    return p


def crate() -> Prop:
    """Shipping crate. 0.95 m — a low vault. Edge framing reads as a crate rather
    than a featureless cube."""
    p = Prop("crate")
    size = 0.95
    p.slab(0.0, 0.0, 0.0, (size, size, size), MAT_CONCRETE)
    edge = 0.055
    half = size * 0.5
    for sz in (edge * 0.5, size - edge * 0.5):
        for sy in (-half + edge * 0.5, half - edge * 0.5):
            p.box((0.0, sy, sz), (size, edge, edge), MAT_DARK)
        for sx in (-half + edge * 0.5, half - edge * 0.5):
            p.box((sx, 0.0, sz), (edge, size, edge), MAT_DARK)
    for sx in (-half + edge * 0.5, half - edge * 0.5):
        for sy in (-half + edge * 0.5, half - edge * 0.5):
            p.box((sx, sy, size * 0.5), (edge, edge, size), MAT_DARK)
    return p


def transformer() -> Prop:
    """Chest-high utility cabinet. 1.45 m — a high vault, which costs a little
    speed, so the kit has an obstacle that makes route choice meaningful."""
    p = Prop("transformer")
    h = 1.45
    p.slab(0.0, 0.0, 0.0, (1.1, 0.95, h), MAT_TRIM)
    p.slab(0.0, 0.0, h, (1.2, 1.05, 0.07), MAT_DARK)
    # Door seam and hazard stripe: makes the front face identifiable.
    p.box((0.56, 0.0, h * 0.5), (0.03, 0.62, h - 0.2), MAT_DARK)
    p.box((0.575, 0.0, h - 0.34), (0.02, 0.44, 0.1), MAT_ACCENT)
    p.cylinder((0.0, 0.0, h + 0.07), 0.22, 0.06, MAT_DARK, sides=6)
    return p


def duct_section() -> Prop:
    """Overhead duct, 3 m long. Mounted so the gap beneath forces a slide.

    Exported with its underside at Z = 0, so placement code positions it by the
    clearance it leaves — which is the only dimension that matters to gameplay.
    """
    p = Prop("duct_section")
    h = 0.66
    p.slab(0.0, 0.0, 0.0, (3.0, 0.95, h), MAT_METAL)
    # Flange rings, which read as segmented ductwork from the side.
    for x in (-1.0, 0.0, 1.0):
        p.box((x, 0.0, h * 0.5), (0.09, 1.05, h + 0.06), MAT_TRIM)
    return p


# ---------------------------------------------------------------------------
# scenery — lives behind the play plane, never collides
# ---------------------------------------------------------------------------


def vent_stack() -> Prop:
    """Extract stack with a rain cap. A tall vertical accent against the sky."""
    p = Prop("vent_stack")
    p.cylinder((0.0, 0.0, 0.0), 0.12, 0.30, MAT_DARK, sides=10)
    p.cylinder((0.0, 0.0, 0.12), 1.35, 0.20, MAT_METAL, sides=10)
    p.cylinder((0.0, 0.0, 1.47), 0.1, 0.34, MAT_TRIM, sides=10, top_radius=0.26)
    p.cylinder((0.0, 0.0, 1.57), 0.06, 0.30, MAT_DARK, sides=10)
    return p


def pipe_run() -> Prop:
    """4 m pipe run on brackets, horizontal along X. Reads as building services and
    gives the roofline a strong horizontal to contrast the verticals."""
    p = Prop("pipe_run")
    p.cylinder((-2.0, 0.0, 0.42), 4.0, 0.115, MAT_METAL, sides=8, axis="X")
    p.cylinder((-2.0, 0.0, 0.16), 4.0, 0.07, MAT_TRIM, sides=6, axis="X")
    for x in (-1.6, -0.4, 0.8, 1.8):
        p.slab(x, 0.0, 0.0, (0.1, 0.16, 0.42), MAT_DARK)
        p.box((x, 0.0, 0.42), (0.12, 0.3, 0.06), MAT_DARK)
    return p


def railing() -> Prop:
    """2 m railing section. Two rails and posts, deliberately open."""
    p = Prop("railing")
    h = 1.02
    for x in (-0.95, 0.0, 0.95):
        p.slab(x, 0.0, 0.0, (0.07, 0.07, h), MAT_TRIM)
    for z in (h - 0.04, h * 0.55):
        p.box((0.0, 0.0, z), (2.0, 0.055, 0.055), MAT_TRIM)
    return p


def scaffold() -> Prop:
    """Scaffold bay, 2 m wide and 3 m tall. Open tube frame."""
    p = Prop("scaffold")
    w, h = 2.0, 3.0
    for sx in (-w * 0.5 + 0.05, w * 0.5 - 0.05):
        for sy in (-0.35, 0.35):
            p.slab(sx, sy, 0.0, (0.09, 0.09, h), MAT_TRIM)
    for z in (0.9, 1.9, 2.9):
        for sy in (-0.35, 0.35):
            p.box((0.0, sy, z), (w, 0.07, 0.07), MAT_TRIM)
    # Deck plank at mid height, and a diagonal brace for that unmistakable
    # scaffolding read.
    p.box((0.0, 0.0, 1.92), (w - 0.1, 0.72, 0.06), MAT_CONCRETE)
    p.box((0.0, 0.38, 1.4), (w * 1.02, 0.05, 0.05), MAT_DARK)
    return p


def water_tank() -> Prop:
    """Tank on a leg frame — a distinctive rooftop silhouette, and useful as a
    landmark the player can navigate by."""
    p = Prop("water_tank")
    leg_h = 1.15
    for sx in (-0.55, 0.55):
        for sy in (-0.55, 0.55):
            p.slab(sx, sy, 0.0, (0.1, 0.1, leg_h), MAT_DARK)
    p.box((0.0, 0.0, leg_h - 0.08), (1.35, 1.35, 0.09), MAT_DARK)
    p.cylinder((0.0, 0.0, leg_h), 1.55, 0.7, MAT_TRIM, sides=12)
    p.cylinder((0.0, 0.0, leg_h + 1.55), 0.26, 0.7, MAT_DARK, sides=12, top_radius=0.1)
    # Cross-bracing between the legs, so the base is not four bare sticks.
    for sy in (-0.55, 0.55):
        p.box((0.0, sy, leg_h * 0.45), (1.2, 0.05, 0.05), MAT_DARK)
    return p


def antenna_mast() -> Prop:
    """Lattice mast with cross arms. Thin vertical punctuation on the skyline."""
    p = Prop("antenna_mast")
    h = 4.2
    p.slab(0.0, 0.0, 0.0, (0.34, 0.34, 0.12), MAT_DARK)
    p.cylinder((0.0, 0.0, 0.12), h, 0.055, MAT_TRIM, sides=6, top_radius=0.03)
    for z in (1.5, 2.4, 3.2):
        p.box((0.0, 0.0, z), (0.9, 0.05, 0.05), MAT_TRIM)
        p.box((0.0, 0.0, z + 0.03), (0.05, 0.05, 0.28), MAT_TRIM)
    # Warning lamp at the top: one accent pixel that catches the eye.
    p.cylinder((0.0, 0.0, h + 0.12), 0.1, 0.05, MAT_ACCENT, sides=6)
    return p


def billboard() -> Prop:
    """Billboard frame with a panel. Large background mass that breaks up the
    skyline without closing it off."""
    p = Prop("billboard")
    panel_w, panel_h = 5.2, 2.6
    base_z = 1.6
    for sx in (-1.7, 1.7):
        p.slab(sx, 0.0, 0.0, (0.16, 0.16, base_z + 0.2), MAT_DARK)
    p.frame((0.0, 0.0, base_z + panel_h * 0.5), (panel_w, 0.14, panel_h), 0.13, MAT_DARK)
    p.box((0.0, 0.05, base_z + panel_h * 0.5), (panel_w - 0.26, 0.05, panel_h - 0.26), MAT_TRIM)
    # Gantry lights along the bottom edge.
    for x in (-1.6, 0.0, 1.6):
        p.box((x, -0.16, base_z + 0.1), (0.3, 0.22, 0.1), MAT_DARK)
    return p


def roof_door() -> Prop:
    """Stair housing with a door. Reads as the way onto the roof, which gives the
    space a reason to exist."""
    p = Prop("roof_door")
    w, d, h = 1.5, 1.7, 2.25
    p.slab(0.0, 0.0, 0.0, (w, d, h), MAT_CONCRETE)
    p.box((0.0, 0.0, h + 0.05), (w + 0.18, d + 0.18, 0.1), MAT_DARK)
    # Door recessed into the leading face.
    p.box((w * 0.5 + 0.01, 0.0, 1.02), (0.05, 0.86, 1.98), MAT_DARK)
    p.box((w * 0.5 + 0.04, 0.3, 1.0), (0.04, 0.09, 0.09), MAT_ACCENT)
    return p


def skylight() -> Prop:
    """Low glazed skylight. Its glass is the only emissive surface in the kit, so it
    gives a dark roof a point of interest without lighting cost."""
    p = Prop("skylight")
    p.slab(0.0, 0.0, 0.0, (2.0, 1.4, 0.18), MAT_DARK)
    p.slab(0.0, 0.0, 0.18, (1.78, 1.2, 0.26), MAT_GLASS)
    for y in (-0.4, 0.0, 0.4):
        p.box((0.0, y, 0.32), (1.84, 0.06, 0.05), MAT_DARK)
    return p


# ---------------------------------------------------------------------------

PROPS = {
    # furniture — collision is provided separately by BoxBlock
    "ac_unit": ac_unit,
    "crate": crate,
    "transformer": transformer,
    "duct_section": duct_section,
    # scenery — never collides
    "vent_stack": vent_stack,
    "pipe_run": pipe_run,
    "railing": railing,
    "scaffold": scaffold,
    "water_tank": water_tank,
    "antenna_mast": antenna_mast,
    "billboard": billboard,
    "roof_door": roof_door,
    "skylight": skylight,
}


def main() -> None:
    out_dir = os.path.abspath(parse_out_dir("game/assets/props"))
    print(f"[build_kit] output -> {out_dir}")

    total_triangles = 0
    for name, factory in PROPS.items():
        # Full scene reset per prop. Exporting with `use_selection` from a shared
        # scene is one stray selection away from bundling the wrong mesh, and that
        # failure is invisible until something appears in the wrong place in game.
        reset_scene()
        materials = ensure_materials()

        prop = factory()
        obj = prop.to_object(materials)
        recalculate_normals(obj)

        path = os.path.join(out_dir, f"{name}.glb")
        export_glb(obj, path)

        triangles = prop.triangle_count()
        total_triangles += triangles
        print(f"[build_kit] {name:<14} {triangles:>5} tris  -> {os.path.basename(path)}")

    print(f"[build_kit] {len(PROPS)} props, {total_triangles} triangles total")
    print("BUILD_KIT: DONE")


if __name__ == "__main__":
    main()
