"""Update only the eye paths and horizontal placement of confirmed closed-eye presets."""
import sys, importlib.util, hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from rive_client import anim, cmd
from design import pose, R, PRESETS
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('before_spacing', HERE/'backups/design.py')
old = importlib.util.module_from_spec(spec); spec.loader.exec_module(old)
manifest = json.loads((ROOT/'authored.json').read_text())
indices = [int(i) for i in sys.argv[1].split(',')]
assert indices and set(indices).issubset({2,3,16,17,18,26,28})
eyes = {R[n]['id'] for n in ['ExpressionEyeLeft','ExpressionEyeRight']}
vertices = {v for n in ['ExpressionEyeLeft','ExpressionEyeRight'] for v in R[n]['vertices']}
def target(k):
    return k['objectId'] in vertices or (k['objectId'] in eyes and k['propertyKey'] == 13)
def key(k): return k['objectId']+':'+str(k['propertyKey'])
def save(name, value): (HERE/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
sm = anim('queryStateMachine', {'stateMachineId':'0-7'})
if not (HERE/'backups/state-machine.json').exists(): save('backups/state-machine.json',sm)
if not (HERE/'backups/viewmodels.json').exists(): save('backups/viewmodels.json',cmd('viewmodel_editor','listViewModels'))
report=[]

def modify(name, index_at_frame):
    aid=manifest['timelines'][name]['id']
    before=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
    backup=HERE/'backups'/('before-keyframes-'+aid+'.json')
    if not backup.exists(): backup.write_text(json.dumps(before))
    changes=[]
    for k in before:
        i=index_at_frame(k['frame'])
        if i not in indices or not target(k): continue
        prop=key(k); previous=old.pose(i)[prop]; current=pose(i)[prop]
        if abs(previous-current)<1e-8: continue
        # Preserve unexpected user changes rather than overwriting them silently.
        assert abs(k['value']-previous)<1e-6 or abs(k['value']-current)<1e-6,(name,prop,k['frame'],k['value'],previous)
        if abs(k['value']-current)>1e-8:
            changes.append({'keyframeId':k['keyframeId'],'value':current})
    for off in range(0,len(changes),1500):
        anim('modifyKeyFrames',{'animationId':aid,'change':changes[off:off+1500]})
    after=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
    b={k['keyframeId']:k for k in before};a={k['keyframeId']:k for k in after}
    assert a.keys()==b.keys()
    changed={c['keyframeId']:c['value'] for c in changes}
    for kid in a:
        expected=dict(b[kid]);expected.update({'value':changed[kid]} if kid in changed else {})
        actual=dict(a[kid])
        if kid in changed:
            assert abs(actual['value']-expected['value'])<1e-6,(name,kid,'value readback')
            actual['value']=expected['value']
        assert actual==expected,(name,kid,'unexpected keyframe difference')
    report.append({'animation':name,'animationId':aid,'changedKeys':len(changes),'otherKeysUnchanged':True,'readback':True})
    print(name,len(changes),'read back',flush=True)

for i in indices:
    name=next(x[1] for x in PRESETS if x[0]==i)
    for prefix in ['Expr_','Expr_Close_','Expr_Pulse_']:
        modify(prefix+name,lambda frame,i=i:i)
modify('Preview_Expressions_28',lambda frame:min(28,int(frame)//108+1))
if 2 in indices:
    modify('Preview_LightActions_4',lambda frame:2 if 93<=frame<279 else 1)
assert sm==anim('queryStateMachine',{'stateMachineId':'0-7'})
save('readback-'+sys.argv[1].replace(',','-')+'.json',{'indices':indices,'stateMachineUnchanged':True,'animations':report})
print('batch verified',sum(x['changedKeys'] for x in report))
