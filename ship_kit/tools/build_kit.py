"""Build one self-contained modular ship family. No imports of older handoffs.
Python stdlib only. Axes X starboard, Y up, Z aft; metres.
"""
from pathlib import Path
import json, math, struct
from collections import defaultdict, deque

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'canonical'
for folder in ['meshes','assemblies','briefs']:(OUT/folder).mkdir(parents=True,exist_ok=True)
PITCH=2.6
FLOOR=.18

def area(p):return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(p,p[1:]+p[:1]))/2
def close(a,b):return math.dist(a,b)<1e-8
def inset_open_chain(chain,t=.2):
    # Inner parallel edges; open attachment endpoints stay exactly on Z=4.
    lines=[]
    for a,b in zip(chain,chain[1:]):
        dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz)
        n=(-dz/length,dx/length)
        lines.append(((a[0]+t*n[0],a[1]+t*n[1]),(dx,dz)))
    result=[]
    for i in range(len(chain)):
        if i in [0,len(chain)-1]:
            p,v=lines[0 if i==0 else -1];k=(4-p[1])/v[1]
            result.append((p[0]+k*v[0],4.0))
        else:
            a,u=lines[i-1];b,v=lines[i]
            den=u[0]*v[1]-u[1]*v[0]
            k=((b[0]-a[0])*v[1]-(b[1]-a[1])*v[0])/den
            result.append((a[0]+k*u[0],a[1]+k*u[1]))
    # Rear mating strip must be exactly 0.20 m wide in X.
    result[0]=(-2.8,4);result[-1]=(2.8,4)
    return [(round(x,9),round(z,9)) for x,z in result]

BOW=[(-3,4),(-2.2,2),(-1.2,1),(0,0),(1.2,1),(2.2,2),(3,4)]
BOW_IN=inset_open_chain(BOW)
STERN=[(round(3*math.cos(i*math.pi/16),9),round(2*math.sin(i*math.pi/16),9)) for i in range(17)]
STERN_IN=[(round(2.8*math.cos(i*math.pi/16),9),round(1.8*math.sin(i*math.pi/16),9)) for i in range(17)]
CHAINS={'BOW':[(BOW,BOW_IN)],'CENTRE':[([(-3,2),(-3,0)],[(-2.8,2),(-2.8,0)]), ([(3,0),(3,2)],[(2.8,0),(2.8,2)])],'STERN':[(STERN,STERN_IN)]}
PLANS={'BOW':BOW_IN,'CENTRE':[(-2.8,0),(2.8,0),(2.8,2),(-2.8,2)],'STERN':STERN_IN}
OUTER_PLANS={'BOW':BOW,'CENTRE':[(-3,0),(3,0),(3,2),(-3,2)],'STERN':STERN}

def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def dot(a,b):return sum(x*y for x,y in zip(a,b))

class Mesh:
    def __init__(self):self.v=[];self.f=[];self.mat=[]
    def add(self,other,offset=(0,0,0)):
        n=len(self.v);self.v += [tuple(x+y for x,y in zip(p,offset)) for p in other.v]
        self.f += [tuple(i+n for i in f) for f in other.f];self.mat+=other.mat
        return self
    def solid(self,verts,faces,material='wood'):
        # Orient adjacent triangle faces consistently, then outwards per closed solid.
        tris=[]
        for f in faces:
            for j in range(1,len(f)-1):
                t=(f[0],f[j],f[j+1]);n=cross(sub(verts[t[1]],verts[t[0]]),sub(verts[t[2]],verts[t[0]]))
                if dot(n,n)>1e-18:tris.append(t)
        edges=defaultdict(list)
        for k,f in enumerate(tris):
            for a,b in zip(f,f[1:]+f[:1]):edges[tuple(sorted((a,b)))].append((k,a<b))
        assert all(len(a)==2 for a in edges.values()),'solid has an open/nonmanifold edge'
        adj=defaultdict(list)
        for pair in edges.values():
            (a,ad),(b,bd)=pair;adj[a].append((b,ad==bd));adj[b].append((a,ad==bd))
        flip={0:False};q=deque([0])
        while q:
            a=q.popleft()
            for b,different in adj[a]:
                wanted=flip[a]^different
                if b in flip:assert flip[b]==wanted
                else:flip[b]=wanted;q.append(b)
        assert len(flip)==len(tris),'primitive must be one connected solid'
        tris=[tuple(reversed(f)) if flip[i] else f for i,f in enumerate(tris)]
        volume=sum(dot(verts[a],cross(verts[b],verts[c]))/6 for a,b,c in tris)
        assert abs(volume)>1e-9
        if volume<0:tris=[tuple(reversed(f)) for f in tris]
        n=len(self.v);self.v+=verts;self.f += [tuple(i+n for i in f) for f in tris];self.mat += [material]*len(tris)
        return self

