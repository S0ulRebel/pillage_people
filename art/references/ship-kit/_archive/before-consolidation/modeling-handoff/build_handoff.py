"""Generate the v1 modeling contract and exact hull interface reference assets.
Python standard library only. Re-run from any directory; writes beside this script.
"""
from pathlib import Path
import json, math, html

ROOT = Path(__file__).resolve().parent
OUTER = [(-3,2.6),(-3,2),(-2.8,1),(-2,.3),(0,0),(2,.3),(2.8,1),(3,2),(3,2.6)]
INNER = [(-2.8,2.6),(-2.8,2),(-2.6,1.12),(-1.92,.5),(0,.2),(1.92,.5),(2.6,1.12),(2.8,2),(2.8,2.6)]

def socket(name, family, position, normal, **kw):
    return dict(name=name, interface=family, position=position, outward_normal=normal,
                roll_reference=[0,0,1] if abs(normal[1])==1 else [0,1,0], **kw)

parts = []
def part(id, bounds, origin, sockets, instructions, **kw):
    p=dict(id=id, bounds_min=bounds[0], bounds_max=bounds[1], origin=origin,
           sockets=sockets, modeling_instructions=instructions, **kw)
    parts.append(p)
    return p

for id,length in [('H01_BOW',4),('H02_MID',2),('H03_STERN',2)]:
    sockets=[]
    if id!='H01_BOW': sockets.append(socket('FORE','HULL_U6',[0,0,0],[0,0,-1]))
    if id!='H03_STERN': sockets.append(socket('AFT','HULL_U6',[0,0,length],[0,0,1]))
    part(id,([-3,0,0],[3,2.6,length]),'Fore station on keel baseline; bow nose for H01',sockets,
         'Preserve supplied OBJ vertices within 0.10 m of each HULL_U6 connection. Open U-shaped ends, never a wall across the interior. End caps close shell thickness ONLY. Bow nose / stern transom may close their non-connection ends.',
         starter_mesh=f'meshes/{id}.obj')
part('D01_DECK',([-2.8,1.82,0],[2.8,2,2]),'Same origin as host H02',
     [socket('FORE','DECK_56',[0,2,0],[0,0,-1]),socket('AFT','DECK_56',[0,2,2],[0,0,1])],
     'Deck top Y=2.0. Fits H02 only. Follow starter beveled underside to avoid intersecting curved hull. No railings on connection edges.',starter_mesh='meshes/D01_DECK.obj')
part('D02_HATCH_DECK',([-2.8,1.82,0],[2.8,2,2]),'Same origin as host H02',
     [socket('FORE','DECK_56',[0,2,0],[0,0,-1]),socket('AFT','DECK_56',[0,2,2],[0,0,1])],
     'Same deck as D01, replace rather than overlay. Clear opening X=-0.6..0.6, Z=0.4..1.6 through full thickness. Do not fill opening.',starter_mesh='meshes/D02_HATCH_DECK.obj')
for id in ['D03_BOW_DECK','D04_STERN_DECK']:
    host='H01_BOW' if id=='D03_BOW_DECK' else 'H03_STERN'
    length=4 if host=='H01_BOW' else 2
    part(id,([-2.8,1.82,0],[2.8,2,length]),'Same origin as host hull',[],
         f'Use shaped starter deck on {host} only, never stretch rectangular D01. Deck top Y=2.0; exact end meets adjacent deck.',starter_mesh=f'meshes/{id}.obj',host=host)

part('C01_CABIN_WALL',([-1,0,-.1],[1,2.4,.1]),'Bottom centre of 2 m wall',
     [socket('LEFT','WALL_EDGE',[-1,0,0],[-1,0,0]),socket('RIGHT','WALL_EDGE',[1,0,0],[1,0,0])],
     'Wall runs along X; exterior +Z. Final 0.10 m at each end is reserved for junction posts: wall geometry spans X=-0.9..0.9. Y=0 sits on deck. Opaque solid variant.')
