#!/usr/bin/env python3
"""Bake Together mascot production timelines to a complete, deterministic v6 pose schema.
Only reads versioned design sources and writes the selected local JSON output.
No Rive editor or application mutations are performed.
"""
import argparse, bisect, copy, hashlib, importlib.util, json, math
from pathlib import Path
P=argparse.ArgumentParser();P.add_argument('--source-dir',type=Path,default=Path(__file__).resolve().parent);P.add_argument('--output',type=Path,default=Path('/tmp/mascot-v6-motion.json'));args=P.parse_args()
v3=json.loads((args.source_dir/'motion-v3.json').read_text());v5=json.loads((args.source_dir/'motion-v5-study.json').read_text())
spec=importlib.util.spec_from_file_location('sphere_eye_projection',args.source_dir/'sphere-eye-projection.py');H=importlib.util.module_from_spec(spec);spec.loader.exec_module(H)
neutral=copy.deepcopy(v5['neutral']);rig=v5['sphereEyeRig'];SCHEMA=set(neutral);OPACITY_GROUPS=['0-19:18','0-20:18','0-21:18','0-13091:18'];BASEKEYS=set(v3['plans']['Idle']['tracks'])
SURFACE_IDS={vid for eye in rig.values() for vid in eye['vertices']}

def ease(t):
 if t<=0:return 0.
 if t>=1:return 1.
 lo,hi=0.,1.
 for _ in range(30):
  u=(lo+hi)/2;x=3*(1-u)**2*u*.35+3*(1-u)*u*u*.65+u**3
  if x<t:lo=u
  else:hi=u
 u=(lo+hi)/2;return 3*(1-u)*u*u+u**3

def sample(vs,f,cubic=False):
 if f<=vs[0][0]:return vs[0][1]
 i=bisect.bisect_right([x[0] for x in vs],f)-1
 if i>=len(vs)-1:return vs[-1][1]
 a,x=vs[i];b,y=vs[i+1];t=(f-a)/(b-a)
 return x+(y-x)*(ease(t) if cubic else t)

def values(plan,f,cubic=False):return {k:sample(v,f,cubic) for k,v in plan['tracks'].items()}
def project(p):
 p=dict(p);p['0-24:18']=p['0-28:18']=0
 for eye,path,name,bw in [('0-24','0-25','SphereEyeNear',30),('0-28','0-29','SphereEyeFar',24)]:
  r=rig[name];p[r['shape']+':18']=100
  verts=H.project_eye(p[eye+':13'],p[eye+':14'],bw*p[eye+':16']/100,p[path+':21'],p[eye+':15'])
  for vid,props in zip(r['vertices'],H.as_rive_properties(verts)):p.update({vid+':'+k:v for k,v in props.items()})
 return p

def gaze(p,yaw=.15,pitch=.2,blink=0):
 theta=math.asin(78/184)*yaw
 for eye,path,arc,s,bw in [('0-24','0-25','0-13104',-1,30),('0-28','0-29','0-13110',1,24)]:
  x=184*math.sin(theta)+s*44*math.cos(theta);y=-27-46*pitch-5*s*yaw*pitch
  width=30*math.cos(theta)*(1-.13*s*yaw);height=84*(1-.065*s*yaw)*(1-.027*yaw*yaw);r=-(22+2*s)*yaw*pitch
  p.update({eye+':13':x,eye+':14':y,eye+':15':r,eye+':16':100*width/bw,eye+':17':100,path+':21':height*(1-.91*blink),arc+':13':x,arc+':14':y+7,arc+':15':r,arc+':16':100*(50*width/30)/(48 if s==-1 else 42),arc+':17':100*(1-.04*s*yaw)})
 return project(p)

def original3(name,f):
 p=dict(neutral);p.update(values(v3['plans'][name],f,True))
 # Existing approved WritingFace/SweatingFace paths and positions are retained.
 # Only the legacy Idle capsules are reprojected from the shared v5 facing.
 h=p['0-25:21'];b=max(0,min(1,(1-h/86)/.92))
 return gaze(p,blink=b)

