"""Builds the Electric, Petrol, Professional and Ride-On mowers for Mow the World.

Run:  blender --background --factory-startup --python build_mowers.py
Outputs (next to this script): mower_<name>.fbx x4, mowers.blend,
preview_front.png, preview_rear.png

Each mower is a Body mesh plus four separate wheels and a Blade, so they can spin later.
Units: 1 Blender unit = 1 stud. Front faces +Y. On the pushed mowers the handle is always
the tallest and rearmost part: the game sizes the model by its height and puts the hands
on the bar. The Ride-On is sat on instead and has no handle.
"""
import math
import os

import bpy
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))

DARK = "#2B2D33"
BLACK = "#1B1C1E"
METAL = "#A9AFB7"
WHITE = "#ECEDEF"


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


_mats = {}


def mat(hex_color, rough=0.55):
    if hex_color in _mats:
        return _mats[hex_color]
    h = hex_color.lstrip("#")
    s = tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    lin = tuple(srgb_to_lin(c) for c in s) + (1.0,)
    m = bpy.data.materials.new("Col_" + h)
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
    _mats[hex_color] = m
    return m


def box(size, loc, color, bevel=0.05, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat(color))
    return o


def cyl(r, depth, loc, color, axis="Z", verts=16, rot=None):
    if rot is None:
        rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4  # smooth sides, flat caps
    o.data.materials.append(mat(color))
    return o


def tube(p1, p2, r, color, verts=10):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    return cyl(r, d.length, (p1 + p2) / 2, color, verts=verts, rot=rot)


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
    me = o.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cols = [tuple(m["srgb"]) + (1.0,) for m in me.materials]
    for p in me.polygons:
        c = cols[p.material_index]
        for li in p.loop_indices:
            attr.data[li].color_srgb = c


# ------------------------------------------------------------------ shared pieces
def handle(parts, half_w, start, top, bar=METAL, grip=BLACK, brace=True):
    """Two bars from `start` (y, z) up and back to `top` (y, z), joined by a grip bar."""
    for sx in (-1, 1):
        x = half_w * sx
        parts.append(tube((x, start[0], start[1]), (x, top[0], top[1]), 0.07, bar))
    parts.append(tube((-half_w, top[0], top[1]), (half_w, top[0], top[1]), 0.07, bar))
    parts.append(tube((-0.65, top[0], top[1]), (0.65, top[0], top[1]), 0.11, grip, verts=12))
    if brace:
        ym, zm = (start[0] + top[0]) / 2, (start[1] + top[1]) / 2
        parts.append(tube((-half_w, ym, zm), (half_w, ym, zm), 0.05, bar, verts=8))


def wheels(specs, tyre=BLACK):
    """specs: (label, x, y, radius, width, hub colour). Returns one object per wheel."""
    out = []
    for label, x, y, r, w, hub in specs:
        t = cyl(r, w, (x, y, r), tyre, axis="X", verts=20)
        h = cyl(r * 0.55, w + 0.06, (x, y, r), hub, axis="X", verts=12)
        cap = cyl(r * 0.2, w + 0.12, (x, y, r), DARK, axis="X", verts=8)
        out.append(join("Wheel_" + label, [t, h, cap]))
    return out


def blade(z, length):
    return join("Blade", [
        cyl(0.15, 0.1, (0, 0, z), METAL, verts=10),
        box((length, 0.22, 0.05), (0, 0, z), METAL, bevel=0),
    ])


# ------------------------------------------------------------------ the four mowers
def electric():
    """Sleek and low: rounded blue deck, white motor dome, battery with a green light."""
    BLUE, GREEN, LAMP = "#3CAAE6", "#52E06A", "#FFE98A"
    b = [
        box((2.3, 3.0, 0.45), (0, 0, 0.72), BLUE, bevel=0.18),
        box((2.36, 2.2, 0.14), (0, 0, 0.6), WHITE, bevel=0.05),           # white skirt stripe
        box((1.5, 0.12, 0.16), (0, 1.5, 0.78), LAMP, bevel=0.04),         # light bar
        cyl(0.78, 0.42, (0, 0.25, 1.14), WHITE, verts=20),                # motor housing
        cyl(0.52, 0.16, (0, 0.25, 1.42), BLUE, verts=20),
        cyl(0.2, 0.08, (0, 0.25, 1.53), WHITE, verts=12),
        box((1.0, 0.62, 0.52), (0, -0.85, 1.2), DARK, bevel=0.1),         # battery
        box((0.6, 0.06, 0.12), (0, -0.53, 1.3), GREEN, bevel=0.02),       # charge light
        box((0.3, 0.2, 0.1), (0, -0.85, 1.5), DARK, bevel=0.03),          # battery handle
        box((1.5, 1.0, 0.9), (0, -2.0, 1.1), "#C9CED6", bevel=0.22),      # grass box
        box((1.56, 0.12, 0.12), (0, -1.5, 1.5), BLUE, bevel=0.03),
        cyl(0.07, 2.5, (0, 1.05, 0.38), METAL, axis="X", verts=8),
        cyl(0.07, 2.5, (0, -1.05, 0.45), METAL, axis="X", verts=8),
    ]
    handle(b, 0.85, (-1.35, 0.9), (-3.0, 3.5), bar=WHITE)
    b.append(box((1.76, 0.24, 0.3), (0, -2.86, 3.28), BLUE, bevel=0.06))  # control panel between the bars
    b.append(box((0.7, 0.08, 0.1), (0, -2.74, 3.3), GREEN, bevel=0.02))   # start lever
    ws = wheels([("FL", -1.3, 1.05, 0.38, 0.3, WHITE), ("FR", 1.3, 1.05, 0.38, 0.3, WHITE),
                 ("RL", -1.3, -1.05, 0.45, 0.32, WHITE), ("RR", 1.3, -1.05, 0.45, 0.32, WHITE)])
    return join("Body", b), ws, blade(0.42, 1.8)


