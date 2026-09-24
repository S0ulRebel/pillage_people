"""Additive multi-deck contract and geometric blockouts. Does not modify v1.
Run with Python 3; standard library only. All coordinates metres, X right Y up Z aft.
"""
import importlib.util
import json
import math
from pathlib import Path
import zipfile

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('base',ROOT/'build_handoff.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
OUT=ROOT/'multi-deck-v2'
for folder in ['meshes','assemblies','prompts','drawings']:(OUT/folder).mkdir(parents=True,exist_ok=True)
PITCH=2.6
THICK=.18

def prism(poly,y0,y1):
    """Closed extrusion of an XZ polygon; face winding uses outward normals."""
    area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
    if area<0:poly=list(reversed(poly))
    n=len(poly);v=[(x,y,z) for y in [y0,y1] for x,z in poly]
    f=[list(range(n)),list(range(2*n-1,n-1,-1))]
    for i in range(n):
        j=(i+1)%n;f.append([i,i+n,j+n,j])
    return v,f

def box(x0,x1,y0,y1,z0,z1):return prism([(x0,z0),(x1,z0),(x1,z1),(x0,z1)],y0,y1)

def shift(mesh,offset):
    v,f=mesh;return [(x+offset[0],y+offset[1],z+offset[2]) for x,y,z in v],f

def wall(host,height,ports=False):
    stations=base.hull_rings(host);pieces=[]
    for side in [-1,1]:
        if ports:
            x0,x1=sorted([side*2.8,side*3])
            # One true opening per side per 2 m bay. Nothing across the opening.
            pieces += [box(x0,x1,0,.8,0,2),box(x0,x1,1.6,height,0,2),
                       box(x0,x1,.8,1.6,0,.5),box(x0,x1,.8,1.6,1.5,2)]
        else:
            for (a,sa),(b,sb) in zip(stations,stations[1:]):
                pieces.append(prism([(side*2.8*sa,a),(side*3*sa,a),(side*3*sb,b),(side*2.8*sb,b)],0,height))
    if host!='H02_MID':
        z,s=stations[0] if host=='H01_BOW' else stations[-1]
        za,zb=(z,z+.08) if host=='H01_BOW' else (z-.08,z)
        pieces.append(box(-2.8*s,2.8*s,0,height,za,zb))
    return base.combine(pieces)

def floor(host):
    stations=base.hull_rings(host)
    if host=='H01_BOW':stations[0]=(.08,.074)
    elif host=='H03_STERN':stations[-1]=(1.92,.8128)
    return base.combine([prism([(-2.8*sa,a),(2.8*sa,a),(2.8*sb,b),(-2.8*sb,b)],-THICK,0)
                         for (a,sa),(b,sb) in zip(stations,stations[1:])])

meshes={};parts=[]
def add(id,mesh,role,notes):
    meshes[id]=mesh
    v,_=mesh
    parts.append(dict(id=id,role=role,bounds_min=[min(p[i] for p in v) for i in range(3)],
        bounds_max=[max(p[i] for p in v) for i in range(3)],origin='Fore station centre at current finished floor height',
        mesh=f'meshes/{id}.obj',notes=notes))

for suffix,host in [('BOW','H01_BOW'),('MID','H02_MID'),('STERN','H03_STERN')]:
    add('U_'+suffix,wall(host,PITCH),'stackable upper hull wall',
        f'Footprint follows {host}. Open top and bottom. At lengthwise interfaces, side-wall strips only; no transverse bulkhead. Bottom Y=0, top Y=2.6. Locks first/last 0.10 m of each mating surface.')
    add('F_'+suffix,floor(host),'floor insert',
        'Top Y=0, underside Y=-0.18. Place at chosen floor datum, not wall base origin. Same XZ footprint as upper wall interior. Never duplicate an existing floor.')
    add('R_'+suffix,wall(host,.6),'topmost bulwark',
        'Place only on highest exposed deck. Do not retain it under another U wall. No ceiling or floor included.')
add('U_GUNPORT_MID',wall('H02_MID',PITCH,True),'upper gun-deck wall',
    'Replaces U_MID. Openings on both sides: Z=0.5..1.5, Y=0.8..1.6 ABOVE this level floor. Bottom and top wall strips are unchanged. Cannon barrel centre must be fitted to this opening; do not scale whole hull.')
add('F_STAIR_PORT',base.combine([box(-2.8,-2.05,-THICK,0,0,2),box(-.95,2.8,-THICK,0,0,2)]),'stair-opening floor',
    'Replaces F_MID. Through-slot X=-2.05..-0.95 over full 2 m length. Use this tile followed by its END variant for a 1.10x3.25 m shaft. No framing intrudes into clear opening.')
add('F_STAIR_STARBOARD',base.combine([box(-2.8,.95,-THICK,0,0,2),box(2.05,2.8,-THICK,0,0,2)]),'stair-opening floor',
    'Mirrored port slot X=0.95..2.05. Follow with the matching END tile. Do not rotate port mesh silently or change its origin.')
stairs=[]
for side,lo,hi in [('PORT',-2.05,-.95),('STARBOARD',.95,2.05)]:
    add('F_STAIR_'+side+'_END',base.combine([meshes['F_STAIR_'+side],box(lo,hi,-THICK,0,1.25,2)]),'stair exit floor',
        'Use after the matching opening tile. Slot ends at local Z=1.25; the final 0.75 m is solid landing. Together the two tiles form a 1.10 x 3.25 m shaft, exactly matching the stair run.')
for i in range(13):
    # Individual closed treads; separate stringers can be added away from walking clearance.
    top=(i+1)*.2
    stairs.append(box(-.5,.5,top-.08,top,i*.25,(i+1)*.25))
add('A_STAIRS_260',base.combine(stairs),'inter-floor stairs',
    '13 rises of 0.20 m, 13 treads of 0.25 m; 3.25 m run, top Y=2.60. Width1.0. Upper slot is 1.10x3.25 m. Preserve headroom and add side stringers/handrails in modeling without closing shaft. Require 1 m approach/exit landing.')

wall_profiles={}
for host in ['H01_BOW','H02_MID','H03_STERN']:
    wall_profiles[host]=base.hull_rings(host)
contract=dict(version='2.0-additive',base_contract='../contract.json',units='metres',axes=base.contract['axes'],
    pitch=PITCH,floor_thickness=THICK,clear_room_height=PITCH-THICK,
    floor_datums=[2.6,5.2,7.8],
    rule='The v1 lower hull is used ONCE. Replace all v1 D floors in multi-deck assemblies with F floors at Y=2.6. Add U walls at a floor datum, then F floor at datum+2.6. Highest floor receives R bulwarks, never another U by default.',
    interfaces=dict(UPPER_WALL_6=dict(side_strips_x=[[-3,-2.8],[2.8,3]],bay_length=2,height=2.6),
        VERTICAL_STACK=dict(footprints_by_host=wall_profiles,outer_half_width=3,inner_half_width=2.8,skin_thickness_at_full_beam=.2),
        FLOOR=dict(top=0,bottom=-.18),STAIR=dict(clear_width=1.1,shaft_length=3.25,rise=2.6)),
    sockets='Upper wall: BOTTOM at [0,0,0], normal -Y; TOP at [0,2.6,0], normal +Y. Mate identical footprint IDs only. Longitudinal FORE at Z=0 and AFT at Z=length have side strips matching adjacent parts; up is +Y. Floor origins coincide with level datum. Rails BOTTOM shares corresponding footprint.',
    cabin_rule='Cabins mount by their floor origin on the highest deck datum. Cabin roof rise stays 2.58 m: use v1 A01 stairs for cabin roofs, v2 A_STAIRS_260 only between full ship levels. Galleries need opening walls and bracket clearance; not instantiated in these examples.',
    lower_hold='Below Y=2.6 is structural hold volume with curved bilge, not an extra flat walkable floor. Add a separately designed hold walkway and ladder if gameplay requires access.',
    allowed_examples='Two or three walkable decks only in this blockout; no seaworthiness, mass, stability or buoyancy claim.',parts=parts)

assemblies=[]
for levels in [2,3]:
    placement=[]
    stations=[('BOW','H01_BOW',0)]+[('MID','H02_MID',4+2*i) for i in range(4)]+[('STERN','H03_STERN',12)]
    for suffix,host,z in stations:placement.append(dict(part=host,position=[0,0,z],source='v1'))
    for level in range(levels):
        y=round(2.6*(level+1),6)
        for suffix,host,z in stations:
            floor_id='F_'+suffix
            if level==1 and z in [4,6]:floor_id='F_STAIR_PORT'+('_END' if z==6 else '')
            if level==2 and z in [8,10]:floor_id='F_STAIR_STARBOARD'+('_END' if z==10 else '')
            placement.append(dict(part=floor_id,position=[0,y,z],source='v2'))
            wall_id=('U_' if level<levels-1 else 'R_')+suffix
            if level==0 and suffix=='MID':wall_id='U_GUNPORT_MID'
            placement.append(dict(part=wall_id,position=[0,y,z],source='v2'))
        if level>0:
            placement.append(dict(part='A_STAIRS_260',position=[-1.5 if level==1 else 1.5,round(y-2.6,6),4 if level==1 else 8],source='v2'))
    assemblies.append(dict(id=f'{levels}_DECK_SHIP',walkable_decks=levels,length=14,beam=6,placements=placement))
contract['assemblies']=assemblies
(OUT/'contract.json').write_text(json.dumps(contract,indent=2),encoding='utf8')
for id,mesh in meshes.items():
    base.obj(OUT/'meshes'/f'{id}.obj',*mesh)
    (OUT/'drawings'/f'{id}.svg').write_text(base.sheet(id,*mesh),encoding='utf8')
for p in parts:
    (OUT/'prompts'/f"{p['id']}.md").write_text('# Model '+p['id']+'\n\nRead ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.\n\n'+json.dumps(p,indent=2)+'\n\nDeliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.\n',encoding='utf8')

checks=[]
for assembly in assemblies:
    instances=[]
    for p in assembly['placements']:
        mesh=base.meshes[p['part']] if p['source']=='v1' else meshes[p['part']]
        instances.append(shift(mesh,p['position']))
    base.obj(OUT/'assemblies'/f"{assembly['id']}.obj",*base.combine(instances))
    # Socket surfaces: upper wall top and next wall bottom match at every footprint station.
    for suffix,host,z in stations:
        profiles=base.hull_rings(host)
        lower_top={(round(x*s,6),2.6,round(zz+z,6)) for zz,s in profiles for x in [-3,-2.8,2.8,3]}
        upper_bottom={(round(x*s,6),2.6,round(zz+z,6)) for zz,s in profiles for x in [-3,-2.8,2.8,3]}
        assert lower_top==upper_bottom
    for p in assembly['placements']:
        if p['part']!='A_STAIRS_260':continue
        x,y,z=p['position'];target=round(y+2.6,6)
        wanted='F_STAIR_PORT' if x<0 else 'F_STAIR_STARBOARD'
        slots=[q for q in assembly['placements'] if q['part'] in [wanted,wanted+'_END'] and abs(q['position'][1]-target)<1e-6 and q['position'][2] in [z,z+2]]
        assert len(slots)==2
        assert 1.0<1.1 and 3.25==3.25
        checks.append(dict(assembly=assembly['id'],stair_origin=p['position'],exit_height=target,opening_tiles=2,side_clearance=.05))
    assert not any(p['part'].startswith('D0') for p in assembly['placements'])

# Side elevation diagram from declared stations/levels, not an AI rendering.
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760"><rect width="1200" height="760" fill="#f5f1e8"/><g font-family="sans-serif" fill="#26343c"><text x="40" y="40" font-size="26">Multi-deck family U6 — three walkable levels</text>']
for level in range(3):
    y=round((level+1)*2.6,2);yy=640-y*60
    svg.append(f'<rect x="100" y="{yy}" width="840" height="11" fill="#ad793e"/><text x="960" y="{yy+5}" font-size="18">Floor {level+1}: {y:.2f} m</text>')
    if level<2:
        for z in [0,4,6,8,10,12,14]:svg.append(f'<path d="M{100+z*60},{yy} v-156" stroke="#33596b" stroke-width="2"/>')
        svg.append(f'<text x="370" y="{yy-72}" font-size="18">2.42 m clear height</text>')
svg.append('<path d="M100,484 L160,620 L820,620 L940,484" stroke="#33596b" stroke-width="4" fill="none"/><text x="330" y="597" font-size="18">Curved lower hull / hold — used once</text>')
for x,z,y in [(-1.5,4,2.6),(1.5,8,5.2)]:
    x1=100+z*60;y1=640-y*60
    svg.append(f'<path d="M{x1},{y1} l195,-156" stroke="#b34a35" stroke-width="5"/><text x="{x1}" y="{y1-10}" font-size="14">Stairs, {"port" if x<0 else "starboard"}</text>')
svg.append('<text x="40" y="700" font-size="17">Side schematic: bow left, stern right. Brown = floors; blue = shell; red = stairs.</text><text x="40" y="730" font-size="15">Not a styled model. Dimensions and openings are defined in contract.json.</text></g></svg>')
(OUT/'drawings'/'levels.svg').write_text(''.join(svg),encoding='utf8')
(OUT/'validation.json').write_text(json.dumps(dict(stair_connections=checks,clear_height=2.42,parts=len(parts),assemblies=2,
    limits='Blockout and declared opening checks only. No game collision, styled export, structural stability or buoyancy validation.'),indent=2),encoding='utf8')
print(json.dumps(dict(parts=len(parts),assemblies=2,stair_connections=len(checks))))
