from rive_client import *
from design import PRESETS
checks=[]
def check(name,inputs,expected,visited=None,frames=120):
    d=anim('simulateStateMachine',{'stateMachineId':'0-7','fps':30,'frames':frames,'inputs':inputs})
    end={s['layerName']:s['stateName']for s in d['finalStates']};seen={s['stateName']for s in d['trace']if s['kind']=='state'}
    passed=all(end.get(k)==v for k,v in expected.items())and set(visited or []).issubset(seen)
    if not passed:save('evidence/FAILED-'+name+'.json',d)
    checks.append(dict(name=name,passed=passed,finalStates=end,requiredVisited=visited or []));assert passed,(name,end,seen)
def number(f,p,v):return dict(frame=f,property=p,value=v)
for i,n,_,_ in PRESETS:
    check('hold-'+n,[number(0,'expression',i)],{'Expressions':'Hold_'+n,'LightActions':'Action_Rest'},['Hold_'+n])
    check('pulse-'+n,[number(0,'expression',6),number(15,'reaction',i),number(16,'react',True)],{'Expressions':'Hold_Love'},['Pulse_'+n],150)
    for action,an in [('observe','Observe'),('nod','Nod'),('celebrateMotion','Celebrate'),('poke','Poke')]:
        check(n+'-'+action,[number(0,'expression',i),number(20,action,True)],{'Expressions':'Hold_'+n,'LightActions':'Action_Rest'},['Action_'+an])
check('rapid-final-selection',[number(f,'expression',i)for f,i in [(0,2),(1,3),(2,6),(3,13),(4,17),(7,28),(11,19),(16,4)]],{'Expressions':'Hold_Excited'})
check('pulse-restores-latest-selection',[number(0,'expression',6),number(15,'reaction',3),number(16,'react',True),number(25,'expression',19)],{'Expressions':'Hold_Sad'},['Pulse_Laugh'])
for action,an in [('observe','Observe'),('nod','Nod'),('celebrateMotion','Celebrate'),('poke','Poke')]:
 check('repeat-'+action,[number(0,'expression',2)]+[number(f,action,True)for f in range(5,35,3)],{'Expressions':'Hold_SoftHappy','LightActions':'Action_Rest'},['Action_'+an],180)
check('interrupted-actions',[number(0,'expression',6)]+[number(f,p,True)for f,p in [(10,'poke'),(14,'observe'),(18,'celebrateMotion'),(22,'nod')]],{'Expressions':'Hold_Love','LightActions':'Action_Rest'},['Action_Poke','Action_Observe','Action_Celebrate','Action_Nod'])
for mode,typing,state in [(1,True,'Writing'),(1,False,'WritingHold'),(2,False,'Concerned'),(3,False,'Thinking'),(4,False,'Doze')]:
 check('legacy-'+state,[number(0,'expression',0),number(0,'mode',mode),number(0,'isTyping',typing)],{'Behavior':state,'Expressions':'Expr_Auto','LightActions':'Action_Rest'},frames=150)
check('legacy-acknowledge',[number(0,'expression',0),number(10,'acknowledge',True)],{'Expressions':'Expr_Auto','LightActions':'Action_Rest'},['Acknowledge'])
check('automatic-celebration',[number(0,'expression',0),number(10,'celebrateMotion',True)],{'Expressions':'Expr_Auto','LightActions':'Action_Rest'},['Action_Celebrate','Pulse_SoftHappy'])
original=json.loads((HERE/'source-keyframes.json').read_text())['keyframes'];actual=anim('queryKeyFrames',{'animationIds':list(original)})['keyframes'];assert actual==original
sm=anim('queryStateMachine',{'stateMachineId':'0-7'});save('state-machine-current.json',sm);a=json.loads((HERE/'source-state-machine.json').read_text());assert sm['layers'][0]['states']==a['layers'][0]['states'];assert sm['layers'][0]['transitions']==a['layers'][0]['transitions'];assert sm['listeners']==a['listeners']
vm=cmd('viewmodel_editor','listViewModels');save('viewmodels-final.json',vm)
result=dict(passed=True,checks=checks,checkCount=len(checks),legacyTimelinesUnchanged=len(original),legacyKeyframesUnchanged=sum(map(len,original.values())),legacyStatesUnchanged=32,legacyTransitionsUnchanged=141,currentLayers=[dict(name=l['layerName'],nodes=len(l['states']),transitions=len(l['transitions']))for l in sm['layers']]);save('verification-final.json',result);print('PASS',len(checks),'behavior/combination cases; all original animation and graph records unchanged')
