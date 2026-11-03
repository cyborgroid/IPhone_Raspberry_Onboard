"""Renders the device as it can really be built from the purchase list.

    blender -b -P design/render/after_v2.py -- OUTPUT.png [SIZE] [SAMPLES]

Dimensions in mm. Panel: official 5-inch Touch Display 2, 143.5 x 91.5 outline and 16
deep (maker's spec); its display area and the split of that depth are estimates. Board:
Raspberry Pi 5, 85 x 56, screwed to the back of the panel. The screen is
design/render/screen.png, captured from the built OS image.

The device is shown lying screen-up, resting on its ports. Axes: x along its length
with the USB end at +x, y across with the board's USB-C edge at -y, z up from the table.
"""
import math
import os
import sys

import bmesh
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
OUTPUT = os.path.abspath(argv[0])
SIZE = int(argv[1]) if len(argv) > 1 else 1024
SAMPLES = int(argv[2]) if len(argv) > 2 else 256
HERE = os.path.dirname(os.path.abspath(__file__))

PANEL_L, PANEL_W = 143.5, 91.5
SCREEN_L, SCREEN_W = 110.7, 62.3
BOARD_L, BOARD_W, BOARD_T = 85.0, 56.0, 1.6
PORT_H = 16.0  # USB stack height; the ports hang below the board in this pose.
BOARD_Z = PORT_H
PANEL_BACK_Z = BOARD_Z + BOARD_T + 9.0
PANEL_TOP_Z = BOARD_Z + BOARD_T + 16.0

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.scale_length = 0.001


def material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Coat Weight"].default_value = coat
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


ALUMINIUM = material("aluminium", (0.55, 0.55, 0.56), metallic=1.0, roughness=0.35)
PCB = material("pcb", (0.02, 0.22, 0.1), roughness=0.45)
GLASS_BLACK = material("glass_black", (0.004, 0.004, 0.005), roughness=0.06, coat=1.0)
CAVITY = material("cavity", (0.006, 0.006, 0.007), roughness=0.6)
SHELL = material("shell", (0.62, 0.62, 0.64), metallic=1.0, roughness=0.3)
BLUE = material("usb3_blue", (0.02, 0.2, 0.75), roughness=0.4)
GOLD = material("usb2_black", (0.01, 0.01, 0.012), roughness=0.5)
LED_GREEN = material("led_green", (0.1, 0.8, 0.2), emission=(0.1, 1, 0.2), strength=3)
LED_YELLOW = material("led_yellow", (0.8, 0.8, 0.1), emission=(1, 0.85, 0.1), strength=3)


def rounded_prism(name, x0, x1, y0, y1, z0, z1, r, mat, edge_bevel=0.0, segments=10):
    """A box whose vertical edges have radius r, optionally softening top and bottom."""
    bm = bmesh.new()
    outline = []
    corners = ((x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270))
    for cx, cy, start in corners:
        for i in range(segments + 1):
            a = math.radians(start + 90 * i / segments)
            outline.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    bottom = [bm.verts.new((x, y, z0)) for x, y in outline]
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    if edge_bevel:
        mod = obj.modifiers.new("edges", "BEVEL")
        mod.width = edge_bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(50)
    return obj


def box(name, x0, x1, y0, y1, z0, z1, mat):
    return rounded_prism(name, x0, x1, y0, y1, z0, z1, 0.05, mat, segments=1)


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def cut(body, cutter):
    mod = body.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    apply_modifiers(body)
    bpy.data.objects.remove(cutter)


x0, x1 = -BOARD_L / 2, BOARD_L / 2
y0, y1 = -BOARD_W / 2, BOARD_W / 2

rounded_prism("board", x0, x1, y0, y1, BOARD_Z, BOARD_Z + BOARD_T, 3.0, PCB)
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    cx, cy = sx * 29.0, sy * 24.5
    rounded_prism("standoff", cx - 1.8, cx + 1.8, cy - 1.8, cy + 1.8, BOARD_Z + BOARD_T, PANEL_BACK_Z, 1.7, SHELL)


def end_port(a, b, z0, z1, tongue=None):
    """A connector on the +x edge, with its opening facing the viewer."""
    box("port_shell", x1 - 16, x1 + 2.5, a, b, z0, z1, SHELL)
    box("port_mouth", x1 + 2.5, x1 + 2.56, a + 0.6, b - 0.6, z0 + 0.6, z1 - 0.6, CAVITY)
    if tongue:
        mid = (z0 + z1) / 2
        box("port_tongue", x1 + 2.56, x1 + 2.62, a + 1.6, b - 1.6, mid - 0.7, mid + 0.7, tongue)