def look(f):
 p=dict(neutral)
 yaw=sample([[0,.15],[8,.15],[28,-.58],[59,-.58],[90,.15],[96,.15]],f,True)
 pitch=sample([[0,.2],[8,.2],[28,.1],[59,.1],[90,.2],[96,.2]],f,True)
 p['0-14:15']=sample([[0,0],[8,0],[30,-.8],[60,-.8],[92,0],[96,0]],f,True)
 p['0-14:16']=p['0-14:17']=sample([[0,100],[38,100.35],[82,100],[96,100]],f,True)
 return gaze(p,yaw,pitch)

def reduce(points,tol):
 def rec(a,b):
  if b-a<=1:return [a,b]
  f0,v0=points[a];f1,v1=points[b]
  err,i=max((abs(points[i][1]-(v0+(v1-v0)*(points[i][0]-f0)/(f1-f0))),i) for i in range(a+1,b))
  return [a,b] if err<=tol else rec(a,i)[:-1]+rec(i,b)
 return [points[i] for i in rec(0,len(points)-1)]

def compile_clip(name,poses,loop=False,boundaries=()):
 end=len(poses)-1;tracks={};boundary={0,end,*boundaries}
 for pose in poses:
  assert set(pose)==SCHEMA,(name,len(pose),set(pose)-SCHEMA,SCHEMA-set(pose))
  assert all(math.isfinite(x) for x in pose.values()),name
 for k in neutral:
  tol=.20 if k.split(':')[0] in SURFACE_IDS else .035
  knots={int(f) for f,_ in reduce([[f,p[k]] for f,p in enumerate(poses)],tol)}|boundary
  # Keep opacity zero/visible boundaries exact; the spherical eye pair uses one
  # shared geometry but no old/new or open/expression visibility overlap.
  if k.endswith(':18'):
   for f in range(end):
    if (abs(poses[f][k])<1e-10)!=(abs(poses[f+1][k])<1e-10):knots.update([f,f+1])
  tracks[k]=[[f,poses[f][k]] for f in sorted(knots)]
 for eye in rig.values():
  for i,j in [(0,1),(2,3),(4,5),(6,7)]:
   keys=[eye['vertices'][n]+':'+prop for n in [i,j] for prop in ['24','25']]
   times=sorted({f for k in keys for f,_ in tracks[k]})
   for k in keys:tracks[k]=[[f,poses[f][k]] for f in times]
  for vid in eye['vertices']:
   for prop in ['85','87']:
    k=vid+':'+prop;times={f for f,_ in tracks[k]}
    for f in range(end):
     if (abs(poses[f][k])<1e-10)!=(abs(poses[f+1][k])<1e-10):times.update([f,f+1])
    tracks[k]=[[f,poses[f][k]] for f in sorted(times)]
 return dict(name=name,frames=end,loop=loop,interpolation='linear',tracks=tracks)

poses={};plans={}
for name,a in v3['plans'].items():
 if name=='Preview':continue
 poses[name]=[look(f) if name=='Idle_Look' else dict(neutral) if name=='Idle_Select' else original3(name,f) for f in range(a['frames']+1)]

# The neutral input/output is a full pose, including hidden props, so interrupted
# clips cannot leak eye/hand state into the next action. The first three frames
# of eye-group routing retain the source expression for 50 ms state blending.
for name in ['Idle','Idle_QuietShort','Idle_QuietMedium','Idle_Look','Acknowledge']:
 poses[name][0]=dict(neutral);poses[name][-1]=dict(neutral)
for name in ['WritingEnter','ConcernEnter']:
 poses[name][0]=dict(neutral)
 target=poses['Writing'][0] if name=='WritingEnter' else poses['Concerned'][0]
 poses[name][-1]=dict(target)
for name in ['WritingExit','Recover']:
 poses[name][-1]=dict(neutral)
