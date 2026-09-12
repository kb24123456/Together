#!/usr/bin/env python3
"""Author six restrained sphere-facing glances from the verified Rive snapshot.

Writes motion.json only; does not connect to or mutate the editor.
"""
import ast
import bisect
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / '2026-09-08-rive-study'
V6 = json.loads((BASE / 'motion-v6.json').read_text())
SOURCE = json.loads((HERE / 'source-keyframes.json').read_text())['keyframes']
spec = importlib.util.spec_from_file_location('sphere', BASE / 'sphere-eye-projection.py')
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)

# Reuse tested interpolation/reduction functions without running the old builder.
module = ast.parse((HERE.parent / '2026-09-09-refinement/build-refinement.py').read_text())
ns = dict(bisect=bisect, V6=V6)
exec(compile(ast.Module(body=[n for n in module.body if isinstance(n, ast.FunctionDef)
                             and n.name in ('sample', 'smooth', 'trackify')], type_ignores=[]),
             'shared_timeline_helpers', 'exec'), ns)
sample, smooth, trackify = (ns[n] for n in ('sample', 'smooth', 'trackify'))

def tracks(animation_id):
    result = {}
    for k in SOURCE[animation_id]:
        assert k['interpolationType'] == 'linear'
        result.setdefault(k['objectId'] + ':' + str(k['propertyKey']), []).append([k['frame'], k['value']])
    return {k: sorted(v) for k,v in result.items()}

# frame boundaries: begin, arrive, dwell, small correction, release, return.
SPECS = {
    'Idle': dict(id='0-6', frames=384, source='0-6', direction='upper-left',
                 target=[-.63,.66], correction=[-.57,.72], times=[74,104,148,170,206,247], lag=5),
    'Idle_QuietMedium': dict(id='0-8762', frames=300, source='0-8762', direction='lower-right',
                 target=[.62,-.53], correction=[.68,-.48], times=[60,90,129,151,180,221], lag=-4),
    'Idle_Look': dict(id='0-5972', frames=96, source='0-5972', direction='lower-left',
                 target=[-.50,-.38], correction=[-.46,-.42], times=[9,27,41,48,53,79], lag=3),
    'Idle_GazeUp': dict(id='0-359913', frames=264, source='0-6', direction='up',
                 target=[.03,.87], correction=[-.03,.80], times=[51,80,123,140,167,204], lag=-5),
    'Idle_GazeDown': dict(id='0-359914', frames=288, source='0-6', direction='down',
                 target=[-.12,-.72], correction=[-.04,-.65], times=[82,114,145,163,191,230], lag=-6),
    'Idle_GazeUpRight': dict(id='0-359915', frames=336, source='0-6', direction='upper-right',
                 target=[.58,.54], correction=[.64,.60], times=[107,135,185,210,244,282], lag=6),
}

def eye_pose(yaw, pitch, base):
    theta = math.asin(78/184)*yaw
    out = {}
    for sign,path,name in [(-1,'0-25','SphereEyeNear'),(1,'0-29','SphereEyeFar')]:
        x = 184*math.sin(theta) + sign*44*math.cos(theta)
        y = -27 - 46*pitch - 5*sign*yaw*pitch
        w = 30*math.cos(theta)*(1-.13*sign*yaw)
        h = 84*(1-.065*sign*yaw)*(1-.027*yaw*yaw)*base[path+':21']/V6['neutral'][path+':21']
        r = -(22+2*sign)*yaw*pitch
        projected = H.as_rive_properties(H.project_eye(x,y,w,h,r))
        for vertex, values in zip(V6['sphereEyeRig'][name]['vertices'], projected):
            out.update({vertex+':'+key:value for key,value in values.items()})
    return out

plans = {}
for name, s in SPECS.items():
    original = tracks(s['source'])
    old_end = max(v[-1][0] for v in original.values())
    end = s['frames']
    a,b,c,d,e,f = s['times']
    yaw = [[0,.15],[a,.15],[b,s['target'][0]],[c,s['target'][0]],
           [d,s['correction'][0]],[e,s['correction'][0]],[f,.15],[end,.15]]
    lag=s['lag']
    pitch = [[0,.2],[a+lag,.2],[b+lag,s['target'][1]],[c+lag,s['target'][1]],
             [d+lag,s['correction'][1]],[e+lag,s['correction'][1]],[f+lag,.2],[end,.2]]
    frames=[]
    is_new=s['id'] not in SOURCE
    for frame in range(end+1):
        base={k:sample(v, frame*old_end/end) for k,v in original.items()}
        eye=eye_pose(smooth(yaw,frame),smooth(pitch,frame),base)
        frames.append(base | eye if is_new else eye)
    plans[name]=s | dict(tracks=trackify(frames), yaw=yaw, pitch=pitch, complete=is_new)

# The existing non-resident orientation study now demonstrates all six glances.
preview=[]; segments=[]; cursor=0
for name in ['Idle_GazeUp','Idle_QuietMedium','Idle_GazeUpRight','Idle_GazeDown','Idle','Idle_Look']:
    s=plans[name]; original=tracks(s['source']); old_end=max(v[-1][0] for v in original.values())
    for frame in range(s['frames']):
        base={k:sample(v,frame*old_end/s['frames']) for k,v in original.items()}
        preview.append(base | {k:sample(v,frame) for k,v in s['tracks'].items()})
    segments.append(dict(name=name,startFrame=cursor,endFrame=cursor+s['frames']))
    cursor+=s['frames']
preview.append({k:v[0][1] for k,v in tracks('0-6').items()})
plans['Idle_Orient']=dict(id='0-18430',frames=cursor,tracks=trackify(preview),complete=True)

# Keep the Idle segment of the full expression preview in sync. Other expression
# frames/keys are retained verbatim by the scoped write step.
EX=json.loads((BASE/'expression-integration/motion-integrated.json').read_text())
preview_segments=[x for x in EX['segments'] if x['name'] in SPECS]
all_tracks=tracks('0-185850')
edits={}
for segment in preview_segments:
    plan=plans[segment['name']]; start,stop=segment['startFrame'],segment['endFrame']
    for key, values in plan['tracks'].items():
        # Only existing directional eye curves are scoped into Preview_All.
        if key not in eye_pose(.15,.2,V6['neutral']):continue
        edits.setdefault(key,list(all_tracks[key]))
        edits[key]=[v for v in edits[key] if not start<=v[0]<stop]
        edits[key]+=[[frame+start,value] for frame,value in values if frame+start<stop]
        edits[key]=sorted(edits[key])
plans['Preview_All']=dict(id='0-185850',frames=3297,tracks=edits,complete=False)

out=dict(fileId=2564580,artboardId='0-2',fps=60,neutralYaw=.15,neutralPitch=.2,
         note='Shared neutral endpoints preserve existing business transitions. Directions and timing are randomly selected from authored glances; no frame-wise noise.',
         plans=plans,orientationSegments=segments)
(HERE/'motion.json').write_text(json.dumps(out,separators=(',',':'))+'\n')
print(json.dumps({n:dict(frames=s['frames'],tracks=len(s['tracks']),keys=sum(map(len,s['tracks'].values()))) for n,s in plans.items()}))
