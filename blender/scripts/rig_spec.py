"""The runner's skeleton and proportions — the single source of truth.

Imported by the mesh builder, the armature builder and (indirectly, via the
exported GLB) the Godot animator. Nothing about the character's dimensions is
written down twice.

Coordinate conventions
----------------------
Built in Blender's Z-up space. The glTF exporter converts to Y-up, mapping
Blender ``(x, y, z)`` to glTF ``(x, z, -y)``. So:

===============  ==================  ====================
Blender axis     glTF / Godot axis   Meaning in the game
===============  ==================  ====================
``+X``           ``+X``              forward, direction of travel
``+Z``           ``+Y``              up
``+Y``           ``-Z``              into the screen
===============  ==================  ====================

Left-side limbs therefore sit at **negative** Blender Y so they arrive at
positive Godot Z — the camera-facing side. That side is deliberately the one the
animator lights slightly brighter, so limb positions read against the torso.

Units are metres. The runner is 1.74 m tall with deliberately slightly long
limbs: at the ~150 px the character occupies on screen, exaggerated limb length
is what keeps a pose legible.
"""

# --- headline proportions -----------------------------------------------------

HEIGHT = 1.74
HIP_Y = 0.94
CHEST_Y = 1.26
SHOULDER_Y = 1.45
NECK_Y = 1.50
HEAD_TOP = 1.74

THIGH = 0.46
SHIN = 0.42
FOOT_LIFT = 0.06

UPPER_ARM = 0.31
FOREARM = 0.29
HAND = 0.11

# Lateral offsets. Negative Blender Y == camera-facing side in game.
LEG_SPREAD = 0.105
ARM_SPREAD = 0.165
SHOULDER_ROOT = 0.055

# --- radii, for the mesh builder ---------------------------------------------
# Tapered so the silhouette narrows toward the extremities, which reads as
# athletic rather than tubular.

R_HIP = 0.135
R_WAIST = 0.115
R_CHEST = 0.150
R_NECK = 0.058
R_HEAD = 0.098

R_THIGH_TOP = 0.088
R_THIGH_BOTTOM = 0.070
R_SHIN_TOP = 0.066
R_SHIN_BOTTOM = 0.044

R_UPPER_ARM_TOP = 0.058
R_UPPER_ARM_BOTTOM = 0.048
R_FOREARM_TOP = 0.046
R_FOREARM_BOTTOM = 0.034
R_HAND = 0.040


def mirrored(name: str, side: str) -> str:
    """Bone naming: ``Thigh`` -> ``ThighL`` / ``ThighR``."""
    return f"{name}{side}"


# --- skeleton -----------------------------------------------------------------
# (name, head, tail, parent). Bone roll is left at zero; the Godot animator poses
# bones about their local axes, and a zero-roll rest pose keeps "rotate about Z to
# swing forward" true for every bone, which is what the pose convention relies on.

def build_skeleton() -> list[tuple[str, tuple, tuple, str | None]]:
    bones: list[tuple[str, tuple, tuple, str | None]] = [
        # Spine chain. `Root` stays at the origin so the GLB has a stable anchor
        # for the whole rig regardless of how the body is posed.
        ("Root", (0.0, 0.0, 0.0), (0.0, 0.0, HIP_Y), None),
        ("Hips", (0.0, 0.0, HIP_Y), (0.0, 0.0, 1.06), "Root"),
        ("Spine", (0.0, 0.0, 1.06), (0.0, 0.0, CHEST_Y), "Hips"),
        ("Chest", (0.0, 0.0, CHEST_Y), (0.0, 0.0, SHOULDER_Y), "Spine"),
        ("Neck", (0.0, 0.0, SHOULDER_Y), (0.0, 0.0, NECK_Y), "Chest"),
        ("Head", (0.0, 0.0, NECK_Y), (0.0, 0.0, HEAD_TOP), "Neck"),
    ]

    for side, sign in (("L", -1.0), ("R", 1.0)):
        lateral_leg = sign * LEG_SPREAD
        lateral_arm = sign * ARM_SPREAD

        bones += [
            (
                mirrored("Shoulder", side),
                (0.0, sign * SHOULDER_ROOT, SHOULDER_Y - 0.02),
                (0.0, lateral_arm, SHOULDER_Y - 0.02),
                "Chest",
            ),
            (
                mirrored("UpperArm", side),
                (0.0, lateral_arm, SHOULDER_Y - 0.02),
                (0.0, lateral_arm, SHOULDER_Y - 0.02 - UPPER_ARM),
                mirrored("Shoulder", side),
            ),
            (
                mirrored("Forearm", side),
                (0.0, lateral_arm, SHOULDER_Y - 0.02 - UPPER_ARM),
                (0.0, lateral_arm, SHOULDER_Y - 0.02 - UPPER_ARM - FOREARM),
                mirrored("UpperArm", side),
            ),
            (
                mirrored("Hand", side),
                (0.0, lateral_arm, SHOULDER_Y - 0.02 - UPPER_ARM - FOREARM),
                (0.0, lateral_arm, SHOULDER_Y - 0.02 - UPPER_ARM - FOREARM - HAND),
                mirrored("Forearm", side),
            ),
            (
                mirrored("Thigh", side),
                (0.0, lateral_leg, HIP_Y),
                (0.0, lateral_leg, HIP_Y - THIGH),
                "Hips",
            ),
            (
                mirrored("Shin", side),
                (0.0, lateral_leg, HIP_Y - THIGH),
                (0.0, lateral_leg, HIP_Y - THIGH - SHIN),
                mirrored("Thigh", side),
            ),
            (
                mirrored("Foot", side),
                (0.0, lateral_leg, FOOT_LIFT),
                (0.16, lateral_leg, 0.015),
                mirrored("Shin", side),
            ),
        ]

    return bones


# --- materials ----------------------------------------------------------------
# Only names and rough values are set here. Godot replaces these on import with
# tuned StandardMaterial3D instances (see `runner_materials.gd`), because art
# direction needs a fast iteration loop and re-running Blender is not one.

MATERIALS = {
    "suit": (0.042, 0.050, 0.068),
    "trim": (0.082, 0.092, 0.115),
    "accent": (0.860, 0.460, 0.130),
}
