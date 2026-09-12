#!/usr/bin/env python3
"""Read-only reconstruction of scoped Rive patches; writes geometry evidence only."""
import ast
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / '2026-09-08-rive-study'
V6 = json.loads((BASE / 'motion-v6.json').read_text())
EX = json.loads((BASE / 'expression-integration/motion-integrated.json').read_text())
PATCH_FILE = HERE / 'timeline-patches.json'
patch_bytes = PATCH_FILE.read_bytes()
PATCH = json.loads(patch_bytes)

# Reuse the prior auditor's cubic reconstruction/intersection routines without
# importing its top-level audit, which would write another stage's evidence.
source = ast.parse((BASE / 'expression-integration/verify-integration.py').read_text())
keep_assign = {'KEYS', 'N', 't', 'u', 'W'}
keep_functions = {'controls', 'outline', 'cross', 'crosses'}
nodes = [node for node in source.body if isinstance(node, (ast.Import, ast.ImportFrom))
         or isinstance(node, ast.FunctionDef) and node.name in keep_functions
         or isinstance(node, ast.Assign) and all(isinstance(t, ast.Name) and t.id in keep_assign for t in node.targets)]
G = {}
exec(compile(ast.Module(body=nodes, type_ignores=[]), 'shared_geometry_helpers', 'exec'), G)

EYES = [dict(name='near', first=32883, n=8, origin=(0,0), shape='0-32859'),
        dict(name='far', first=32891, n=8, origin=(0,0), shape='0-32871')]
SLEEP = [('near','0-13104','0-13106','0-13107','0-13108',24),
         ('far','0-13110','0-13112','0-13113','0-13114',21)]
GROUP = '0-318752'
SYMBOLS = [('0-318753',8,6), ('0-318761',11,7), ('0-318769',14,8)]

def sample(plan, frame):
    return {key: float(np.interp(frame, [v[0] for v in values], [v[1] for v in values]))
            for key, values in plan['tracks'].items()}

def pose(name, frame):
    original = EX['plans'].get(name) or V6['plans'][name]
    return EX['neutral'] | sample(original, frame) | sample(PATCH['patches'][name], frame)

def transform(points, p, node):
    sx, sy = p.get(node+':16',100)/100, p.get(node+':17',100)/100
    a = math.radians(p.get(node+':15',0))
    rotation = np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
    return (np.asarray(points)*[sx,sy]) @ rotation.T + [p.get(node+':13',0),p.get(node+':14',0)]

def eye_outline(d,p):
    return G['outline'](G['controls'](d,p))

def sleep_outline(d,p):
    _,shape,first,second,_,half = d
    a,b = np.array([-half,0.]),np.array([half,0.])
    def handle(point, node, angle, length):
        r=math.radians(p[node+':'+angle]); l=p[node+':'+length]
        return point + l*np.array([math.cos(r),math.sin(r)])
    c=np.stack([a,handle(a,first,'86','87'),handle(b,second,'84','85'),b])
    t=np.linspace(0,1,25);u=1-t
    w=np.stack([u**3,3*u*u*t,3*u*t*t,t**3],axis=1)
    return transform(w@c,p,shape)

def world_sleep(d,p):
    return transform(sleep_outline(d,p),p,'0-14')

def normalized_difference(a,b,key):
    d=a-b
    return (d+180)%360-180 if key.endswith((':84',':86',':15')) else d

checks=[]
def check(name, passed, **details):
    checks.append(dict(name=name,passed=bool(passed),**details))

gaze={}
for name in ['Idle','Idle_QuietMedium']:
    plan=PATCH['patches'][name]
    bad=[]; outside=[]; max_radius=0.; minimum_height={d['name']:float('inf') for d in EYES}
    endpoint_error=0.
    for f in np.arange(0,plan['frames']+.01,.5):
        p=pose(name,f)
        for d in EYES:
            outline=eye_outline(d,p)
            if G['crosses'](outline):bad.append([float(f),d['name']])
            radius=float(np.linalg.norm(outline,axis=1).max());max_radius=max(max_radius,radius)
            if radius>184+1e-5:outside.append([float(f),d['name'],radius])
            minimum_height[d['name']]=min(minimum_height[d['name']],float(np.ptp(outline[:,1])))
    for f in [0,plan['frames']]:
        for d in EYES:
            endpoint_error=max(endpoint_error,float(np.linalg.norm(eye_outline(d,pose(name,f))-eye_outline(d,EX['neutral']),axis=1).max()))
    blink_keys=['0-25:21','0-29:21']
    unchanged=all(key not in plan['tracks'] for key in blink_keys)
    gaze[name]=dict(halfFramePoses=plan['frames']*2+1,selfIntersections=bad,outsideSphere=outside,
                    maximumLocalRadius=max_radius,endpointOutlineError=endpoint_error,
                    minimumProjectedHeight=minimum_height,originalBlinkHeightTracksUntouched=unchanged)
    check(name+' spherical eye topology',not bad and not outside,maximumRadius=max_radius)
    check(name+' neutral endpoints',endpoint_error<1e-6,maximumOutlineError=endpoint_error)
    check(name+' authored blink retained',unchanged and max(minimum_height.values())<12,
          minimumProjectedHeights=minimum_height)

preview_gaze=[]
for seg in EX['segments']:
    if seg['name'] not in ['Idle','Idle_QuietMedium']:continue
    bad=[];outside=[];maximum=0.
    for f in np.arange(seg['startFrame'],seg['endFrame']+.01,.5):
        p=pose('Preview_All',f)
        for d in EYES:
            if p['0-19:18']*p[d['shape']+':18']<=.001:continue
            q=eye_outline(d,p)
            if G['crosses'](q):bad.append([float(f),d['name']])
            radius=float(np.linalg.norm(q,axis=1).max());maximum=max(maximum,radius)
            if radius>184+1e-5:outside.append([float(f),d['name'],radius])
    preview_gaze.append(dict(segment=seg['name'],selfIntersections=bad,outsideSphere=outside,maximumLocalRadius=maximum))
    check('Preview_All '+seg['name']+' recompressed eye topology',not bad and not outside)