def loft(bottom,top,material='wood'):
    assert len(bottom)==len(top);n=len(bottom)
    faces=[list(range(n-1,-1,-1)),list(range(n,2*n))]
    faces += [[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)]
    return Mesh().solid(bottom+top,faces,material)
def prism(poly,y0,y1,material='wood'):
    # All input polygons convex. Shared panel boundaries are separate closed solids.
    return loft([(x,y0,z) for x,z in poly],[(x,y1,z) for x,z in poly],material)
def box(x0,x1,y0,y1,z0,z1,mat='wood'):return prism([(x0,z0),(x1,z0),(x1,z1),(x0,z1)],y0,y1,mat)
def scaled(p,f,section):
    x,z=p
    if section=='BOW':return x*f,4+(z-4)*f
    if section=='STERN':return x*f,z*f
    return x*f,z

def wall(section,height):
    m=Mesh()
    levels=[0,.8,1.6,2.6] if height==2.6 else [0,height]
    for outer,inner in CHAINS[section]:
        for i in range(len(outer)-1):
            for y0,y1 in zip(levels,levels[1:]):m.add(prism([outer[i],outer[i+1],inner[i+1],inner[i]],y0,y1))
    return m

def bottom(section):
    m=Mesh();olevels=[(0,.2),(.3,.62),(1,.9),(2.42,1),(2.6,1)];ilevels=[(.2,.2),(.5,.6),(1.12,.9),(2.42,1),(2.6,1)]
    for outer,inner in CHAINS[section]:
        for i in range(len(outer)-1):
            a=[];b=[]
            for j,target in [(i,a),(i+1,b)]:
                for y,f in olevels:
                    x,z=scaled(outer[j],f,section);target.append((x,y,z))
                for y,f in reversed(ilevels):
                    x,z=scaled(inner[j],f,section);target.append((x,y,z))
            # This cross section is concave: triangulate its end caps explicitly.
            n=len(a);faces=[]
            for j in range(4):faces += [[j,j+1,8-j,9-j],[n+j,n+9-j,n+8-j,n+j+1]]
            for j in range(n):faces.append([j,(j+1)%n,(j+1)%n+n,j+n])
            m.solid(a+b,faces)
    # Lower closure follows the same fore/aft profile as every shell column.
    op=[(*scaled(p,.2,section),) for p in OUTER_PLANS[section]]
    ip=[(*scaled(p,.2,section),) for p in PLANS[section]]
    m.add(loft([(x,0,z) for x,z in op],[(x,.2,z) for x,z in ip]))
    return m

def gunwall():
    m=Mesh()
    for a,b in [(-3,-2.8),(2.8,3)]:
        for y0,y1,z0,z1 in [(0,.8,0,2),(1.6,2.6,0,2),(.8,1.6,0,.5),(.8,1.6,1.5,2)]:m.add(box(a,b,y0,y1,z0,z1))
    return m

meshes={};parts=[]
def layer(mesh,axis,value):return sorted(set(p for p in mesh.v if abs(p[axis]-value)<1e-7))
def socket(name,family,axis,value,normal,mesh):
    p=[0.,0.,0.];p[axis]=value
    return dict(name=name,interface=family,position=p,normal=normal,points=layer(mesh,axis,value))
