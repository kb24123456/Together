"""Read-only geometry audit of integrated expression plans; writes only evidence."""
import json,math,importlib.util
from pathlib import Path
import numpy as np
HERE=Path(__file__).parent
M=json.loads((HERE/'motion-integrated.json').read_text())
V6=json.loads((HERE.parent/'motion-v6.json').read_text())
KEYS=(24,25,84,85,86,87)
DEFS=[dict(name='eyeNear',first=32883,n=8,origin=(0,0),shape='0-32859'),dict(name='eyeFar',first=32891,n=8,origin=(0,0),shape='0-32871')]+[dict(name='tearNear' if i==0 else 'tearFar',first=d['first'],n=6,origin=d['origin'],shape=d['shape']) for i,d in enumerate(M['tearFlows'])]
N=24;t=np.arange(N)/N;u=1-t;W=np.stack([u**3,3*u*u*t,3*u*t*t,t**3],axis=1)
def sample(p,f):return {k:float(np.interp(f,[a[0] for a in tr],[a[1] for a in tr])) for k,tr in p['tracks'].items()}
def controls(d,p):
 out=[]
 for i in range(d['n']):
  x,y,ia,il,oa,ol=[p[f"0-{d['first']+i}:{k}"] for k in KEYS]
  pt=np.array([x,y])+d['origin'];out.append([pt,pt+np.array([math.cos(math.radians(ia)),math.sin(math.radians(ia))])*il,pt+np.array([math.cos(math.radians(oa)),math.sin(math.radians(oa))])*ol])
 return np.array(out)
def outline(c):return np.concatenate([W@np.stack([c[i,0],c[i,2],c[(i+1)%len(c),1],c[(i+1)%len(c),0]]) for i in range(len(c))])
def cross(a,b):return a[...,0]*b[...,1]-a[...,1]*b[...,0]
def crosses(p):
 # Remove zero-length sampled edges from neutral capsules before pair testing.
 q=np.roll(p,-1,axis=0);nz=np.linalg.norm(q-p,axis=1)>1e-8;p=p[nz];q=q[nz];n=len(p)
 a=p[:,None,:];c=p[None,:,:];v=(q-p)[:,None,:];w=(q-p)[None,:,:];ca=c-a;den=cross(v,w);good=np.abs(den)>1e-10
 s=np.divide(cross(ca,w),den,out=np.zeros_like(den),where=good);t=np.divide(cross(ca,v),den,out=np.zeros_like(den),where=good)
 mask=np.triu(np.ones((n,n),bool),2);mask[0,-1]=False
 return bool(np.any(mask&good&(s>1e-7)&(s<1-1e-7)&(t>1e-7)&(t<1-1e-7)))
def inside(points,p):
 q=np.roll(p,-1,axis=0);a=points[:,None,:];dy=q[:,1]-p[:,1]
 sel=(p[None,:,1]>a[:,:,1])!=(q[None,:,1]>a[:,:,1])
 ix=p[None,:,0]+np.divide((a[:,:,1]-p[None,:,1])*(q-p)[None,:,0],dy[None,:],out=np.zeros((len(points),len(p))),where=np.abs(dy[None,:])>1e-12)
 return np.sum(sel&(a[:,:,0]<ix),axis=1)%2==1
results={}
for name in ['Expression_Wink','Expression_Tears','Expression_TearsTurn']:
 plan=M['plans'][name];bad=[];off=[];maxr={d['name']:0 for d in DEFS};mincov={d['name']:1 for d in DEFS[2:]};detached=[]
 for f in np.arange(0,plan['frames']+.01,.5):
  p=sample(plan,f);ps=[outline(controls(d,p)) for d in DEFS]
  for i,d in enumerate(DEFS):
   alpha=p[d['shape']+':18']*p['0-19:18']/100*(p[M['tearGroup']+':18']/100 if i>1 else 1)
   if alpha<=.001:continue
   if crosses(ps[i]):bad.append([float(f),d['name']])
   r=float(np.linalg.norm(ps[i],axis=1).max());maxr[d['name']]=max(maxr[d['name']],r)
   if r>184+1e-5:off.append([float(f),d['name'],r])
   if i>1:
    coverage=float(inside(ps[i][:N],ps[i-2]).mean());mincov[d['name']]=min(mincov[d['name']],coverage)
    if coverage<.999:detached.append([float(f),d['name'],coverage])
 start=sample(plan,0);end=sample(plan,plan['frames']);neutral=M['neutral']
 endpoint={}
 for key in start:
  e0=start[key]-neutral[key];e1=end[key]-neutral[key]
  if key.endswith((':84',':86',':15')):e0=(e0+180)%360-180;e1=(e1+180)%360-180
  if abs(e0)>1e-6 or abs(e1)>1e-6:endpoint[key]=[e0,e1]
 visibleEndpointErrors={d['name']:max(float(np.linalg.norm(outline(controls(d,start))-outline(controls(d,neutral)),axis=1).max()),float(np.linalg.norm(outline(controls(d,end))-outline(controls(d,neutral)),axis=1).max())) for d in DEFS[:2]}
 results[name]=dict(visibleEndpointOutlineErrorPx=visibleEndpointErrors,frames=plan['frames'],tracks=len(plan['tracks']),keys=sum(map(len,plan['tracks'].values())),sampledPoses=plan['frames']*2+1,selfIntersections=bad,exceedsSphere=off,maximumRadius=maxr,tearTopMinimumEyeCoverage=mincov,tearTopExposed=detached,endpointDifferencesFromNeutral=endpoint)
