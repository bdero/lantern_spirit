# Shared Blender helpers for Lumi mockups: render setup, materials, the
# character in any pose, accessories, and soft-body deformations.
# Blender coordinates: Z up, the character faces -Y.
import bpy, bmesh, math, random
from mathutils import Vector, Euler, Matrix

R = 0.62  # head radius
FACE_K = 1.3

THEMES = {
    "aurora": dict(skin=(0.45, 0.78, 1.0), sss=(0.5, 0.9, 1.2), rim=(0.55, 0.85, 1.0), ember=(1.0, 0.55, 0.18),
                   key=(0.75, 0.85, 1.0), back=(0.7, 0.45, 1.0), world=(0.01, 0.015, 0.04), trans=0.0),
    "ember": dict(skin=(1.0, 0.42, 0.22), sss=(1.2, 0.45, 0.25), rim=(1.0, 0.62, 0.3), ember=(1.0, 0.25, 0.5),
                  key=(1.0, 0.85, 0.75), back=(1.0, 0.35, 0.55), world=(0.04, 0.012, 0.015), trans=0.0),
    "ghost": dict(skin=(0.72, 0.96, 0.9), sss=(0.6, 1.0, 0.9), rim=(0.55, 1.0, 0.85), ember=(0.45, 1.0, 0.75),
                  key=(0.85, 1.0, 0.95), back=(0.35, 0.9, 1.0), world=(0.01, 0.03, 0.03), trans=0.35),
}

# Rest offsets (Blender coords) and per-pose overrides.
BASE = dict(head=(0, 0, 1.8), head_scale=(1, 1, 1), head_rot=(0, 0, 0), body=(0, 0, 1.02),
            wisp=(0, 0.02, 0.6), hl=(-0.66, -0.08, 1.12), hr=(0.68, -0.12, 1.18), glow=1.0)
POSES = {
    "awake": {},
    "sleepy": dict(head=(0, 0, 1.66), head_scale=(1.05, 1.05, 0.93), head_rot=(math.radians(9), 0, 0),
                   body=(0, 0, 0.98), wisp=(0, 0.02, 0.56), hl=(-0.5, -0.12, 0.96), hr=(0.5, -0.12, 0.94), glow=0.35),
    "delighted": dict(head=(0, 0, 2.08), head_scale=(0.96, 0.96, 1.06), body=(0, 0, 1.28), wisp=(0, 0.02, 0.86),
                      hl=(-0.66, -0.1, 2.12), hr=(0.7, -0.1, 2.16), glow=1.45),
    "content": dict(head_rot=(0, math.radians(-10), 0), hl=(-0.24, -0.4, 1.08), hr=(0.24, -0.4, 1.1), glow=0.85),
    "glum": dict(head=(0, 0, 1.7), head_rot=(math.radians(10), 0, 0), body=(0, 0, 0.98), wisp=(0, 0.02, 0.58),
                 hl=(-0.5, 0.0, 0.86), hr=(0.5, 0.0, 0.86), glow=0.5),
    "grumpy": dict(head_scale=(1.06, 1.06, 1.02), hl=(-0.38, 0.08, 1.0), hr=(0.38, 0.08, 1.0), glow=1.15),
    "wow": dict(head=(0, 0, 1.86), head_rot=(math.radians(-14), 0, 0), hl=(-0.42, -0.36, 1.5),
                hr=(0.42, -0.36, 1.5), glow=1.3),
    "glance_down": dict(head_rot=(math.radians(22), math.radians(-6), math.radians(-18)), hr=(0.72, -0.3, 1.0), glow=1.0),
    "catch": dict(head=(0, 0, 1.9), head_rot=(math.radians(-16), 0, 0), hl=(-0.55, -0.25, 2.45),
                  hr=(0.55, -0.25, 2.5), glow=1.35),
    "lift": dict(head=(0, 0, 1.95), head_rot=(math.radians(-10), 0, 0), body=(0, 0.05, 1.1), wisp=(0, 0.08, 0.55),
                 hl=(-0.62, 0.15, 1.35), hr=(0.62, 0.15, 1.35), glow=1.3),
    "watch": dict(head=(0, 0, 1.78), head_rot=(math.radians(-20), math.radians(8), 0), hl=(-0.3, -0.35, 1.02),
                  hr=(0.3, -0.35, 1.04), glow=1.0),
    "cheer": dict(head=(0, 0, 1.95), head_rot=(math.radians(-18), 0, 0), hl=(-0.7, -0.1, 2.3), hr=(0.72, -0.1, 2.35),
                  body=(0, 0, 1.12), glow=1.5),
}