def add(id,tier,section,m,notes):
    meshes[id]=m;length=4 if section=='BOW' else 2
    p=dict(id=id,tier=tier,section=section,mesh=f'meshes/{id}.obj',glb=f'meshes/{id}.glb',origin='Local fore station at tier base / floor top; X=0 centreline',notes=notes,sockets=[],bounds_min=[min(v[i] for v in m.v) for i in range(3)],bounds_max=[max(v[i] for v in m.v) for i in range(3)])
    if tier in ['BOTTOM','MIDDLE','TOP']:
        h=2.6 if tier!='TOP' else .8
        p['inner_outline_xz']=PLANS[section]
        p['outer_outline_xz']=OUTER_PLANS[section]
        if section=='BOW':p['nose_solid_test_points']=[[.01,2.5 if tier=='BOTTOM' else h/2,.12],[-.01,2.5 if tier=='BOTTOM' else h/2,.12]]
        if tier!='BOTTOM':p['sockets'].append(socket('DOWN','STACK_'+section,1,0,[0,-1,0],m))
        if tier!='TOP':p['sockets'].append(socket('UP','STACK_'+section,1,h,[0,1,0],m))
        if section!='BOW':p['sockets'].append(socket('FORE','JOIN_'+tier,2,0,[0,0,-1],m))
        if section!='STERN':p['sockets'].append(socket('AFT','JOIN_'+tier,2,length,[0,0,1],m))
    if tier=='FLOOR':p['floor_outline_xz']=PLANS[section]
    parts.append(p)

for section in ['BOW','CENTRE','STERN']:
    add('BOTTOM_'+section,'BOTTOM',section,bottom(section),'Bilge and lower hull only. Place once at Y=0; upper connection Y=2.6. No raised posts.')
    if section!='CENTRE':add('MIDDLE_'+section,'MIDDLE',section,wall(section,2.6),'Uniform-height wall. Open at connection ends; bow nose/stern back closed. No floor or raised end feature.')
    add('TOP_'+section,'TOP',section,wall(section,.8),'Final low bulwark tier only. No elevated prow/stern. No stacking above this tier.')
    add('FLOOR_'+section,'FLOOR',section,prism(PLANS[section],-.18,0,'deck'),'Flat 0.18 m slab matching the shell inner outline; no columns, curb, wall or railing.')
add('MIDDLE_CENTRE_GUN','MIDDLE','CENTRE',gunwall(),'Default middle centre bay. One true opening per side at Z=.5..1.5,Y=.8..1.6 relative to floor. Closed sill and lintel. No gunport holes in the bottom bilge.')
add('MIDDLE_CENTRE','MIDDLE','CENTRE',wall('CENTRE',2.6),'Optional solid substitute for MIDDLE_CENTRE_GUN. Same sockets, no openings.')
for side,lo,hi in [('PORT',-2.05,-.95),('STARBOARD',.95,2.05)]:
    for end in [False,True]:
        m=Mesh().add(box(-2.8,lo,-.18,0,0,2,'deck')).add(box(hi,2.8,-.18,0,0,2,'deck'))
        if end:m.add(box(lo,hi,-.18,0,1.25,2,'deck'))
        add('STAIR_'+side+('_END' if end else '_START'),'ACCESS','CENTRE',m,'Replaces one FLOOR_CENTRE. START then END at consecutive bays: 1.1 x 3.25 m open shaft; final 0.75 m solid landing. Never overlay solid floor.')
m=Mesh()
for i in range(13):m.add(box(-.5,.5,(i+1)*.2-.08,(i+1)*.2,i*.25,(i+1)*.25,'deck'))
# Stringers support treads from below; do not change walking envelope.
for x0,x1 in [(-.5,-.42),(.42,.5)]:
    v=[(x,y,z) for x in [x0,x1] for z,y in [(0,0),(0,.12),(3.25,2.60),(3.25,2.42)]]
    m.solid(v,[[0,1,2,3],[7,6,5,4],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]])
