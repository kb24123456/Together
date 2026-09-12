"""Increase only production Writing grip motion around its approved rest pose."""
import json, sys, shutil, hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE.parent / '2026-09-09-expression-system'))
from rive_client import call, anim

assert call('open_file_editor', {'command': 'getCurrentFile'})['fileId'] == 2564580
native = Path('/Users/papertiger/Library/Containers/app.rive.editor/Data/Documents/writing-amplitude-20260910/before/together_sphere_motion_study.rev')
assert native.stat().st_size > 12000000
backup = HERE / 'backups'
shutil.copy2(native, backup / 'before-amplitude.rev')
shutil.copy2(ROOT / 'Together/Resources/BrandMascot/together_sphere_motion_study.riv', backup / 'app-before.riv')
before = json.loads((backup / 'writing-keyframes.json').read_text())
live = anim('queryKeyFrames', {'animationIds': ['0-108']})['keyframes']['0-108']
assert live == before, 'Live Writing changed after snapshot; inspect before editing.'
machine = anim('queryStateMachine', {'stateMachineId': '0-7'})
(backup / 'state-machine.json').write_text(json.dumps(machine, indent=2))

factors = {13: (-122, 2.4), 14: (132, 2.2), 15: (0, 3)}
selected = [k for k in before if k['objectId'] == '0-23' and k['propertyKey'] in factors]
assert len(selected) == 651
adds = []
for k in selected:
    base, factor = factors[k['propertyKey']]
    adds.append(dict(objectId=k['objectId'], propertyKey=k['propertyKey'], frame=k['frame'],
                     value=base + (k['value'] - base) * factor,
                     interpolationType=k['interpolationType']))
anim('modifyKeyFrames', {'animationId': '0-108', 'delete': [k['keyframeId'] for k in selected]})
anim('modifyKeyFrames', {'animationId': '0-108', 'add': adds})
after = anim('queryKeyFrames', {'animationIds': ['0-108']})['keyframes']['0-108']
(HERE / 'writing-after.json').write_text(json.dumps(after, indent=2))
def untouched(keys):
    return sorted((k for k in keys if not (k['objectId'] == '0-23' and k['propertyKey'] in factors)), key=lambda k: k['keyframeId'])
assert untouched(before) == untouched(after)
assert anim('queryStateMachine', {'stateMachineId': '0-7'}) == machine
ranges = {}
for prop, (base, factor) in factors.items():
    track = sorted((k for k in after if k['objectId'] == '0-23' and k['propertyKey'] == prop), key=lambda k: k['frame'])
    assert len(track) == 217 and track[0]['value'] == track[-1]['value'] == base
    expected = {(k['frame'], k['propertyKey']): k['value'] for k in adds}
    assert all(abs(k['value'] - expected[k['frame'], prop]) < 1e-8 for k in track)
    ranges[prop] = dict(min=min(k['value'] for k in track), max=max(k['value'] for k in track), factor=factor)
result = dict(changedAnimation='Writing', animationId='0-108', changedObject='Grip',
              changedKeys=651, unchangedKeys=len(untouched(before)), stateMachineUnchanged=True,
              loopEndpointsUnchanged=True, factors=ranges, durationSeconds=3.6,
              priorResourceSHA256=hashlib.sha256((backup / 'app-before.riv').read_bytes()).hexdigest())
(HERE / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
