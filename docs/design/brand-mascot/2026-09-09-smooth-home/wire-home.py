"""Extend the existing Expressions layer; preserve all original edges and APIs."""
from common import *
M=json.loads((HERE/'home-clips.json').read_text());old=json.loads((EX/'authored.json').read_text())['states']
S={k:v['state']for k,v in M.items()}|old
IDLE='0-671006'; E='0-452654'; MODE='0-377'
def cond(p,v,op='equal'):return dict(leftComparator=dict(viewModelPropertyId=p),operation=op,rightComparator=dict(valueType='constantValueType',value=v))
edges=[]
def edge(a,b,cs=(),duration=0,end=False):edges.append(dict(a=S[a],b=S[b],conditions=list(cs),duration=duration,end=end))
edge('Expr_Auto','Home_Calm',[cond(IDLE,0,'greaterThanOrEqual'),cond(E,0),cond(MODE,0)])
for kind,value in [('Curious',21),('Happy',2)]:
    en,hold,ex=['Home_'+kind+s for s in ['Enter','Hold','Exit']]
    edge('Home_Calm',en,[cond(IDLE,value),cond(E,0),cond(MODE,0)])
    edge(en,hold,[cond(IDLE,value)],end=True)
    edge(en,ex,[cond(IDLE,value,'notEqual')],end=True)
    edge(hold,ex,[cond(IDLE,value,'notEqual')])
    edge(ex,'Home_Calm',end=True)
for name in M:
    if name=='Home_Release':continue
    edge(name,'Home_Release',[cond(IDLE,0,'lessThan')],duration=180)
    # External legacy controls remain authoritative even if a manual preview
    # forgot to release idleFace. Separate destinations represent OR guards.
    edge(name,'Expr_Auto',[cond(E,0,'notEqual')],duration=140)
    edge(name,'Expr_Resolve',[cond(MODE,0,'notEqual')],duration=140)
edge('Home_Release','Expr_Auto',end=True)
before=anim('queryStateMachine',{'stateMachineId':'0-7'});ids={t['id']for l in before['layers']for t in l['transitions']}
groups={}
for e in edges:groups.setdefault(e['a'],[]).append({'to':e['b']})
anim('createTransitions',{'states':[{'id':k,'transitions':v}for k,v in groups.items()]})
after=anim('queryStateMachine',{'stateMachineId':'0-7'});fresh={(t['fromStateId'],t['toStateId']):t['id']for l in after['layers']for t in l['transitions']if t['id']not in ids}
values={};conditions=[]
for e in edges:
    tid=fresh[e['a'],e['b']];e['id']=tid;values[tid]={'158':e['duration'],'152':28 if e['end']else 0,'160':100 if e['end']else 0}
    if e['conditions']:conditions.append({'id':tid,'conditions':e['conditions']})
props(values);anim('createConditions',{'transitions':conditions})
save('home-edges.json',edges);save('state-machine.json',anim('queryStateMachine',{'stateMachineId':'0-7'}))
vms=cmd('viewmodel_editor','listViewModelInstances',{'viewModelId':'0-375'});save('instances.json',vms)
print(len(edges),'new home routes; original routes preserved')
print([p for p in vms['instances'][0]['viewModelProperties']if p['name']=='idleFace'])
