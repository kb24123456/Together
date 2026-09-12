#!/usr/bin/env python3
"""Independent, read-only reconstruction of the authored natural-gaze tracks.

Writes verification-geometry.json only. Does not connect to or edit Rive or App.
"""
import ast
import hashlib
import json
import math
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / '2026-09-08-rive-study'
MOTION_BYTES = (HERE / 'motion.json').read_bytes()
M = json.loads(MOTION_BYTES)
SOURCE_BYTES = (HERE / 'source-keyframes.json').read_bytes()
SOURCE = json.loads(SOURCE_BYTES)['keyframes']
EX = json.loads((BASE / 'expression-integration/motion-integrated.json').read_text())

# Import only pure geometry helpers, avoiding the old auditor's top-level writes.
tree = ast.parse((BASE / 'expression-integration/verify-integration.py').read_text())
assigns = {'KEYS', 'N', 't', 'u', 'W'}
functions = {'controls', 'outline', 'cross', 'crosses', 'inside'}
nodes = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))
         or isinstance(n, ast.FunctionDef) and n.name in functions
         or isinstance(n, ast.Assign) and all(isinstance(t, ast.Name) and t.id in assigns for t in n.targets)]
G = {}
exec(compile(ast.Module(body=nodes, type_ignores=[]), 'shared_geometry_helpers', 'exec'), G)

EYES = [dict(name='near', first=32883, n=8, origin=(0, 0), shape='0-32859'),
        dict(name='far', first=32891, n=8, origin=(0, 0), shape='0-32871')]
GAZES = ['Idle', 'Idle_QuietMedium', 'Idle_Look', 'Idle_GazeUp', 'Idle_GazeDown', 'Idle_GazeUpRight']
HIDDEN = {'writingFace': '0-20', 'concernedFace': '0-21', 'handsAndPen': '0-22',
          'sweat': '0-89', 'expressionEyes': '0-13091', 'tears': '0-185826', 'zzz': '0-318752'}

def tracks(keyframes):
    out = {}
    for k in keyframes:
        assert k['interpolationType'] == 'linear'
        out.setdefault(k['objectId'] + ':' + str(k['propertyKey']), []).append([k['frame'], k['value']])
    return {k: sorted(v) for k, v in out.items()}

needed_sources = {'0-6', '0-8762', '0-5972', '0-185850'}
ST = {name: tracks(values) for name, values in SOURCE.items() if name in needed_sources}

def sample(tr, frame):
    return {k: float(np.interp(frame, [v[0] for v in values], [v[1] for v in values]))
            for k, values in tr.items()}

NEUTRAL = sample(ST['0-6'], 0)

def pose(name, frame):
    p = M['plans'][name]
    if p['complete']:
        return NEUTRAL | sample(p['tracks'], frame)
    return NEUTRAL | sample(ST[p['id']], frame) | sample(p['tracks'], frame)

def transform(points, p, node):
    sx, sy = p.get(node + ':16', 100) / 100, p.get(node + ':17', 100) / 100
    a = math.radians(p.get(node + ':15', 0))
    r = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
    return np.asarray(points) * [sx, sy] @ r.T + [p.get(node + ':13', 0), p.get(node + ':14', 0)]

def eyes(p, world=False):
    out = [transform(transform(G['outline'](G['controls'](d, p)), p, d['shape']), p, '0-19') for d in EYES]
    return [transform(q, p, '0-14') for q in out] if world else out

def distance(a, b):
    return max(float(np.linalg.norm(x - y, axis=1).max()) for x, y in zip(eyes(a), eyes(b)))

def difference(a, b, key):
    d = a - b
    return (d + 180) % 360 - 180 if key.endswith((':84', ':86', ':15')) else d

def outlines_overlap(a, b):
    if np.any(a.max(axis=0) < b.min(axis=0)) or np.any(b.max(axis=0) < a.min(axis=0)):
        return False
    av = np.roll(a, -1, axis=0) - a
    bv = np.roll(b, -1, axis=0) - b
    delta = b[None, :, :] - a[:, None, :]
    den = G['cross'](av[:, None, :], bv[None, :, :])
    nonparallel = abs(den) > 1e-10
    s = np.divide(G['cross'](delta, bv[None, :, :]), den, out=np.zeros_like(den), where=nonparallel)
    t = np.divide(G['cross'](delta, av[:, None, :]), den, out=np.zeros_like(den), where=nonparallel)
    crossing = np.any(nonparallel & (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1))
    return bool(crossing or G['inside'](a[:1], b).any() or G['inside'](b[:1], a).any())

checks = []
def check(name, passed, **details):
    checks.append(dict(name=name, passed=bool(passed), **details))