# ------------------------------------------------------------------ setup
def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
        for b in list(coll):
            coll.remove(b)


def setup_render(w, h, samples, transparent):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU setup failed:", e)
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.film_transparent = transparent
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    if not sc.world:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    return sc


def world_color(color, strength=0.5):
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*color, 1)
    bg.inputs[1].default_value = strength


def world_gradient(bottom, top, strength=1.0):
    """Sky gradient by ray elevation."""
    nt = bpy.context.scene.world.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (*top, 1)
    mapr = nt.nodes.new("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = -1
    mapr.inputs["From Max"].default_value = 1
    # For the world, Generated is the normalized view direction.
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mapr.inputs["Value"])
    nt.links.new(mapr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs[1].default_value = strength


def area(name, loc, target, power, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA")
    l.energy, l.size, l.color, l.shape = power, size, color, "DISK"
    o = bpy.data.objects.new(name, l)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def point(name, loc, power, color, radius=0.1):
    l = bpy.data.lights.new(name, "POINT")
    l.energy, l.color = power, color
    l.shadow_soft_size = radius
    o = bpy.data.objects.new(name, l)
    bpy.context.collection.objects.link(o)
    o.location = loc
    return o


def camera(loc, target, lens=70, dof=None):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    if dof:
        cd.dof.use_dof = True
        cd.dof.focus_distance, cd.dof.aperture_fstop = dof
    o = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = o
    return o


def lantern_lights(theme):
    T = THEMES[theme]
    area("Key", (-3, -4, 4.5), (0, 0, 1.4), 500, 4, T["key"])
    area("Rim", (3.5, 3, 3.5), (0, 0, 1.5), 900, 3, T["back"])
    area("Fill", (4, -3, 1), (0, 0, 1.2), 80, 4, T["rim"])


def shadow_catcher(size=5):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    bpy.context.object.is_shadow_catcher = True


# ------------------------------------------------------------------ materials
def principled(name, **inputs):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    for k, v in inputs.items():
        b.inputs[k].default_value = v
    return m


def emissive(name, color, strength):
    return principled(name, **{"Base Color": (*color, 1), "Emission Color": (*color, 1), "Emission Strength": strength})


def skin_material(theme, glow=1.0, base=0.0):
    T = THEMES[theme]
    m = principled("Skin", **{
        "Base Color": (*T["skin"], 1), "Roughness": 0.3,
        "Subsurface Weight": 1.0, "Subsurface Radius": T["sss"], "Subsurface Scale": 0.35,
        "Transmission Weight": T["trans"], "Coat Weight": 0.6, "Coat Roughness": 0.08})
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    # base > 0 lets the whole shell glow softly, for night scenes.
    ramp.color_ramp.elements[0].color = (*(c * base for c in T["skin"]), 1)
    ramp.color_ramp.elements[1].color = (*T["rim"], 1)
    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 3.0 * glow
    return m


def face_material(path, strength):
    m = bpy.data.materials.new("Face")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    tex.extension = "CLIP"
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def knit(name, color, scale=60):
    m = principled(name, **{"Base Color": (*color, 1), "Roughness": 0.95, "Sheen Weight": 0.8})
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexWave")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Distortion"].default_value = 2
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], nt.nodes["Principled BSDF"].inputs["Normal"])
    return m