# The 50 ms state blend fades the source drop from its current alpha. Keep
# the target drop hidden so an already absent drop cannot reappear on recovery.
for f,p in enumerate(poses['Recover']):
 p['0-89:18']=0
 if f==0:p['0-89:14']=poses['Concerned'][0]['0-89:14']
poses['Recover'][0]=dict(poses['Concerned'][0]);poses['Recover'][0]['0-89:18']=0;poses['Recover'][-1]=dict(neutral)

for name in ['Idle_Orient','Thinking','Celebrate','Remind','Doze','Wake']:
 a=v5['plans'][name];poses[name]=[values(a,f) for f in range(a['frames']+1)]
for name,a in v5['bridges'].items():poses[name]=[values(a,f) for f in range(a['frames']+1)]
# Reset only invisible geometry at action boundaries; maintain all visible
# authored motion from v5. Opening poses of the three bridges match the routed
# source state exactly. Endpoints match their destination's complete pose.
for name in ['Celebrate','Remind']:
 poses[name][0]=dict(neutral);poses[name][-1]=dict(neutral)
poses['ThinkingEnter'][0]=dict(neutral);poses['ThinkingEnter'][-1]=dict(poses['Thinking'][0])
poses['ThinkingExit'][0]=dict(poses['Thinking'][0]);poses['ThinkingExit'][-1]=dict(neutral)
poses['DozeEnter'][0]=dict(neutral);poses['DozeEnter'][-1]=dict(poses['Doze'][0])
poses['Wake'][0]=dict(poses['Doze'][0]);poses['Wake'][-1]=dict(neutral)
# This is a one-shot, not a new persistent condition. A real completion while
# concerned first recovers the sweat face, then plays the same quiet celebration.
poses['CelebrateConcern']=poses['Recover'][:-1]+poses['Celebrate']
# Internal interruption bridge: during the 50 ms state blend the source eye
# group fades to zero. Once blending is finished, only the common IdleFace
# reopens. This is deliberately a brief blink, not an extra mascot behavior.
poses['Settle']=[]
for f in range(13):
 p=dict(neutral)
 for k in OPACITY_GROUPS:p[k]=0
 p['0-19:18']=sample([[0,0],[3,0],[4,0],[9,100],[12,100]],f,True)
 p['0-22:18']=p['0-13090:18']=0
 poses['Settle'].append(p)

for name,pp in poses.items():
 src=v3['plans'].get(name) or v5['plans'].get(name) or v5['bridges'].get(name)
 loop=src.get('loop',False) if src else False
 if loop:pp[-1]=dict(pp[0])
 bounds={0,len(pp)-1}
 if name=='CelebrateConcern':bounds.add(12)
 plans[name]=compile_clip(name,pp,loop,bounds)

# Validation is independent of the Rive editor: all poses are deterministic,
# but runtime transitions, live playback and exported asset cost remain external.
checks={'allTrackCounts184':all(len(a['tracks'])==184 for a in plans.values()),'allFinite':True,'eyeGroupOverlaps':[],'loopEndpointMismatches':[],'handoffEndpointMismatches':[],'firstThreeFrameSourceGroups':{},'unchangedHistoricalTimelines':['Preview','Preview_Behaviors_v5'],'sourcePoseCount':sum(len(p) for p in poses.values())}
for name,a in plans.items():
 for f in range(a['frames']*4+1):
  p=values(a,f/4)
  visible=[k for k in OPACITY_GROUPS if p[k]>.000001]
  if len(visible)>1:checks['eyeGroupOverlaps'].append([name,f/4,visible]);break
  assert p['0-24:18']==p['0-28:18']==0
 if a['loop']:
  mismatch=[k for k,v in a['tracks'].items() if abs(v[0][1]-v[-1][1])>1e-8]
  if mismatch:checks['loopEndpointMismatches'].append([name,mismatch])
