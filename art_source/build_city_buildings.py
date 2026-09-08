"""Build three building families and exact-size instances for the current map."""
import sys, json, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_models as m

def building(kind, w, d, h):
    m.clean(); m.palette()
    color = {"apartment": 15, "utility": 8, "office": 12}[kind]
    walls=[]
    def b(name, pos, size, col):
        obj=m.box(name,pos,size,col); walls.append(obj); return obj
    # Keep facade accents inside the collision footprint. Entry stays exactly 2 m.
    shell_w, shell_d=w-.12,d-.12
    b('back',(0,shell_d/2-.25,h/2),(shell_w,.5,h),color)
    for sign in (-1,1):
        b('side',(sign*(shell_w/2-.25),0,h/2),(.5,shell_d-1,h),color)
        span=shell_w/2-1
        b('front',(sign*(1+span/2),-shell_d/2+.25,h/2),(span,.5,h),color)
    b('entry_lintel',(0,-shell_d/2+.25,(h+2.4)/2),(2,.5,h-2.4),color)
    floors=round(h/3.5)
    # Fixed-size windows are distributed, never stretched with the building.
    for floor in range(floors):
        z=floor*3.5+1.9
        for side in (-1,1):
            count=max(2,int((w-1)/2.5))
            for j in range(count):
                x=(j-(count-1)/2)*2.5
                if side==-1 and floor==0 and abs(x)<1.9: continue
                ww=1.65 if kind=='office' else 1.35
                wh=.85 if kind=='utility' else 1.45
                b('window_frame',(x,side*(d/2-.035),z),(ww+.16,.05,wh+.16),23 if kind=='apartment' else 11)
                b('window_glass',(x,side*(d/2-.009),z),(ww,.018,wh),16 if kind!='office' else 20)
                if kind=='apartment':
                    b('window_mullion',(x,side*(d/2-.005),z),(.065,.008,wh),23)
            count=max(2,int((d-1)/2.5))
            for j in range(count):
                y=(j-(count-1)/2)*2.5
                b('side_frame',(side*(w/2-.035),y,z),(.05,1.51,1.01 if kind=='utility' else 1.61),11)
                b('side_glass',(side*(w/2-.009),y,z),(.018,1.35,.85 if kind=='utility' else 1.45),16)
        # Thin horizontal bands distinguish the repeated storeys.
        if floor>0:
            for sign in (-1,1):
                b('facade_band',(0,sign*(d/2-.03),floor*3.5),(w,.06,.12),22)
                b('side_band',(sign*(w/2-.03),0,floor*3.5),(.06,d-.12,.12),22)
    for sign in (-1,1):
        b('entry_jamb',(sign*1.07,-d/2+.02,1.2),(.14,.04,2.4),23)
    b('entry_header',(0,-d/2+.02,2.5),(2.28,.04,.2),23)
    if kind=='utility':
        # Large service panel and hazard-colored facade blocks, clear of the entry.
        b('service_panel',(-w*.30,-d/2+.02,1.45),(2.6,.04,2.5),24)
        for z in (.5,.9,1.3,1.7,2.1,2.5):
            b('panel_slat',(-w*.30,-d/2+.002,z),(2.5,.004,.04),15)
    m.join(walls,'Walls')
    roof=[]
    roof.append(m.box('roof_slab',(0,0,h+.08),(w,d,.16),24))
    for sign in (-1,1):
        roof.append(m.box('parapet',(sign*(w/2-.12),0,h+.30),(.24,d,.44),22))
        roof.append(m.box('parapet',(0,sign*(d/2-.12),h+.30),(w-.48,.24,.44),22))
    roof.append(m.box('roof_access',(-w*.23,d*.20,h+.7),(1.7,2.1,1.25),color))
    for x in (w*.12,w*.30):
        roof.append(m.box('ventilation',(x,d*.20,h+.40),(.8,1.3,.65),11))
        roof.append(m.box('vent_cap',(x,d*.20,h+.76),(.95,1.45,.10),15))
    m.join(roof,'Roof')
    m.box('Floor',(0,0,-.1),(w-1,d-1,.2),25)

if __name__=='__main__':
    layout=json.loads((m.ROOT/'art_source/building_layout.json').read_text())
    specs=[dict(id='building_apartment_a',kind='apartment',width=12,depth=11,height=14),
           dict(id='building_utility_a',kind='utility',width=15,depth=13,height=7),
           dict(id='building_office_a',kind='office',width=12,depth=12,height=17.5)]+layout
    for spec in specs:
        building(spec['kind'],spec['width'],spec['depth'],spec['height'])
        m.save_asset(spec['id'],'buildings')
    (m.ROOT/'art_source/city_buildings_manifest.json').write_text(json.dumps(m.catalog,indent=2))
    catalog='extends RefCounted\n## Exact-size exports; rebuild after changing the map.\nconst ENTRIES = {\n'
    for spec in layout:
        catalog+=f'\t{spec["floor_id"]}: {{"size": Vector3({spec["width"]}, {spec["height"]}, {spec["depth"]}), "model": preload("res://assets/models/buildings/{spec["id"]}.glb")}},\n'
    catalog+='}\n'
    (m.ROOT/'scripts/city_building_catalog.gd').write_text(catalog,encoding='utf-8')
    print('CITY_BUILDINGS_COMPLETE',len(specs))
