#!/usr/bin/env python3
"""Build scoped Rive timeline patches; this script never writes to the editor."""
import bisect
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / '2026-09-08-rive-study'
V6 = json.loads((BASE / 'motion-v6.json').read_text())
EX = json.loads((BASE / 'expression-integration/motion-integrated.json').read_text())
spec = importlib.util.spec_from_file_location('sphere', BASE / 'sphere-eye-projection.py')
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)
IDS = {**V6['ids'], **EX['ids'], 'Preview':'0-110', 'Preview_Behaviors_v5':'0-13233'}
IDS.update(ThinkingEnter='0-122622', ThinkingExit='0-122623', DozeEnter='0-122624', CelebrateConcern='0-122625', Settle='0-122626')
GROUP = '0-318752'
ZS = [('0-318753',116,-106), ('0-318761',149,-134), ('0-318769',186,-164)]

def sample(track, f):
    if f <= track[0][0]: return track[0][1]
    j = bisect.bisect_right([x[0] for x in track], f) - 1
    if j == len(track)-1: return track[-1][1]
    a,x=track[j]; b,y=track[j+1]
    return x+(y-x)*(f-a)/(b-a)

def smooth(track, f):
    if f <= track[0][0]: return track[0][1]
    j = bisect.bisect_right([x[0] for x in track], f) - 1
    if j == len(track)-1: return track[-1][1]
    a,x=track[j]; b,y=track[j+1]; t=(f-a)/(b-a); t=t*t*(3-2*t)
    return x+(y-x)*t

def pose(name,f):
    plan = EX['plans'].get(name) or V6['plans'][name]
    return {**EX['neutral'], **{k:sample(v,f) for k,v in plan['tracks'].items()}}

DEFAULT = {GROUP+':18':0, '0-13108:47':12, '0-13114:47':11}
for z,x,y in ZS:
    DEFAULT.update({z+':13':x,z+':14':y,z+':16':100,z+':17':100,z+':18':0})

def gaze_patch(name,f):
    p=pose(name,f)
    if name=='Idle':
        yaw=smooth([[0,.15],[120,.15],[158,.70],[194,.70],[242,.15],[384,.15]],f)
        pitch=smooth([[0,.2],[120,.2],[158,.10],[194,.10],[242,.2],[384,.2]],f)
    else:
        yaw=smooth([[0,.15],[90,.15],[120,-.55],[154,-.55],[196,.15],[300,.15]],f)
        pitch=smooth([[0,.2],[90,.2],[120,.05],[154,.05],[196,.2],[300,.2]],f)
    theta=math.asin(78/184)*yaw
    patch={}
    for sign,eye,path,name2 in [(-1,'0-24','0-25','SphereEyeNear'),(1,'0-28','0-29','SphereEyeFar')]:
        x=184*math.sin(theta)+sign*44*math.cos(theta)
        y=-27-46*pitch-5*sign*yaw*pitch
        w=30*math.cos(theta)*(1-.13*sign*yaw)
        # Preserve the authored blink fraction in the reprojected eye surface.
        neutral_h=V6['neutral'][path+':21']
        h=84*(1-.065*sign*yaw)*(1-.027*yaw*yaw)*p[path+':21']/neutral_h
        r=-(22+2*sign)*yaw*pitch
        verts=H.as_rive_properties(H.project_eye(x,y,w,h,r))
        for vid,properties in zip(V6['sphereEyeRig'][name2]['vertices'],verts):
            patch.update({vid+':'+key:value for key,value in properties.items()})
    return patch

def sleep_patch(name,f):
    p=pose(name,f)
    t=1 if name=='Doze' else smooth([[0,0],[38,0],[44,1],[60,1]],f) if name=='DozeEnter' else 1-smooth([[0,0],[12,0],[18,1],[84,1]],f)
    out={}
    for shape,first,second,stroke in [('0-13104','0-13106','0-13107','0-13108'),('0-13110','0-13112','0-13113','0-13114')]:
        targets={first+':86':48.0,first+':87':16.0,second+':84':132.0,second+':85':16.0}
        for k,v in targets.items(): out[k]=p[k]+(v-p[k])*t
        out[shape+':16']=p[shape+':16']*(1-.08*t)
        out[shape+':14']=p[shape+':14']+2*t
        out[stroke+':47']=DEFAULT[stroke+':47']+t
    # A complete, looping sequence: marks appear one by one, drift, and fade.
    # Wake hides the group immediately in the target pose; Rive's 50ms blend
    # smoothly fades whatever symbol phase was visible instead of flashing it.
    out[GROUP+':18']=100 if name=='Doze' else 0
    if name=='Doze':
        for i,(z,x,y) in enumerate(ZS):
            a=22+i*24
            alpha=smooth([[0,0],[a,0],[a+20,78],[a+76,78],[a+130,0],[288,0]],f)
            drift=smooth([[0,0],[a,0],[a+130,1],[288,1]],f)
            out.update({z+':13':x+6*drift,z+':14':y-12*drift,z+':18':alpha})
            if f in (0,288):out[z+':13']=x;out[z+':14']=y
    return out

