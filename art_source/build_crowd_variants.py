"""Two additional editable civilian silhouettes and reusable hand props."""
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import build_models as m
import bpy

for name, height, color, width in [('civilian_normal_b',1.78,18,.94),('civilian_normal_c',1.65,19,1.06)]:
    m.character('civilian_normal_a',height,color,width)
    if name.endswith('_b'):
        m.box('cap',(0,0,height-.025),(.31,.28,.08),4,.02)
        m.box('cap_brim',(0,-.18,height-.055),(.29,.17,.025),4,.006)
        m.box('jacket_zip',(0,-.17,1.10),(.025,.02,.34),23)
    else:
        m.box('hair',(0,.09,1.44),(.30,.17,.30),5,.025)
        m.box('backpack',(0,.21,1.10),(.31,.18,.37),7,.035)
    m.save_asset(name,'characters',mass=True)

for name in ['prop_phone','prop_camera','prop_pistol']:
    m.clean();m.palette()
    if name=='prop_phone':
        m.box('phone',(0,0,.055),(.075,.015,.15),2,.004)
        m.box('screen',(0,-.009,.055),(.062,.003,.122),9)
    elif name=='prop_camera':
        m.box('camera',(-.05,0,.045),(.18,.07,.115),2,.008)
        m.limb('lens',(-.05,-.035,.045),(-.05,-.105,.045),.045,.043,12,8)
    else:
        m.box('grip',(0,0,.015),(.045,.065,.095),2,.005)
        m.box('slide',(0,-.055,.072),(.052,.20,.05),11,.005)
    m.save_asset(name,'props',mass=True)
(m.ROOT/'art_source'/'crowd_variants_manifest.json').write_text(json.dumps(m.catalog,indent=2),encoding='utf8')
