"""Generates the runner: mesh, armature, skin weights, exported as GLB.

Run headlessly:

    blender --background --factory-startup \
        --python blender/scripts/build_runner.py -- --out game/assets/characters

Nothing here is hand-edited in a GUI. The whole character is reproducible from
this file plus ``rig_spec.py``, which is the point: a ``.blend`` that cannot be
regenerated is a liability the moment proportions need to change, and they will.

Design brief
------------
Original minimalist courier. Dark, athletic, clean geometry, and above all
**readable in silhouette from the side** — that is the only visual property the
game actually depends on. Concretely:

* limbs taper toward the extremities, so the outline narrows and reads as athletic
  rather than tubular,
* an accent shoulder yoke gives body orientation and lean a readable landmark at
  small sizes,
* a low backpack breaks the torso outline so the back is distinguishable from the
  front even when the figure is a flat dark shape,
* low polygon count — this is a browser game, and a stylised figure gains nothing
  from density.

Skinning is deliberate rather than automatic. Blender's automatic weights produce
soft, slightly blobby falloff; each mesh ring here is instead bound to its own
bone, with only the rings flanking a joint blended. For a stylised figure that
gives crisp, predictable deformation, and predictable is worth more than smooth
when the same rig has to hold up in a vault, a slide and a hang.
"""

from __future__ import annotations

import math
import os
import sys

import bpy  # type: ignore
from mathutils import Vector  # type: ignore

# Blender runs this file directly, so the script's own directory is not on the
# path. Add it so `rig_spec` imports.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rig_spec as spec  # noqa: E402

# Sides of each limb tube. Eight reads as round enough at gameplay scale while
# keeping the whole character a few hundred triangles.
SIDES = 8


# ---------------------------------------------------------------------------
# scene helpers
# ---------------------------------------------------------------------------


def reset_scene() -> None:
    """Empties the file. `--factory-startup` avoids user config, not the cube."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
        for item in list(collection):
            collection.remove(item)


def make_material(name: str, rgb: tuple[float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.72
        bsdf.inputs["Metallic"].default_value = 0.0
    return mat


# ---------------------------------------------------------------------------
# geometry primitives
# ---------------------------------------------------------------------------


class MeshBuilder:
    """Accumulates vertices, faces, per-face material and per-vertex bone weights.

    Weights are recorded as the geometry is generated. That is the reason this is a
    builder rather than a pile of `bpy.ops` calls: at generation time we know
    exactly which bone every ring belongs to, so binding is exact and needs no
    guessing afterwards.
    """

    def __init__(self) -> None:
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_material: list[int] = []
        # vertex index -> {bone name: weight}
        self.weights: list[dict[str, float]] = []

    def add_ring(
        self,
        centre: Vector,
        radius_y: float,
        radius_x: float,
        bone_weights: dict[str, float],
        squash_x: float = 1.0,
    ) -> list[int]:
        """A ring of vertices in the plane perpendicular to the body's up axis."""
        indices = []
        for i in range(SIDES):
            angle = TAU * i / SIDES
            # mathutils.Vector takes a single sequence, not separate components.
            offset = Vector((
                math.cos(angle) * radius_x * squash_x,
                math.sin(angle) * radius_y,
                0.0,
            ))
            self.verts.append(centre + offset)
            self.weights.append(dict(bone_weights))
            indices.append(len(self.verts) - 1)
        return indices

    def bridge(self, lower: list[int], upper: list[int], material: int) -> None:
        """Quads between two equal-length rings."""
        for i in range(SIDES):
            j = (i + 1) % SIDES
            self.faces.append((lower[i], lower[j], upper[j], upper[i]))
            self.face_material.append(material)

    def cap(self, ring: list[int], centre: Vector, material: int,
            bone_weights: dict[str, float], flip: bool = False) -> None:
        self.verts.append(centre)
        self.weights.append(dict(bone_weights))
        hub = len(self.verts) - 1
        for i in range(SIDES):
            j = (i + 1) % SIDES
            tri = (ring[i], ring[j], hub) if not flip else (ring[j], ring[i], hub)
            self.faces.append(tri)
            self.face_material.append(material)

    def add_box(
        self,
        centre: Vector,
        size: Vector,
        material: int,
        bone_weights: dict[str, float],
    ) -> None:
        """Axis-aligned box. Used for the accent yoke, backpack and feet."""
        half = size * 0.5
        base = len(self.verts)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    self.verts.append(
                        centre + Vector((half.x * sx, half.y * sy, half.z * sz))
                    )
                    self.weights.append(dict(bone_weights))
        # Corner ordering above is (x, y, z) with z innermost.
        c = [base + i for i in range(8)]
        quads = [
            (c[0], c[1], c[3], c[2]),  # -X
            (c[4], c[6], c[7], c[5]),  # +X
            (c[0], c[2], c[6], c[4]),  # -Z... (orientation fixed by recalc below)
            (c[1], c[5], c[7], c[3]),
            (c[0], c[4], c[5], c[1]),
            (c[2], c[3], c[7], c[6]),
        ]
        for quad in quads:
            self.faces.append(quad)
            self.face_material.append(material)


