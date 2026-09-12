#!/usr/bin/env python3
"""Author cubic Rive geometry; reads the accepted study, never mutates Rive."""
import bisect
import json
import math
from pathlib import Path

HERE = Path(__file__).parent
SOURCE = json.loads((HERE / 'motion.json').read_text())
RADIUS = 184.0
END = 576
KEYS = (24, 25, 84, 85, 86, 87)
DEFS = [
    dict(name='eyeNear', first=169195, shape='0-169175', origin=(38,-55), kind='eye'),
    dict(name='eyeFar', first=169201, shape='0-169185', origin=(126,-65), kind='eye'),
    dict(name='tearNear', first=169157, shape='0-169155', origin=(38,-44), kind='tear', sx=1, sy=1, delay=0),
    dict(name='tearFar', first=169167, shape='0-169165', origin=(126,-54), kind='tear', sx=.65, sy=.8, delay=6),
]

def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)

def ramp(f, start, end):
    return smooth((f-start)/(end-start))

def lerp(a,b,t):
    return a+(b-a)*t

def sample(track, f):
    i = min(max(0, bisect.bisect_right([x[0] for x in track], f)-1), len(track)-2)
    a,b = track[i:i+2]
    return lerp(a[1],b[1],(f-a[0])/(b[0]-a[0]))

def source_value(object_id, key, f):
    return sample(SOURCE['tracks'][f'{object_id}:{key}'], f)

def angles(f):
    yaw = -28 - 18*ramp(f,94,142) + 46*ramp(f,182,268) - 28*ramp(f,310,358)
    pitch = 10*(ramp(f,358,396)-ramp(f,424,454))
    return yaw,pitch

def rotate3(v, yaw, pitch):
    a,b=math.radians(yaw),math.radians(pitch)
    x,y,z=v
    x,z=math.cos(a)*x+math.sin(a)*z,-math.sin(a)*x+math.cos(a)*z
    y,z=math.cos(b)*y+math.sin(b)*z,-math.sin(b)*y+math.cos(b)*z
    return x,y,z

def project(p, yaw, pitch):
    x,y=p
    z=math.sqrt(RADIUS*RADIUS-x*x-y*y)
    return rotate3((x,y,z),yaw,pitch)

def differential(p, h, yaw, pitch):
    x,y=p
    z=math.sqrt(RADIUS*RADIUS-x*x-y*y)
    return rotate3((h[0],h[1],-(x*h[0]+y*h[1])/z),yaw,pitch)[:2]

def eye_source_time(f):
    if f<=20: return .9*f
    if f<=40: return f-2
    if f<498: return 90
    if f<=520: return f-296
    return 224+(f-520)*16/56

def original_vertices(definition, f):
    result=[]
    for i in range(6):
        oid=f"0-{definition['first']+i}"
        x,y,ia,il,oa,ol=[source_value(oid,k,f) for k in KEYS]
        result.append(((x,y), (math.cos(math.radians(ia))*il, math.sin(math.radians(ia))*il),
                       (math.cos(math.radians(oa))*ol, math.sin(math.radians(oa))*ol)))
    return result

def flow_vertex(p,h1,h2,d,f):
    # Growth and flowing contour are on the source surface, before rotation.
    t=f-d['delay']
    onset=ramp(t,42,72)
    fade=ramp(t,464,489)
    envelope=ramp(t,72,88)*(1-ramp(t,454,464))
    length=.005+.995*onset+.018*envelope*math.sin(2*math.pi*(t-72)/96)+.05*fade
    x,y=p
    yn=y/d['sy']
    phase=2*math.pi*(yn/180-(t-72)/96)
    weight=math.sin(math.pi*yn/145)
    wave=1.2*envelope*weight*math.sin(phase)
    deriv=1.2*envelope*(math.pi/145*math.cos(math.pi*yn/145)*math.sin(phase)+weight*math.cos(phase)*2*math.pi/180)
    def dh(h): return h[0]+d['sx']*deriv*h[1]/d['sy'], h[1]*length
    return (x+d['sx']*wave,y*length),dh(h1),dh(h2)

def geometry(f):
    yaw,pitch=angles(f)
    shapes=[]
    for d in DEFS:
        src=original_vertices(d,eye_source_time(f) if d['kind']=='eye' else 0)
        projected=[]
        for p,hi,ho in src:
            if d['kind']=='tear': p,hi,ho=flow_vertex(p,hi,ho,d,f)
            p=(p[0]+d['origin'][0],p[1]+d['origin'][1])
            x,y,z=project(p,yaw,pitch)
            hi=differential(p,hi,yaw,pitch)
            ho=differential(p,ho,yaw,pitch)
            projected.append(dict(x=x-d['origin'][0],y=y-d['origin'][1],
                inr=math.degrees(math.atan2(hi[1],hi[0])),ind=math.hypot(*hi),
                outr=math.degrees(math.atan2(ho[1],ho[0])),outd=math.hypot(*ho),depth=z))
        shapes.append(projected)
    return shapes

def simplify(values,tolerance):
    chosen={0,len(values)-1}
    stack=[(0,len(values)-1)]
    while stack:
        a,b=stack.pop()
        if b-a<2: continue
        errors=[(abs(values[i]-lerp(values[a],values[b],(i-a)/(b-a))),i) for i in range(a+1,b)]
        error,i=max(errors)
        if error>tolerance:
            chosen.add(i)
            stack.extend([(a,i),(i,b)])
    return [[i,values[i]] for i in sorted(chosen)]

def build():
    frames=[geometry(f) for f in range(END+1)]
    dense={}
    names=['x','y','inr','ind','outr','outd']
    for si,d in enumerate(DEFS):
        for vi in range(6):
            for key,name in zip(KEYS,names):
                values=[frame[si][vi][name] for frame in frames]
                if key in (84,86):
                    for i in range(1,len(values)):
                        values[i]+=360*round((values[i-1]-values[i])/360)
                dense[f"0-{d['first']+vi}:{key}"]=values
    for d in DEFS:
        if d['kind']=='tear':
            dense[f"{d['shape']}:17"]=[100]*(END+1)
            dense[f"{d['shape']}:18"]=[100*ramp(f-d['delay'],42,52)*(1-ramp(f-d['delay'],464,489)) for f in range(END+1)]
    presence=[ramp(f,20,72)*(1-ramp(f,464,520)) for f in range(END+1)]
    dense['0-169150:14']=[240+1.4*v for v in presence]
    dense['0-169150:15']=[-.3*v for v in presence]
    dense['0-169150:16']=[100+.2*v for v in presence]
    dense['0-169150:17']=dense['0-169150:16'][:]
    tracks={k:simplify(v,.04 if int(k.split(':')[-1]) not in (84,86) else .07) for k,v in dense.items()}
    plan=dict(artboardId='0-169138',animationId='0-174151',name='Tears_B_Turn_Preview',fps=60,durationFrames=END,
              loop=True,reference='motion.json',projection='lift accepted silhouette to R184 sphere, yaw then pitch, analytic differential handles',
              shapeDefinitions=DEFS,poseFrames=dict(front=86,left=162,right=288,down=412,returnFront=458,recovered=544),
              yawDegrees=[-46,0],pitchDegrees=[0,10],tracks=tracks)
    (HERE/'motion-turn.json').write_text(json.dumps(plan,indent=2)+'\n')
    print(json.dumps(dict(tracks=len(tracks),keyframes=sum(map(len,tracks.values())),frames=END+1,
        minAnchorDepth=min(v['depth'] for fr in frames for shape in fr for v in shape))))

if __name__=='__main__': build()