def audit_geometry(name, start, end):
    intersections, overlap, outside, leaks = [], [], [], []
    max_radius = 0.
    centers = []
    for f in np.arange(start, end + .01, .5):
        p = pose(name, f)
        q = eyes(p)
        centers.append(np.mean([a.mean(axis=0) for a in q], axis=0))
        for d, outline in zip(EYES, q):
            if G['crosses'](outline):
                intersections.append([float(f), d['name']])
            radius = float(np.linalg.norm(outline, axis=1).max())
            max_radius = max(max_radius, radius)
            if radius > 184 + 1e-5:
                outside.append([float(f), d['name'], radius])
        if outlines_overlap(*q):
            overlap.append(float(f))
        for part, object_id in HIDDEN.items():
            if p.get(object_id + ':18', 0) > .001:
                leaks.append([float(f), part])
    result = dict(sampledHalfFrames=len(centers), selfIntersections=intersections, eyeOverlap=overlap,
                  outsideSphere=outside, maximumLocalRadius=max_radius, accessoryVisibilityLeaks=leaks,
                  centerRanges=np.stack(centers).min(axis=0).tolist() + np.stack(centers).max(axis=0).tolist())
    check(name + f' frames {start}-{end}: topology and sphere bounds', not intersections and not overlap and not outside,
          maximumRadius=max_radius)
    check(name + f' frames {start}-{end}: no accessory leaks', not leaks)
    return result

gaze = {}
for name in GAZES:
    p = M['plans'][name]
    result = audit_geometry(name, 0, p['frames'])
    endpoint_error = max(distance(pose(name, f), NEUTRAL) for f in [0, p['frames']])
    check(name + ': neutral eye endpoints', endpoint_error < 1e-6, maximumOutlineError=endpoint_error)
    result['neutralEndpointOutlineError'] = endpoint_error
    y, pitch = p['yaw'], p['pitch']
    target_pose = pose(name, max(y[2][0], pitch[2][0]))
    centers = lambda value: np.mean([a.mean(axis=0) for a in eyes(value)], axis=0)
    screen_delta = centers(target_pose) - centers(NEUTRAL)
    # Positive authored pitch moves eyes upward in the screen coordinate system.
    expected = dict(up=(0, -1), down=(0, 1), **{'upper-left': (-1, -1), 'upper-right': (1, -1),
                                                            'lower-left': (-1, 1), 'lower-right': (1, 1)})[p['direction']]
    direction_ok = all(want == 0 or np.sign(value) == want for want, value in zip(expected, screen_delta))
    check(name + ': visible intended direction', direction_ok, direction=p['direction'], displacement=screen_delta.tolist())
    result['timing'] = dict(firstAxisStartsSeconds=min(y[1][0], pitch[1][0]) / 60,
                            bothAxesArriveSeconds=max(y[2][0], pitch[2][0]) / 60,
                            initialDwellSeconds=(min(y[3][0], pitch[3][0]) - max(y[2][0], pitch[2][0])) / 60,
                            microCorrectionSeconds=[min(y[3][0], pitch[3][0]) / 60, max(y[4][0], pitch[4][0]) / 60],
                            bothAxesHomeSeconds=max(y[-2][0], pitch[-2][0]) / 60,
                            completeSeconds=p['frames'] / 60,
                            axisLagFrames=p['lag'])
    if p['complete']:
        diff = {key: [pose(name, f)[key], NEUTRAL[key]] for f in [0, p['frames']]
                for key in NEUTRAL if abs(difference(pose(name, f)[key], NEUTRAL[key], key)) > 1e-6}
        result['fullEndpointDifferences'] = diff
        check(name + ': complete endpoint reset', not diff, differenceCount=len(diff))
        missing = sorted(set(NEUTRAL) - set(p['tracks']))
        check(name + ': full source channel coverage', not missing, missing=missing)
    gaze[name] = result

orientation = audit_geometry('Idle_Orient', 0, M['plans']['Idle_Orient']['frames'])
joins = []
for s in M['orientationSegments'][1:] + [dict(name='Loop', startFrame=M['plans']['Idle_Orient']['frames'])]:
    frame = s['startFrame']
    a, b = pose('Idle_Orient', frame - 1), pose('Idle_Orient', frame)
    error = distance(a, b)
    neutral_error = max(distance(a, NEUTRAL), distance(b, NEUTRAL))
    joins.append(dict(into=s['name'], frame=frame, eyeDisplacement=error, neutralOutlineError=neutral_error))
check('Idle_Orient six joins: neutral spherical eyes', max(j['neutralOutlineError'] for j in joins) < .1,
      maximumError=max(j['neutralOutlineError'] for j in joins))

preview = {}
changed_segments = [s for s in EX['segments'] if s['name'] in GAZES]
for s in changed_segments:
    preview[s['name']] = audit_geometry('Preview_All', s['startFrame'], s['endFrame'] - .5)
    # A following expression may legitimately move the face at its first frame;
    # preserve the existing boundary key exactly instead of requiring neutrality.
    f = s['endFrame']
    old, current = sample(ST['0-185850'], f), pose('Preview_All', f)
    check('Preview_All ' + s['name'] + ': boundary matches source', distance(old, current) < .1,
          maximumOutlineError=distance(old, current))

changed_key_errors = []
for key, values in M['plans']['Preview_All']['tracks'].items():
    outside = lambda frame: not any(s['startFrame'] <= frame < s['endFrame'] for s in changed_segments)
    if [v for v in values if outside(v[0])] != [v for v in ST['0-185850'][key] if outside(v[0])]:
        changed_key_errors.append(key)
