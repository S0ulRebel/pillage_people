from pathlib import Path
import json, math, zipfile
from collections import Counter
from PIL import Image, ImageDraw, ImageFont
R=Path(__file__).resolve().parent
O=R/'multi-deck-v2'
c=json.loads((O/'contract.json').read_text())
def read(p):
 v=[];f=[]
 for l in p.read_text().splitlines():
  if l.startswith('v '):v.append(tuple(map(float,l.split()[1:])))
  if l.startswith('f '):f.append([int(x)-1 for x in l.split()[1:]])
 assert all(math.isfinite(n) for p in v for n in p)
 assert all(len(set(a))>=3 and all(0<=i<len(v) for i in a) for a in f)
 return v,f
m={p.stem:read(p) for p in (O/'meshes').glob('*.obj')}
checks=[]
for name,(v,f) in m.items():
 edges=Counter(tuple(sorted((i,j))) for a in f for i,j in zip(a,a[1:]+a[:1]))
 assert all(n==2 for n in edges.values()),name
 if name.startswith('U_'):
  bottom={(x,z) for x,y,z in v if abs(y)<1e-6}
  top={(x,z) for x,y,z in v if abs(y-2.6)<1e-6}
  assert bottom==top,name
  checks.append(name+' exported top/bottom footprints match')
for side,x in [('PORT',-1.5),('STARBOARD',1.5)]:
 v,f=m['F_STAIR_'+side+'_END']
 # Actual exported top landing vertices must bridge full slot at stair exit.
 for xx in [x-.55,x+.55]:
  for zz in [1.25,2.0]:assert any(math.dist((xx,0,zz),p)<1e-6 for p in v)
 checks.append(side+' exported landing meets tread at Z=3.25')
v,_=m['A_STAIRS_260'];assert max(p[1] for p in v)==2.6 and max(p[2] for p in v)==3.25
for a in c['assemblies']:
 read(O/'assemblies'/(a['id']+'.obj'))
 for s in [p for p in a['placements'] if p['part']=='A_STAIRS_260']:
  x,y,z=s['position'];side='PORT' if x<0 else 'STARBOARD'
  assert any(p['part']=='F_STAIR_'+side+'_END' and math.dist(p['position'],(0,y+2.6,z+2))<1e-6 for p in a['placements'])
 checks.append(a['id']+' exported mesh valid and stair landing transforms match')
report={'parts':len(m),'checks':checks,'limits':'Checks exported blockout topology, stack footprints and stair landing coordinates. Styled meshes, collision, supports and gameplay remain modeling tasks.'}
(O/'export-checks.json').write_text(json.dumps(report,indent=2))
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',22)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',17)
im=Image.new('RGB',(1200,760),'#f5f1e8');d=ImageDraw.Draw(im)
d.text((35,25),'MODULAR SHIP | Three walkable decks',font=font,fill='#26343c')
for i in range(3):
 y=(i+1)*2.6;yy=640-y*60
 d.rectangle((100,yy,940,yy+10),fill='#ad793e')
 d.text((950,yy-5),f'{y:.2f} m',font=font,fill='#26343c')
 if i<2:
  for z in [0,4,6,8,10,12,14]:d.line((100+z*60,yy,100+z*60,yy-156),fill='#33596b',width=2)
  d.text((390,yy-85),'2.42 m clear',font=small,fill='#26343c')
d.line([(100,484),(160,620),(820,620),(940,484)],fill='#33596b',width=4)
d.text((340,585),'Lower hull / hold: used once',font=small,fill='#26343c')
for z,y,side in [(4,2.6,'Port'),(8,5.2,'Starboard')]:
 x=100+z*60;yy=640-y*60
 d.line((x,yy,x+195,yy-156),fill='#b34a35',width=5)
 d.text((x,yy-25),side+' stairs',font=small,fill='#26343c')
d.text((35,690),'Side schematic: 14 m length / 6 m beam. Floor pitch 2.6 m; floor thickness 0.18 m.',font=small,fill='#26343c')
d.text((35,721),'15 starter modules + two assembled OBJ examples. Shape and style pass follows in the modeling agent.',font=small,fill='#26343c')
im.save(O/'drawings/levels.png')
archive=R.parent/'ship-modeling-handoff-v2-floors.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in R.rglob('*'):
  if p.is_file() and '__pycache__' not in p.parts:z.write(p,Path('ship-kit')/p.relative_to(R.parent))
 for p in R.parent.glob('*.png'):z.write(p,Path('ship-kit')/p.name)
print(json.dumps(report));print(archive)
