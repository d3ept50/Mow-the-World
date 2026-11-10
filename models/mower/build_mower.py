"""Builds a low-poly push mower for Mow the World.

Run:  blender --background --factory-startup --python build_mower.py
Outputs (next to this script): mower.blend, mower.fbx, preview_front.png, preview_rear.png

Units: 1 Blender unit = 1 Roblox stud. Front of the mower faces +Y (Roblox front, -Z).
"""
import math
import os

import bpy
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))

PALETTE = {
    "Red": "#D8342B",
    "DarkGrey": "#3A3D42",
    "Black": "#1B1C1E",
    "Yellow": "#F5C22E",
    "Metal": "#A9AFB7",
    "White": "#ECEDEF",
    "Bag": "#4A5A3C",
}


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


_mats = {}


def mat(name, hex_color=None, rough=0.6):
    if name in _mats:
        return _mats[name]
    s = hexc(hex_color or PALETTE[name])
    lin = tuple(srgb_to_lin(c) for c in s) + (1.0,)
    m = bpy.data.materials.new(name)
    m.diffuse_color = lin
    if m.node_tree is None:
        try:
            m.use_nodes = True
        except Exception:
            pass
    if m.node_tree:
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b:
            b.inputs["Base Color"].default_value = lin
            b.inputs["Roughness"].default_value = rough
    m["srgb"] = s
    _mats[name] = m
    return m


def box(name, size, loc, m, bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat(m))
    return o


def cyl(name, r, depth, loc, m, axis="Z", verts=20, rot=None):
    if rot is None:
        rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4  # smooth sides, flat caps
    o.data.materials.append(mat(m))
    return o


def tube(name, p1, p2, r, m, verts=10):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    return cyl(name, r, d.length, (p1 + p2) / 2, m, verts=verts, rot=rot)


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


def bake_vertex_colors(o):
    """Copy each face's material colour into a colour attribute (Roblox reads these)."""
    me = o.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cols = [tuple(m["srgb"]) + (1.0,) for m in me.materials]
    for p in me.polygons:
        c = cols[p.material_index]
        for li in p.loop_indices:
            attr.data[li].color_srgb = c


# ---------------------------------------------------------------- scene reset
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

# ---------------------------------------------------------------- body
body = [
    box("Deck", (2.4, 3.2, 0.55), (0, 0, 0.78), "Red", bevel=0.14),
    box("Bumper", (2.5, 0.22, 0.3), (0, 1.58, 0.62), "Black", bevel=0.05),
    box("Stripe", (2.44, 0.3, 0.59), (0, 1.05, 0.78), "White", bevel=0.14),
    box("Chute", (0.45, 0.9, 0.32), (-1.3, 0.0, 0.72), "Black", bevel=0.08),
    box("Engine", (1.3, 1.5, 0.7), (0, 0.1, 1.38), "DarkGrey", bevel=0.1),
    cyl("RecoilCap", 0.55, 0.22, (0, 0.1, 1.84), "Yellow"),
    cyl("RecoilKnob", 0.2, 0.1, (0, 0.1, 2.0), "Black", verts=12),
    box("Tank", (0.8, 0.6, 0.5), (0, -0.95, 1.28), "White", bevel=0.1),
    cyl("FuelCap", 0.14, 0.1, (0, -0.95, 1.58), "Red", verts=12),
    cyl("Exhaust", 0.14, 0.5, (0.85, 0.45, 1.3), "Metal", axis="X", verts=12),
    cyl("AxleFront", 0.08, 2.7, (0, 1.1, 0.4), "Metal", axis="X", verts=8),
    cyl("AxleRear", 0.08, 2.7, (0, -1.1, 0.55), "Metal", axis="X", verts=8),
    box("Bag", (1.5, 1.3, 1.1), (0, -2.2, 1.15), "Bag", bevel=0.22),
    box("BagFrame", (1.6, 0.14, 0.14), (0, -1.6, 1.62), "Black", bevel=0.03),
]
H0, H1 = (-1.45, 0.95), (-3.1, 3.5)  # handle (y, z) bottom / top
for sx in (-1, 1):
    x = 0.95 * sx
    body.append(tube("HandleBar", (x, H0[0], H0[1]), (x, H1[0], H1[1]), 0.07, "Metal"))
