#!/usr/bin/env python3
"""Author shared-eye expressions and a review timeline. No Rive or App writes."""
import importlib.util
import json
import math
from pathlib import Path

HERE=Path(__file__).parent
BASE=HERE.parent
V6=json.loads((BASE/'motion-v6.json').read_text())
S=json.loads((BASE/'tears-b-preview/motion.json').read_text())
spec=importlib.util.spec_from_file_location('turn',BASE/'tears-b-preview/build-turn-preview.py')
T=importlib.util.module_from_spec(spec);spec.loader.exec_module(T)
KEYS=(24,25,84,85,86,87)
EYES=[list(range(32883,32891)),list(range(32891,32899))]
FLOWS=[dict(shape='0-185837',first=185839,source=169157,origin=(38,-44)),
       dict(shape='0-185827',first=185829,source=169167,origin=(126,-54))]
GROUP='0-185826'
IDS={'Expression_Wink':'0-185847','Expression_Tears':'0-185848',
     'Expression_TearsTurn':'0-185849','Preview_All':'0-185850'}

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mix(a,b,t): return tuple(T.lerp(x,y,t) for x,y in zip(a,b))

def controls(values):
    x,y,ia,il,oa,ol=values
    return [(x,y),(x+math.cos(math.radians(ia))*il,y+math.sin(math.radians(ia))*il),
            (x+math.cos(math.radians(oa))*ol,y+math.sin(math.radians(oa))*ol)]

def from_pose(p,ids): return [controls([p[f'0-{i}:{k}'] for k in KEYS]) for i in ids]
NEUTRAL_EYES=[from_pose(V6['neutral'],ids) for ids in EYES]

def split_segment(seg):
    a,b,c,d=seg
    ab,bc,cd=mix(a,b,.5),mix(b,c,.5),mix(c,d,.5)
    abc,bcd=mix(ab,bc,.5),mix(bc,cd,.5)
    mid=mix(abc,bcd,.5)
    return [a,ab,abc,mid],[mid,bcd,cd,d]

def six_to_eight(v):
    seg=[]
    for i,a in enumerate(v):
        b=v[(i+1)%6]
        s=[a[0],a[2],b[1],b[0]]
        seg.extend(split_segment(s) if i in (1,4) else [s])
    return [[s[0],seg[i-1][2],s[1]] for i,s in enumerate(seg)]

def rotate_curve(v,yaw,pitch):
    out=[]
    for p,hi,ho in v:
        q=T.project(p,yaw,pitch)[:2]
        out.append([q,add(q,T.differential(p,sub(hi,p),yaw,pitch)),add(q,T.differential(p,sub(ho,p),yaw,pitch))])
    return out

def curve_from_vertices(verts,origin=(0,0)):
    return [[add(p,origin) for p in controls([v[n] for n in ('x','y','inr','ind','outr','outd')])] for v in verts]

def fixed_cry_eyes(yaw,pitch):
    result=[]
    for si,d in enumerate(T.DEFS[:2]):
        src=T.original_vertices(d,90)
        verts=[]
        for p,hi,ho in src:
            p=add(p,d['origin']);q=T.project(p,yaw,pitch)[:2]
            verts.append([q,add(q,T.differential(p,hi,yaw,pitch)),add(q,T.differential(p,ho,yaw,pitch))])
        result.append(six_to_eight(verts))
    return result

def put_curve(p,ids,v):
    for i,(pt,hi,ho) in zip(ids,v):
        a,b=sub(hi,pt),sub(ho,pt)
        vals=(pt[0],pt[1],math.degrees(math.atan2(a[1],a[0])),math.hypot(*a),math.degrees(math.atan2(b[1],b[0])),math.hypot(*b))
        for key,value in zip(KEYS,vals):p[f'0-{i}:{key}']=value

