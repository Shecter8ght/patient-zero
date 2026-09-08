"""Blender source generator for the mall, its repeatable floor, kiosks and transitions.
Reads spatial settings from scripts/tuning.gd; exports editable Blender sources and GLB.
"""
import sys, re, json, math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_models as m
import bpy

def setting(name):
    text=(m.ROOT/'scripts/tuning.gd').read_text(encoding='utf-8')
    return float(re.search(r'const '+name+r'\s*:=\s*([0-9.]+)',text).group(1))

def shell(size, floors, step, entrance):
    m.clean(); m.palette()
    half=size/2; height=floors*step; walls=[]
    def b(n,p,s,c):
        o=m.box(n,p,s,c);walls.append(o);return o
    # Front is +Y in Blender -> -Z in Godot, matching the city entrance.
    b('rear',(0,-half+.56,height/2),(size-.12,1,height),12)
    for sign in (-1,1):
        b('wing',(sign*(half-.56),0,height/2),(1,size-2.12,height),12)
        width=half-.06-entrance/2
        b('front',(sign*(entrance/2+width/2),half-.56,height/2),(width,1,height),15)
    b('entry_lintel',(0,half-.56,(height+2.9)/2),(entrance,1,height-2.9),15)
    # Large facade panes, floor bands and mullions, all within the footprint.
    for floor in range(floors):
        z=floor*step+1.75
        for side in (-1,1):
            n=int((size-3)/3)
            for j in range(n):
                x=(j-(n-1)/2)*3
                if side==1 and abs(x)<entrance/2+1.4: continue
                b('glazing',(x,side*(half-.015),z),(2.6,.025,2.25),20)
                b('glass_highlight',(x-.85,side*(half-.002),z),(.10,.004,2.1),16)
                b('side_glazing',(side*(half-.015),x,z),(.025,2.6,2.25),20)
            b('front_band',(0,side*(half-.03),(floor+1)*step-.12),(size,.06,.24),23)
            b('side_band',(side*(half-.03),0,(floor+1)*step-.12),(.06,size,.24),23)
    # Entrance surround with canopy fully inside the outer footprint.
    for sign in (-1,1):
        b('entry_pier',(sign*(entrance/2+.18),half-.25,1.5),(.36,.5,3),23)
    b('entry_canopy',(0,half-.55,3.15),(entrance+1.4,1.1,.26),19)
    b('sign_backplate',(0,half-.07,4.25),(entrance+2,.14,1.25),11)
    # Simple own-name signage, converted to editable mesh; no brands.
    bpy.ops.object.text_add(location=(0,half+.005,4.0),rotation=(math.pi/2,0,math.pi))
    sign=bpy.context.object; sign.data.body='CENTR'; sign.data.align_x='CENTER'; sign.data.size=.80; sign.data.extrude=.008
    bpy.ops.object.convert(target='MESH');m.finish(bpy.context.object,'mall_sign',23);walls.append(bpy.context.object)
    m.join(walls,'MallExteriorWalls')
    roof=[m.box('roof_slab',(0,0,height+.1),(size,size,.2),24)]
    for sign in (-1,1):
        roof.append(m.box('parapet',(sign*(half-.2),0,height+.4),(.4,size,.6),15))
        roof.append(m.box('parapet',(0,sign*(half-.2),height+.4),(size-.8,.4,.6),15))
    for x in (-size*.22,size*.22):
        for y in (-size*.20,size*.20):
            roof.append(m.box('hvac',(x,y,height+.7),(3,2,1.2),11))
            for dx in (-.8,.8):
                roof.append(m.box('hvac_vent',(x+dx,y,height+1.33),(.55,1.7,.08),22))
    # Opaque skylight panels: the current simulation uses a continuous floor.
    for x in (-4,0,4):
        roof.append(m.box('skylight_frame',(x,0,height+.30),(3.2,8,.32),11))
        roof.append(m.box('skylight',(x,0,height+.48),(2.95,7.75,.04),16))
    m.join(roof,'MallRoof')

