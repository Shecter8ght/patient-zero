import bpy,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_models as m

for name,category,scale in [('building_house_a','buildings',16),('evac_bus','vehicles',13)]:
    m.clean(); m.palette()
    bpy.ops.import_scene.gltf(filepath=str(m.EXPORT/category/(name+'.glb')))
    m.box('preview_ground',(0,0,-.22 if category=='buildings' else -.05),(40,40,.08),20)
    scene=bpy.context.scene; scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.world.color=(.22,.22,.22)
    for loc,power,size in [((2,-7,12),2500,8),((-6,5,9),1800,7)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object
        o.data.energy=power;o.data.shape='DISK';o.data.size=size
        o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(12,-16,12));cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=scale;scene.camera=cam
    scene.view_settings.view_transform='AgX'
    scene.render.filepath=str(m.PREVIEW/(name+'.png'));bpy.ops.render.render(write_still=True)
    if category=='buildings':
        bpy.data.objects.get('Roof').hide_render=True
        scene.render.filepath=str(m.PREVIEW/(name+'_interior.png'));bpy.ops.render.render(write_still=True)
