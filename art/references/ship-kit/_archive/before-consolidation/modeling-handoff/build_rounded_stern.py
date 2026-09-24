"""Rounded stern revision; exact mesh-derived construction preview."""
from pathlib import Path
import importlib.util,json,math,zipfile
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('v2',R/'build_floors.py');v2=importlib.util.module_from_spec(spec);spec.loader.exec_module(v2)
O=R/'multi-deck-v3'
for d in ['meshes','drawings','assemblies','prompts']:(O/d).mkdir(parents=True,exist_ok=True)
N=16
outer=[(round(3*math.cos(i*math.pi/N),6),round(2*math.sin(i*math.pi/N),6)) for i in range(N+1)]
inner=[(round(2.8*math.cos(i*math.pi/N),6),round(1.8*math.sin(i*math.pi/N),6)) for i in range(N+1)]
def stern_wall(height):
 return v2.base.combine([v2.prism([outer[i],outer[i+1],inner[i+1],inner[i]],0,height) for i in range(N)])
def lower_stern():
 # Revolve the exact HULL_U6 cross-section around a half ellipse; fore remains open.
 profile=[(3,2.6,2),(3,2,2),(2.8,1,2*2.8/3),(2,.3,2*2/3),(0,0,0),(0,.2,0),(1.92,.5,1.8*1.92/2.8),(2.6,1.12,1.8*2.6/2.8),(2.8,2,1.8),(2.8,2.6,1.8)]
 vv=[];ff=[];lookup={}
 def vertex(p):
  p=tuple(round(t,6) for t in p)
  if p not in lookup:lookup[p]=len(vv);vv.append(p)
  return lookup[p]
 rings=[[vertex((rx*math.cos(i*math.pi/N),y,rz*math.sin(i*math.pi/N))) for rx,y,rz in profile] for i in range(N+1)]
 def face(ids):
  ids=list(dict.fromkeys(ids))
  if len(ids)>2:ff.append(ids)
 for a,b in zip(rings,rings[1:]):
  for j in range(len(profile)):
   k=(j+1)%len(profile);face([a[j],b[j],b[k],a[k]])
 face(list(reversed(rings[0])));face(rings[-1])
 return vv,ff
meshes=dict(v2.meshes)
meshes.update(U_STERN=stern_wall(2.6),R_STERN=stern_wall(.6),F_STERN=v2.prism(inner,-.18,0),H03_ROUND_STERN=lower_stern())
c=json.loads(json.dumps(v2.contract));c['version']='3.0-rounded-stern';c['base_contract']='../contract.json'
c['revision']='Use this revision instead of v2. Stern floor and ALL stern tiers share a faceted half-ellipse. No raised rear portion or corner posts. Bow and middle floors retain their matching host outlines.'
c['interfaces']['VERTICAL_STACK']['stern_override']={'outer_xz':outer,'inner_xz':inner,'lower_host':'H03_ROUND_STERN','replaces':'H03_STERN; do not mix the old transom with these rounded tiers'}
c['interfaces']['VERTICAL_STACK']['footprints_by_host'].pop('H03_STERN',None)
c['rule']=c['rule'].replace('v1 lower hull','v1 bow and mid plus H03_ROUND_STERN lower hull')
c['source_priority']=['v3 contract and meshes','v3 exact mesh drawings','08-corrected-stern-and-decks-v1.png for style only; earlier stern concepts superseded']
c['parts']=[p for p in c['parts'] if p['id'] not in ['U_STERN','R_STERN','F_STERN']]
for name in ['U_STERN','R_STERN','F_STERN','H03_ROUND_STERN']:
 verts,_=meshes[name]
 c['parts'].append({'id':name,'mesh':f'meshes/{name}.obj','bounds_min':[min(p[i] for p in verts) for i in range(3)],'bounds_max':[max(p[i] for p in verts) for i in range(3)],'notes':'Faceted rounded stern footprint. Open fore. No elevated rear feature. Floor has no posts; wall upper/lower boundaries are level. H03_ROUND_STERN alone contains the lower bilge.'})