def floor(size):
    m.clean();m.palette();inner=size-2;half=inner/2
    pieces=[m.box('slab',(0,0,-.12),(inner,inner,.24),28)]
    # Thin tile joints are geometry in one mesh, not hundreds of scene nodes.
    for i in range(-int(half)+2,int(half),2):
        pieces.append(m.box('tile_joint_x',(i,0,.002),(.018,inner,.004),22))
        pieces.append(m.box('tile_joint_y',(0,i,.002),(inner,.018,.004),22))
    for sign in (-1,1):
        pieces.append(m.box('gallery_border',(sign*3.8,0,.005),(.18,inner,.01),19))
        pieces.append(m.box('gallery_border',(0,sign*3.8,.005),(inner,.18,.01),19))
    m.join(pieces,'Floor')
    panels=[]
    # Low perimeter curb keeps the view open; all solid geometry outside walk bounds.
    for sign in (-1,1):
        panels.append(m.box('perimeter',(sign*(half+.12),0,.45),(.24,inner,.9),15))
        # Leave a central 6 m opening in both end walls.
        width=half-3
        for side in (-1,1):
            panels.append(m.box('perimeter',(side*(3+width/2),sign*(half+.12),.45),(width,.24,.9),15))
    m.join(panels,'Perimeter')

def kiosk(kind):
    m.clean();m.palette();w=3.5;d=2.75
    items=[]
    def b(n,p,s,c):
        o=m.box(n,p,s,c);items.append(o);return o
    accent={'food':19,'clothes':18,'electronics':10}[kind]
    b('base',(0,0,.12),(w,d,.24),11)
    b('counter_front',(0,-1.13,.65),(w,.42,1.05),17)
    b('counter_top',(0,-1.13,1.21),(w,.50,.12),accent)
    for sign in (-1,1):b('side_counter',(sign*1.5,0,.65),(.5,2.2,1.05),17)
    b('back_shelf',(0,1.14,.87),(3.4,.38,1.5),15)
    b('sign',(0,1.15,1.87),(3.3,.16,.26),accent)
    if kind=='food':
        for x in (-1.05,-.35,.35,1.05):
            b('produce_crate',(x,-.95,1.36),(.56,.47,.2),7)
            for dy in (-.12,.12):
                for dx in (-.15,.15):b('produce',(x+dx,-.95+dy,1.53),(.20,.18,.17),6 if x<0 else 18)
        for z in (.5,1.0,1.5):
            for j in range(9):b('carton',((j-4)*.33,1.02,z),(.21,.22,.30),23 if j%2 else 19)
    elif kind=='clothes':
        for z in (.4,.85,1.3):
            for j in range(6):b('folded_clothes',((j-2.5)*.5,1.02,z),(.4,.25,.18),[9,18,6][j%3])
        for x in (-.8,.0,.8):
            b('shirt',(x,.25,1.05),(.43,.20,.60),[9,18,6][round(x/.8)+1])
            b('sleeves',(x,.25,1.22),(.67,.19,.20),[9,18,6][round(x/.8)+1])
        b('rail',(0,.25,1.58),(2.8,.07,.07),22)
    else:
        for x in (-1.05,0,1.05):
            b('monitor',(x,-.95,1.55),(.70,.10,.45),11)
            b('screen',(x,-1.008,1.55),(.59,.015,.34),9)
            b('stand',(x,-.95,1.29),(.13,.14,.13),22)
        for z in (.45,1.0,1.5):
            for j in range(7):b('boxed_stock',((j-3)*.42,1.01,z),(.33,.25,.35),15 if j%2 else 10)
    m.join(items,'Kiosk')

