"""Shared mesh-building helpers for the headless environment kit.

Kept separate from ``build_kit.py`` so the primitives can be reasoned about and
fixed once. Everything here builds raw vertex/face lists rather than calling
``bpy.ops``: operator-based modelling depends on selection state and the active
object, which makes a long generation script fragile in exactly the way a
reproducible pipeline must not be.

Coordinate convention matches ``rig_spec.py`` — built in Blender's Z-up space and
converted on export, so in game terms:

===============  ==================  ====================
Blender axis     glTF / Godot axis   Meaning in the game
===============  ==================  ====================
``+X``           ``+X``              forward, direction of travel
``+Z``           ``+Y``              up
``+Y``           ``-Z``              into the screen
===============  ==================  ====================

Props are modelled with their **base at Z = 0 and centred on X/Y**, so placement
code can position them by their footprint rather than by guessing at an offset.
"""

from __future__ import annotations

import math
import os

import bpy  # type: ignore
from mathutils import Vector  # type: ignore

TAU = math.pi * 2.0

# Material names. Godot replaces these on import with tuned materials keyed by
# name, so the kit only has to declare *intent* — which surface is structure, which
# is furniture, which is an accent.
MAT_CONCRETE = "kit_concrete"
MAT_METAL = "kit_metal"
MAT_DARK = "kit_dark"
MAT_TRIM = "kit_trim"
MAT_ACCENT = "kit_accent"
MAT_GLASS = "kit_glass"

MATERIAL_COLOURS = {
    MAT_CONCRETE: (0.30, 0.325, 0.37),
    MAT_METAL: (0.44, 0.475, 0.53),
    MAT_DARK: (0.125, 0.14, 0.175),
    MAT_TRIM: (0.20, 0.22, 0.26),
    MAT_ACCENT: (0.86, 0.46, 0.13),
    MAT_GLASS: (0.16, 0.24, 0.32),
}


def reset_scene() -> None:
    """Empties the file. ``--factory-startup`` avoids user config, not the cube."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.objects, bpy.data.materials):
        for item in list(collection):
            try:
                collection.remove(item)
            except RuntimeError:
                pass


def ensure_materials() -> dict[str, bpy.types.Material]:
    materials: dict[str, bpy.types.Material] = {}
    for name, rgb in MATERIAL_COLOURS.items():
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
                bsdf.inputs["Roughness"].default_value = 0.78
                bsdf.inputs["Metallic"].default_value = (
                    0.25 if name == MAT_METAL else 0.0
                )
        materials[name] = mat
    return materials


class Prop:
    """Accumulates geometry for one prop, tracking a material per face."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_material: list[str] = []

    # -- primitives ---------------------------------------------------------

    def box(self, centre: tuple | Vector, size: tuple | Vector, material: str) -> None:
        """Axis-aligned box, centred on `centre`."""
        c = Vector(centre)
        h = Vector(size) * 0.5
        base = len(self.verts)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    self.verts.append(c + Vector((h.x * sx, h.y * sy, h.z * sz)))
        v = [base + i for i in range(8)]
        # Winding is not consistent here; `normals_make_consistent` on export fixes
        # it. Ordering all six quads by hand is error-prone and buys nothing.
        for quad in (
            (v[0], v[1], v[3], v[2]),
            (v[4], v[6], v[7], v[5]),
            (v[0], v[2], v[6], v[4]),
            (v[1], v[5], v[7], v[3]),
            (v[0], v[4], v[5], v[1]),
            (v[2], v[3], v[7], v[6]),
        ):
            self.faces.append(quad)
            self.face_material.append(material)

    def slab(
        self,
        x: float,
        y: float,
        z_base: float,
        size: tuple,
        material: str,
    ) -> None:
        """Box sitting *on* `z_base` rather than centred on it — how props are
        actually described ("a 0.9 m tall unit on the roof")."""
        self.box((x, y, z_base + size[2] * 0.5), size, material)

    def cylinder(
        self,
        base: tuple | Vector,
        height: float,
        radius: float,
        material: str,
        sides: int = 8,
        top_radius: float | None = None,
        axis: str = "Z",
    ) -> None:
        """Vertical (or axis-aligned) tapered cylinder, `base` at the bottom centre."""
        b = Vector(base)
        r_top = radius if top_radius is None else top_radius

        def point(angle: float, r: float, along: float) -> Vector:
            ca, sa = math.cos(angle) * r, math.sin(angle) * r
            if axis == "Z":
                return b + Vector((ca, sa, along))
            if axis == "X":
                return b + Vector((along, ca, sa))
            return b + Vector((ca, along, sa))

        lower = []
        upper = []
        for i in range(sides):
            angle = TAU * i / sides
            self.verts.append(point(angle, radius, 0.0))
            lower.append(len(self.verts) - 1)
            self.verts.append(point(angle, r_top, height))
            upper.append(len(self.verts) - 1)

        for i in range(sides):
            j = (i + 1) % sides
            self.faces.append((lower[i], lower[j], upper[j], upper[i]))
            self.face_material.append(material)

        # Caps as fans.
        for ring, along, r in ((lower, 0.0, radius), (upper, height, r_top)):
            self.verts.append(point(0.0, 0.0, along))
            hub = len(self.verts) - 1
            for i in range(sides):
                j = (i + 1) % sides
                self.faces.append((ring[i], ring[j], hub))
                self.face_material.append(material)

    def frame(
        self,
        centre: tuple,
        size: tuple,
        thickness: float,
        material: str,
    ) -> None:
        """A rectangular outline in the X/Z plane — railings, billboard frames,
        scaffolding. Four bars rather than a solid panel, so the silhouette stays
        open and does not read as a wall."""
        cx, cy, cz = centre
        w, d, h = size
        half_w, half_h = w * 0.5, h * 0.5
        # verticals
        for sx in (-1, 1):
            self.box(
                (cx + sx * (half_w - thickness * 0.5), cy, cz),
                (thickness, d, h),
                material,
            )
        # horizontals
        for sz in (-1, 1):
            self.box(
                (cx, cy, cz + sz * (half_h - thickness * 0.5)),
                (w - thickness * 2.0, d, thickness),
                material,
            )

    # -- output -------------------------------------------------------------

    def triangle_count(self) -> int:
        return sum(len(f) - 2 for f in self.faces)

    def to_object(self, materials: dict[str, bpy.types.Material]) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(f"{self.name}_mesh")
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.validate(verbose=False)

        # One material slot per material actually used, so a prop made of concrete
        # and metal exports as two surfaces and Godot can override each.
        used: list[str] = []
        for name in self.face_material:
            if name not in used:
                used.append(name)
        for name in used:
            mesh.materials.append(materials[name])
        index_of = {name: i for i, name in enumerate(used)}
        for polygon, name in zip(mesh.polygons, self.face_material):
            polygon.material_index = index_of[name]
            # Flat shading: faceted geometry suits the stylised look and avoids
            # arguing with normal seams on low-poly meshes.
            polygon.use_smooth = False

        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def recalculate_normals(obj: bpy.types.Object) -> None:
    """Outward-facing normals. Generated faces have inconsistent winding, which
    shows up as holes once backface culling is on."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def export_glb(obj: bpy.types.Object, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=False,
        export_texcoords=False,
    )


def parse_out_dir(default: str) -> str:
    import sys

    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
        for i, arg in enumerate(argv):
            if arg == "--out" and i + 1 < len(argv):
                return argv[i + 1]
    return default