part('C02_GALLERY_OPENING',([-1,0,-.1],[1,2.4,.1]),'Same as C01',
     [socket('GALLERY','GALLERY_18',[0,0,.1],[0,0,1])],
     'Replaces C01. Open rectangle X=-0.9..0.9, Y=0..2.2 through wall. Frame only above opening and in junction-post strips. No window, back wall, floor lip or door in passage.')
part('C03_DOOR_WALL',([-1,0,-.1],[1,2.4,.1]),'Same as C01',[],
     'Replaces C01. Doorway clear X=-0.45..0.45,Y=0..2.0. Door mesh separate, pivot at left jamb. Closed door may occlude doorway; open rotation must clear stairs.')
part('C04_JUNCTION_POST',([-.1,0,-.1],[.1,2.4,.1]),'Bottom centre',[],
     'One post at every 2 m wall endpoint; shared endpoints use one post only. Compatible with straight and right-angle walls. Walls butt against post; no duplicate corner end caps.')
part('C05_ROOF_TILE',([-1,2.4,0],[1,2.58,2]),'Cabin floor datum, tile fore centre',[],
     '2x2 m tile, four make 4x4 m cabin roof. Walkable top Y=2.58. No railing across adjacent tile edges. Exterior fascia a separate decoration, never resize tile.')
for id in ['G01_REAR_BAY','G02_PORT_BAY','G03_STARBOARD_BAY']:
    part(id,([-1,-.3,0],[1,2.4,.8]),'Floor centre at inboard mating plane',
         [socket('INBOARD','GALLERY_18',[0,0,0],[0,0,-1])],
         'Window bay projects along local +Z. Open attachment rectangle X=-0.9..0.9,Y=0..2.2. Floor TOP Y=0; roof aligns to cabin Y=2.4. Windowed exterior at +Z. Mount only into C02; no solid wall behind. Side variants may add mirrored trim strictly inside bounds. Local topology is shared; placement rotation selects ship side.')
part('A01_STAIRS',([-.5,0,0],[.5,2.58,3.3]),'Bottom landing edge centre',
     [socket('LOW','WALK_10',[0,0,0],[0,0,-1]),socket('HIGH','WALK_10',[0,2.58,3.3],[0,0,1])],
     '12 equal rises of 0.215 m over 3.3 m run; 0.275 m tread. Reaches C05 roof. Reserve 1x1 m clear landings at both ends and 2 m headroom. Not for arbitrary deck heights.')
part('A02_LADDER',([-.35,0,-.15],[.35,2.58,.15]),'Bottom centre',[],
     'Fixed roof-height ladder, 0.7 m wide. Top Y=2.58. Needs separate clear 0.8x0.8 m roof hatch and side access; do not run through a solid roof tile. Place against exterior wall, away from projecting galleries.')
part('M01_LOWER_MAST',([-.25,0,-.25],[.25,5.5,.25]),'Deck centre',
     [socket('TOP','MAST_036',[0,5.5,0],[0,1,0])],
     'Solid round wooden spar: radius 0.25 at deck tapering to 0.18 at Y=5.5. Last 0.15 m stays exact circular radius 0.18. Mount on deck replacing hatch tile if necessary; collision is not decorative rope.')
part('M02_TOPMAST',([-.18,0,-.18],[.18,3,.18]),'Bottom centre',
     [socket('BOTTOM','MAST_036',[0,0,0],[0,-1,0])],
     'Solid spar radius 0.18 at foot tapering to 0.08 at top. First 0.15 m preserves radius 0.18. Mate directly to M01 TOP at Y=5.5; cosmetic collar may cover joint.')
part('M03_LOOKOUT',([-1.1,-.18,-1.1],[1.1,1.1,1.1]),'Floor top centre',[],
     'Floor thickness .18, central circular through-hole radius .185; mounts around M01 mast neck at local Y=5.5. Separate access opening X=.3..1.0,Z=-.4.. .4 through floor. No geometry in mast hole. Rails height1.1, offset hatch clear. This is a wrap attachment, not an end-to-end mast socket.')
