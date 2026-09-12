import sys,json,hashlib,math
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim
old=json.loads((HERE/'backups/all-keyframes.json').read_text())
now={}
ids=list(old)
for off in range(0,len(ids),15):now.update(anim('queryKeyFrames',{'animationIds':ids[off:off+15]})['keyframes'])
def normalized(keys):return sorted(keys,key=lambda k:k['keyframeId'])
changed=[aid for aid in old if normalized(old[aid])!=normalized(now[aid])]
old_sm=json.loads((HERE/'backups/state-machine.json').read_text())
new_sm=anim('queryStateMachine',{'stateMachineId':'0-7'})
review_sm=anim('queryStateMachine',{'stateMachineId':'0-896281'})
(HERE/'review-state-machine.json').write_text(json.dumps(review_sm,indent=2)+'\n')
oldprops=json.loads((HERE/'backups/properties.json').read_text())
# Geometry values, rather than editor-only dependencies or current selection.
keys=[13,14,15,16,17,18,20,21,24,25,47,48,49,50,84,85,86,87]
query={o:[k for k in keys if str(k)in ps]for o,ps in oldprops.items()}
values=call('query_property_values',{'propertyKeys':query})['values']
geomdiff=[(o,k)for o in query for k in query[o]if values[o][str(k)]!=oldprops[o][str(k)]]
resource=HERE.parents[3]/'Together/Resources/BrandMascot/together_sphere_motion_study.riv'
asset_sha=hashlib.sha256(resource.read_bytes()).hexdigest()
motion=json.loads((HERE/'motion-samples.json').read_text())
maxstep=max(math.hypot(b['grip'][0]-a['grip'][0],b['grip'][1]-a['grip'][1])for a,b in zip(motion,motion[1:]))
result={'originalTimelinesCompared':len(old),'originalKeysCompared':sum(map(len,old.values())),'changedOriginalAnimations':changed,'productionStateMachineUnchanged':old_sm==new_sm,'baseGeometryDifferences':geomdiff,'appAssetSHA256':asset_sha,'appAssetUnchanged':asset_sha=='f271aa4f51dd5673f273463a6f29d1f1041f5944b214ed6d0f52a12509243691','reviewStates':[(s['stateName'],s.get('animationId'))for l in review_sm['layers']for s in l['states']if s['type']=='animation'],'cycleEndpointsEqual':motion[0]['grip']==motion[-1]['grip'] and abs(motion[-1]['bodyFollow'])<1e-9,'maxGripDistancePerFrameAt60fps':maxstep,'nativeFramesRendered':864,'staticReview':'A4 proportions and sampled hand/pen continuity checked; no clear visual P1/P2 found','browserPlayback':'All four video elements readyState 4, paused false; advancing playhead observed; normal and half-speed controls exercised','limits':['Motion aesthetics await user approval','No physical iPhone playback validation','No App resource replaced or installed','Browser checks do not establish device frame rate or energy use']}
assert not changed and old_sm==new_sm and not geomdiff and result['appAssetUnchanged'] and result['cycleEndpointsEqual'],result
(HERE/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