end_port(-26.0, -10.0, 2.5, BOARD_Z)
box("rj45_led_y", x1 + 2.6, x1 + 2.68, -25.0, -22.5, 3.2, 5.0, LED_YELLOW)
box("rj45_led_g", x1 + 2.6, x1 + 2.68, -13.5, -11.0, 3.2, 5.0, LED_GREEN)
for a, b, tongue in ((-6.0, 8.2, BLUE), (12.0, 26.2, GOLD)):
    end_port(a, b, 0.6, 7.6, tongue)
    end_port(a, b, 8.4, BOARD_Z, tongue)


def side_port(center, width):
    """A connector on the -y edge."""
    a, b = center - width / 2, center + width / 2
    rounded_prism("side_shell", a, b, y0 - 1.2, y0 + 7, BOARD_Z - 3.6, BOARD_Z, 1.0, SHELL)
    box("side_mouth", a + 0.6, b - 0.6, y0 - 1.26, y0 - 1.2, BOARD_Z - 3.0, BOARD_Z - 0.6, CAVITY)


side_port(-31.3, 9.0)
side_port(-16.7, 6.8)
side_port(-3.3, 6.8)

# Panel: a metal back tray under the glass, with the screen roughly centred.
hl, hw = PANEL_L / 2, PANEL_W / 2
rounded_prism("panel_back", -hl + 2, hl - 2, -hw + 2, hw - 2, PANEL_BACK_Z, PANEL_TOP_Z - 2.0, 3.5, ALUMINIUM, edge_bevel=0.3)
rounded_prism("panel", -hl, hl, -hw, hw, PANEL_TOP_Z - 2.0, PANEL_TOP_Z, 4.0, GLASS_BLACK, edge_bevel=0.3)

screen_mat = material("screen", (0, 0, 0), roughness=0.12, coat=0.3)
nodes = screen_mat.node_tree.nodes
texture = nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load(os.path.join(HERE, "screen.png"))
texture.interpolation = "Smart"
bsdf = nodes["Principled BSDF"]
screen_mat.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Emission Color"])
bsdf.inputs["Emission Strength"].default_value = 1.35

# Held upright the USB end is at the bottom, so the top of the UI is towards -x.
sx1 = SCREEN_L / 2
sx0 = -SCREEN_L / 2
sy = SCREEN_W / 2
sz = PANEL_TOP_Z + 0.01
mesh = bpy.data.meshes.new("screen")
mesh.from_pydata([(sx1, -sy, sz), (sx1, sy, sz), (sx0, sy, sz), (sx0, -sy, sz)], [], [(0, 1, 2, 3)])
uv = mesh.uv_layers.new()
for loop, coord in zip(mesh.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
    uv.data[loop.index].uv = coord
screen = bpy.data.objects.new("screen", mesh)
bpy.context.collection.objects.link(screen)
mesh.materials.append(screen_mat)

# Studio: glossy white table, with a dim surround so the metal has something darker
# than white to reflect. The camera sees the table lit by the area lights.
floor = material("floor", (0.95, 0.95, 0.95), roughness=0.2)
mesh = bpy.data.meshes.new("floor")
mesh.from_pydata([(-3000, -3000, 0), (3000, -3000, 0), (3000, 3000, 0), (-3000, 3000, 0)], [], [(0, 1, 2, 3)])
table = bpy.data.objects.new("floor", mesh)
bpy.context.collection.objects.link(table)
mesh.materials.append(floor)

world = bpy.data.worlds.new("world")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.42
scene.world = world


def area_light(name, location, target, size, power):
    data = bpy.data.lights.new(name, "AREA")
    data.size = size
    data.energy = power
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    point_at(obj, target)


def point_at(obj, target):
    direction = (obj.location[0] - target[0], obj.location[1] - target[1], obj.location[2] - target[2])
    from mathutils import Vector

    obj.rotation_euler = Vector(direction).to_track_quat("Z", "Y").to_euler()


area_light("key", (-250, -320, 620), (0, 0, 20), 700, 3.4e6)
area_light("fill", (520, -60, 240), (0, 0, 20), 260, 5.0e5)
area_light("strip", (-40, -620, 150), (0, 0, 15), 240, 5.5e5)

# A black card out of frame, in the direction the glass mirrors towards the camera.
# Without it the panel reflects the surround and its blacks turn grey.
card = material("card", (0, 0, 0), roughness=1.0)
mesh = bpy.data.meshes.new("card")
mesh.from_pydata([(-700, -350, 0), (700, -350, 0), (700, 350, 0), (-700, 350, 0)], [], [(0, 1, 2, 3)])
flag = bpy.data.objects.new("card", mesh)
bpy.context.collection.objects.link(flag)
mesh.materials.append(card)
flag.location = (-620, 980, 900)
point_at(flag, (0, 0, 20))

camera_data = bpy.data.cameras.new("camera")
camera_data.lens = 92
camera_data.clip_end = 20000
camera = bpy.data.objects.new("camera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (225, -360, 200)
point_at(camera, (-1, 0, 17))
scene.camera = camera

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 8
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.filepath = OUTPUT
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
bpy.ops.render.render(write_still=True)