loops={}
for name,plan in PATCH['patches'].items():
    original=EX['plans'].get(name) or V6['plans'].get(name)
    if not original or not original.get('loop',False):continue
    a,b=pose(name,0),pose(name,plan['frames'])
    diffs={k:normalized_difference(a[k],b[k],k) for k in a if abs(normalized_difference(a[k],b[k],k))>1e-6}
    loops[name]=diffs
    check(name+' loop endpoints',not diffs,differenceCount=len(diffs))

joins=[]
for left,right in [('DozeEnter','Doze'),('Doze','Wake')]:
    a=pose(left,PATCH['patches'][left]['frames']);b=pose(right,0)
    errors={d[0]:float(np.linalg.norm(world_sleep(d,a)-world_sleep(d,b),axis=1).max()) for d in SLEEP}
    strokes={d[0]:abs(a[d[4]+':47']-b[d[4]+':47']) for d in SLEEP}
    alpha=abs(a['0-13091:18']-b['0-13091:18'])
    joins.append(dict(fromClip=left,toClip=right,worldOutlineErrors=errors,strokeErrors=strokes,alphaError=alpha))
    check(left+' -> '+right+' visible eyelid continuity',max([*errors.values(),*strokes.values(),alpha])<1e-6)

# These eyelids are single open cubic strokes. Verify x monotonicity in their
# local parent frame rather than testing an artificial closing edge.
sleep_geometry={}
for name in ['DozeEnter','Doze','Wake']:
    errors=[];maximum=0.
    for f in np.arange(0,PATCH['patches'][name]['frames']+.01,.5):
        p=pose(name,f)
        if p['0-13091:18']<=.001:continue
        for d in SLEEP:
            q=sleep_outline(d,p)
            if np.any(np.diff(q[:,0])<=0):errors.append([float(f),d[0],'nonmonotonic open eyelid'])
            radius=float(np.linalg.norm(q,axis=1).max())+p[d[4]+':47']/2*max(p[d[1]+':16'],p[d[1]+':17'])/100
            maximum=max(maximum,radius)
            if radius>184:errors.append([float(f),d[0],'eyelid outside sphere'])
    sleep_geometry[name]=dict(errors=errors,maximumLocalRadiusIncludingStroke=maximum)
    check(name+' visible eyelid geometry',not errors)

symbol_bounds={}; symbol_off=[]; symbol_leaks=[]
for name,plan in PATCH['patches'].items():
    if name not in ['Doze','Preview_All']:
        if any(v>.001 for _,v in plan['tracks'][GROUP+':18']):symbol_leaks.append(name)
check('sleep symbols hidden in every other clip',not symbol_leaks,leaks=symbol_leaks)
for name in ['Doze','Preview_All']:
    points=[];visible_frames=0
    for f in np.arange(0,PATCH['patches'][name]['frames']+.01,.5):
        p=pose(name,f)
        for z,half,stroke in SYMBOLS:
            if p[GROUP+':18']*p[z+':18']/100<=.001:continue
            visible_frames+=1
            extent=half+stroke/2
            q=np.array([[-extent,-extent],[extent,-extent],[extent,extent],[-extent,extent]])
            q=transform(transform(q,p,z),p,'0-14')
            points.extend(q.tolist())
            if np.any(q<0) or np.any(q>512):symbol_off.append([name,float(f),z,q.tolist()])
            if name=='Preview_All':
                seg=next((s for s in EX['segments'] if s['startFrame']<=f<s['endFrame']),None)
                if not seg or seg['name']!='Doze':symbol_leaks.append([name,float(f),z])
    q=np.array(points)
    symbol_bounds[name]=dict(visibleSymbolSamples=visible_frames,minimum=q.min(axis=0).tolist(),maximum=q.max(axis=0).tolist())
check('all visible Z glyphs including strokes fit 512 artboard',not symbol_off,outsideCount=len(symbol_off))
check('Preview_All symbols only during Doze',not symbol_leaks,leaks=symbol_leaks)
check('patch artifact unchanged during audit',PATCH_FILE.read_bytes()==patch_bytes)

out=dict(passed=all(c['passed'] for c in checks),sourceSHA256=hashlib.sha256(patch_bytes).hexdigest(),
         scope='Independent reconstruction of timeline-patches over the existing integrated poses; no Rive edits, App build, or rendering.',
         sampling='Half-frame poses; shared 24 samples/cubic for closed eyes, 25 samples/open eyelid cubic; transformed conservative Z stroke bounds.',
         staticGeometryEvidence='Root agent confirmed by live MCP: ExpressionEyes local transform identity; near endpoints ±24, far ±21; Z open four-point paths with half sizes 8/11/14, strokes 6/7/8, identity SleepSymbols child of CharacterRoot.',
         checks=checks,gaze=gaze,previewGaze=preview_gaze,loopEndpointDifferences=loops,sleepJoins=joins,sleepGeometry=sleep_geometry,
         symbolWorldBounds=symbol_bounds,symbolOutside=symbol_off,symbolVisibilityLeaks=symbol_leaks,
         limits=['Mathematical checks do not replace editor/runtime visual acceptance.','Sampling is finite and checks the authored linear simplified tracks; not a formal continuous-curve proof.'])
(HERE/'verification-geometry.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(dict(passed=out['passed'],checks=len(checks),failed=[c for c in checks if not c['passed']],symbolWorldBounds=symbol_bounds),indent=2))