def petrol():
    """Chunky orange deck, finned engine, fuel tank and an upright exhaust."""
    ORANGE, TANK = "#F0961E", "#E8E4D8"
    b = [
        box((2.5, 3.3, 0.6), (0, 0, 0.82), ORANGE, bevel=0.14),
        box((2.6, 0.24, 0.32), (0, 1.63, 0.66), BLACK, bevel=0.05),       # bumper
        box((0.5, 1.0, 0.34), (-1.38, 0.0, 0.76), BLACK, bevel=0.08),     # discharge chute
        box((1.45, 1.5, 0.8), (0, 0.2, 1.5), DARK, bevel=0.1),            # engine block
        cyl(0.58, 0.24, (0, 0.2, 2.0), BLACK, verts=18),                  # recoil housing
        cyl(0.2, 0.12, (0, 0.2, 2.17), ORANGE, verts=12),
        box((0.82, 0.62, 0.52), (0, -0.92, 1.38), TANK, bevel=0.1),       # fuel tank
        cyl(0.14, 0.1, (0, -0.92, 1.68), ORANGE, verts=12),
        cyl(0.24, 0.5, (-0.92, 0.3, 1.55), "#3A3D42", axis="X", verts=12),  # air filter
        cyl(0.2, 0.55, (0.95, 0.55, 1.45), METAL, axis="Y", verts=12),    # muffler
        cyl(0.1, 0.95, (0.95, 0.55, 1.95), METAL, verts=10),              # exhaust stack
        cyl(0.13, 0.12, (0.95, 0.55, 2.45), DARK, verts=10),
        box((1.6, 1.3, 1.15), (0, -2.3, 1.22), "#3A3D42", bevel=0.22),    # grass bag
        box((1.68, 0.14, 0.14), (0, -1.68, 1.72), BLACK, bevel=0.03),
        cyl(0.08, 2.8, (0, 1.15, 0.42), METAL, axis="X", verts=8),
        cyl(0.08, 2.8, (0, -1.15, 0.6), METAL, axis="X", verts=8),
    ]
    for i in range(4):  # cooling fins stacked on the front of the engine
        b.append(box((1.25, 0.2, 0.07), (0, 1.0, 1.24 + i * 0.17), METAL, bevel=0))
    handle(b, 0.95, (-1.5, 1.0), (-3.2, 3.6))
    b.append(box((1.96, 0.22, 0.26), (0, -3.04, 3.36), DARK, bevel=0.05))   # control panel between the bars
    b.append(box((0.3, 0.1, 0.2), (0.55, -2.94, 3.5), ORANGE, bevel=0.03))  # throttle lever
    ws = wheels([("FL", -1.45, 1.15, 0.42, 0.36, DARK), ("FR", 1.45, 1.15, 0.42, 0.36, DARK),
                 ("RL", -1.45, -1.15, 0.6, 0.4, DARK), ("RR", 1.45, -1.15, 0.6, 0.4, DARK)])
    return join("Body", b), ws, blade(0.46, 2.0)