body.append(tube("HandleTop", (-0.95, H1[0], H1[1]), (0.95, H1[0], H1[1]), 0.07, "Metal"))
body.append(tube("Grip", (-0.65, H1[0], H1[1]), (0.65, H1[0], H1[1]), 0.11, "Black", verts=12))
ym, zm = (H0[0] + H1[0]) / 2, (H0[1] + H1[1]) / 2
body.append(tube("HandleBrace", (-0.95, ym, zm), (0.95, ym, zm), 0.05, "Metal", verts=8))
body_obj = join("Body", body)
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

# ---------------------------------------------------------------- wheels (separate, so they can spin)
wheels = []
for label, x, y, r in (("FL", -1.42, 1.1, 0.4), ("FR", 1.42, 1.1, 0.4),
                       ("RL", -1.42, -1.1, 0.55), ("RR", 1.42, -1.1, 0.55)):
    tyre = cyl("Tyre", r, 0.36, (x, y, r), "Black", axis="X", verts=20)
    hub = cyl("Hub", r * 0.55, 0.42, (x, y, r), "Yellow", axis="X", verts=12)
    wheels.append(join("Wheel_" + label, [tyre, hub]))

# ---------------------------------------------------------------- blade (separate, spins around Z)
blade = join("Blade", [
    cyl("BladeHub", 0.15, 0.1, (0, 0, 0.42), "Metal", verts=10),
    box("BladeBar", (1.9, 0.22, 0.05), (0, 0, 0.42), "Metal", bevel=0),
])

model = [body_obj, blade] + wheels
tris = 0
for o in model:
    bake_vertex_colors(o)
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
print("MOWER_TRIS", tris)

# ---------------------------------------------------------------- export FBX (model only)
bpy.ops.object.select_all(action="DESELECT")
for o in model:
    o.select_set(True)
bpy.context.view_layer.objects.active = body_obj
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "mower.fbx"),
    use_selection=True,
    global_scale=0.01,          # 1 Blender unit -> 1 stud in Roblox
    object_types={"MESH"},
    colors_type="SRGB",
    mesh_smooth_type="FACE",
    bake_anim=False,
)

# ---------------------------------------------------------------- preview scene
scene = bpy.context.scene
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "PreviewGround"
ground.data.materials.append(mat("Grass", "#6DBB4A", rough=0.9))

bpy.ops.object.light_add(type="SUN", location=(4, 2, 10), rotation=(math.radians(40), 0, math.radians(120)))
bpy.context.active_object.data.energy = 3.5
bpy.context.active_object.data.angle = math.radians(8)

world = scene.world or bpy.data.worlds.new("World")
scene.world = world
if world.node_tree is None:
    try:
        world.use_nodes = True
    except Exception:
        pass
if world.node_tree:
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.55, 0.75, 1.0, 1.0)
        bg.inputs[1].default_value = 1.0

bpy.ops.object.empty_add(location=(0, -0.7, 1.4))
target = bpy.context.active_object
target.name = "PreviewTarget"
bpy.ops.object.camera_add()
cam = bpy.context.active_object
cam.name = "PreviewCamera"
con = cam.constraints.new("TRACK_TO")
con.target = target
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.samples = 48
try:
    scene.cycles.use_denoising = True
except Exception:
    pass
scene.render.resolution_x = 1000
scene.render.resolution_y = 750
scene.view_settings.view_transform = "Standard"

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "mower.blend"))

for fname, loc in (("preview_front.png", (6.2, 6.0, 4.2)), ("preview_rear.png", (-5.5, -8.0, 4.6))):
    cam.location = loc
    scene.render.filepath = os.path.join(OUT, fname)
    bpy.ops.render.render(write_still=True)
print("MOWER_DONE")