add('STAIRS_260','ACCESS','CENTRE',m,'13 rises of .20 m, .25 m treads, 3.25 m run, 1 m width. Landing begins at exactly Z=3.25,Y=2.6. Reserve at least 1m approach and exit. Final rails/collision are modeling tasks.')

PARTS={p['id']:p for p in parts}
assemblies=[]
def assembly(id,bays,decks,explode=False):
    placements=[];joins=[];floorfits=[];rows={};floor_rows={};stair_checks=[]
    stations=[('BOW',0)]+[('CENTRE',4+2*i) for i in range(bays)]+[('STERN',4+2*bays)]
    def put(part,pos):placements.append(dict(part=part,position=pos));return len(placements)-1
    for row in range(decks+1):
        tier='BOTTOM' if row==0 else ('TOP' if row==decks else 'MIDDLE')
        y=row*2.6+(row*1.8 if explode else 0)
        rows[row]=[]
        for section,z in stations:
            name=tier+'_'+section+('_GUN' if tier=='MIDDLE' and section=='CENTRE' else '')
            rows[row].append(put(name,[0,round(y,6),z]))
        for a,b in zip(rows[row],rows[row][1:]):joins.append(dict(a=a,socket_a='AFT',b=b,socket_b='FORE'))
        if row>0:
            floor_rows[row]=[]
            for j,(section,z) in enumerate(stations):
                name='FLOOR_'+section
                if decks>1 and row==2 and z in [4,6]:name='STAIR_PORT_'+('START' if z==4 else 'END')
                if decks>2 and row==3 and z in [8,10]:name='STAIR_STARBOARD_'+('START' if z==8 else 'END')
                fi=put(name,[0,round(y-(.65 if explode else 0),6),z]);floor_rows[row].append(fi)
                if name.startswith('FLOOR_'):floorfits.append(dict(floor=fi,shell=rows[row][j]))
            if not explode:
                for a,b in zip(rows[row-1],rows[row]):joins.append(dict(a=a,socket_a='UP',b=b,socket_b='DOWN'))
    for row in range(2,decks+1):
        x=-1.5 if row==2 else 1.5;z=4 if row==2 else 8
        si=put('STAIRS_260',[x,round((row-1)*2.6+((row-1)*1.8 if explode else 0),6),z])
        if not explode:stair_checks.append(dict(stair=si,lower_y=(row-1)*2.6,upper_y=row*2.6,opening={'x':[x-.55,x+.55],'z':[z,z+3.25]},floor_indices=floor_rows[row]))
    combined=Mesh()
    for p in placements:combined.add(meshes[p['part']],p['position'])
    assemblies.append(dict(id=id,label=id.replace('_',' ').title(),mesh=f'assemblies/{id}.obj',glb=f'assemblies/{id}.glb',length=6+2*bays,bays=bays,decks=decks,exploded=explode,placements=placements,joins=joins,floorfits=floorfits,stair_checks=stair_checks))
    export(OUT/'assemblies'/id,combined)

