"""Add only the approved, additive result glance to the live V1 project.

Run after backups are captured. No existing keyframe, transition, or property
is rewritten. The FaceMotion parent preserves the live sphere-facing gaze.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / '2026-09-09-expression-system'))
from rive_client import call, anim, props, cmd

assert call('open_file_editor', {'command': 'getCurrentFile'})['fileId'] == 2564580
assert (HERE / 'backups/before-continuity.rev').stat().st_size > 12_000_000
assert hashlib.sha256((HERE / 'backups/app-before.riv').read_bytes()).hexdigest() == '8dfea4c3f2655a5de53f4ac8b7777d16d82647d6ea527d49d0a9ad7b3c75d924'
before = json.loads((HERE / 'backups/state-machine.json').read_text())
assert anim('queryStateMachine', {'stateMachineId': '0-7'}) == before
assert before['stateMachineName'] == 'Mascot'
models = call('viewmodel_editor', {'command': 'listViewModels'})
assert models == json.loads((HERE / 'backups/viewmodels.json').read_text())
model = next(m for m in models['viewModels'] if m['name'] == 'TogetherSphereModel')
assert not any(p['name'] == 'noticeResult' for p in model['viewModelProperties'])
assert not any(a['name'] == 'Action_NoticeResult' for a in anim('listLinearAnimations')['linearAnimations'])

cmd('viewmodel_editor', 'addProperties', {'viewModels': [dict(
    viewModelId=model['id'], viewModelProperties=[dict(name='noticeResult', propertyType='trigger')])]})
models = call('viewmodel_editor', {'command': 'listViewModels'})
trigger = next(p['id'] for m in models['viewModels'] if m['id'] == model['id']
               for p in m['viewModelProperties'] if p['name'] == 'noticeResult')
anim('createLinearAnimations', {'linearAnimations': [dict(name='Action_NoticeResult', duration=0.9)]})
timeline = next(a['id'] for a in anim('listLinearAnimations')['linearAnimations'] if a['name'] == 'Action_NoticeResult')
props({timeline: {'59': 0}})

# Keep the rest pose of the existing action layer, including its body guards.
# Only these two parent offsets vary; no eye shape, expression, blink, or body
# motion is replaced. Minimum-jerk curves meet the hold/rest with zero velocity.
rest = anim('queryKeyFrames', {'animationIds': ['0-457437']})['keyframes']['0-457437']
keys = [dict(objectId=k['objectId'], propertyKey=k['propertyKey'], frame=0,
             value=k['value'], interpolationType='linear') for k in rest
        if (k['objectId'], k['propertyKey']) not in [('0-452672', 13), ('0-452672', 14)]]
def ease(t):
    return t*t*t*(10 + t*(-15 + 6*t))
for frame in range(55):
    weight = ease(frame/18) if frame < 18 else 1 if frame <= 29 else 1-ease((frame-29)/25)
    for prop, target in [(13, -14), (14, 30)]:
        keys.append(dict(objectId='0-452672', propertyKey=prop, frame=frame,
                         value=target*weight, interpolationType='linear'))
anim('modifyKeyFrames', dict(animationId=timeline, add=keys))
layer = next(l for l in before['layers'] if l['layerName'] == 'LightActions')
anim('createStates', dict(layerId=layer['layerId'], states=[dict(name='Action_NoticeResult',
    linearAnimationName='Action_NoticeResult', x=670, y=210)]))
machine = anim('queryStateMachine', {'stateMachineId': '0-7'})
state = next(s['id'] for l in machine['layers'] for s in l['states'] if s['name'] == 'Action_NoticeResult')
rest_state = next(s['id'] for s in layer['states'] if s['name'] == 'Action_Rest')
def condition(prop, value=None, operation='equal'):
    result = dict(leftComparator=dict(viewModelPropertyId=prop))
    if value is not None:
        result.update(operation=operation, rightComparator=dict(valueType='constantValueType', value=value))
    return result
# A duplicated destination is deliberate: Rive joins a transition's conditions
# with AND, so separate routes admit idle OR concerned without changing modes.
edges = [dict(source=layer['anyStateId'], target=state, duration=100,
              conditions=[condition(trigger), condition('0-377', mode)]) for mode in [0, 2]]
edges += [dict(source=state, target=rest_state, duration=70, end=True, conditions=[]),
          dict(source=state, target=rest_state, duration=100,
               conditions=[condition('0-377', 0, 'notEqual'), condition('0-377', 2, 'notEqual')])]
created = []
for edge in edges:
    existing = {t['id'] for l in anim('queryStateMachine', {'stateMachineId': '0-7'})['layers'] for t in l['transitions']}
    anim('createTransitions', {'states': [dict(id=edge['source'], transitions=[dict(to=edge['target'])])]})
    now = anim('queryStateMachine', {'stateMachineId': '0-7'})
    new = [t for l in now['layers'] for t in l['transitions'] if t['id'] not in existing]
    assert len(new) == 1
    tid = new[0]['id']
    props({tid: {'158': edge['duration'], '152': 28 if edge.get('end') else 0,
                 '160': 100 if edge.get('end') else 0}})
    if edge['conditions']:
        anim('createConditions', {'transitions': [dict(id=tid, conditions=edge['conditions'])]})
    created.append(dict(edge, id=tid))
manifest = dict(fileId=2564580, artboard='TogetherSphere', stateMachine='Mascot',
                viewModel='TogetherSphereModel', trigger='noticeResult', triggerId=trigger,
                animationId=timeline, stateId=state, layerId=layer['layerId'],
                durationSeconds=0.9, fps=60, keyCount=len(keys),
                targetOffset=dict(x=-14, y=30), entryFrames=18, holdEndFrame=29,
                endFrame=54, allowedModes=[0,2], interruptions='mode other than 0 or 2',
                edges=created)
(HERE / 'result-glance.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(manifest, indent=2))