def shop(kind):
    m.clean();m.palette();pieces=[]
    def b(n,p,s,c):
        o=m.box(n,p,s,c);pieces.append(o);return o
    accent={'food':19,'clothes':18,'electronics':10}[kind]
    # Godot footprint 8 x 6. Fixtures correspond to MapGen local Rect2s.
    b('shop_floor',(0,0,.008),(8,6,.016),25 if kind=='clothes' else 15)
    m.join(pieces,'ShopFloor');pieces=[]
    b('back_shelf',(0,2.7,1.0),(8,.6,2.0),11)
    for sign in (-1,1):
        b('side_shelf',(sign*3.8,-.3,.75),(.4,5.4,1.5),17)
        for z in (.3,.7,1.1):
            for y in (-2.5,-1.5,-.5,.5,1.5):
                b('side_stock',(sign*3.79,y,z+.15),(.32,.55,.25),accent)
    b('checkout',(-1.95,-1.85,.53),(2.5,.7,1.06),17)
    b('checkout_top',(-1.95,-1.85,1.10),(2.5,.7,.08),accent)
    b('register',(-2.55,-1.85,1.30),(.35,.35,.32),11)
    for z in (.4,.9,1.4):
        for j in range(14):
            x=(j-6.5)*.52
            if kind=='electronics':
                b('display_monitor',(x,2.37,z+.22),(.42,.20,.34),11)
                b('display_screen',(x,2.263,z+.22),(.33,.015,.25),9)
            elif kind=='food':
                b('product_crate',(x,2.45,z+.18),(.43,.36,.30),6 if j%3==0 else 19 if j%3==1 else 18)
            else:
                b('folded_stock',(x,2.45,z+.12),(.43,.36,.18),[9,18,6,23][j%4])
    m.join(pieces,'Fixtures');pieces=[]
    b('back_sign',(0,2.76,2.42),(7.8,.35,.52),accent)
    for sign in (-1,1):b('sign_support',(sign*3.82,2.7,1.3),(.18,.3,2.6),11)
    m.join(pieces,'ShopWalls')


def escalator(up):
    m.clean();m.palette();parts=[]
    # Compact transition marker, 4 x 4 footprint; entry landing at Godot -Z.
    parts.append(m.box('landing',(0,1.2,.025),(2.7,1.5,.05),24))
    for i in range(8):
        y=.45-i*.32;z=.10+i*.12
        parts.append(m.box('step',(0,y,z/2),(1.65,.34,z),22))
        parts.append(m.box('step_edge',(0,y+.13,z+.008),(1.65,.035,.016),23))
    for sign in (-1,1):
        rail=m.box('side',(sign*1.0,-.7,.72),(.30,2.9,.55),11)
        rail.rotation_euler.x=-.25;parts.append(rail)
        rail=m.box('handrail',(sign*1.0,-.7,1.06),(.35,2.95,.10),10 if up else 18)
        rail.rotation_euler.x=-.25;parts.append(rail)
    parts.append(m.box('direction_panel',(0,1.3,.058),(.75,.62,.015),10 if up else 18))
    m.join(parts,'Escalator')

if __name__=='__main__':
    size=setting('MALL_SIZE');floors=int(setting('MALL_FLOORS'));step=setting('FLOOR_HEIGHT');entry=setting('MALL_ENTRANCE_W')
    shell(size,floors,step,entry);m.save_asset('mall_shell','mall')
    floor(size);m.save_asset('mall_floor','mall')
    for kind in ('food','clothes','electronics'):
        kiosk(kind);m.save_asset('mall_kiosk_'+kind,'mall')
    for kind in ('food','clothes','electronics'):
        shop(kind);m.save_asset('mall_shop_'+kind,'mall')
    for up in (True,False):
        escalator(up);m.save_asset('mall_escalator_'+('up' if up else 'down'),'mall')
    (m.ROOT/'art_source/mall_manifest.json').write_text(json.dumps(m.catalog,indent=2))
    print('MALL_ASSETS_COMPLETE',size,len(m.catalog))