COLORS={'wood':(.47,.24,.085,1),'deck':(.67,.39,.14,1),'iron':(.08,.09,.10,1)}
def export(path,m):
    lines=['# Metres; X starboard Y up Z aft; canonical ship family','mtllib ship.mtl']
    lines += ['v %.9f %.9f %.9f'%p for p in m.v]
    material=None
    for f,mat in zip(m.f,m.mat):
        if mat!=material:lines.append('usemtl '+mat);material=mat
        lines.append('f '+' '.join(str(i+1) for i in f))
    path.with_suffix('.obj').write_text('\n'.join(lines)+'\n')
    path.parent.joinpath('ship.mtl').write_text('\n'.join('newmtl '+key+'\nKd '+' '.join(str(x) for x in val[:3])+'\nKs 0 0 0\n' for key,val in COLORS.items()))
    buf=bytearray();views=[];accessors=[];primitives=[]
    def accessor(values,kind):
        off=len(buf);flat=[x for v in values for x in v];buf.extend(struct.pack('<'+'f'*len(flat),*flat));views.append(dict(buffer=0,byteOffset=off,byteLength=len(buf)-off,target=34962))
        a=dict(bufferView=len(views)-1,componentType=5126,count=len(values),type=kind)
        if kind=='VEC3':a.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
        accessors.append(a);return len(accessors)-1
    for mat in COLORS:
        positions=[];normals=[]
        for f,tag in zip(m.f,m.mat):
            if tag!=mat:continue
            pts=[m.v[i] for i in f];n=cross(sub(pts[1],pts[0]),sub(pts[2],pts[0]));length=math.sqrt(dot(n,n));n=tuple(x/length for x in n)
            positions.extend(pts);normals.extend([n]*3)
        if positions:primitives.append(dict(attributes={'POSITION':accessor(positions,'VEC3'),'NORMAL':accessor(normals,'VEC3')},material=list(COLORS).index(mat),mode=4))
    gltf=dict(asset=dict(version='2.0',generator='Canonical ship kit'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0)],meshes=[dict(primitives=primitives)],materials=[dict(name=k,pbrMetallicRoughness=dict(baseColorFactor=v,metallicFactor=0,roughnessFactor=.85)) for k,v in COLORS.items()],buffers=[dict(byteLength=len(buf))],bufferViews=views,accessors=accessors)
    js=json.dumps(gltf,separators=(',',':')).encode();js+=b' '*((-len(js))%4);buf+=b'\0'*((-len(buf))%4)
    path.with_suffix('.glb').write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(buf))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(buf),0x004e4942)+buf)

for p in parts:
    export(OUT/'meshes'/p['id'],meshes[p['id']])
    (OUT/'briefs'/(p['id']+'.md')).write_text('# '+p['id']+'\n\nImport ../'+p['glb']+' or OBJ at unit scale. Read ../contract.json.\n\n'+p['notes']+'\n\nPreserve locked interface vertices within 1 mm and 0.10 m join bands. Do not reconstruct dimensions from concept images. Broad warm planks, restrained grain, dark iron, faceted bevels and toon shading. No protruding corner posts on floors or tier boundaries. Deliver source model, GLB, named sockets and separate collision; check assembled fit after styling.\n')
assembly('SINGLE_DECK',2,1)
assembly('DOUBLE_DECK',4,2)
assembly('TRIPLE_DECK',6,3)
assembly('DOUBLE_DECK_EXPLODED',4,2,True)
contract=dict(name='Canonical modular pirate ship kit',units='metres',axes={'X':'starboard','Y':'up','Z':'aft'},blender_conversion='(X,Y,Z) -> (X,-Z,Y); export GLB Y-up',
    beam=6,centre_bay_length=2,bow_length=4,stern_length=2,bottom_height=2.6,middle_height=2.6,top_height=.8,floor_thickness=.18,clear_room_height=2.42,
    assembly_rule='BOTTOM once, zero/one/two MIDDLE tiers, TOP once. FLOOR modules at every shell tier base except BOTTOM. Same bow/centre/stern outline per column. More length adds entire centre columns through ALL tiers. Optional MIDDLE_CENTRE replaces MIDDLE_CENTRE_GUN without changing footprint.',
    scope='Construction geometry for styling/modeling. No finished game materials, rigging, collision or buoyancy simulation.',
    interfaces={'bow_outer_xz':BOW,'bow_inner_xz':BOW_IN,'stern_outer_xz':STERN,'stern_inner_xz':STERN_IN,'locked_join_band':.1,'tolerance_m':.001},
    stairs={'rise':2.6,'run':3.25,'width':1,'shaft_width':1.1,'shaft_length':3.25,'landing_length_min':1},
    accessories='Mast/lookout and helm/deck fitting references are retained separately, unchanged. Their existing briefs are reference envelopes, not included in structural fit claims. Place on highest floor; through-deck masts require matching apertures.',parts=parts,assemblies=assemblies)
(OUT/'contract.json').write_text(json.dumps(contract,indent=2))
print(f'Built {len(parts)} canonical modules and {len(assemblies)} assemblies.')