for a in c['assemblies']:
 for p in a['placements']:
  if p['part']=='H03_STERN':p['part']='H03_ROUND_STERN';p['source']='v3'
  elif p['source']=='v2':p['source']='v3'
 blocks=[v2.shift(meshes[p['part']] if p['source']=='v3' else v2.base.meshes[p['part']],p['position']) for p in a['placements']]
 v2.base.obj(O/'assemblies'/(a['id']+'.obj'),*v2.base.combine(blocks))
for name,(v,f) in meshes.items():
 v2.base.obj(O/'meshes'/(name+'.obj'),v,f)
 (O/'drawings'/(name+'.svg')).write_text(v2.base.sheet(name,v,f),encoding='utf8')
 (O/'prompts'/(name+'.md')).write_text(f'# {name}\n\nUse contract.json and meshes/{name}.obj. Exact geometry overrides concept art. Preserve interface coordinates within 1 mm. Flat floors: no raised posts or perimeter curbs. Uniform-height wall tiers: no raised transom. Warm broad wooden planks, dark iron, restrained grain, toon shading. Keep stair openings and landings unchanged. Deliver model, collision separately, socket empties and measured bounds.\n',encoding='utf8')
(O/'contract.json').write_text(json.dumps(c,indent=2))
# Independent exported-vertex footprint checks.
def vertices(name):
 return [tuple(map(float,l.split()[1:])) for l in (O/'meshes'/(name+'.obj')).read_text().splitlines() if l.startswith('v ')]
def layer(name,y):return {(x,z) for x,yy,z in vertices(name) if abs(yy-y)<1e-6}
assert layer('H03_ROUND_STERN',2.6)==layer('U_STERN',0)==layer('U_STERN',2.6)==layer('R_STERN',0)
assert layer('F_STERN',0)==set(inner)
for name in ['F_BOW','F_MID','F_STERN']:
 assert {p[1] for p in vertices(name)}=={-.18,0}
assert layer('U_STERN',0)==set(outer+inner)
# Fore socket matches base mid's whole cross-section (extra collinear y2 nodes retained).
actual={(x,y) for x,y,z in vertices('H03_ROUND_STERN') if abs(z)<1e-6}
assert actual==set(v2.base.OUTER+v2.base.INNER)
(O/'validation.json').write_text(json.dumps({'checks':['Exported lower stern / upper stern / rail footprints equal','Exported rounded deck perimeter equals inner stern wall','All three floor types flat and post-free','Lower stern fore socket matches HULL_U6'],'limits':'Blockout interface checks only; final styled model and collision not tested.'},indent=2))
# Exact isometric projections of the actual meshes, not invented concept geometry.
im=Image.new('RGB',(1500,980),'#efede7');d=ImageDraw.Draw(im);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',24)
names=['U_BOW','U_MID','U_STERN','F_BOW','F_MID','F_STERN']
for k,name in enumerate(names):
 v,f=meshes[name];col=k%3;row=k//3
 def project(p):
  x,y,z=p;return ((x-z)*.866,(x+z)*.35-y)
 pp=[project(p) for p in v];xmin=min(p[0] for p in pp);ymin=min(p[1] for p in pp)
 scale=min(430/(max(p[0] for p in pp)-xmin),340/max(.01,max(p[1] for p in pp)-ymin))
 pts=[(col*500+35+(x-xmin)*scale,row*470+60+(y-ymin)*scale) for x,y in pp]
 for face in sorted(f,key=lambda face:sum(sum(v[i]) for i in face)/len(face)):
  yy=[v[i][1] for i in face];color='#c48b49' if max(yy)-min(yy)<1e-6 else '#825533'
  d.polygon([pts[i] for i in face],fill=color,outline='#49382b')
 d.text((col*500+45,row*470+425),name,font=font,fill='#26343c')
d.text((35,940),'Exact starter geometry: flat matching decks; level wall tiers; rounded stern; no raised posts.',font=font,fill='#26343c')
im.save(O/'drawings/corrected-modules.png')
print('Validated v3: 16 meshes, 2 assemblies, exact deck and stern interfaces.')