pairs=[('WritingEnter','Writing'),('ConcernEnter','Concerned'),('WritingExit','Idle'),('Recover','Idle'),('ThinkingEnter','Thinking'),('ThinkingExit','Idle'),('DozeEnter','Doze'),('Doze','Wake'),('Wake','Idle'),('Celebrate','Idle'),('Remind','Idle'),('Acknowledge','Idle'),('CelebrateConcern','Idle'),('Settle','Idle')]
for a,b in pairs:
 mismatch=[k for k in neutral if abs(poses[a][-1][k]-poses[b][0][k])>1e-8]
 if mismatch:checks['handoffEndpointMismatches'].append([a,b,mismatch])
sourcegroups={'WritingEnter':'0-19:18','ConcernEnter':'0-19:18','WritingExit':'0-20:18','Recover':'0-21:18','Celebrate':'0-19:18','Remind':'0-19:18','Acknowledge':'0-19:18','ThinkingEnter':'0-19:18','ThinkingExit':'0-19:18','DozeEnter':'0-19:18','Wake':'0-13091:18','CelebrateConcern':'0-21:18'}
for name,key in sourcegroups.items():
 checks['firstThreeFrameSourceGroups'][name]=all(abs(values(plans[name],f/4)[key]-100)<1e-8 for f in range(13))
checks['settleFirstThreeFramesInvisible']=all(all(values(plans['Settle'],f/4)[k]==0 for k in OPACITY_GROUPS+['0-22:18','0-13090:18']) for f in range(13))
checks['settleFinalFourFramesNeutral']=all(all(abs(values(plans['Settle'],f/4)[k]-neutral[k])<1e-8 for k in neutral) for f in range(36,49))
checks['passed']=checks['settleFirstThreeFramesInvisible'] and checks['settleFinalFourFramesNeutral'] and checks['allTrackCounts184'] and not checks['eyeGroupOverlaps'] and not checks['loopEndpointMismatches'] and not checks['handoffEndpointMismatches'] and all(checks['firstThreeFrameSourceGroups'].values())
ids={**{k:v for k,v in v3['animationIds'].items() if k!='Preview'},**{k:v for k,v in v5['ids'].items() if k!='Preview_Behaviors_v5'}}
result=dict(fileId=v5['fileId'],artboardId=v5['artboardId'],fps=60,phase='v6 production timeline unification; state routes authored separately',ids=ids,plans=plans,neutral=neutral,sphereEyeRig=rig,fixedGroups=v5['fixedGroups'],rig=v5['rig'],checks=checks,notes=['184 keyed properties on every production clip; linear sampled interpolation with 0.035 pose and 0.20 surface tolerances.','Default facing inherits v5 neutral yaw .15/pitch .2; the eye center is near the upper middle of the ball, not the previous upper-right corner.','Idle_Look is a restrained 96-frame glance left and return; Idle_Orient is retained as a non-resident demonstration clip.','WritingFace/SweatingFace shapes and positions are unchanged; the new spherical path only replaces IdleFace rectangle eyes.','New ThinkingEnter/ThinkingExit/DozeEnter reuse v5 preview bridges as standalone timelines.','CelebrateConcern contains 12-frame Recover plus 84-frame Celebrate with a single shared join frame.','Settle is an internal 12-frame cancellation bridge: all face groups are hidden through frame 4; IdleFace fades up during frames 4 through 9 and holds neutral through frame 12. Route interrupted clips to Settle with a 50 ms blend, then use the next mode entry after completion.','Historical Preview and Preview_Behaviors_v5 are intentionally excluded from mutations.','Not a runtime performance or live transition visual acceptance report.'])
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'output':str(args.output),'sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),'checks':checks,'clips':{n:{'frames':a['frames'],'tracks':len(a['tracks']),'keys':sum(map(len,a['tracks'].values()))} for n,a in plans.items()},'totalKeys':sum(sum(map(len,a['tracks'].values())) for a in plans.values())},ensure_ascii=False,indent=2))
if not checks['passed']:raise SystemExit('v6 pose validation failed')
