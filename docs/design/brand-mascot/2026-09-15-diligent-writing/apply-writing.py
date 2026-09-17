"""Apply the approved focused-writing pose to the four existing production timelines.

Requires a fresh full native backup and matching keyframe snapshot. No state-machine
or base-geometry edits. Run once; readback verifies exact scope and loop continuity.
"""
import json
import gzip
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / '2026-09-09-expression-system'))
from rive_client import call, anim

IDS = ['0-108', '0-1033', '0-1032', '0-1034']
assert call('open_file_editor', {'command': 'getCurrentFile'})['fileId'] == 2564580
assert (HERE / 'backups/before.rev').stat().st_size > 12_000_000
with gzip.open(HERE / 'backups/all-keyframes.json.gz', 'rt') as snapshot:
    before = json.load(snapshot)
machine = json.loads((HERE / 'backups/state-machine.json').read_text())
assert anim('queryStateMachine', {'stateMachineId': '0-7'}) == machine
assert anim('queryKeyFrames', {'animationIds': IDS})['keyframes'] == {i: before[i] for i in IDS}

# Local coordinates on the existing 512 artboard; body diameter remains 368.
layout = {
    ('0-44', 13): -100, ('0-44', 14): 22, ('0-44', 15): 16,
    ('0-50', 13): 70, ('0-50', 14): 35, ('0-50', 15): -6,
    ('0-48', 47): 16, ('0-54', 47): 16,
    ('0-37', 20): 108, ('0-37', 21): 108,
    ('0-41', 20): 100, ('0-41', 21): 100,
    ('0-23', 13): -132, ('0-23', 14): 128, ('0-23', 15): 0,
    ('0-40', 13): 108, ('0-40', 14): 148, ('0-40', 15): 0,
    ('0-33', 21): 178,
    ('0-65', 13): 57, ('0-65', 14): 75,
    ('0-69', 13): 64, ('0-69', 14): 93,
    ('0-96', 18): 0,
}
for left, right in [('0-46', '0-47'), ('0-52', '0-53')]:
    for obj, x in [(left, -32), (right, 32)]:
        layout[obj, 24] = x
        layout[obj, 85] = 64 / 3 if x > 0 else 0
        layout[obj, 87] = 64 / 3 if x < 0 else 0

# Three brief phrases: deliberate downstrokes, short pen lifts, then return.
# Seconds, horizontal travel, vertical pressure/lift, grip angle in degrees.
poses = [
    (0, 0, -3, 0), (.16, 0, -3, 0), (.27, 4, 4, 1.6),
    (.41, 13, -1, -1.4), (.53, 6, 5, 2.2), (.69, 22, 0, -1.6),
    (.83, 13, 4, 1.5), (1.00, 28, -1, -1.2),
    (1.12, 28, -6, -1.8), (1.29, 28, -6, -1.8),
    (1.41, 18, 5, 2), (1.58, 33, -1, -1.5),
    (1.72, 23, 4, 1.8), (1.89, 36, -1, -1.4),
    (2.03, 29, 5, 2.3), (2.19, 35, 0, -.8),
    (2.31, 35, -6, -1.6), (2.48, 35, -6, -1.6),
    (2.62, 24, 4, 1.8), (2.77, 33, -1, -1.1),
    (2.91, 23, 5, 2), (3.05, 30, 0, -.7),
    (3.18, 30, -6, -1), (3.44, 0, -3, 0), (3.6, 0, -3, 0),
]

def sample(t):
    for a, b in zip(poses, poses[1:]):
        if t <= b[0]:
            u = max(0, min(1, (t-a[0])/(b[0]-a[0])))
            u = u*u*u*(10+u*(-15+6*u))
            return tuple(a[j]+(b[j]-a[j])*u for j in range(1, 4))
    return poses[-1][1:]

changes = []
for aid, end in zip(IDS, [216, 240, 12, 12]):
    tracks = {key: [(0, value)] for key, value in layout.items()}
    if aid == '0-108':
        dynamic = [(o, p) for o, ps in [
            ('0-14', [14, 16, 17]), ('0-20', [16, 17]),
            ('0-22', [14, 16, 17]), ('0-23', [13, 14, 15]),
            ('0-40', [14, 15]),
        ] for p in ps]
        tracks.update({key: [] for key in dynamic})
        for f in range(end+1):
            t = f/60
            dx, dy, angle = sample(t)
            lag = sample(max(0, t-.05))[1]
            envelope = math.sin(math.pi*t/3.6)**2
            pressure = max(0, lag)/5
            follow = (pressure*3.6 + .5*math.sin(2*math.pi*t/3.6))*envelope
            sx = 1 + .004*pressure*envelope
            sy = 1 - .008*pressure*envelope
            values = [240+follow, sx*100, sy*100, 100/sx, 100/sy,
                      -follow/sy, 100/sx, 100/sy,
                      -132+dx, 128+dy, angle, 148+.8*pressure*envelope,
                      .35*pressure*envelope]
            for key, value in zip(dynamic, values):
                tracks[key].append((f, value))
    elif aid == '0-1033':
        tracks['0-23', 14] = [(0, 125), (end, 125)]
        # Slight relaxation during a pause, keeping the same attentive eye shape.
        tracks['0-44', 15] = [(0, 13), (end, 13)]
        tracks['0-50', 15] = [(0, -5), (end, -5)]
    else:
        tracks['0-23', 14] = [(0, 125), (end, 125)]
    selected = [k for k in before[aid] if (k['objectId'], k['propertyKey']) in tracks]
    adds = [dict(objectId=o, propertyKey=p, frame=f, value=v, interpolationType='linear')
            for (o, p), values in tracks.items() for f, v in values]
    anim('modifyKeyFrames', {'animationId': aid, 'delete': [k['keyframeId'] for k in selected]})
    for start in range(0, len(adds), 1000):
        anim('modifyKeyFrames', {'animationId': aid, 'add': adds[start:start+1000]})
    changes.append(dict(animation=aid, replaced=len(selected), added=len(adds)))

after = anim('queryKeyFrames', {'animationIds': list(before)})['keyframes']
assert set(after) == set(before)
for aid in before:
    if aid not in IDS:
        assert before[aid] == after[aid], aid
assert anim('queryStateMachine', {'stateMachineId': '0-7'}) == machine
assert anim('listLinearAnimations') == json.loads((HERE / 'backups/timelines.json').read_text())
for aid in IDS:
    assert all(k['value'] == 0 for k in after[aid] if (k['objectId'], k['propertyKey']) == ('0-96', 18))
for obj, prop in [('0-23', 13), ('0-23', 14), ('0-23', 15), ('0-14', 14), ('0-14', 16), ('0-14', 17)]:
    vs = sorted([k for k in after['0-108'] if (k['objectId'], k['propertyKey']) == (obj, prop)], key=lambda k: k['frame'])
    assert abs(vs[0]['value']-vs[-1]['value']) < 1e-9
(HERE / 'writing-after.json').write_text(json.dumps({i: after[i] for i in IDS}))
(HERE / 'verification.json').write_text(json.dumps(dict(changes=changes, unchangedAnimations=135,
    stateMachineUnchanged=True, timelineDurationsUnchanged=True, loopEndpointsMatch=True,
    scribbleHiddenInAllWritingPhases=True, nativeRendering='pending', deviceAcceptance='pending'), indent=2)+'\n')
print(json.dumps(changes), flush=True)