def stripes(name, a, b, scale=8):
    m = principled(name, **{"Roughness": 0.45, "Coat Weight": 0.4})
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = scale
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (*a, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return m


def assign(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


# ------------------------------------------------------------------ geometry
def sphere(name, r, loc, scale=(1, 1, 1), rot=(0, 0, 0), seg=96, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc)
    o = bpy.context.object
    o.name, o.scale, o.rotation_euler = name, scale, rot
    for p in o.data.polygons:
        p.use_smooth = True
    if parent:
        o.parent = parent
    return o


def deform_mesh(o, fn):
    """fn(local_co, local_normal) -> new local co."""
    me = o.data
    for v in me.vertices:
        v.co = fn(v.co.copy(), v.co.normalized())
    me.update()


def stretch_fn(direction, amount, power=2.0, thin=0.0):
    d = Vector(direction).normalized()

    def fn(co, n):
        k = max(0.0, n.dot(d)) ** power
        side = co - d * co.dot(d)
        return co + d * (amount * k) - side * (thin * k)
    return fn


def dent_fn(direction, radius, depth, r=R):
    p = Vector(direction).normalized() * r

    def fn(co, n):
        x = min(1.0, (co - p).length / radius)
        h = depth * (1 - x * x * (3 - 2 * x))
        return co - co.normalized() * h
    return fn


def ripple_fn(axis, waves, amp, phase=0.0):
    a = Vector(axis).normalized()

    def fn(co, n):
        t = co.normalized().dot(a)
        return co + co.normalized() * amp * math.sin(t * waves * math.pi + phase) * (1 - abs(t) * 0.3)
    return fn


def face_cap_obj(img_path, strength, deform=None, k=FACE_K, cap_deg=70):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=128, v_segments=64, radius=R * 1.012)
    fwd = Vector((0, -1, 0))
    c = math.cos(math.radians(cap_deg))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.normalized().dot(fwd) < c], context="VERTS")
    uv = bm.loops.layers.uv.new()
    for f in bm.faces:
        f.smooth = True
        for l in f.loops:
            l[uv].uv = (l.vert.co.x / (2 * k * R) + 0.5, l.vert.co.z / (2 * k * R) + 0.5)
    me = bpy.data.meshes.new("FaceCap")
    bm.to_mesh(me)
    o = bpy.data.objects.new("FaceCap", me)
    bpy.context.collection.objects.link(o)
    if deform:
        for v in me.vertices:
            v.co = deform(v.co.copy() / 1.012, v.co.normalized()) * 1.012
    assign(o, face_material(img_path, strength))
    o.visible_shadow = False
    return o


def build_lumi(faces_dir, pose="awake", face=None, theme="aurora", origin=(0, 0, 0), yaw=-13.0, scale=1.0,
               glow=None, accessories=(), head_deform=None, body_deform=None, overrides=None, sparks=0,
               inner_lights=False, base_glow=0.0):
    """Builds Lumi under a root empty. Returns (root, head_frame_empty, info)."""
    P = dict(BASE)
    P.update(POSES[pose])
    if overrides:
        P.update(overrides)
    g = glow if glow is not None else P["glow"]
    T = THEMES[theme]
    root = bpy.data.objects.new("Lumi", None)
    bpy.context.collection.objects.link(root)

    skin = skin_material(theme, g, base_glow)
    ember = emissive("Ember", T["ember"], 3.0 * g)

    head_frame = bpy.data.objects.new("HeadFrame", None)
    bpy.context.collection.objects.link(head_frame)
    head_frame.parent = root
    head_frame.location = P["head"]
    head_frame.rotation_euler = P["head_rot"]
    head_frame.scale = P["head_scale"]

    head = sphere("Head", R, (0, 0, 0), parent=head_frame)
    if head_deform:
        deform_mesh(head, lambda co, n: head_deform(co, n))
    assign(head, skin)
    cap = face_cap_obj(f"{faces_dir}/lantern_{face or pose_face(pose)}.png", 3.0 * max(g, 0.7), head_deform)
    cap.parent = head_frame

    body = sphere("Body", 0.3, P["body"], parent=root)
    if body_deform:
        deform_mesh(body, body_deform)
    assign(body, skin)
    for name, key, r in (("Wisp", "wisp", 0.13), ("HandL", "hl", 0.1), ("HandR", "hr", 0.1)):
        o = sphere(name, r, P[key], parent=root)
        assign(o, ember)
        if inner_lights and name != "Wisp":
            pl = point(name + "Light", P[key], 240 * g, T["ember"], 0.08)
            pl.parent = root
    if inner_lights:
        pl = point("HeadLight", P["head"], 120 * g, T["rim"], 0.3)
        pl.parent = root

    rnd = random.Random(11)
    for i in range(sparks):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.95, 1.6)
        s = sphere(f"Spark{i}", rnd.uniform(0.012, 0.03),
                   (rr * math.cos(a), rr * math.sin(a) * 0.6 + 0.2, rnd.uniform(0.7, 2.6)), seg=16, parent=root)
        assign(s, ember)

    for acc in accessories:
        ACCESSORIES[acc](head_frame, root, P, theme)

    root.location = origin
    root.rotation_euler = (0, 0, math.radians(yaw))
    root.scale = (scale, scale, scale)
    return root, head_frame, P


