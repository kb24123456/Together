import sys
from rive_client import *
from design import PRESETS
m=json.loads((HERE/'authored.json').read_text());S=m['states'];l=m['expressionsLayer'];al=m['actionsLayer'];initial=sys.argv[1:]!=['remaining'];rep=[1,2,3,6,10,17];indices=rep if initial else [i for i,_,_,_ in PRESETS if i not in rep]
E='0-452654';EC='0-452660';REA='0-452656';REACT='0-452658'
def cond(p,v=None,op='equal'):
 d={'leftComparator':{'viewModelPropertyId':p}}
 if v is not None:d.update(operation=op,rightComparator={'valueType':'constantValueType','value':v})
 return d
edges=[]
def edge(a,b,conditions=[],dur=0,end=False):edges.append(dict(a=a,b=b,conditions=conditions,duration=dur,end=end))
if initial:
 edge('0-452885',S['Expr_Resolve'])
 edge(S['Expr_Auto'],S['Close_Auto'],[cond(E,0,'notEqual')],0)
 edge(S['Close_Auto'],S['Expr_Resolve'],end=True)
 edge(S['Expr_Resolve'],S['Expr_Auto'],[cond(E,0)],120)
 edge('0-452883',S['Expr_ReactionBlank'],[cond(REACT)],90)
 edge('0-452883',S['Expr_CelebrationBlank'],[cond('0-452666'),cond(E,0)],70)
 edge(S['Expr_CelebrationBlank'],S['Pulse_SoftHappy'],[],120,True)
 edge(S['Expr_ReactionBlank'],S['Pulse_SoftHappy'],[cond(REA,0)],120,True)
 edge('0-452889',S['Action_Rest'])
 for name,trigger in [('Observe','0-452662'),('Nod','0-452664'),('Celebrate','0-452666'),('Poke','0-452668')]:
  edge('0-452887',S['Action_'+name],[cond(trigger)],70)
  edge(S['Action_'+name],S['Action_Rest'],[],70,True)
for idx in indices:
 name=next(p[1]for p in PRESETS if p[0]==idx)
 edge(S['Expr_Resolve'],S['Hold_'+name],[cond(E,idx)],120)
 edge(S['Hold_'+name],S['Close_'+name],[cond(E,idx,'notEqual')],0)
 edge(S['Close_'+name],S['Expr_Resolve'],end=True)
 edge(S['Expr_ReactionBlank'],S['Pulse_'+name],[cond(REA,idx)],120,True)
 edge(S['Pulse_'+name],S['Expr_Resolve'],end=True)
# Every transition is identified by fresh diff, avoiding positional IDs.
before=anim('queryStateMachine',{'stateMachineId':'0-7'});old={t['id']for la in before['layers']for t in la['transitions']}
groups={}
for e in edges:groups.setdefault(e['a'],[]).append({'to':e['b']})
anim('createTransitions',{'states':[{'id':a,'transitions':ts}for a,ts in groups.items()]})
after=anim('queryStateMachine',{'stateMachineId':'0-7'});new={(t['fromStateId'],t['toStateId']):t['id']for la in after['layers']for t in la['transitions']if t['id']not in old}
values={};conditions=[]
for e in edges:
 tid=new[e['a'],e['b']];e['id']=tid;values[tid]={'158':e['duration'],'152':28 if e['end']else 0,'160':100 if e['end']else 0}
 if e['conditions']:conditions.append({'id':tid,'conditions':e['conditions']})
props(values)
if conditions:anim('createConditions',{'transitions':conditions})
owned=json.loads((HERE/'edges.json').read_text())if(HERE/'edges.json').exists()else[];save('edges.json',owned+edges);save('state-machine-current.json',anim('queryStateMachine',{'stateMachineId':'0-7'}));print(len(edges),'routes wired')
