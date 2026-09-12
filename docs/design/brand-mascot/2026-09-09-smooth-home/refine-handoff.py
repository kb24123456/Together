"""Retain the legacy face while its existing event exit animation settles."""
from common import *
R=json.loads((HERE/'rig.json').read_text());M=json.loads((HERE/'home-clips.json').read_text())
assert 'Home_Acquire' not in M
static={R['home']+':18':0,OLD_RIG['legacyFace']+':18':100,OLD_RIG['newFace']+':18':0}
# Do not snap a departing smile back to capsules while fading into an event.
aid=M['Home_Release']['id'];ks=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
anim('modifyKeyFrames',dict(animationId=aid,delete=[k['keyframeId']for k in ks]))
write_tracks(aid,{k:[[0,v],[6,v]]for k,v in static.items()})
name='Home_Acquire'
anim('createLinearAnimations',{'linearAnimations':[{'name':name,'fps':60,'duration':.9}]})
aid=next(a['id']for a in anim('listLinearAnimations')['linearAnimations']if a['name']==name)
count=write_tracks(aid,{k:[[0,v],[54,v]]for k,v in static.items()})
anim('createStates',{'layerId':'0-452882','states':[{'name':name,'linearAnimationName':name,'x':1170,'y':-500}]})
l=anim('queryStateMachineLayer',{'layerId':'0-452882'});states=l.get('states')or l['layer']['states'];sid=next(s['id']for s in states if s['name']==name)
M[name]=dict(id=aid,state=sid,frames=54,keys=count);save('home-clips.json',M)
edges=json.loads((HERE/'home-edges.json').read_text());entry=edges[0]
props({entry['id']:{'151':sid}});entry['b']=sid
old=json.loads((EX/'authored.json').read_text())['states']
def cond(p,v,op='equal'):return dict(leftComparator=dict(viewModelPropertyId=p),operation=op,rightComparator=dict(valueType='constantValueType',value=v))
new=[dict(b=M['Home_Calm']['state'],conditions=[cond('0-671006',0,'greaterThanOrEqual'),cond('0-377',0),cond('0-452654',0)],end=True),dict(b=old['Expr_Auto'],conditions=[cond('0-671006',0,'lessThan')],end=False),dict(b=old['Expr_Resolve'],conditions=[cond('0-377',0,'notEqual')],end=False),dict(b=old['Close_Auto'],conditions=[cond('0-452654',0,'notEqual')],end=False)]
anim('createTransitions',{'states':[{'id':sid,'transitions':[{'to':e['b']}for e in new]}]})
sm=anim('queryStateMachine',{'stateMachineId':'0-7'});found={t['toStateId']:t['id']for la in sm['layers']for t in la['transitions']if t['fromStateId']==sid}
for e in new:
    e.update(id=found[e['b']],a=sid,duration=0)
    props({e['id']:{'158':0,'152':28 if e['end']else 0,'160':100 if e['end']else 0}})
anim('createConditions',{'transitions':[{'id':e['id'],'conditions':e['conditions']}for e in new]})
save('home-edges.json',edges+new);save('state-machine.json',anim('queryStateMachine',{'stateMachineId':'0-7'}))
print('Event hand-off retains the original face until its exit is settled.')
