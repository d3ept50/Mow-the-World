"""Builds the five treasure chest variants for Mow the World.

Run:  blender --background --factory-startup --python build_chests.py
Outputs (next to this script): chest_<rarity>.fbx x5, chests.blend,
preview_closed.png, preview_open.png

Each chest is two meshes: Base and Lid. The Lid's origin is on the hinge
(back edge), so rotating it around its X axis opens the chest.
Units: 1 Blender unit = 1 Roblox stud. Front faces +Y (Roblox front, -Z).
"""
import math
import os

import bmesh
import bpy

OUT = os.path.dirname(os.path.abspath(__file__))

IRON, SILVER, GOLD = "#4A4D52", "#C9CED6", "#F2C230"
VARIANTS = [
    dict(name="Common", body="#8B5A2B", band=IRON, lock="#8E949B", scale=1.0),
    dict(name="Uncommon", body="#3F9B4B", band=SILVER, lock=SILVER, scale=1.0,
         guards=1),
    dict(name="Rare", body="#2F6FD6", band=GOLD, lock=GOLD, scale=1.05,
         guards=1, gems="#FFFFFF"),
    dict(name="Epic", body="#8A3FD1", band=GOLD, lock=GOLD, scale=1.1,
         guards=2, gems="#3DE0E0", lid_gem=True, mid_band=True),
    dict(name="Legendary", body="#F5B921", band="#B8641A", lock="#FFF1B0", scale=1.2,
         guards=2, gems="#E5302B", lid_gem=True, mid_band=True, ridge=True, handles=True),
]

W, D, H = 3.0, 2.0, 1.1      # base width (X), depth (Y), height (Z)
LID_Z, LID_H = 1.16, 0.72    # where the lid sits, and how tall its arc is


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