def tear_short_geometry(f):
    shapes=[]
    for di,d in enumerate(T.DEFS[2:]):
        src=T.original_vertices(d,f)
        scale=T.source_value(d['shape'],17,f)/100
        v=[]
        for p,hi,ho in src:
            p=(p[0],p[1]*scale);hi=(hi[0],hi[1]*scale);ho=(ho[0],ho[1]*scale)
            p=add(p,d['origin']);q=T.project(p,-28,0)[:2]
            v.append([q,add(q,T.differential(p,hi,-28,0)),add(q,T.differential(p,ho,-28,0))])
        shapes.append(v)
    return shapes

EXTRA_DEFAULT={f'{GROUP}:18':0}
for d in FLOWS:
    EXTRA_DEFAULT[f"{d['shape']}:17"]=100
    EXTRA_DEFAULT[f"{d['shape']}:18"]=0
    for i in range(6):
        for k in KEYS: EXTRA_DEFAULT[f"0-{d['first']+i}:{k}"]=T.source_value(f"0-{d['source']+i}",k,0)
NEUTRAL={**V6['neutral'],**EXTRA_DEFAULT}

def tear_pose(f,long):
    p=NEUTRAL.copy()
    end=576 if long else 240
    yaw,pitch=T.angles(f) if long else (-28,0)
    close=T.ramp(f,18,40)*(1-T.ramp(f,498 if long else 202,520 if long else 224))
    target=fixed_cry_eyes(yaw,pitch)
    for i in range(2):
        neutral=rotate_curve(NEUTRAL_EYES[i],yaw+28,pitch)
        blended=[[mix(a,b,close) for a,b in zip(v,w)] for v,w in zip(neutral,target[i])]
        put_curve(p,EYES[i],blended)
    flow_shapes=[curve_from_vertices(v,d['origin']) for v,d in zip(T.geometry(f)[2:],T.DEFS[2:])] if long else tear_short_geometry(f)
    p[f'{GROUP}:18']=100
    for i,d in enumerate(FLOWS):
        local=[[sub(pt,d['origin']) for pt in v] for v in flow_shapes[i]]
        put_curve(p,range(d['first'],d['first']+6),local)
        p[f"{d['shape']}:18"]=100*T.ramp(f-6*i,42,52)*(1-T.ramp(f-6*i,464,489)) if long else T.source_value(T.DEFS[i+2]['shape'],18,f)
    presence=T.ramp(f,18,72)*(1-T.ramp(f,464 if long else 168,520 if long else 224))
    p['0-14:14']=240+1.4*presence
    p['0-14:15']=-.3*presence
    p['0-14:16']=p['0-14:17']=100+.2*presence
    if f in (0,end): p[f'{GROUP}:18']=0
    return p

def wink_arc():
    # Eight vertices, outer arch and inset arch with two round terminals.
    k=.5522847498
    seg=[[(0,-20),(33*k,-20),(33,15-35*k),(33,15)],
         [(33,15),(33,23.7),(20,23.7),(20,15)],
         [(20,15),(20,15-21*k),(20*k,-6),(0,-6)],
         [(0,-6),(-20*k,-6),(-20,15-21*k),(-20,15)],
         [(-20,15),(-20,23.7),(-33,23.7),(-33,15)],
         [(-33,15),(-33,15-35*k),(-33*k,-20),(0,-20)]]
    pieces=[]
    for i,s in enumerate(seg):pieces.extend(split_segment(s) if i in (0,5) else [s])
    return [[s[0],pieces[i-1][2],s[1]] for i,s in enumerate(pieces)]

def wink_pose(f):
    p=NEUTRAL.copy()
    look=T.ramp(f,8,26)*(1-T.ramp(f,58,82))
    closed=T.ramp(f,24,31)*(1-T.ramp(f,45,59))
    yaw,pitch=12*look,-3*look
    for i,base in enumerate(NEUTRAL_EYES):
        v=base
        if i==1:
            target=[[add(pt,(56,-36)) for pt in vv] for vv in wink_arc()]
            v=[[mix(a,b,closed) for a,b in zip(vv,ww)] for vv,ww in zip(base,target)]
        put_curve(p,EYES[i],rotate_curve(v,yaw,pitch))
    return p