def professional():
    """Wide green deck with yellow trim, guard bar, twin filters, chrome stack, big bag."""
    GREEN, YELLOW, CHROME, BAG = "#32A050", "#FADC3C", "#D5DAE0", "#245C33"
    b = [
        box((3.0, 3.5, 0.6), (0, 0, 0.9), GREEN, bevel=0.14),
        box((3.06, 2.6, 0.14), (0, 0, 0.74), YELLOW, bevel=0.05),         # yellow skirt
        box((0.55, 1.1, 0.36), (-1.65, 0.0, 0.82), BLACK, bevel=0.08),    # discharge chute
        box((1.65, 1.6, 0.9), (0, 0.25, 1.65), DARK, bevel=0.1),          # engine
        cyl(0.62, 0.26, (0, 0.25, 2.2), YELLOW, verts=18),
        cyl(0.22, 0.12, (0, 0.25, 2.38), BLACK, verts=12),
        cyl(0.26, 0.5, (-1.05, 0.55, 1.75), "#3A3D42", axis="X", verts=12),   # twin air filters
        cyl(0.26, 0.5, (-1.05, -0.1, 1.75), "#3A3D42", axis="X", verts=12),
        cyl(0.22, 0.6, (1.05, 0.6, 1.55), CHROME, axis="Y", verts=12),    # muffler
        cyl(0.11, 1.15, (1.05, 0.6, 2.15), CHROME, verts=10),             # chrome stack
        box((0.34, 0.3, 0.04), (1.05, 0.66, 2.76), CHROME, bevel=0, rot=(math.radians(-20), 0, 0)),  # rain cap
        box((0.95, 0.66, 0.56), (0, -0.98, 1.5), WHITE, bevel=0.1),       # fuel tank
        cyl(0.15, 0.1, (0, -0.98, 1.82), YELLOW, verts=12),
        box((2.0, 1.5, 1.3), (0, -2.55, 1.4), BAG, bevel=0.25),           # big grass bag
        box((2.06, 1.2, 0.16), (0, -2.55, 1.4), YELLOW, bevel=0.04),      # bag band
        box((2.1, 0.16, 0.16), (0, -1.82, 1.95), BLACK, bevel=0.03),
        cyl(0.09, 3.3, (0, 1.2, 0.5), METAL, axis="X", verts=8),
        cyl(0.09, 3.3, (0, -1.2, 0.68), METAL, axis="X", verts=8),
        # front guard bar on two brackets, with headlights
        tube((-1.35, 2.0, 0.95), (1.35, 2.0, 0.95), 0.08, YELLOW),
        tube((-1.1, 1.7, 0.9), (-1.1, 2.0, 0.95), 0.06, YELLOW, verts=8),
        tube((1.1, 1.7, 0.9), (1.1, 2.0, 0.95), 0.06, YELLOW, verts=8),
        cyl(0.17, 0.12, (-0.8, 1.78, 1.0), "#FFF3B0", axis="Y", verts=12),
        cyl(0.17, 0.12, (0.8, 1.78, 1.0), "#FFF3B0", axis="Y", verts=12),
    ]
    handle(b, 1.1, (-1.6, 1.1), (-3.5, 3.8))
    b.append(box((2.26, 0.3, 0.4), (0, -3.24, 3.42), DARK, bevel=0.06))   # control panel between the bars
    b.append(box((0.3, 0.1, 0.22), (-0.45, -3.12, 3.62), YELLOW, bevel=0.03))
    b.append(box((0.3, 0.1, 0.22), (0.45, -3.12, 3.62), "#E5302B", bevel=0.03))
    ws = wheels([("FL", -1.72, 1.2, 0.5, 0.4, YELLOW), ("FR", 1.72, 1.2, 0.5, 0.4, YELLOW),
                 ("RL", -1.72, -1.2, 0.68, 0.46, YELLOW), ("RR", 1.72, -1.2, 0.68, 0.46, YELLOW)])
    return join("Body", b), ws, blade(0.5, 2.5)