def trackify(frames):
    # Dense sampling only on the small set of changed properties. Linear RDP
    # keeps faithful intermediate geometry without adding thousands of holds.
    def reduce(points,tol=.045):
        if len(points)<3:return points
        a,x=points[0];b,y=points[-1]
        err,j=max((abs(v-(x+(y-x)*(f-a)/(b-a))),j) for j,(f,v) in enumerate(points[1:-1],1))
        return points[:1]+points[-1:] if err<=tol else reduce(points[:j+1],tol)[:-1]+reduce(points[j:],tol)
    keys=set().union(*(p.keys() for p in frames))
    for key in keys:
        if key.endswith((':84', ':86')):
            for i in range(1,len(frames)):
                frames[i][key]+=360*round((frames[i-1][key]-frames[i][key])/360)
    tracks={k:reduce([[f,p[k]] for f,p in enumerate(frames)]) for k in sorted(keys)}
    # Match paired capsule XY knots, retaining topology across every subframe.
    for eye in V6['sphereEyeRig'].values():
        for a,b in [(0,1),(2,3),(4,5),(6,7)]:
            ks=[eye['vertices'][i]+':'+key for i in [a,b] for key in ['24','25']]
            if not all(k in tracks for k in ks):continue
            times=sorted({f for k in ks for f,_ in tracks[k]})
            for k in ks:tracks[k]=[[f,frames[f][k]] for f in times]
    return tracks

patches={}
lengths={**{n:p['frames'] for n,p in V6['plans'].items()},**{n:p['frames'] for n,p in EX['plans'].items()},'Preview':1443,'Preview_Behaviors_v5':1665}
for name,end in lengths.items():
    frames=[]
    for f in range(end+1):
        p=DEFAULT.copy()
        if name in ('Idle','Idle_QuietMedium'):p.update(gaze_patch(name,f))
        if name in ('Doze','DozeEnter','Wake'):p.update(sleep_patch(name,f))
        frames.append(p)
    patches[name]={'id':IDS[name],'frames':end,'tracks':trackify(frames)}

# Keep the user-facing complete preview current without rebuilding unrelated
# expression geometry or changing segment durations.
preview=[]
changed=set().union(*(set(a['tracks']) for n,a in patches.items() if n!='Preview_All'))
for f in range(EX['plans']['Preview_All']['frames']+1):
    p=pose('Preview_All',f);p.update(DEFAULT)
    seg=next((s for s in EX['segments'] if s['startFrame']<=f<s['endFrame']),None)
    if seg and seg['name'] in patches:
        a=patches[seg['name']];p.update({k:sample(v,f-seg['startFrame']) for k,v in a['tracks'].items()})
    preview.append({k:p[k] for k in changed})
patches['Preview_All']['tracks']=trackify(preview)

out={'fileId':2564580,'artboardId':'0-2','fps':60,'defaults':DEFAULT,'patches':patches,
     'scope':'Idle and QuietMedium spherical gaze; Doze/Enter/Wake eyelids and sleep symbols; guards on all timelines and refreshed Preview_All. Existing routes/inputs untouched.',
     'writingBase':{'0-44':{'13':-51,'14':32,'15':-5},'0-50':{'13':34,'14':27,'15':-5},'0-48':{'47':17},'0-54':{'47':16},
                    '0-46':{'24':-19,'25':-2,'84':0,'85':0,'86':33.6900675,'87':14.4222051},
                    '0-47':{'24':19,'25':1,'84':147.5288077,'85':13.0384048,'86':0,'87':0},
                    '0-52':{'24':-17,'25':-2,'84':0,'85':0,'86':30.9637565,'87':11.6619038},
                    '0-53':{'24':17,'25':1,'84':149.0362435,'85':11.6619038,'86':0,'87':0}}}
(HERE/'timeline-patches.json').write_text(json.dumps(out,separators=(',',':'))+'\n')
print(json.dumps({n:{'tracks':len(p['tracks']),'keys':sum(map(len,p['tracks'].values()))} for n,p in patches.items()}))