TAU = math.pi * 2.0


def tube(
    builder: MeshBuilder,
    start: Vector,
    end: Vector,
    r_start: float,
    r_end: float,
    bone: str,
    material: int,
    parent_bone: str | None = None,
    segments: int = 3,
    squash_x: float = 1.0,
) -> None:
    """A tapered tube from `start` to `end`, bound to `bone`.

    The first ring blends 50/50 with `parent_bone` when given. That single blended
    ring is what stops a joint from tearing open or visibly creasing when the limb
    rotates, without the soft smearing that full automatic weighting produces.
    """
    rings: list[list[int]] = []
    for s in range(segments + 1):
        t = s / segments
        centre = start.lerp(end, t)
        radius = r_start + (r_end - r_start) * t
        if s == 0 and parent_bone:
            weights = {bone: 0.5, parent_bone: 0.5}
        else:
            weights = {bone: 1.0}
        rings.append(
            builder.add_ring(centre, radius, radius, weights, squash_x=squash_x)
        )

    for s in range(segments):
        builder.bridge(rings[s], rings[s + 1], material)

    builder.cap(rings[0], start, material, {bone: 1.0}, flip=True)
    builder.cap(rings[-1], end, material, {bone: 1.0})


# ---------------------------------------------------------------------------
# the character
# ---------------------------------------------------------------------------