part('F01_HELM',([-.55,0,-.45],[.55,1.5,.45]),'Deck contact centre',[],
     'Decorative deck attachment; reserve X +/-0.8 and Z +/-1.1 for player access. No claim of physical steering linkage in v1.')
part('F02_CAPSTAN',([-1.4,0,-1.4],[1.4,1.1,1.4]),'Deck contact centre',[],
     'Bounds include extended bars. Reserve radius1.7 for operation. Keep outside stairs and mast clearances; do not shrink solely to fit a crowded deck.')
part('F03_BOWSPRIT',([-.15,-.15,0],[.15,.15,3]),'Base centre, spar extends local +Z',[],
     'Solid spar. Requires named bow mounting fixture; no HULL_U6 socket. V1 geometry envelope only; not included in validated hull assemblies.')
part('F04_RUDDER',([-.12,-1.5,0],[.12,.5,1]),'Hinge axis origin',[],
     'Rudder rotates about local Y; hangs aft. Requires matching stern hinge fixture; no HULL_U6 socket. V1 geometry envelope only; not included in validated hull assemblies.')

assemblies=[]
for name,n in [('SHORT_HULL',1),('TRADER_HULL',3),('LONG_HULL',5)]:
    placements=[dict(part='H01_BOW',position=[0,0,0]),dict(part='D03_BOW_DECK',position=[0,0,0])]
    for i in range(n):
        placements += [dict(part='H02_MID',position=[0,0,4+2*i]),dict(part='D01_DECK',position=[0,0,4+2*i])]
    placements += [dict(part='H03_STERN',position=[0,0,4+2*n]),dict(part='D04_STERN_DECK',position=[0,0,4+2*n])]
    assemblies.append(dict(id=name,length=6+2*n,placements=placements))

contract=dict(version='1.0',units='metres',axes=dict(X='starboard',Y='up',Z='aft'),
    handedness='right-handed',blender_conversion='(X,Y,Z) contract -> (X,-Z,Y) Blender, apply transforms before GLB export; imported GLB returns Y-up',
    tolerances=dict(socket_position_m=.001,normal_dot_max=-.999,locked_band_m=.1),
    source_priority=['contract.json interface coordinates','starter OBJ geometry','orthographic SVG outlines','approved PNGs for style only'],
    interfaces=dict(HULL_U6=dict(outer_xy=OUTER,inner_xy=INNER,deck_y=2,bulwark_y=2.6),
        DECK_56=dict(width=5.6,top_y=2,thickness=.18),WALL_EDGE=dict(height=2.4,thickness=.2),
        GALLERY_18=dict(clear_width=1.8,clear_height=2.2,floor_offset=0),MAST_036=dict(radius=.18)),
    mating_rule='Matching interface ID, coincident socket positions, opposite outward normals, same up vector, unit scale. Never mate parts merely because their bounding boxes touch.',
    exclusions=['No arbitrary-width hulls','No gunport variant until a separate gun-deck elevation is defined; prior art places ports below main deck','No verified rigging or sail system in v1','No validated bow/stern rudder or bowsprit fixtures yet'],
    parts=parts,assemblies=assemblies)

def hull_rings(id):
    if id=='H01_BOW': return [(0,.05),(1,.35),(2,.7),(4,1)]
    if id=='H03_STERN': return [(0,1),(1,.96),(2,.8)]
    return [(0,1),(2,1)]

def ring(scale,z):
    return [(x*scale,y,z) for x,y in OUTER+list(reversed(INNER))]

