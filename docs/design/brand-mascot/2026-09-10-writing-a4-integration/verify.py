import sys,json,math,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim
old=json.loads((HERE/'backups/all-keyframes.json').read_text());now={};ids=list(old)
for off in range(0,len(ids),15):now.update(anim('queryKeyFrames',{'animationIds':ids[off:off+15]})['keyframes'])
def norm(vs):return sorted(vs,key=lambda k:k['keyframeId'])
changed=[a for a in ids if norm(old[a])!=norm(now[a])]
assert set(changed)=={'0-108','0-1032','0-1033','0-1034'},changed
sm=anim('queryStateMachine',{'stateMachineId':'0-7'})
assert sm==json.loads((HERE/'backups/state-machine.json').read_text())
opac_checks=[]
for aid in changed:
 for o in ['0-19','0-20','0-22','0-32','0-65','0-69','0-96']:
  expected=sorted((round(k['frame']*.9)if aid=='0-108'else k['frame'],k['value'])for k in old[aid]if k['objectId']==o and k['propertyKey']==18)
  actual=sorted((k['frame'],k['value'])for k in now[aid]if k['objectId']==o and k['propertyKey']==18)
  assert expected==actual,(aid,o,expected,actual)
  opac_checks.append([aid,o])
def track(a,o,p):return sorted((k['frame'],k['value'])for k in now[a]if k['objectId']==o and k['propertyKey']==p)
def sample(vs,f):
 if f<=vs[0][0]:return vs[0][1]
 for (a,x),(b,y)in zip(vs,vs[1:]):
  if f<=b:return x+(y-x)*(f-a)/(b-a)
 return vs[-1][1]
errors=[]
for f in range(217):
 get=lambda a,o,p:sample(track(a,o,p),f)
 rx,ry=get('0-108','0-14',16)/100,get('0-108','0-14',17)/100
 follow=get('0-108','0-14',14)-240
 for p,r in [(16,rx),(17,ry)]:
  for group in ['0-20','0-22']:errors.append(abs(r*get('0-108',group,p)/100-1))
 errors.append(abs(follow-get('0-893641','0-15',14)))
 for o in ['0-23','0-40','0-96']:
  x=rx*(get('0-108','0-22',13)+get('0-108','0-22',16)/100*get('0-108',o,13))
  y=follow+ry*(get('0-108','0-22',14)+get('0-108','0-22',17)/100*get('0-108',o,14))
  errors.extend([abs(x-get('0-893641',o,13)),abs(y-get('0-893641',o,14))])
assert max(errors)<1e-8,max(errors)
# No newly introduced global face/body ownership in production Writing.
for aid in changed:assert not any(k['objectId']in ['0-15','0-452672','0-452670','0-452671','0-452673','0-452647','0-670901']for k in now[aid])
props=json.loads((HERE.parent/'2026-09-10-writing-a4-motion/backups/properties.json').read_text())
keys=[13,14,15,16,17,18,20,21,24,25,47,48,49,50,84,85,86,87]
qs={o:[p for p in keys if str(p)in d]for o,d in props.items()}
values=call('query_property_values',{'propertyKeys':qs})['values']
assert all(values[o][str(p)]==props[o][str(p)]for o in qs for p in qs[o])
result={'timelinesTotal':len(now),'changedTimelineIds':changed,'unchangedTimelines':len(now)-len(changed),'originalStateMachineUnchanged':True,'baseGeometryUnchanged':True,'preservedOpacityChannels':len(opac_checks),'approvedMotionWorldTransformSamples':217,'maxWorldTransformError':max(errors),'noGlobalBodyOrFaceMotionOwnershipAdded':True,'assetSHA256':hashlib.sha256((HERE/'deliverables/together_sphere_motion_study.riv').read_bytes()).hexdigest(),'assetBytes':(HERE/'deliverables/together_sphere_motion_study.riv').stat().st_size}
(HERE/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
