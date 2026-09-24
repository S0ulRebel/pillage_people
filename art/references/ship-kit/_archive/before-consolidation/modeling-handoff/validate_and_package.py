"""Independent checks of exported OBJ seams; PNG previews; portable handoff ZIP.
Requires Pillow for reference drawings, but does not modify any concept art.
"""
from pathlib import Path
import json, math, zipfile
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parent
data=json.loads((root/'contract.json').read_text())
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
meshes={}
for path in (root/'meshes').glob('*.obj'):
    vertices=[];faces=[]
    for line in path.read_text().splitlines():
        if line.startswith('v '): vertices.append(tuple(map(float,line.split()[1:])))
        if line.startswith('f '): faces.append([int(x)-1 for x in line.split()[1:]])
    assert all(math.isfinite(n) for v in vertices for n in v)
    assert all(len(set(f))>=3 and all(0<=i<len(vertices) for i in f) for f in faces)
    meshes[path.stem]=(vertices,faces)
    image=Image.new('RGB',(1500,650),'#f5f1e8');d=ImageDraw.Draw(image)
    d.text((24,18),path.stem+' | Exact starter geometry',font=font,fill='#26343c')
    for col,(title,a,b) in enumerate([('TOP: X / Z',0,2),('SIDE: Z / Y',2,1),('END: X / Y',0,1)]):
        xs=[v[a] for v in vertices];ys=[v[b] for v in vertices]
        sx=max(xs)-min(xs);sy=max(ys)-min(ys);scale=min(440/max(sx,.1),430/max(sy,.1))
        def pt(v):return (col*500+28+(v[a]-min(xs))*scale,550-(v[b]-min(ys))*scale)
        d.text((col*500+28,65),title,font=font,fill='#26343c')
        edges=set()
        for f in faces:
            for i,j in zip(f,f[1:]+f[:1]):edges.add(tuple(sorted((i,j))))
        for i,j in edges:d.line([pt(vertices[i]),pt(vertices[j])],fill='#33596b',width=2)
        d.text((col*500+28,575),f'Projected span: {sx:.3f} x {sy:.3f} m',font=small,fill='#26343c')
    d.text((24,618),'Hidden edges shown. Dimensions in contract.json; style in separate concept PNGs.',font=small,fill='#26343c')
    image.save(root/'drawings'/f'{path.stem}.png')

expected=data['interfaces']['HULL_U6']['outer_xy']+list(reversed(data['interfaces']['HULL_U6']['inner_xy']))
checks=[]
for p in data['parts']:
    if p['id'] not in meshes:continue
    vertices,_=meshes[p['id']]
    for s in p['sockets']:
        if s['interface']!='HULL_U6':continue
        z=s['position'][2]
        actual=[v for v in vertices if abs(v[2]-z)<1e-7]
        assert len(actual)==18,(p['id'],s['name'],len(actual))
        error=max(min(math.dist((x,y,z),v) for v in actual) for x,y in expected)
        assert error<=.001
        checks.append({'part':p['id'],'socket':s['name'],'max_exported_vertex_error_m':error})

# Numerically verify the gallery socket transforms in the documented cabin recipe.
gallery_checks=[]
for wall,yaw,bay in [([-1,2,10],0,[-1,2,10.1]),([1,2,10],0,[1,2,10.1]),([-2,2,9],-90,[-2.1,2,9]),([2,2,9],90,[2.1,2,9])]:
    rad=math.radians(yaw)
    host=[wall[0]+.1*math.sin(rad),wall[1],wall[2]+.1*math.cos(rad)]
    error=math.dist(host,bay);assert error<1e-9
    gallery_checks.append({'host':wall,'yaw_deg':yaw,'bay':bay,'socket_gap_m':error})

report={'exported_hull_sockets':checks,'gallery_socket_transforms':gallery_checks,
        'limits':'Socket equality is not collision validation. No styled final models or gameplay integration tested.'}
(root/'export-checks.json').write_text(json.dumps(report,indent=2))
archive=root.parent/'ship-modeling-handoff-v1.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for path in root.rglob('*'):
        if path.is_file() and '__pycache__' not in path.parts:z.write(path,Path('ship-kit')/path.relative_to(root.parent))
    for path in root.parent.glob('*.png'):z.write(path,Path('ship-kit')/path.name)
print(json.dumps({'obj_interfaces_checked':len(checks),'gallery_socket_transforms_checked':len(gallery_checks),'archive':str(archive)}))