def build_body(builder: MeshBuilder, mat: dict[str, int]) -> None:
    suit, trim, accent = mat["suit"], mat["trim"], mat["accent"]

    # --- torso ---------------------------------------------------------------
    # Built as three stacked tapered sections so the waist pinches and the chest
    # broadens. Slightly flattened front-to-back (`squash_x`), which makes the
    # side-on silhouette read as a body rather than a cylinder.
    hips = Vector((0.0, 0.0, spec.HIP_Y))
    waist = Vector((0.0, 0.0, 1.08))
    chest = Vector((0.0, 0.0, spec.CHEST_Y))
    shoulders = Vector((0.0, 0.0, spec.SHOULDER_Y))

    tube(builder, hips, waist, spec.R_HIP, spec.R_WAIST, "Hips", suit, squash_x=0.78)
    tube(builder, waist, chest, spec.R_WAIST, spec.R_CHEST, "Spine", suit,
         parent_bone="Hips", squash_x=0.78)
    tube(builder, chest, shoulders, spec.R_CHEST, spec.R_CHEST * 0.88, "Chest", suit,
         parent_bone="Spine", squash_x=0.78)

    # --- head and neck -------------------------------------------------------
    neck_top = Vector((0.0, 0.0, spec.NECK_Y))
    tube(builder, shoulders, neck_top, spec.R_NECK * 1.2, spec.R_NECK, "Neck", suit,
         parent_bone="Chest")
    # Head: a tube stretched *forward* rather than squashed.
    #
    # Deeper than it is wide, because the side profile is the only view that matters.
    # The first version was 0.20 m front-to-back and 0.24 m tall, which from the side
    # is a tall narrow box — on screen it read unmistakably as a top hat.
    tube(builder, neck_top, Vector((0.0, 0.0, spec.HEAD_TOP)),
         spec.R_HEAD, spec.R_HEAD * 0.86, "Head", suit,
         parent_bone="Neck", segments=2, squash_x=spec.HEAD_DEPTH_SCALE)
    # Occipital mass at the back of the skull. Gives the head a clear direction in
    # silhouette, which is what tells the player which way the runner faces when
    # everything else is a flat dark shape.
    builder.add_box(
        Vector((-0.07, 0.0, spec.HEAD_TOP - 0.11)),
        Vector((0.075, 0.155, 0.125)),
        suit,
        {"Head": 1.0},
    )

    # --- accent shoulder yoke ------------------------------------------------
    # The one bright element. It is doing readability work: at 150 px a
    # near-black figure's *orientation* and *lean* are otherwise guesswork.
    builder.add_box(
        Vector((0.0, 0.0, spec.SHOULDER_Y - 0.055)),
        Vector((0.20, 0.40, 0.062)),
        accent,
        {"Chest": 1.0},
    )

    # --- backpack ------------------------------------------------------------
    # Breaks the torso outline so front and back are distinguishable in pure
    # silhouette, which matters the instant the runner turns around.
    builder.add_box(
        Vector((-0.115, 0.0, 1.20)),
        Vector((0.11, 0.24, 0.30)),
        trim,
        {"Chest": 1.0},
    )

    # --- limbs ---------------------------------------------------------------
    for side, sign in (("L", -1.0), ("R", 1.0)):
        lateral_arm = sign * spec.ARM_SPREAD
        lateral_leg = sign * spec.LEG_SPREAD

        shoulder_z = spec.SHOULDER_Y - 0.02
        elbow_z = shoulder_z - spec.UPPER_ARM
        wrist_z = elbow_z - spec.FOREARM

        # Deltoid cap, so the arm joins the torso instead of intersecting it.
        tube(
            builder,
            Vector((0.0, sign * spec.SHOULDER_ROOT, shoulder_z)),
            Vector((0.0, lateral_arm, shoulder_z)),
            spec.R_CHEST * 0.42,
            spec.R_UPPER_ARM_TOP,
            f"Shoulder{side}",
            suit,
            parent_bone="Chest",
            segments=2,
        )
        tube(
            builder,
            Vector((0.0, lateral_arm, shoulder_z)),
            Vector((0.0, lateral_arm, elbow_z)),
            spec.R_UPPER_ARM_TOP,
            spec.R_UPPER_ARM_BOTTOM,
            f"UpperArm{side}",
            # Arms use the lighter `trim` value, not `suit`.
            #
            # They hang directly in front of the torso in a side view, and at the same
            # value they vanished into it — the figure read as a headless block with
            # legs, and no arm-swing was visible at all despite being animated. A
            # single value step is enough to separate them while keeping the whole
            # figure firmly in silhouette.
            trim,
            parent_bone=f"Shoulder{side}",
        )
        tube(
            builder,
            Vector((0.0, lateral_arm, elbow_z)),
            Vector((0.0, lateral_arm, wrist_z)),
            spec.R_FOREARM_TOP,
            spec.R_FOREARM_BOTTOM,
            f"Forearm{side}",
            trim,
            parent_bone=f"UpperArm{side}",
        )
        tube(
            builder,
            Vector((0.0, lateral_arm, wrist_z)),
            Vector((0.0, lateral_arm, wrist_z - spec.HAND)),
            spec.R_HAND,
            spec.R_HAND * 0.7,
            f"Hand{side}",
            trim,
            parent_bone=f"Forearm{side}",
            segments=1,
        )

        knee_z = spec.HIP_Y - spec.THIGH
        ankle_z = knee_z - spec.SHIN
        tube(
            builder,
            Vector((0.0, lateral_leg, spec.HIP_Y + 0.02)),
            Vector((0.0, lateral_leg, knee_z)),
            spec.R_THIGH_TOP,
            spec.R_THIGH_BOTTOM,
            f"Thigh{side}",
            suit,
            parent_bone="Hips",
            segments=4,
        )
        tube(
            builder,
            Vector((0.0, lateral_leg, knee_z)),
            Vector((0.0, lateral_leg, ankle_z)),
            spec.R_SHIN_TOP,
            spec.R_SHIN_BOTTOM,
            f"Shin{side}",
            suit,
            parent_bone=f"Thigh{side}",
            segments=4,
        )
        # Foot as a forward wedge. A visible foot shape is what makes a running
        # gait's contacts legible; a rounded stump does not read as planting.
        builder.add_box(
            Vector((0.055, lateral_leg, spec.FOOT_LIFT * 0.55)),
            Vector((0.22, 0.085, 0.072)),
            trim,
            {f"Foot{side}": 1.0},
        )


