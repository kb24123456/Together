"""Scoped authoring helpers for the live, backed-up Together sphere."""
import json, math, sys, importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
EX = HERE.parent / '2026-09-09-expression-system'
sys.path.insert(0, str(EX))
from rive_client import call, cmd, anim, props, group
from design import arc, resample
spec = importlib.util.spec_from_file_location('projection', HERE.parent/'2026-09-08-rive-study/sphere-eye-projection.py')
H = importlib.util.module_from_spec(spec); spec.loader.exec_module(H)
V6 = json.loads((HERE.parent/'2026-09-08-rive-study/motion-v6.json').read_text())
OLD = json.loads((HERE/'backups/keyframes.json').read_text())
OLD_RIG = json.loads((EX/'rig.json').read_text())
def save(name, data): (HERE/name).write_text(json.dumps(data, indent=2)+'\n')
def sample(vs, f):
    if f <= vs[0][0]: return vs[0][1]
    for (a,x),(b,y) in zip(vs,vs[1:]):
        if f <= b: return x+(y-x)*(f-a)/(b-a)
    return vs[-1][1]
def smooth(vs, f):
    if f <= vs[0][0]: return vs[0][1]
    for (a,x),(b,y) in zip(vs,vs[1:]):
        if f <= b:
            t=(f-a)/(b-a); t=t*t*t*(t*(t*6-15)+10)
            return x+(y-x)*t
    return vs[-1][1]
def tracks(aid):
    out={}
    for k in OLD[aid]: out.setdefault(k['objectId']+':'+str(k['propertyKey']),[]).append([k['frame'],k['value']])
    return {k:sorted(v) for k,v in out.items()}
def write_tracks(aid, ts):
    old=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
    delete=[k['keyframeId'] for k in old if k['objectId']+':'+str(k['propertyKey']) in ts]
    if delete: anim('modifyKeyFrames',dict(animationId=aid,delete=delete))
    keys=[]
    for k,vs in ts.items():
        oid,pk=k.split(':')
        keys += [dict(objectId=oid,propertyKey=int(pk),frame=v[0],value=v[1],interpolationType=v[2] if len(v)>2 else 'linear') for v in vs]
    for i in range(0,len(keys),1400): anim('modifyKeyFrames',dict(animationId=aid,add=keys[i:i+1400]))
    return len(keys)
def cmds_for_vertices(vertices):
    vs=[H.absolute_handles(v) for v in vertices]
    out=[dict(commandType='moveTo',x=vs[0]['x'],y=vs[0]['y'])]
    for i,a in enumerate(vs):
        b=vs[(i+1)%len(vs)]
        out.append(dict(commandType='cubicTo',control1X=a['outX'],control1Y=a['outY'],control2X=b['inX'],control2Y=b['inY'],endX=b['x'],endY=b['y']))
    return out+[dict(commandType='close')]
def eye_parameters(yaw,pitch,sign):
    theta=math.asin(78/184)*yaw
    return (184*math.sin(theta)+sign*44*math.cos(theta),
            -27-46*pitch-5*sign*yaw*pitch,
            30*math.cos(theta)*(1-.13*sign*yaw),
            84*(1-.065*sign*yaw)*(1-.027*yaw*yaw),
            -(22+2*sign)*yaw*pitch)
def local_eye(x,y,w,h,r):
    # Shared parent owns center and tilt. The contour still uses the exact old
    # spherical projection, including its non-affine wrapping and natural blink.
    out=H.project_eye(x,y,w,h,r,local=True)
    c,s=math.cos(math.radians(r)),math.sin(math.radians(r))
    for v in out:
        v['x'],v['y']=c*v['x']+s*v['y'],-s*v['x']+c*v['y']
        v['inr']-=r; v['outr']-=r
    return out