def hull_mesh(id):
    stations=hull_rings(id); verts=[]; faces=[]; count=18
    for z,s in stations: verts.extend(ring(s,z))
    for j in range(len(stations)-1):
        for i in range(count):
            k=(i+1)%count
            faces.append([j*count+i,j*count+k,(j+1)*count+k,(j+1)*count+i])
    # Triangular end faces cap only the solid skin, never its open interior.
    for j in [0,len(stations)-1]:
        for i in range(8):
            a=j*count+i;b=a+1;c=j*count+17-i;d=c-1
            fs=[[a,c,b],[b,c,d]]
            if j: fs=[list(reversed(f)) for f in fs]
            faces.extend(fs)
    # Close non-connection ends with a transom across interior, thin solid box form.
    if id!='H02_MID':
        z,s=stations[0] if id=='H01_BOW' else stations[-1]
        delta=.08 if id=='H01_BOW' else -.08
        base=len(verts)
        for zz in [z,z+delta]: verts.extend([(x*s,y,zz) for x,y in INNER])
        # Separate closed transom overlaps shell, permitted inside terminal end only.
        faces.extend([[base+i for i in range(9)],[base+i for i in range(17,8,-1)]])
        for i in range(9): faces.append([base+i,base+(i+1)%9,base+9+(i+1)%9,base+9+i])
    return verts,faces

def prism(z0,z1,w0,w1,xlo=None,xhi=None):
    # Width at underside is narrower along outer edge to fit hull slope.
    top0=(-w0,w0) if xlo is None else (xlo,xhi)
    top1=(-w1,w1) if xlo is None else (xlo,xhi)
    def bot(pair,w): return [v*(1-(.18*.2/.88)/2.8) if abs(abs(v)-w)<1e-7 else v for v in pair]
    b0=bot(top0,w0);b1=bot(top1,w1)
    v=[(top0[0],2,z0),(top0[1],2,z0),(top1[1],2,z1),(top1[0],2,z1),
       (b0[0],1.82,z0),(b0[1],1.82,z0),(b1[1],1.82,z1),(b1[0],1.82,z1)]
    f=[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]
    return v,f

def combine(meshes):
    vv=[];ff=[]
    for v,f in meshes:
        off=len(vv);vv.extend(v);ff.extend([[i+off for i in a] for a in f])
    return vv,ff

meshes={id:hull_mesh(id) for id in ['H01_BOW','H02_MID','H03_STERN']}
meshes['D01_DECK']=prism(0,2,2.8,2.8)
meshes['D02_HATCH_DECK']=combine([prism(0,.4,2.8,2.8),prism(1.6,2,2.8,2.8),prism(.4,1.6,2.8,2.8,-2.8,-.6),prism(.4,1.6,2.8,2.8,.6,2.8)])
for id,host in [('D03_BOW_DECK','H01_BOW'),('D04_STERN_DECK','H03_STERN')]:
    stations=hull_rings(host)
    # Deck terminates before solid terminal transom; avoids transom overlap.
    if host=='H01_BOW': stations[0]=(.08,.074)
    else: stations[-1]=(1.92,.8128)
    meshes[id]=combine([prism(a,b,2.8*sa,2.8*sb) for (a,sa),(b,sb) in zip(stations,stations[1:])])

def obj(path,v,f):
    path.write_text('# Contract axes: X starboard Y up Z aft; metres\n'+''.join('v %.6f %.6f %.6f\n'%p for p in v)+''.join('f '+' '.join(str(i+1) for i in face)+'\n' for face in f),encoding='utf8')

def sheet(id,v,f):
    # Exact projections of the starter vertices, never AI-inferred geometry.
    panels=[('TOP: X / Z',0,2),('SIDE: Z / Y',2,1),('END: X / Y',0,1)]
    body=[]
    for col,(label,a,b) in enumerate(panels):
        xs=[p[a] for p in v];ys=[p[b] for p in v]
        lo=min(xs);hi=max(xs);bot=min(ys);top=max(ys)
        scale=min(340/max(hi-lo,.1),340/max(top-bot,.1))
        def xy(p): return (col*400+30+(p[a]-lo)*scale,420-(p[b]-bot)*scale)
        edges=set()
        for face in f:
            for i,j in zip(face,face[1:]+face[:1]): edges.add(tuple(sorted((i,j))))
        body.append(f'<text x="{col*400+30}" y="65" fill="#28343c" stroke="none" font-family="sans-serif">{label}</text>')
        for i,j in edges:
            x,y=xy(v[i]);xx,yy=xy(v[j]);body.append(f'<path d="M{x:.2f},{y:.2f} L{xx:.2f},{yy:.2f}"/>')
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="490" viewBox="0 0 1200 490"><rect width="1200" height="490" fill="#f5f1e8"/><g font-family="sans-serif" font-size="16" fill="#28343c"><text x="30" y="28">'+id+' — exact starter geometry, metres; hidden edges also shown</text></g><g fill="none" stroke="#33596b" stroke-width="1">'+''.join(body)+'</g><text x="30" y="465" font-family="sans-serif" font-size="14">Use contract.json for dimensions. PNG concept art does not define mating geometry.</text></svg>'

