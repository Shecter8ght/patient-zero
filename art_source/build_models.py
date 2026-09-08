"""Run with Blender 4.5 --background --python build_models.py. No external packages."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source' / 'blender'
EXPORT = ROOT / 'assets' / 'models'
PREVIEW = ROOT / 'art_source' / 'previews'
for p in (SOURCE, EXPORT, PREVIEW): p.mkdir(parents=True, exist_ok=True)
COLORS = ['c9c4b4','313c49','202b35','d8a483','453931','786951','ddb743','8b6951',
          '667859','58a2a9','416992','343f49','809398','cf987f','ead8b0','b9bec1',
          '587078','e0d5b9','bf775a','659481','1c2932','dbbd77','8c9493','ede4d1',
          '68727a','b09c84','574d49','3b5654','a8afab','918476','d6a45e','849d98']
PAL = None
parts = []
catalog = []

def clean():
    global parts
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    parts = []
    bpy.context.preferences.filepaths.save_version=0

def palette():
    global PAL
    img = bpy.data.images.get('patient_zero_palette')
    if not img:
        img = bpy.data.images.new('patient_zero_palette', width=256, height=128)
        pixels=[]
        for y in range(128):
            for x in range(256):
                h=COLORS[(y//32)*8+x//32]
                pixels.extend([int(h[i:i+2],16)/255 for i in (0,2,4)]+[1])
        img.pixels=pixels
        img.pack()
    PAL=bpy.data.materials.get('pz_palette') or bpy.data.materials.new('pz_palette')
    PAL.use_nodes=True
    bs=next((n for n in PAL.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs is None:bs=PAL.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output=next((n for n in PAL.node_tree.nodes if n.type=='OUTPUT_MATERIAL'),None)
    if output is None:output=PAL.node_tree.nodes.new('ShaderNodeOutputMaterial')
    PAL.node_tree.links.new(bs.outputs['BSDF'],output.inputs['Surface'])
    bs.inputs['Roughness'].default_value=.86
    tex=PAL.node_tree.nodes.get('Palette') or PAL.node_tree.nodes.new('ShaderNodeTexImage')
    tex.name='Palette'; tex.image=img; tex.interpolation='Closest'
    PAL.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])

def finish(o,name,c):
    o.name=name
    o.data.materials.clear(); o.data.materials.append(PAL)
    uv=o.data.uv_layers.active or o.data.uv_layers.new(name='UVMap')
    for loop in uv.data: loop.uv=((c%8+.5)/8,(c//8+.5)/4)
    for p in o.data.polygons: p.use_smooth=False
    parts.append(o)
    return o

def box(name,loc,size,c,bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=o.modifiers.new('edge_chamfer','BEVEL'); m.width=bevel; m.segments=1
        bpy.ops.object.modifier_apply(modifier=m.name)
    return finish(o,name,c)

def rings(name,levels,c,n=8):
    # levels: z, half width, half depth, y offset. Front in Blender is -Y.
    verts=[]
    for z,w,d,y in levels:
        for i in range(n):
            a=2*math.pi*i/n+math.pi/8
            verts.append((math.cos(a)*w, y+math.sin(a)*d,z))
    faces=[tuple(reversed(range(n)))]
    for j in range(len(levels)-1):
        for i in range(n): faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    faces.append(tuple((len(levels)-1)*n+i for i in range(n)))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o)
    return finish(o,name,c)

def limb(name,a,b,r1,r2,c,n=6):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r1,radius2=r2,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object; o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,c)

def join(objs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join()
    o=bpy.context.object; o.name=name
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return o

def character(kind,height,coat,width=1):
    clean(); palette()
    child=kind=='civilian_child_a'; elder=kind=='civilian_elder_a'
    cop=kind=='police_officer_a'; swat=kind=='swat_officer_a'
    hero=kind=='patient_zero'; journalist=kind=='civilian_journalist_a'
    headbase=1.34 if not child else 1.24
    headtop=1.68
    lean=-.06 if elder else 0
    trousers=1 if not elder else 26
    for s in (-1,1):
        x=s*.115*width
        box('boot', (x,-.045,.075),(.18,.31,.15),2, .025)
        limb('shin',(x,.015,.15),(x,.015,.46),.085,.09,trousers)
        limb('trouser_leg',(x,.015,.43),(x,.015,.85),.095,.11,trousers)
    rings('jacket',[(.78,.21*width,.13,0),(.87,.23*width,.14,0),
                    (1.19,.25*width,.15,lean),(1.30,.20*width,.125,lean)],coat)
    box('shirt_insert',(0,-.139+lean,1.19),(.085,.025,.20),23)
    box('jacket_zip',(0,-.15+lean,1.015),(.016,.014,.25),25)
    limb('neck',(0,lean,1.28),(0,lean,headbase+.055),.085,.085,3)
    hw=.155 if not child else .19
    rings('head',[(headbase,hw*.72,.10,lean), (headbase+.085,hw,.13,lean),
                  (headtop-.065,hw,.13,lean),(headtop,hw*.73,.105,lean)],3)
    box('nose',(0,-.137+lean,headbase+.155),(.052,.065,.067),3,.009)
    # Brow, ears and faceted hair carry expression without microscopic facial detail.
    for s in (-1,1):
        box('ear',(s*hw*.94,lean,headbase+.15),(.05,.08,.095),3,.012)
        box('brow',(s*.066,-.124+lean,headtop-.108),(.062,.023,.019),4)
    if not swat:
        rings('hair',[(headtop-.085,hw*1.03,.135,lean+.01),
                      (headtop-.005,hw*1.02,.13,lean+.01),(1.70,hw*.63,.09,lean+.01)],15 if elder else 4)
    for s in (-1,1):
        shoulder=(s*.24*width,lean,1.22)
        elbow=(s*.295*width,lean-.005,1.01)
        wrist=(s*.30*width,lean-.035,.83)
        limb('upper_sleeve',elbow,shoulder,.083,.105,coat)
        limb('lower_sleeve',wrist,elbow,.063,.079,coat)
        box('hand',(s*.30*width,lean-.035,.785),(.102,.105,.135),3,0 if child else .022)
    if child:
        box('backpack',(0,.175,1.05),(.30,.17,.34),8)
        for s in (-1,1):box('pack_strap',(s*.145,-.13,1.16),(.035,.032,.24),8)
    if elder:
        box('cardigan_pocket',(-.125,-.132,.92),(.10,.025,.115),25)
    if hero:
        rings('hood',[(1.26,.14,.145,.04),(1.34,.125,.13,.04),(1.37,.095,.10,.04)],18)
        for s in (-1,1):box('hood_cord',(s*.055,-.157,1.19),(.012,.015,.13),23)
        box('arm_wrap',(.30*width,-.036,.87),(.134,.134,.054),23)
    if journalist:
        box('camera',(0,-.215,1.065),(.22,.11,.14),2,.012)
        limb('lens',(0,-.25,1.065),(0,-.32,1.065),.057,.057,12,8)
        for s in (-1,1):limb('camera_strap',(s*.10,-.16,1.27),(s*.08,-.21,1.12),.012,.012,2,4)
        box('press_patch',(-.135,-.159,1.20),(.082,.018,.046),23)
        box('shoulder_bag',(.23,.10,.87),(.16,.17,.21),25,.016)
    if cop or swat:
        rings('belt',[(.795,.225*width,.148,0),(.84,.225*width,.148,0)],2)
        box('buckle',(0,-.157,.82),(.065,.025,.04),21)
        box('radio',(-.17,-.165,1.19),(.068,.045,.095),2)
        limb('antenna',(-.18,-.164,1.22),(-.18,-.164,1.30),.008,.008,2,4)
        box('holster',(.245*width,0,.805),(.08,.115,.17),2,.01)
        box('pistol_grip',(.245*width,-.015,.914),(.05,.065,.07),11)
    if cop:
        rings('cap',[(1.62,.163,.14,0),(1.69,.177,.145,0),(1.71,.135,.12,0)],10)
        box('cap_brim',(0,-.137,1.631),(.27,.18,.026),2,.009)
        box('badge',(.115,-.165,1.19),(.055,.016,.075),21,.012)
    if swat:
        rings('helmet',[(1.48,.18,.16,0),(1.62,.187,.164,0),(1.71,.125,.115,0)],11)
        box('visor',(0,-.151,1.575),(.29,.035,.095),16,.016)
        box('armor',(0,-.117,1.085),(.40*width,.125,.34),11,.025)
        box('armor_back',(0,.14,1.10),(.38*width,.08,.33),11,.015)
        for s in (-1,1):
            box('armor_pouch',(s*.105,-.194,1.055),(.115,.055,.13),24,.007)
            box('knee_pad',(s*.115*width,-.063,.475),(.125,.045,.12),11,.015)
        box('chest_band',(0,-.19,1.21),(.25,.02,.035),12)
    # Exact authored height, ground at zero, separate source parts retained.
    bpy.context.view_layer.update()
    top=max((o.matrix_world@Vector(v)).z for o in parts for v in o.bound_box)
    factor=height/top
    for o in parts:
        o.location*=factor
        o.scale*=factor
        bpy.context.view_layer.objects.active=o; o.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        o.select_set(False)
    return parts

def house():
    clean();palette()
    w,d,h=9,7.5,3.5
    wall=[]
    wall.append(box('back',(0,d/2-.25,h/2),(w,.5,h),17))
    for s in (-1,1):wall.append(box('side',(s*(w/2-.25),0,h/2),(.5,d-1,h),17))
    for s in (-1,1):wall.append(box('front',(s*2.75,-d/2+.25,h/2),(3.5,.5,h),17))
    wall.append(box('lintel',(0,-d/2+.25,2.95),(2,.5,1.1),17))
    for x in (-3,3):
        wall.append(box('window_trim',(x,-d/2-.008,1.9),(1.45,.06,1.35),25))
        wall.append(box('window',(x,-d/2-.042,1.9),(1.24,.03,1.15),16))
        wall.append(box('mullion',(x,-d/2-.065,1.9),(.055,.035,1.15),23))
        wall.append(box('sill',(x,-d/2-.08,1.25),(1.5,.16,.09),15))
    for s in (-1,1):
        for y in (-1.9,1.8):
            wall.append(box('side_window',(s*(w/2+.008),y,1.9),(.04,1.15,1.2),16))
    for s in (-1,1):wall.append(box('door_jamb',(s*1.065,-d/2-.03,1.2),(.13,.10,2.4),25))
    wall.append(box('door_header',(0,-d/2-.03,2.43),(2.26,.10,.13),25))
    join(wall,'Walls')
    roof=[]
    roof.append(box('roof_slab',(0,0,3.56),(9,7.5,.12),24))
    for s in (-1,1):
        roof.append(box('parapet',(s*4.40,0,3.70),(.20,7.5,.28),22))
        roof.append(box('parapet',(0,s*3.65,3.70),(8.6,.20,.28),22))
    roof.append(box('vent',(-2,1.5,3.94),(.6,.6,.48),15,.02))
    join(roof,'Roof')
    box('Floor',(0,0,-.1),(8,6.5,.2),25)

def bus():
    clean();palette()
    body=[]
    def b(n,l,s,c,be=0):
        o=box(n,l,s,c,be);body.append(o);return o
    b('lower_body',(0,0,.97),(2.38,7.95,.84),17,.09)
    b('upper_body',(0,0,2.01),(2.30,7.85,1.34),17,.08)
    b('roof',(0,.05,2.76),(2.35,7.8,.16),23,.055)
    b('roof_hvac',(0,.8,2.91),(1.35,1.7,.18),15,.025)
    b('windshield',(0,-3.94,2.10),(1.99,.04,.98),16,.06)
    b('destination',(0,-3.96,2.65),(1.3,.04,.18),20)
    b('evac_accent',(0,-3.99,2.65),(.78,.016,.045),19)
    for s in (-1,1):
        for y in (-2.75,-1.4,-.05,1.3,2.65):
            if s==1 and y==-2.75: continue
            b('side_window',(s*1.16,y,2.10),(.035,1.16,.94),16,.025)
        b('stripe',(s*1.199,0,1.21),(.018,7.4,.17),19)
        for y in (-2.5,2.5):
            o=limb('wheel',(s*1.02,y,.46),(s*1.2,y,.46),.46,.46,2,12);body.append(o)
            o=limb('hub',(s*1.201,y,.46),(s*1.212,y,.46),.23,.23,22,8);body.append(o)
        b('headlight',(s*.84,-3.982,.95),(.34,.035,.18),23,.025)
        b('rear_light',(s*.89,3.986,1.01),(.17,.03,.27),18)
    b('bumper',(0,-3.99,.66),(2.12,.035,.14),11)
    b('rear_window',(0,3.94,2.1),(1.95,.04,.84),16,.04)
    join(body,'Body')
    door=[]
    door.append(box('door_panel',(1.17,-2.85,1.5),(.055,1.02,2.05),11,.012))
    for y in (-3.10,-2.6):door.append(box('door_glass',(1.205,y,1.89),(.022,.42,1.08),16))
    join(door,'Door')
    bpy.ops.object.empty_add(location=(1.95,-2.85,0));bpy.context.object.name='BoardingPoint'

def save_asset(name,category,mass=False):
    out=EXPORT/category;src=SOURCE/category
    out.mkdir(parents=True,exist_ok=True);src.mkdir(parents=True,exist_ok=True)
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    # Keep source parts and export a consolidated copy in a separate collection.
    source_objects=list(bpy.context.scene.objects)
    bpy.ops.wm.save_as_mainfile(filepath=str(src/(name+'.blend')))
    if mass:
        o=join([o for o in source_objects if o.type=='MESH'],name)
        export_objects=[o]
    else:export_objects=source_objects
    bpy.ops.object.select_all(action='DESELECT')
    for o in export_objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out/(name+'.glb')),export_format='GLB',use_selection=True,
                             export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    meshes=[o for o in export_objects if o.type=='MESH']
    for o in meshes:o.data.calc_loop_triangles()
    coords=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
    dims=[round(max(v[i] for v in coords)-min(v[i] for v in coords),4) for i in range(3)]
    catalog.append(dict(id=name,category=category,glb=f'assets/models/{category}/{name}.glb',
                        blend=f'art_source/blender/{category}/{name}.blend',
                        triangles=sum(len(o.data.loop_triangles) for o in meshes),mesh_count=len(meshes),
                        dimensions_godot_xyz=[dims[0],dims[2],dims[1]],forward='+Z',
                        materials=1,rigged=False))

def render_sheet(ids,filename):
    clean()
    for idx,(name,cat) in enumerate(ids):
        bpy.ops.import_scene.gltf(filepath=str(EXPORT/cat/(name+'.glb')))
        imported=list(bpy.context.selected_objects)
        for o in imported:
            if o.parent is None:o.location.x+=(idx-(len(ids)-1)/2)*1.08
    # Preview stage is never exported with an asset.
    palette()
    box('preview_ground',(0,0,-.06),(20,12,.10),20)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=1800;scene.render.resolution_y=850;scene.render.resolution_percentage=100
    scene.world.color=(.20,.20,.20)
    for loc,power,size in [((-3,-4,7),1500,6),((4,2,5),1000,5)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object
        o.data.energy=power;o.data.shape='DISK';o.data.size=size
        o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(4,-9,6.4));cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.85))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=10.2;scene.camera=cam
    scene.view_settings.view_transform='AgX'
    scene.render.filepath=str(PREVIEW/filename);bpy.ops.render.render(write_still=True)

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    control='--control' in args
    specs=[('civilian_normal_a',1.70,0,1),('patient_zero',1.8,13,1)] if control else [
        ('civilian_normal_a',1.70,0,1),('civilian_child_a',1.20,6,.90),
        ('civilian_elder_a',1.60,7,.95),('civilian_brute_a',1.85,8,1.15),
        ('civilian_journalist_a',1.70,9,1),('police_officer_a',1.75,10,1),
        ('swat_officer_a',1.80,11,1.10),('patient_zero',1.80,13,1)]
    for name,height,col,width in specs:
        character(name,height,col,width);save_asset(name,'characters',mass=True)
    if not control:
        house();save_asset('building_house_a','buildings')
        bus();save_asset('evac_bus','vehicles')
    (ROOT/'art_source'/'model_manifest.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
    render_sheet([(s[0],'characters') for s in specs],'characters_control.png' if control else 'characters_lineup.png')
    print('MODEL_BATCH_COMPLETE',json.dumps(catalog))