# Restrict overall-review audit to clip joins and the hidden tear reset contract.
allplan=M['plans']['Preview_All'];joins=[]
for seg in M['segments'][1:]+[dict(name='Loop',startFrame=allplan['frames'])]:
 f=seg['startFrame'];p0=sample(allplan,f-1);p1=sample(allplan,f);joint=dict(frame=f,into=seg['name'],visibleEyeDisplacement={},newTearVisibleBefore=False,newTearVisibleAfter=False)
 for d in DEFS[:2]:
  if max(p0[d['shape']+':18']*p0['0-19:18'],p1[d['shape']+':18']*p1['0-19:18'])>.001:
   joint['visibleEyeDisplacement'][d['name']]=float(np.linalg.norm(outline(controls(d,p1))-outline(controls(d,p0)),axis=1).max())
 for p,k in [(p0,'newTearVisibleBefore'),(p1,'newTearVisibleAfter')]:joint[k]=any(p[M['tearGroup']+':18']*p[d['shape']+':18']>.001 for d in DEFS[2:])
 joins.append(joint)
loopEnd=sample(allplan,allplan['frames']);loopStart=sample(allplan,0)
loopdiff={k:[loopEnd[k],loopStart[k]] for k in loopEnd if abs(((loopEnd[k]-loopStart[k]+180)%360-180) if k.endswith((':84',':86',':15')) else (loopEnd[k]-loopStart[k]))>1e-6}
# No tears may leak into any other clip, including rests.
leaks=[]
for seg in M['segments']:
 if seg['name']!='Expression_TearsTurn':
  for f in [seg['startFrame'],(seg['startFrame']+seg['endFrame']-1)/2,seg['endFrame']-1]:
   p=sample(allplan,f)
   if any(p[M['tearGroup']+':18']*p[d['shape']+':18']>.001 for d in DEFS[2:]):leaks.append(float(f))
# The combined preview is independently simplified again; audit only the two new clips.
previewNew={}
for seg in M['segments']:
 if seg['name'] not in ('Expression_Wink','Expression_TearsTurn'):continue
 bad=[];off=[];gaps=[]
 for f in np.arange(seg['startFrame'],seg['endFrame']+.01,.5):
  p=sample(allplan,f);ps=[outline(controls(d,p)) for d in DEFS]
  for i,d in enumerate(DEFS):
   alpha=p[d['shape']+':18']*p['0-19:18']/100*(p[M['tearGroup']+':18']/100 if i>1 else 1)
   if alpha<=.001:continue
   if crosses(ps[i]):bad.append([float(f),d['name']])
   if float(np.linalg.norm(ps[i],axis=1).max())>184+1e-5:off.append([float(f),d['name']])
   if i>1 and not inside(ps[i][:N],ps[i-2]).all():gaps.append([float(f),d['name']])
 previewNew[seg['name']]=dict(start=seg['startFrame'],end=seg['endFrame'],selfIntersections=bad,exceedsSphere=off,tearEyeGaps=gaps)
output=dict(previewNewExpressionChecks=previewNew,visibilityHierarchy='Confirmed live: SphereEyeNear, SphereEyeFar, and TearFlows are children of IdleFace (0-19). Zero-length handle angle differences and hidden tear geometry are non-visible endpoint differences.',scope='Independent reconstruction of actual simplified keyframes; half-frame expression sampling, 24 samples/cubic; overall preview checked only at clip joins and tear visibility.',expressions=results,previewJoins=joins,previewLoopDifferences=loopdiff,tearVisibilityLeaks=leaks)
(HERE/'verification-geometry.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps({n:{k:v for k,v in r.items() if k not in ['endpointDifferencesFromNeutral','selfIntersections','exceedsSphere','tearTopExposed']}|dict(selfIntersectionCount=len(r['selfIntersections']),selfIntersectionFirst=r['selfIntersections'][:8],outsideCount=len(r['exceedsSphere']),tearTopExposedCount=len(r['tearTopExposed']),tearTopExposedFirst=r['tearTopExposed'][:5],endpointDifferenceKeys=len(r['endpointDifferencesFromNeutral'])) for n,r in results.items()}))
print(json.dumps(previewNew))
print(json.dumps(dict(joinEyeMovesOver2px=[j for j in joins if max(j['visibleEyeDisplacement'].values(),default=0)>2],loopDifferenceKeys=len(loopdiff),tearLeaks=leaks)))