def main():
    for d in ['meshes','drawings','prompts','assemblies']: (ROOT/d).mkdir(exist_ok=True)
    (ROOT/'contract.json').write_text(json.dumps(contract,indent=2),encoding='utf8')
    for id,(v,f) in meshes.items():
        obj(ROOT/'meshes'/f'{id}.obj',v,f)
        (ROOT/'drawings'/f'{id}.svg').write_text(sheet(id,v,f),encoding='utf8')
    for assembly in assemblies:
        ms=[]
        for item in assembly['placements']:
            v,f=meshes[item['part']];off=item['position']
            ms.append(([(p[0]+off[0],p[1]+off[1],p[2]+off[2]) for p in v],f))
        obj(ROOT/'assemblies'/f"{assembly['id']}.obj",*combine(ms))
    for p in parts:
        text=f"# Model {p['id']}\n\nRead ../contract.json and ../../01-hull-modules-v1.png (style only).\n\n"+json.dumps(p,indent=2)+"\n\nDeliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.\n"
        (ROOT/'prompts'/f"{p['id']}.md").write_text(text,encoding='utf8')
    cards=''.join(f'<section><h2>{id}</h2><img src="drawings/{id}.svg"><a href="meshes/{id}.obj">Starter OBJ</a> · <a href="prompts/{id}.md">Agent brief</a></section>' for id in meshes)
    (ROOT/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Ship kit modeling handoff</title><style>body{font:16px system-ui;max-width:1200px;margin:40px auto;background:#f5f1e8;color:#26343c}img{width:100%}section{margin:40px 0;border-top:1px solid #aaa}a{color:#175f7b}</style><h1>Ship kit · Interface family U6</h1><p>Exact geometric references for AI-assisted modeling. 6 m beam · 2 m middle bays · deck Y=2 m. These are construction references, not final styled models.</p><p><a href="AGENT_START_HERE.md">Start here</a> · <a href="contract.json">Machine-readable contract</a></p>'+cards,encoding='utf8')
    # Verify socket rings numerically across all assembly joints.
    checks=[]
    for a in assemblies:
        hulls=[p for p in a['placements'] if p['part'].startswith('H')]
        for left,right in zip(hulls,hulls[1:]):
            la=hull_rings(left['part'])[-1]; rb=hull_rings(right['part'])[0]
            l=ring(la[1],la[0]+left['position'][2]);r=ring(rb[1],rb[0]+right['position'][2])
            error=max(math.dist(x,y) for x,y in zip(l,r));assert error<1e-9
            checks.append(dict(assembly=a['id'],joint=[left['part'],right['part']],max_vertex_gap_m=error))
    assert len({p['id'] for p in parts})==len(parts)
    for p in parts:
        assert all(a<b for a,b in zip(p['bounds_min'],p['bounds_max']))
    for id,(v,f) in meshes.items():
        assert all(0<=i<len(v) for face in f for i in face)
    result=dict(hull_seam_checks=checks,parts=len(parts),starter_meshes=len(meshes),assemblies=len(assemblies),
        limits='Only hull mating rings checked numerically. Cabin/accessory briefs are dimensional contracts, not generated or collision-tested meshes. No final model validation or render QA implied.')
    (ROOT/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print(json.dumps(dict(parts=len(parts),meshes=len(meshes),hull_joints_checked=len(checks),max_gap=0)))

if __name__=='__main__': main()