def ride_on():
    """A small lawn tractor: red hood, seat, steering wheel, big rear wheels, mid deck.
    The player sits on it in the game, so it has no push handle. Its seat, steering wheel
    and size are described to the game in Assets.RIDE (src/ReplicatedStorage/Shared)."""
    RED, SEAT, LAMP = "#C82828", "#26272B", "#FFF3B0"
    b = [
        box((2.0, 4.6, 0.45), (0, 0.3, 1.05), DARK, bevel=0.08),          # chassis
        box((1.9, 2.0, 0.95), (0, 1.6, 1.72), RED, bevel=0.22),           # hood
        box((1.5, 0.1, 0.6), (0, 2.62, 1.68), WHITE, bevel=0.03),         # grille
        cyl(0.18, 0.1, (-0.6, 2.64, 1.95), LAMP, axis="Y", verts=12),
        cyl(0.18, 0.1, (0.6, 2.64, 1.95), LAMP, axis="Y", verts=12),
        box((2.2, 0.22, 0.3), (0, 2.72, 1.1), BLACK, bevel=0.05),         # front bumper
        box((1.5, 0.5, 0.7), (0, 0.45, 1.75), DARK, bevel=0.08),          # dashboard
        box((2.7, 1.9, 0.5), (0, -1.15, 1.5), RED, bevel=0.14),           # rear body / fenders
        box((2.74, 1.5, 0.12), (0, -1.15, 1.38), WHITE, bevel=0.03),      # white stripe
        box((1.15, 1.0, 0.26), (0, -1.0, 1.9), SEAT, bevel=0.08),         # seat base
        box((1.15, 0.28, 0.95), (0, -1.55, 2.35), SEAT, bevel=0.1, rot=(math.radians(-10), 0, 0)),
        tube((0, 0.55, 2.0), (0, 0.05, 2.7), 0.07, METAL, verts=8),       # steering column
        cyl(0.1, 1.05, (0.82, 2.0, 2.45), METAL, verts=10),               # exhaust stack
        cyl(0.13, 0.12, (0.82, 2.0, 3.0), DARK, verts=10),
        # cutting deck slung under the middle
        box((3.0, 2.2, 0.36), (0, 0.5, 0.52), RED, bevel=0.12),
        box((3.06, 1.6, 0.1), (0, 0.5, 0.42), WHITE, bevel=0.03),
        box((0.5, 1.0, 0.3), (-1.7, 0.5, 0.52), BLACK, bevel=0.08),       # discharge chute
        cyl(0.1, 2.9, (0, 2.0, 0.5), METAL, axis="X", verts=8),
        cyl(0.11, 3.3, (0, -1.3, 0.85), METAL, axis="X", verts=8),
    ]
    # steering wheel, tilted to face the seat
    tilt = (math.radians(55), 0, 0)
    b.append(cyl(0.48, 0.08, (0, 0.02, 2.74), BLACK, verts=18, rot=tilt))
    b.append(cyl(0.12, 0.12, (0, 0.02, 2.74), METAL, verts=10, rot=tilt))
    ws = wheels([("FL", -1.25, 2.0, 0.5, 0.42, WHITE), ("FR", 1.25, 2.0, 0.5, 0.42, WHITE),
                 ("RL", -1.55, -1.3, 0.85, 0.62, WHITE), ("RR", 1.55, -1.3, 0.85, 0.62, WHITE)])
    bl = join("Blade", [
        cyl(0.15, 0.1, (0, 0.5, 0.36), METAL, verts=10),
        box((2.5, 0.22, 0.05), (0, 0.5, 0.36), METAL, bevel=0),
    ])
    return join("Body", b), ws, bl


VARIANTS = [("electric", electric), ("petrol", petrol), ("pro", professional), ("rideon", ride_on)]

# ------------------------------------------------------------------ build + export
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.context.scene.cursor.location = (0, 0, 0)

for i, (name, make) in enumerate(VARIANTS):
    body, ws, bl = make()
    objs = [body, bl] + ws
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    tris = 0
    for o in objs:
        bake_vertex_colors(o)
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("MOWER_TRIS", name, tris)

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "mower_%s.fbx" % name),
        use_selection=True,
        global_scale=0.01,          # 1 Blender unit -> 1 stud in Roblox
        object_types={"MESH"},
        colors_type="SRGB",
        mesh_smooth_type="FACE",
        bake_anim=False,
    )
    # line them up for the .blend and the previews
    dx = (i - (len(VARIANTS) - 1) / 2) * 5.6
    for o in objs:
        o.location.x += dx
        o.name = "%s_%s" % (name, o.name)

# ------------------------------------------------------------------ preview scene
scene = bpy.context.scene
bpy.ops.mesh.primitive_plane_add(size=160, location=(0, 0, 0))
bpy.context.active_object.name = "PreviewGround"
bpy.context.active_object.data.materials.append(mat("#6DBB4A", rough=0.9))

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(-48), 0, math.radians(-30)))
sun = bpy.context.active_object
sun.data.energy = 3.5
sun.data.angle = math.radians(8)

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

bpy.ops.object.empty_add(location=(0, -0.3, 1.5))
target = bpy.context.active_object
bpy.ops.object.camera_add()
cam = bpy.context.active_object
cam.data.lens = 38
con = cam.constraints.new("TRACK_TO")
con.target = target
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.samples = 48
try:
    scene.cycles.use_denoising = True
except Exception:
    pass
scene.render.resolution_x = 1700
scene.render.resolution_y = 700
scene.view_settings.view_transform = "Standard"

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "mowers.blend"))

for fname, loc, sun_z in (("preview_front.png", (7, 21, 9), -30), ("preview_rear.png", (-7, -23, 9), 150)):
    cam.location = loc
    sun.rotation_euler = (math.radians(-48 if sun_z == -30 else 48), 0, math.radians(sun_z if sun_z == -30 else 30))
    scene.render.filepath = os.path.join(OUT, fname)
    bpy.ops.render.render(write_still=True)
print("MOWERS_DONE")