def plan(name,frames):
    tracks={};dense={}
    for key in frames[0]:
        vals=[f[key] for f in frames]
        if key.endswith(':84') or key.endswith(':86'):
            for i in range(1,len(vals)):
                vals[i]+=360*round((vals[i-1]-vals[i])/360)
        dense[key]=vals
        tracks[key]=T.simplify(vals,.035 if not key.endswith((':84',':86')) else .06)
    # Capsule endpoints coincide after an eye opens. Shared XY knots keep them
    # coincident between frames; zero-handle boundaries retain exact closure.
    for eye in EYES:
        xy=[f'0-{i}:{k}' for i in eye for k in (24,25)]
        knots={f for key in xy for f,_ in tracks[key]}
        if name=='Expression_Wink':knots.update((24,31,45,59))
        for key in xy:tracks[key]=[[f,dense[key][f]] for f in sorted(knots)]
        for i in eye:
            for k in (85,87):
                key=f'0-{i}:{k}';values=dense[key]
                keep={f for f,_ in tracks[key]}
                for f in range(1,len(values)):
                    if (values[f]<1e-9)!=(values[f-1]<1e-9):keep.update((f-1,f))
                tracks[key]=[[f,values[f]] for f in sorted(keep)]
    return dict(name=name,id=IDS[name],frames=len(frames)-1,fps=60,loop=name=='Preview_All',tracks=tracks)

def sample_plan(p,f):return {**EXTRA_DEFAULT,**{k:T.sample(tr,f) for k,tr in p['tracks'].items()}}

def build():
    new={name:plan(name,[fn(f) for f in range(n+1)]) for name,n,fn in [
        ('Expression_Wink',96,wink_pose),('Expression_Tears',240,lambda f:tear_pose(f,False)),
        ('Expression_TearsTurn',576,lambda f:tear_pose(f,True))]}
    combined={**V6['plans'],**new}
    sequence=[('Idle',384),('Idle_Look',96),('Acknowledge',24),('Rest',30),
      ('WritingEnter',12),('Writing',240),('WritingHold',240),('WritingExit',12),('Rest',30),
      ('ThinkingEnter',45),('Thinking',240),('ThinkingExit',36),('Rest',30),
      ('ConcernEnter',12),('Concerned',360),('Recover',12),('Rest',30),
      ('Celebrate',84),('Rest',30),('Remind',108),('Rest',30),('Expression_Wink',96),('Rest',30),
      ('Expression_TearsTurn',576),('Rest',30),('DozeEnter',60),('Doze',288),('Wake',84),('Rest',48)]
    frames=[];segments=[]
    for name,length in sequence:
        start=len(frames)
        clip=[NEUTRAL.copy() for _ in range(length)] if name=='Rest' else [sample_plan(combined[name],f) for f in range(length)]
        frames.extend(clip)
        segments.append(dict(name=name,startFrame=start,endFrame=len(frames),startSeconds=start/60,endSeconds=len(frames)/60))
    frames.append(NEUTRAL.copy())
    new['Preview_All']=plan('Preview_All',frames)
    output=dict(fileId=2561771,artboardId='0-2',ids=IDS,tearGroup=GROUP,tearFlows=FLOWS,
                neutral=NEUTRAL,plans=new,segments=segments,
                policy='New expression timelines share main spherical eyes; no new business inputs or Mascot routes.')
    (HERE/'motion-integrated.json').write_text(json.dumps(output,separators=(',',':'))+'\n')
    print(json.dumps({k:dict(frames=p['frames'],tracks=len(p['tracks']),keys=sum(map(len,p['tracks'].values()))) for k,p in new.items()}))

if __name__=='__main__':build()