def pose_face(pose):
    return {"catch": "delighted", "lift": "delighted", "glance_down": "curious", "watch": "wow",
            "cheer": "delighted"}.get(pose, pose)


# ------------------------------------------------------------------ accessories
def _star_mesh(name, size, depth):
    bm = bmesh.new()
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = size if i % 2 == 0 else size * 0.45
        pts.append(bm.verts.new((r * math.cos(a), 0, r * math.sin(a))))
    f = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y += depth
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, -depth / 2, 0))
    bmesh.ops.bevel(bm, geom=bm.edges, offset=depth * 0.25, segments=2, affect="EDGES")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def acc_star_sprout(head, root, P, theme):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.018, depth=0.42, location=(0.04, 0, R + 0.17),
                                        rotation=(0, math.radians(8), 0))
    stalk = bpy.context.object
    stalk.parent = head
    assign(stalk, principled("Stalk", **{"Base Color": (0.35, 0.8, 0.45, 1), "Roughness": 0.5}))
    star = _star_mesh("Star", 0.17, 0.06)
    star.location = (0.07, 0, R + 0.45)
    star.rotation_euler = (0, math.radians(-10), 0)
    star.parent = head
    assign(star, emissive("StarGlow", (1.0, 0.78, 0.3), 4.0))


def acc_beanie(head, root, P, theme):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=R * 1.07)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < R * 0.28], context="VERTS")
    me = bpy.data.meshes.new("Beanie")
    bm.to_mesh(me)
    cap = bpy.data.objects.new("Beanie", me)
    bpy.context.collection.objects.link(cap)
    for p in me.polygons:
        p.use_smooth = True
    cap.parent = head
    cap.rotation_euler = (math.radians(-8), math.radians(10), 0)
    assign(cap, knit("Knit", (0.85, 0.22, 0.3)))
    bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.98, minor_radius=0.075, location=(0, 0, R * 0.3),
                                     rotation=(math.radians(-8), math.radians(10), 0))
    band = bpy.context.object
    for p in band.data.polygons:
        p.use_smooth = True
    band.parent = head
    assign(band, knit("Band", (0.96, 0.92, 0.85), 120))
    pom = sphere("Pom", 0.14, (0.12, 0.08, R + 0.12), parent=head)
    assign(pom, knit("PomKnit", (0.96, 0.92, 0.85), 200))


def acc_scarf(head, root, P, theme):
    # A knit scarf around the neck.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.27, minor_radius=0.075,
                                     location=(P["body"][0], P["body"][1], P["body"][2] + 0.26))
    scarf = bpy.context.object
    for p in scarf.data.polygons:
        p.use_smooth = True
    scarf.parent = root
    assign(scarf, knit("Scarf", (0.85, 0.22, 0.3)))
    tail = sphere("ScarfTail", 0.09, (P["body"][0] + 0.18, P["body"][1] - 0.24, P["body"][2] + 0.06),
                  scale=(0.8, 0.6, 1.8), rot=(0, math.radians(-15), 0), parent=root)
    assign(tail, scarf.data.materials[0])



def acc_flower_crown(head, root, P, theme):
    rnd = random.Random(3)
    colors = [(1.0, 0.72, 0.82), (1.0, 0.95, 0.9), (0.82, 0.72, 1.0)]
    for i in range(9):
        a = i / 9 * math.tau
        c = Vector((math.cos(a) * R * 0.74, math.sin(a) * R * 0.74, R * 0.7))
        flower = bpy.data.objects.new(f"Flower{i}", None)
        bpy.context.collection.objects.link(flower)
        flower.parent = head
        flower.location = c
        flower.rotation_euler = (Vector(c) - Vector((0, 0, -0.2))).to_track_quat("Z", "Y").to_euler()
        petal_mat = principled(f"Petal{i}", **{"Base Color": (*colors[i % 3], 1), "Roughness": 0.6,
                                               "Subsurface Weight": 0.3, "Subsurface Radius": (1, 0.8, 0.8),
                                               "Subsurface Scale": 0.05})
        for j in range(5):
            b = j / 5 * math.tau + rnd.uniform(-0.1, 0.1)
            p = sphere("Petal", 0.095, (math.cos(b) * 0.1, math.sin(b) * 0.1, 0), scale=(1, 0.6, 0.25),
                       rot=(0, 0, b), seg=10, parent=flower)
            assign(p, petal_mat)
        ctr = sphere("Center", 0.05, (0, 0, 0.02), seg=10, parent=flower)
        assign(ctr, emissive("FlowerCenter", (1.0, 0.8, 0.3), 1.5))


