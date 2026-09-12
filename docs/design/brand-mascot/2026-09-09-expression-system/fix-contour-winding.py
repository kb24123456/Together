"""Repair only three new eye contours, preserving every other keyed property."""
from rive_client import *
from design import *

m = json.loads((HERE / 'authored.json').read_text())
targets = [15, 19, 23]
vertices = set(R['ExpressionEyeLeft']['vertices'] + R['ExpressionEyeRight']['vertices'])
poses = {i: pose(i) for i in targets}
report = []
for i in targets:
    name = next(p[1] for p in PRESETS if p[0] == i)
    for prefix in ['Expr_', 'Expr_Close_', 'Expr_Pulse_']:
        aid = m['timelines'][prefix + name]['id']
        before = anim('queryKeyFrames', {'animationIds': [aid]})['keyframes'][aid]
        changes = []
        for k in before:
            if k['objectId'] in vertices:
                changes.append(dict(keyframeId=k['keyframeId'], value=poses[i][k['objectId'] + ':' + str(k['propertyKey'])]))
        anim('modifyKeyFrames', {'animationId': aid, 'change': changes})
        after = anim('queryKeyFrames', {'animationIds': [aid]})['keyframes'][aid]
        assert len(before) == len(after)
        expected = {c['keyframeId']: c['value'] for c in changes}
        assert all(abs(k['value'] - expected[k['keyframeId']]) < 1e-7 for k in after if k['keyframeId'] in expected)
        report.append(dict(animation=prefix+name, changed=len(changes), readback=True))

aid = m['timelines']['Preview_Expressions_28']['id']
before = anim('queryKeyFrames', {'animationIds': [aid]})['keyframes'][aid]
changes = []
for k in before:
    i = min(28, int(k['frame']) // 108 + 1)
    if i in targets and k['objectId'] in vertices:
        changes.append(dict(keyframeId=k['keyframeId'], value=poses[i][k['objectId'] + ':' + str(k['propertyKey'])]))
for offset in range(0, len(changes), 1500):
    anim('modifyKeyFrames', {'animationId': aid, 'change': changes[offset:offset+1500]})
after = anim('queryKeyFrames', {'animationIds': [aid]})['keyframes'][aid]
expected = {c['keyframeId']: c['value'] for c in changes}
assert len(before) == len(after)
assert all(abs(k['value'] - expected[k['keyframeId']]) < 1e-7 for k in after if k['keyframeId'] in expected)
report.append(dict(animation='Preview_Expressions_28', changed=len(changes), readback=True))
save('contour-winding-readback.json', report)
print(json.dumps(report))
