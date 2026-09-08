"""Blender 4.5: street props in the shared low-poly palette, editable .blend + GLB."""
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_models as m

def bench():
    m.clean();m.palette()
    for x in (-.85,.85):
        m.box('leg',(x,0,.24),(.12,.62,.48),11)
        m.box('back_support',(x,.22,.64),(.09,.09,.82),11)
    for y in (-.23,0,.23):m.box('seat_slat',(0,y,.49),(2.2,.16,.08),7)
    for z in (.73,.97):m.box('back_slat',(0,.27,z),(2.2,.09,.18),7)

def bin():
    m.clean();m.palette()
    m.box('body',(0,0,.40),(.52,.52,.80),19,.035)
    m.box('rim',(0,0,.84),(.58,.58,.08),11)
    m.box('lid',(0,.16,.92),(.58,.23,.12),11)
    m.box('opening',(0,-.04,.881),(.36,.20,.015),20)

def lamp():
    m.clean();m.palette()
    m.box('base',(0,0,.12),(.40,.40,.24),11,.025)
    m.limb('post',(0,0,.20),(0,0,4.8),.07,.055,22,8)
    m.box('arm',(0,-.55,4.78),(.10,1.2,.10),22)
    m.box('lamp',(0,-1.0,4.71),(.38,.75,.16),11,.035)
    m.box('diffuser',(0,-1.0,4.619),(.29,.63,.025),23)

def planter():
    m.clean();m.palette()
    m.box('pot',(0,0,.28),(1.3,1.3,.56),15,.04)
    m.box('soil',(0,0,.58),(1.16,1.16,.035),26)
    m.rings('shrub',[(.59,.53,.53,0),(.96,.62,.55,0),(1.24,.38,.37,0),(1.37,.1,.1,0)],8,8)

def shelter():
    m.clean();m.palette()
    for x in (-1.8,1.8):
        for y in (-.48,.48):m.box('post',(x,y,1.2),(.08,.08,2.4),22)
    m.box('roof',(0,0,2.44),(4,1.4,.16),11,.04)
    m.box('back',(0,.51,1.3),(3.6,.06,1.7),16)
    for x in (-1.0,1.0):m.box('bench_leg',(x,.20,.25),(.1,.35,.5),11)
    m.box('bench',(0,.20,.53),(2.9,.50,.10),7)
    m.box('route_board',(1.29,.46,1.45),(.68,.025,.9),23)
    for z in (1.15,1.35,1.55,1.75):m.box('route_line',(1.29,.438,z),(.45,.01,.035),10)

def stop_sign():
    m.clean();m.palette()
    m.limb('post',(0,0,0),(0,0,2.5),.045,.045,22,8)
    m.box('sign',(0,0,2.25),(.62,.07,.75),10,.02)
    m.box('bus_icon',(0,-.041,2.26),(.40,.012,.27),23)
    for x in (-.12,.12):m.box('wheel_icon',(x,-.046,2.08),(.08,.008,.07),23)

def car(hatch=False):
    m.clean();m.palette();coat=18 if hatch else 10
    m.box('lower',(0,0,.59),(1.78,4.1,.58),coat,.12)
    m.box('hood',(0,-1.30,.98),(1.72,1.18,.24),coat,.065)
    m.box('cabin',(0,.18,1.24),(1.57,2.22 if hatch else 1.92,.70),coat,.15)
    m.box('roof',(0,.25,1.61),(1.32,1.68 if hatch else 1.40,.08),coat,.025)
    m.box('windshield',(0,-.91 if hatch else -.76,1.32),(1.30,.045,.45),20)
    m.box('rear_window',(0,1.30 if hatch else 1.15,1.31),(1.28,.04,.40),16)
    for sign in (-1,1):
        for y in (-.27,.65):
            m.box('side_window',(sign*.793,y,1.33),(.025,.70,.40),16)
            m.box('handle',(sign*.899,y+.12,.97),(.025,.18,.035),22)
        for y in (-1.25,1.25):
            m.limb('wheel',(sign*.75,y,.34),(sign*.94,y,.34),.34,.34,2,12)
            m.limb('hub',(sign*.942,y,.34),(sign*.95,y,.34),.16,.16,22,8)
        m.box('headlight',(sign*.57,-2.051,.67),(.39,.025,.18),23)
        m.box('taillight',(sign*.58,2.051,.68),(.36,.025,.16),18)
    for sign in (-1,1):m.box('bumper',(0,sign*2.05,.41),(1.6,.10,.11),11)

if __name__=='__main__':
    for name,build in [('street_bench',bench),('street_bin',bin),('street_lamp',lamp),('street_planter',planter),('bus_shelter',shelter),('bus_stop_sign',stop_sign),('parked_sedan',lambda:car(False)),('parked_hatchback',lambda:car(True))]:
        build();m.save_asset(name,'street',mass=True)
    (m.ROOT/'art_source/street_props_manifest.json').write_text(json.dumps(m.catalog,indent=2))
    print('STREET_PROPS_COMPLETE',len(m.catalog))