def acc_headphones(head, root, P, theme):
    bpy.ops.mesh.primitive_torus_add(major_radius=R * 1.08, minor_radius=0.035, location=(0, 0, 0.08),
                                     rotation=(math.radians(90), 0, 0))
    band = bpy.context.object
    bm = bmesh.new()
    bm.from_mesh(band.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.02], context="VERTS")  # keep the top half
    bm.to_mesh(band.data)
    for p in band.data.polygons:
        p.use_smooth = True
    band.parent = head
    pearl = principled("Pearl", **{"Base Color": (0.93, 0.93, 0.97, 1), "Roughness": 0.2,
                                   "Thin Film Thickness": 430.0, "Thin Film IOR": 1.45, "Coat Weight": 0.5})
    assign(band, pearl)
    for s in (-1, 1):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.13, location=(s * (R + 0.02), 0, 0.02),
                                            rotation=(0, math.radians(90), 0))
        cup = bpy.context.object
        cup.parent = head
        assign(cup, pearl)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.02, location=(s * (R + 0.09), 0, 0.02),
                                         rotation=(0, math.radians(90), 0))
        led = bpy.context.object
        led.parent = head
        assign(led, emissive("LED", THEMES[theme]["rim"], 6.0))


def acc_cat_ears(head, root, P, theme):
    for s in (-1, 1):
        bpy.ops.mesh.primitive_cone_add(radius1=0.2, depth=0.38, location=(s * 0.34, 0.02, R * 0.98),
                                        rotation=(0, math.radians(s * 24), 0))
        ear = bpy.context.object
        bpy.ops.object.shade_smooth()
        ear.parent = head
        assign(ear, skin_material(theme))
        bpy.ops.mesh.primitive_cone_add(radius1=0.12, depth=0.24, location=(s * 0.35, -0.07, R * 0.96),
                                        rotation=(0, math.radians(s * 24), 0))
        inner = bpy.context.object
        inner.parent = head
        assign(inner, emissive("EarInner", (1.0, 0.6, 0.75), 1.2))


def acc_party_hat(head, root, P, theme):
    bpy.ops.mesh.primitive_cone_add(radius1=0.24, depth=0.55, location=(0.1, 0, R + 0.18),
                                    rotation=(0, math.radians(14), 0), vertices=64)
    hat = bpy.context.object
    bpy.ops.object.shade_smooth()
    hat.parent = head
    assign(hat, principled("HatCoral", **{"Base Color": (1.0, 0.42, 0.45, 1), "Roughness": 0.45, "Coat Weight": 0.4}))
    for k, h in enumerate((0.0, 0.18, 0.34)):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.24 * (1 - (h + 0.04) / 0.55), minor_radius=0.022,
                                         location=(0.1 + 0.55 * math.sin(math.radians(14)) * (h / 0.55 - 0.5), 0,
                                                   R + 0.18 + 0.55 * math.cos(math.radians(14)) * (h / 0.55 - 0.5)),
                                         rotation=(0, math.radians(14), 0))
        band = bpy.context.object
        band.name = f"HatBand{k}"
        band.parent = head
        assign(band, principled("HatCream", **{"Base Color": (1.0, 0.93, 0.8, 1), "Roughness": 0.5}))
    pom = sphere("HatPom", 0.075, (0.17, 0, R + 0.46), parent=head)
    assign(pom, emissive("HatPomGlow", (1.0, 0.8, 0.3), 3.0))


ACCESSORIES = {
    "star_sprout": acc_star_sprout,
    "beanie": acc_beanie,
    "scarf": acc_scarf,
    "flower_crown": acc_flower_crown,
    "headphones": acc_headphones,
    "cat_ears": acc_cat_ears,
    "party_hat": acc_party_hat,
}


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