# ---------------------------------------------------------------------------
# assembly
# ---------------------------------------------------------------------------


def create_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("RunnerSkeleton")
    obj = bpy.data.objects.new("Skeleton", armature)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    created: dict[str, bpy.types.EditBone] = {}
    for name, head, tail, parent in spec.build_skeleton():
        bone = armature.edit_bones.new(name)
        bone.head = Vector(head)
        bone.tail = Vector(tail)
        bone.roll = 0.0
        if parent:
            bone.parent = created[parent]
            bone.use_connect = False
        created[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def create_mesh(builder: MeshBuilder, materials: list[bpy.types.Material]) -> bpy.types.Object:
    mesh = bpy.data.meshes.new("RunnerMesh")
    mesh.from_pydata([tuple(v) for v in builder.verts], [], builder.faces)
    mesh.validate(verbose=False)

    for material in materials:
        mesh.materials.append(material)
    for polygon, material_index in zip(mesh.polygons, builder.face_material):
        polygon.material_index = material_index

    obj = bpy.data.objects.new("Runner", mesh)
    bpy.context.collection.objects.link(obj)

    # Flat-shade the whole figure. Faceted geometry suits the stylised look, and it
    # means no normal seams to argue with on a low-poly mesh.
    for polygon in mesh.polygons:
        polygon.use_smooth = False

    return obj


def bind_weights(mesh_obj: bpy.types.Object, builder: MeshBuilder) -> None:
    groups: dict[str, bpy.types.VertexGroup] = {}
    for index, weights in enumerate(builder.weights):
        for bone, weight in weights.items():
            if bone not in groups:
                groups[bone] = mesh_obj.vertex_groups.new(name=bone)
            groups[bone].add([index], weight, "REPLACE")


def parent_to_armature(mesh_obj: bpy.types.Object, armature_obj: bpy.types.Object) -> None:
    modifier = mesh_obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature_obj
    mesh_obj.parent = armature_obj


def recalculate_normals(mesh_obj: bpy.types.Object) -> None:
    """Outward-facing normals.

    Generated faces have inconsistent winding — the box helper in particular — and
    inconsistent winding shows up as a figure with holes in it once backface
    culling is on. Cheaper to fix here than to hand-order every quad.
    """
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def export_glb(path: str, mesh_obj: bpy.types.Object, armature_obj: bpy.types.Object) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    armature_obj.select_set(True)
    bpy.context.view_layer.objects.active = armature_obj

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_skins=True,
        export_animations=False,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=False,
        export_texcoords=False,
        # Every bone must survive, including ones with no vertices weighted to
        # them. Godot poses the skeleton by name, and a deformer-only export would
        # silently drop bones the animator expects to find.
        export_def_bones=False,
    )


def parse_out_dir(default: str) -> str:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
        for i, arg in enumerate(argv):
            if arg == "--out" and i + 1 < len(argv):
                return argv[i + 1]
    return default


def main() -> None:
    out_dir = parse_out_dir("game/assets/characters")
    out_path = os.path.abspath(os.path.join(out_dir, "runner.glb"))

    print(f"[build_runner] generating -> {out_path}")
    reset_scene()

    materials = [make_material(name, rgb) for name, rgb in spec.MATERIALS.items()]
    material_index = {mat.name: i for i, mat in enumerate(materials)}

    builder = MeshBuilder()
    build_body(builder, material_index)

    armature_obj = create_armature()
    mesh_obj = create_mesh(builder, materials)
    bind_weights(mesh_obj, builder)
    parent_to_armature(mesh_obj, armature_obj)
    recalculate_normals(mesh_obj)

    export_glb(out_path, mesh_obj, armature_obj)

    triangles = sum(len(f) - 2 for f in builder.faces)
    print(f"[build_runner] vertices : {len(builder.verts)}")
    print(f"[build_runner] triangles: {triangles}")
    print(f"[build_runner] bones    : {len(spec.build_skeleton())}")
    print(f"[build_runner] wrote    : {out_path}")
    print("BUILD_RUNNER: DONE")


if __name__ == "__main__":
    main()