def box(size, loc, color, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
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


def cyl(r, depth, loc, color, axis="Z", verts=10):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(mat(color))
    return o


def gem(r, loc, color, squash=(1, 0.55, 1.3)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = squash
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(color, rough=0.2))
    return o


def arc(length, ry, rz, loc, color, segs=8):
    """Half-barrel shape: a squashed half cylinder running along X, flat side down."""
    verts, faces = [], []
    for x in (-length / 2, length / 2):
        for i in range(segs + 1):
            a = math.pi * i / segs
            verts.append((x, ry * math.cos(a), rz * math.sin(a)))
    n = segs + 1
    for i in range(segs):
        faces.append((i, i + 1, n + i + 1, n + i))
    faces.append(tuple(range(n)))
    faces.append(tuple(range(n, 2 * n)))
    faces.append((0, n, 2 * n - 1, n - 1))
    me = bpy.data.meshes.new("Arc")
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Arc", me)
    o.location = loc
    bpy.context.collection.objects.link(o)
    me.materials.append(mat(color))
    return o


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


def set_origin(o, loc):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.scene.cursor.location = loc
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


def bake_vertex_colors(o):
    me = o.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cols = [tuple(m["srgb"]) + (1.0,) for m in me.materials]
    for p in me.polygons:
        c = cols[p.material_index]
        for li in p.loop_indices:
            attr.data[li].color_srgb = c


def build_chest(v):
    body, band, lock = v["body"], v["band"], v["lock"]
    band_xs = [-1.0, 1.0] + ([0.0] if v.get("mid_band") else [])
    front = D / 2

    # ---- base
    base = [
        box((W, D, H), (0, 0, H / 2), body, bevel=0.06),
        box((W + 0.08, D + 0.08, 0.16), (0, 0, H - 0.02), band, bevel=0.03),      # rim
        box((W - 0.3, D - 0.3, 0.02), (0, 0, LID_Z + 0.005), "#1B1C1E", bevel=0),  # dark inside
        gem(1.0, (0, 0, LID_Z - 0.05), "#F7CF3A", squash=(1.15, 0.65, 0.4)),       # treasure pile
        box((0.42, 0.14, 0.46), (0, front + 0.05, 0.82), lock, bevel=0.04),        # lock
        box((0.1, 0.04, 0.18), (0, front + 0.13, 0.8), "#1B1C1E", bevel=0),        # keyhole
    ]
    for x in band_xs:
        if x != 0.0:  # the middle band stops at the lock, so only the lid gets one
            base.append(box((0.26, D + 0.08, H + 0.02), (x, 0, H / 2), band, bevel=0.03))
            for z in (0.3, 0.75):
                base.append(cyl(0.07, 0.06, (x, front + 0.06, z), lock, axis="Y", verts=8))
    g = v.get("guards", 0)
    if g:
        zs = (0.16,) + ((H - 0.2,) if g > 1 else ())
        for sx in (-1, 1):
            for sy in (-1, 1):
                for z in zs:
                    base.append(box((0.42, 0.42, 0.32),
                                    (sx * (W / 2 - 0.12), sy * (D / 2 - 0.12), z), band, bevel=0.06))
    if v.get("gems"):
        for x in (-0.5, 0.5):
            base.append(gem(0.17, (x, front + 0.02, 0.6), v["gems"]))
    if v.get("handles"):
        for sx in (-1, 1):
            x = sx * (W / 2 + 0.16)
            base.append(box((0.1, 0.7, 0.1), (x, 0, 0.62), lock, bevel=0.03))
            for y in (-0.3, 0.3):
                base.append(box((0.22, 0.1, 0.1), (sx * (W / 2 + 0.08), y, 0.62), lock, bevel=0.03))
    base = join("Base", base)

    # ---- lid
    lid = [arc(W, D / 2, LID_H, (0, 0, LID_Z), body)]
    for x in band_xs:
        lid.append(arc(0.26, D / 2 + 0.04, LID_H + 0.04, (x, 0, LID_Z), band))
    lid.append(box((0.3, 0.1, 0.34), (0, front + 0.03, LID_Z + 0.12), lock, bevel=0.03))  # latch
    if v.get("ridge"):
        lid.append(box((W + 0.1, 0.18, 0.1), (0, 0, LID_Z + LID_H + 0.03), lock, bevel=0.03))
    if v.get("lid_gem"):
        lid.append(gem(0.24, (0, 0, LID_Z + LID_H + 0.1), v["gems"], squash=(1, 1, 1.1)))
    lid = join("Lid", lid)

    # ---- size, origins, colours
    s = v["scale"]
    for o in (base, lid):
        set_origin(o, (0, 0, 0))
        o.scale = (s, s, s)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bake_vertex_colors(o)
    set_origin(lid, (0, -D / 2 * s, LID_Z * s))  # hinge at the back edge
    return base, lid


# ---------------------------------------------------------------- build + export
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

chests = []
for i, v in enumerate(VARIANTS):
    base, lid = build_chest(v)
    tris = sum(len(p.vertices) - 2 for o in (base, lid) for p in o.data.polygons)
    print("CHEST_TRIS", v["name"], tris)

    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    lid.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "chest_%s.fbx" % v["name"].lower()),
        use_selection=True,
        global_scale=0.01,          # 1 Blender unit -> 1 stud in Roblox
        object_types={"MESH"},
        colors_type="SRGB",
        mesh_smooth_type="FACE",
        bake_anim=False,
    )

    # line them up for the .blend and the previews
    dx = ((len(VARIANTS) - 1) / 2 - i) * 4.4  # camera looks from +Y, so this puts Common on the left
    for o in (base, lid):
        o.location.x += dx
        o.name = "%s_%s" % (v["name"], o.name)
    chests.append((base, lid))

# ---------------------------------------------------------------- preview scene
scene = bpy.context.scene
bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0))
bpy.context.active_object.name = "PreviewGround"
bpy.context.active_object.data.materials.append(mat("#6DBB4A", rough=0.9))

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(-50), 0, math.radians(25)))
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

bpy.ops.object.empty_add(location=(0, 0, 1.0))
target = bpy.context.active_object
bpy.ops.object.camera_add(location=(0, 24, 9))
cam = bpy.context.active_object
cam.data.lens = 35
con = cam.constraints.new("TRACK_TO")
con.target = target
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.samples = 48
try:
    scene.cycles.use_denoising = True
except Exception:
    pass
scene.render.resolution_x = 1500
scene.render.resolution_y = 620
scene.view_settings.view_transform = "Standard"

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "chests.blend"))

scene.render.filepath = os.path.join(OUT, "preview_closed.png")
bpy.ops.render.render(write_still=True)

for base, lid in chests:
    lid.rotation_euler.x = math.radians(60)
scene.render.filepath = os.path.join(OUT, "preview_open.png")
bpy.ops.render.render(write_still=True)
print("CHESTS_DONE")
