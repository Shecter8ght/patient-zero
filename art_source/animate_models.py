"""Author segmented low-poly rigs, GLB clips, and compact GPU bone-animation textures."""
import bpy, bmesh, math, json, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'animations'; OUT.mkdir(parents=True,exist_ok=True)
SRC=ROOT/'art_source'/'blender'/'animated';SRC.mkdir(parents=True,exist_ok=True)
FPS=24
CLIPS=[('idle',2,True),('walk',1,True),('run',.666667,True),('grab',1,True),
       ('resist',1,True),('turning',1,False),('fall',1,False),('arrested',1,True),
       ('break_free',.666667,False),('lunge',.5,False),('phone',1,True),
       ('photo',1,True),('shoot',.5,False),
       ('zombie_idle',2,True),('zombie_walk',1.5,True),('zombie_run',.833333,True),
       ('bite',1,True),('bitten_idle',2,True),('bitten_walk',1.25,True),('bitten_run',.875,True)]
MODELS=['civilian_normal_a','civilian_child_a','civilian_elder_a','civilian_brute_a',
        'civilian_journalist_a','police_officer_a','swat_officer_a','patient_zero',
        'civilian_normal_b','civilian_normal_c']
CONVERT=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))

def bind(name):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art_source'/'blender'/'characters'/(name+'.blend')))
    bpy.context.preferences.filepaths.save_version=0
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    # Hand-held equipment is exported as part of the same skinned surface.
    for o in list(objects):
        if o.name.split('.')[0] in {'camera','lens','camera_strap','pistol_grip'}:
            objects.remove(o);bpy.data.objects.remove(o,do_unlink=True)
    top=max((o.matrix_world@Vector(v)).z for o in objects for v in o.bound_box)
    factor=top/(1.71 if 'officer' in name else 1.70)
    # Split the existing lower face into a real hinged jaw; preserve the one-surface palette.
    headmesh=next(o for o in objects if o.name.split('.')[0]=='head')
    cut=min(v.co.z for v in headmesh.data.vertices)+.115*factor
    jaw=headmesh.copy();jaw.data=headmesh.data.copy();jaw.name='jaw'
    bpy.context.collection.objects.link(jaw);objects.append(jaw)
    for obj,lower in [(headmesh,False),(jaw,True)]:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                              plane_co=(0,0,cut),plane_no=(0,0,1),clear_outer=lower,clear_inner=not lower)
        bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data);bm.free()
        for loop in obj.data.uv_layers.active.data:loop.uv=((3+.5)/8,.5/4)
    front=min(v.co.y for v in headmesh.data.vertices)
    def mouth_box(tag,loc,size,palette_index):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc);obj=bpy.context.object
        obj.name=tag;obj.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        obj.data.materials.append(headmesh.data.materials[0])
        for loop in obj.data.uv_layers.active.data:loop.uv=((palette_index%8+.5)/8,(palette_index//8+.5)/4)
        objects.append(obj)
    mouth_box('mouth_inside',(0,front+.025*factor,cut-.014*factor),(.17*factor,.055*factor,.045*factor),20)
    mouth_box('lower_teeth',(0,front+.005*factor,cut-.010*factor),(.11*factor,.023*factor,.014*factor),23)
    # Read actual limb pivots from source parts rather than assume adult proportions.
    def center(prefix,side=None):
        found=[o for o in objects if o.name.split('.')[0]==prefix and (side is None or o.location.x*side>0)]
        return found[0].location.copy() if found else Vector((0,0,0))
    joints=[('root',(0,0,0),None),('pelvis',(0,0,.82*factor),'root'),
            ('spine',(0,0,1.04*factor),'pelvis'),('head',(0,0,1.32*factor),'spine'),
            ('jaw',(0,front+.16*factor,cut),'head')]
    for s,label in [(-1,'L'),(1,'R')]:
        upper=center('upper_sleeve',s);lower=center('lower_sleeve',s)
        joints += [('upper_arm_'+label,(upper.x,upper.y,1.22*factor),'spine'),
                   ('forearm_'+label,(lower.x,lower.y,1.01*factor),'upper_arm_'+label),
                   ('hand_'+label,tuple(center('hand',s)),'forearm_'+label),
                   ('thigh_'+label,(center('trouser_leg',s).x,.015*factor,.85*factor),'pelvis'),
                   ('calf_'+label,(center('shin',s).x,.015*factor,.46*factor),'thigh_'+label),
                   ('foot_'+label,(center('boot',s).x,.015*factor,.15*factor),'calf_'+label)]
    hand=center('hand',1)
    for prop in ['phone','camera','pistol']:
        joints.append(('prop_'+prop,tuple(hand),'hand_R'))
        wanted=(prop=='phone' and ('normal' in name or 'elder' in name)) or (prop=='camera' and 'journalist' in name) or (prop=='pistol' and 'officer' in name)
        if wanted:
            path=ROOT/'art_source'/'blender'/'props'/('prop_'+prop+'.blend')
            with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.objects=src.objects
            for obj in dst.objects:
                if obj.type!='MESH':continue
                bpy.context.collection.objects.link(obj)
                obj.location=hand+obj.location*factor
                obj.scale*=factor
                obj.name='equipment_'+prop
                obj.data.materials.clear();obj.data.materials.append(headmesh.data.materials[0])
                objects.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    armdata=bpy.data.armatures.new('PZ_Skeleton');arm=bpy.data.objects.new('PZ_Rig',armdata)
    bpy.context.collection.objects.link(arm);arm.select_set(True);bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='EDIT')
    for bn,head,parent in joints:
        b=armdata.edit_bones.new(bn);b.head=head;b.tail=Vector(head)+Vector((0,0,.1*factor))
        if parent:b.parent=armdata.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT');arm.show_in_front=True
    bone_names=[x[0] for x in joints]
    head_parts={'head','hair','nose','ear','brow','helmet','visor','cap','cap_brim','mouth_inside'}
    pelvis_parts={'belt','buckle','holster','pistol_grip','shoulder_bag'}
    for o in objects:
        tag=o.name.split('.')[0];side='L' if o.location.x<0 else 'R'
        bn='spine'
        if tag in head_parts:bn='head'
        elif tag.startswith('equipment_'):bn='prop_'+tag.removeprefix('equipment_')
        elif tag in {'jaw','lower_teeth'}:bn='jaw'
        elif tag in pelvis_parts:bn='pelvis'
        elif tag in {'boot'}:bn='foot_'+side
        elif tag in {'shin','knee_pad'}:bn='calf_'+side
        elif tag=='trouser_leg':bn='thigh_'+side
        elif tag=='upper_sleeve':bn='upper_arm_'+side
        elif tag in {'lower_sleeve','arm_wrap'}:bn='forearm_'+side
        elif tag=='hand':bn='hand_'+side
        group=o.vertex_groups.new(name=bn);group.add(list(range(len(o.data.vertices))),1,'REPLACE')
        uv=o.data.uv_layers.new(name='BoneIndex')
        for loop in uv.data:loop.uv=((bone_names.index(bn)+.5)/len(bone_names),.5)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();mesh=bpy.context.object
    mesh.name=name+'_skin';bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    # Mark UV0 as active render UV: UV1 carries a discrete bone ID for the static GPU export.
    mesh.data.uv_layers.active_index=0;mesh.data.uv_layers[0].active_render=True
    mod=mesh.modifiers.new('Armature','ARMATURE');mod.object=arm;mesh.parent=arm
    for p in arm.pose.bones:p.rotation_mode='XYZ'
    verts=[(v.co.copy(),mesh.vertex_groups[v.groups[0].group].name) for v in mesh.data.vertices]
    return arm,mesh,bone_names,verts,factor

def pose(arm,clip,t,factor,verts):
    tau=math.tau*t
    for p in arm.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
    for prop,active in [('phone','phone'),('camera','photo'),('pistol','shoot')]:
        arm.pose.bones['prop_'+prop].scale=(1,1,1) if clip==active else (.0001,.0001,.0001)
    def rotate(b,x=0,y=0,z=0):arm.pose.bones[b].rotation_euler=(x,y,z)
    root=arm.pose.bones['root'];root.location.y=.008*math.sin(tau)*factor
    if clip=='idle':rotate('spine',.025*math.sin(tau));rotate('head',0,0,.045*math.sin(tau))
    if clip in ('walk','run'):
        amplitude=.38 if clip=='walk' else .72
        rotate('spine',.035 if clip=='walk' else .16,0,.025*math.sin(tau))
        for phase,side in [(0,'L'),(math.pi,'R')]:
            wave=math.sin(tau+phase)
            rotate('thigh_'+side,amplitude*wave)
            rotate('calf_'+side,-max(0,-wave)*(.45 if clip=='walk' else 1.05))
            rotate('foot_'+side,-.10*wave)
            rotate('upper_arm_'+side,-amplitude*.85*wave)
            rotate('forearm_'+side,-(.15 if clip=='walk' else .85))
    elif clip in ('bitten_idle','bitten_walk','bitten_run'):
        # Still human: a guarded arm, one shortened step, mild instability, no reaching zombie arms.
        moving=clip!='bitten_idle';fast=clip=='bitten_run'
        sway=math.sin(tau)
        rotate('pelvis',.025,0,.018*sway)
        rotate('spine',(.14 if fast else .105)+.025*math.sin(tau*2),.018*sway,.035*sway)
        rotate('head',.08+.025*math.sin(tau+.6),0,-.035)
        rotate('upper_arm_R',-.18+.055*sway,0,-.10)
        rotate('forearm_R',-.65+.04*math.sin(tau+.4))
        rotate('hand_R',.08)
        for phase,side in [(0,'L'),(math.pi,'R')]:
            wave=math.sin(tau+phase+.10*math.sin(tau))
            if moving:
                amplitude=(.60 if side=='L' else .42) if fast else (.33 if side=='L' else .23)
                rotate('thigh_'+side,.025+amplitude*wave)
                rotate('calf_'+side,-max(0,-wave)*(.73 if fast else .32))
                rotate('foot_'+side,-.07*wave)
                if side=='L':
                    rotate('upper_arm_L',-amplitude*.68*wave)
                    rotate('forearm_L',-.44 if fast else -.22)
            else:
                rotate('thigh_'+side,.02)
                if side=='L':rotate('forearm_L',-.18)
    elif clip in ('zombie_idle','zombie_walk','zombie_run'):
        # Deliberately uneven, planted shamble: forward arms do not swing like a runner.
        moving=clip!='zombie_idle'
        fast=clip=='zombie_run'
        sway=math.sin(tau)
        rotate('pelvis',.06,0,.035*sway)
        rotate('spine',(.40 if fast else .28)+.025*math.sin(tau*2),.025*sway,.075*sway)
        rotate('head',.15+.045*math.sin(tau+.8),.025*math.sin(tau),-.10)
        rotate('jaw',.075+.035*math.sin(tau+.3))
        for phase,side,s in [(0,'L',-1),(math.pi,'R',1)]:
            wave=math.sin(tau+phase+.18*math.sin(tau*2))
            rotate('upper_arm_'+side,(-1.10 if side=='L' else -.80)+.08*math.sin(tau+phase+.6),s*.09,.035*sway)
            rotate('forearm_'+side,-.15+.065*math.sin(tau+phase))
            rotate('hand_'+side,.30+.06*math.sin(tau+phase+.5))
            if moving:
                amplitude=(.49 if side=='L' else .32) if fast else (.28 if side=='L' else .17)
                rotate('thigh_'+side,.08+amplitude*wave)
                rotate('calf_'+side,-.08-max(0,-wave)*(.32 if fast else .14))
                rotate('foot_'+side,.05-.06*wave)
            else:
                rotate('thigh_'+side,.055)
                rotate('calf_'+side,-.09)
    elif clip=='bite':
        strike=max(0,math.sin(tau-.7))**4
        gape=max(0,math.sin(tau+.9))**2
        rotate('pelvis',.08)
        rotate('spine',.25+.19*strike,0,.035*math.sin(tau))
        rotate('head',.13+.29*strike,0,-.08)
        arm.pose.bones['head'].location.z=.045*factor*strike
        rotate('jaw',.025+.62*gape)
        for side,s in [('L',-1),('R',1)]:
            rotate('upper_arm_'+side,-1.18+.12*strike,s*.10)
            rotate('forearm_'+side,-.23-.20*strike)
            rotate('hand_'+side,.18)
            rotate('thigh_'+side,.07+s*.045)
            rotate('calf_'+side,-.12)
    elif clip in ('grab','resist','arrested','turning'):
        a= .12*math.sin(tau*2)
        rotate('spine',.12+a*.3,0,a*.35)
        for side,s in [('L',-1),('R',1)]:
            rotate('upper_arm_'+side, -.95+a if clip=='grab' else -.4, .10*s)
            rotate('forearm_'+side,-.35 if clip=='grab' else -1.0+a*s)
        if clip=='turning':
            rotate('head',-.18*math.sin(math.pi*t),0,.15*math.sin(tau*3))
            rotate('spine',-.22*math.sin(math.pi*t),0,a)
        if clip=='arrested':rotate('head',.20)
    elif clip=='fall':
        k=t*t*(3-2*t)
        rotate('pelvis',1.50*k)
        rotate('spine',.06*k)
        for side in ('L','R'):rotate('upper_arm_'+side,-.75*math.sin(math.pi*t));rotate('calf_'+side,-.2*math.sin(math.pi*t))
    elif clip in ('break_free','lunge'):
        k=math.sin(math.pi*t)
        rotate('spine',.35*k,0,.3*k if clip=='break_free' else 0)
        for side,s in [('L',-1),('R',1)]:
            rotate('upper_arm_'+side,-1.1*k,s*.25*k)
            rotate('forearm_'+side,-.3*k)
            rotate('thigh_'+side,s*.4*k);rotate('calf_'+side,-.4*k)
    elif clip=='phone':
        rotate('upper_arm_R',-1.30,.35);rotate('forearm_R',-1.55)
        rotate('hand_R',2.85,-.35);rotate('head',0,.04,.10)
    elif clip in ('photo','shoot'):
        for side,s in [('L',-1),('R',1)]:
            rotate('upper_arm_'+side,-1.10 if clip=='photo' else -1.50,s*(.55 if clip=='photo' else .32))
            rotate('forearm_'+side,-1.60 if clip=='photo' else -.12)
            rotate('hand_'+side,2.70 if clip=='photo' else 1.62,-s*(.55 if clip=='photo' else .32))
        if clip=='shoot':rotate('spine',-.1*math.sin(math.pi*t))
    bpy.context.view_layer.update()
    if clip in ('phone','photo','shoot'):
        # Solve the two rigid arm segments to authored grip points, keeping props upright.
        def grip(side,point):
            upper=arm.pose.bones['upper_arm_'+side]
            fore=arm.pose.bones['forearm_'+side]
            hand=arm.pose.bones['hand_'+side]
            start=upper.matrix.translation.copy()
            target=Vector(point)*factor
            a=fore.bone.head_local-upper.bone.head_local
            b=hand.bone.head_local-fore.bone.head_local
            direction=target-start;distance=min(direction.length,a.length+b.length-.001)
            direction.normalize();target=start+direction*distance
            x=(a.length_squared-b.length_squared+distance*distance)/(2*distance)
            hint=Vector((1 if side=='R' else -1,0,0))
            bend=(hint-direction*hint.dot(direction)).normalized()
            elbow=start+direction*x+bend*math.sqrt(max(0,a.length_squared-x*x))
            for bone,origin,old,new in [(upper,start,a,elbow-start),(fore,elbow,b,target-elbow)]:
                rotation=old.rotation_difference(new).to_matrix().to_4x4()
                bone.matrix=Matrix.Translation(origin)@rotation@bone.bone.matrix_local.to_3x3().to_4x4()
                bpy.context.view_layer.update()
            hand.matrix=Matrix.Translation(target)@hand.bone.matrix_local.to_3x3().to_4x4()
            bpy.context.view_layer.update()
        if clip=='phone':grip('R',(.18,-.035,1.40))
        elif clip=='photo':
            grip('R',(.10,-.24,1.40));grip('L',(-.025,-.24,1.40))
        else:
            grip('R',(.12,-.35,1.20));grip('L',(.02,-.30,1.18))
    transforms={p.name:p.matrix@p.bone.matrix_local.inverted() for p in arm.pose.bones}
    lowest=min((transforms[bn]@v).z for v,bn in verts)
    root.location.y-=lowest
    if clip=='run':root.location.y+=.035*factor*abs(math.sin(tau))
    bpy.context.view_layer.update()

def generate(name):
    arm,mesh,names,verts,factor=bind(name)
    scene=bpy.context.scene;scene.render.fps=FPS
    arm.animation_data_create();tracks=[];clipdata={};rows=[]
    width=64
    for clip,duration,loop in CLIPS:
        frames=round(duration*FPS)
        action=bpy.data.actions.new(clip);action.use_fake_user=True;arm.animation_data.action=action
        start=len(rows)
        for j in range(frames+1):
            scene.frame_set(j+1);pose(arm,clip,j/frames,factor,verts)
            for p in arm.pose.bones:
                p.keyframe_insert(data_path='rotation_euler',frame=j+1,group=p.name)
                p.keyframe_insert(data_path='location',frame=j+1,group=p.name)
                p.keyframe_insert(data_path='scale',frame=j+1,group=p.name)
            row=[]
            for bn in names:
                p=arm.pose.bones[bn]
                mat=CONVERT @ (p.matrix@p.bone.matrix_local.inverted()) @ CONVERT.inverted()
                for r in range(3):row.extend(mat[r])
            row.extend([0.]*(width*4-len(row)));rows.append(row)
        clipdata[clip]={'start':start,'frames':frames+1,'duration':frames/FPS,'loop':loop}
        arm.animation_data.action=None
        track=arm.animation_data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,1,action);strip.extrapolation='NOTHING'
        track.mute=True;tracks.append(track)
    # Export rest pose mesh for MultiMesh, with one rigid bone ID per vertex in UV2.
    arm.data.pose_position='REST';scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
    mesh.parent=None
    mod=mesh.modifiers.get('Armature');mod.show_viewport=False;mod.show_render=False
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'_gpu.glb')),export_format='GLB',use_selection=True,
                             export_animations=False,export_skins=False,export_yup=True,export_apply=False)
    mesh.parent=arm;mod.show_viewport=True;mod.show_render=True;arm.data.pose_position='POSE'
    arm.select_set(True)
    for tr in tracks:tr.mute=False
    scene.frame_start=1;scene.frame_end=49
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'_rigged.glb')),export_format='GLB',use_selection=True,
                             export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,
                             export_yup=True,export_skins=True)
    # Save authoring file with idle selected, other actions in NLA muted.
    for tr in tracks:tr.mute=True
    arm.animation_data.action=tracks[0].strips[0].action;scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'_animated.blend')))
    flat=[v for row in rows for v in row]
    (OUT/(name+'_bones.bin')).write_bytes(struct.pack('<%sf'%len(flat),*flat))
    metadata={'width':width,'height':len(rows),'bones':names,'fps':FPS,'clips':clipdata,
              'format':'RGBAF row-major: 3 texels per bone; Godot rest-to-pose transform',
              'binding':'UV2.x = (bone_index + 0.5) / bone_count', 'rigid_weights':True}
    (OUT/(name+'.json')).write_text(json.dumps(metadata,indent=2),encoding='utf8')
    print('ANIMATED',name,len(names),'bones',len(rows),'frames',flush=True)

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    for name in (args or MODELS):generate(name)