check('Preview_All preserves all other authored frame keys', not changed_key_errors, changedKeys=changed_key_errors)

sm_evidence = None
sm_path = HERE / 'current-state-machine.json'
if sm_path.exists():
    current_sm = json.loads(sm_path.read_text())
    sm = current_sm['layers'][0]
    old_sm = json.loads((HERE / 'source-state-machine.json').read_text())['layers'][0]
    names = {s['id']: s['name'] for s in sm['states']}
    old_names = {s['id']: s['name'] for s in old_sm['states']}
    def signature(t, state_names):
        conditions = [(c.get('leftComparator', {}).get('viewModelPropertyName'), c['type'], c.get('operation'),
                       c.get('rightComparator', {}).get('value')) for c in t['conditions']]
        return (state_names[t['toStateId']], t['duration'], t['enableExitTime'], t['exitTime'],
                t['exitTimeIsPercentage'], t['isDisabled'], conditions)
    outgoing = lambda name: [t for t in sm['transitions'] if names[t['fromStateId']] == name]
    canonical = [signature(t, old_names) for t in old_sm['transitions'] if old_names[t['fromStateId']] == 'Idle']
    for name in GAZES:
        actual = [signature(t, names) for t in outgoing(name)]
        business_expected = [t for t in canonical if t[0] != 'PickAfterOthers']
        check(name + ': all business interrupts preserved', all(t in actual for t in business_expected), expectedRoutes=len(business_expected))
    choices = [t for t in outgoing('PickAfterShort') if names[t['toStateId']] in GAZES]
    check('five main gaze choices have equal positive random weights', len(choices) == 5 and all(t['randomWeight'] == 1 for t in choices))
    picker = next(s for s in sm['states'] if s['name'] == 'PickAfterShort')
    check('main gaze picker randomized', picker['flags'] & 1)
    short = [t for t in outgoing('PickAfterOthers') if names[t['toStateId']] in ['Idle_QuietShort', 'Idle_Look']]
    ratio = {names[t['toStateId']]: t['randomWeight'] for t in short}
    check('calm dwell and occasional lower-left glance selectable', ratio == {'Idle_QuietShort': 4, 'Idle_Look': 1})
    unresolved = [t['id'] for t in sm['transitions'] if t['fromStateId'] not in names or t['toStateId'] not in names]
    check('all transition endpoints resolve', not unresolved, unresolved=unresolved)
    check('expected state graph size', len(sm['states']) == 32 and len(sm['transitions']) == 141,
          states=len(sm['states']), transitions=len(sm['transitions']))
    exempt = {'Resolve', 'PickAfterShort', 'PickAfterOthers', 'Idle_Look'}
    old_routes = {t['id']: t for t in old_sm['transitions'] if old_names[t['fromStateId']] not in exempt}
    now_routes = {t['id']: t for t in sm['transitions']}
    changed = [key for key, value in old_routes.items() if now_routes.get(key) != value]
    check('existing business graph outside gaze selection unchanged', not changed, changedRouteIds=changed)
    sm_evidence = dict(states=len(sm['states']), transitions=len(sm['transitions']),
                       mainGazeProbabilities={names[t['toStateId']]: t['randomWeight'] / sum(v['randomWeight'] for v in choices) for t in choices},
                       secondaryProbabilities={k: v / sum(ratio.values()) for k, v in ratio.items()},
                       sourceSHA256=hashlib.sha256(sm_path.read_bytes()).hexdigest())
else:
    check('current state machine snapshot supplied', False)

check('input artifacts unchanged during read-only audit',
      (HERE / 'motion.json').read_bytes() == MOTION_BYTES and (HERE / 'source-keyframes.json').read_bytes() == SOURCE_BYTES)
out = dict(passed=all(c['passed'] for c in checks),
           sourceSHA256=hashlib.sha256(MOTION_BYTES).hexdigest(),
           sourceKeyframesSHA256=hashlib.sha256(SOURCE_BYTES).hexdigest(),
           scope='Independent reconstruction of actual reduced linear authored tracks over the immediately preceding Rive snapshot.',
           sampling='Half frames, 24 samples per cubic, 8 cubic vertices per sphere-facing eye; segment intersections and containment checked.',
           checks=checks, gaze=gaze, orientation=orientation, orientationJoins=joins,
           preview=preview, stateMachine=sm_evidence,
           limits=['Finite sampling is not a proof over all continuous times.',
                   'Mathematical geometry and state-graph checks do not replace Rive/native runtime or physical-device visual acceptance.',
                   'Eye outline transforms use the established sphere-eye rig with identity eye-shape transforms.'])
(HERE / 'verification-geometry.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps(dict(passed=out['passed'], checks=len(checks), failed=[c for c in checks if not c['passed']],
                      maximumSphereRadius=max(v['maximumLocalRadius'] for v in gaze.values()),
                      directions={k: v['timing'] for k, v in gaze.items()}), indent=2))
raise SystemExit(0 if out['passed'] else 1)
