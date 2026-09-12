from rive_client import *
from design import *
m=json.loads((HERE/'authored.json').read_text())
for idx in [15,19,23,28]:
 name=next(p[1]for p in PRESETS if p[0]==idx);p=pose(idx)
 targets={k:v for k,v in p.items()if any(k.startswith(o+':')for part in ['ExpressionEyeLeft','ExpressionEyeRight']for o in [R[part]['id']]+R[part]['vertices']) or k.startswith(R['posture']+':')}
 for prefix in ['Expr_','Expr_Close_','Expr_Pulse_']:
  aid=m['timelines'][prefix+name]['id'];ks=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid];doomed=[k['keyframeId']for k in ks if k['objectId']+':'+str(k['propertyKey'])in targets];anim('modifyKeyFrames',{'animationId':aid,'delete':doomed});adds=[]
  for key,v in targets.items():
   o,prop=key.split(':');adds.append(dict(objectId=o,propertyKey=int(prop),frame=0,value=v,interpolationType='linear'))
   if prefix!='Expr_'and key.startswith(R['posture']+':')and v!=pose(0)[key]:
    if prefix=='Expr_Pulse_':adds.append(dict(objectId=o,propertyKey=int(prop),frame=57,value=v,interpolationType='linear'))
    adds.append(dict(objectId=o,propertyKey=int(prop),frame=6 if prefix=='Expr_Close_' else 72,value=pose(0)[key],interpolationType='linear'))
  anim('modifyKeyFrames',{'animationId':aid,'add':adds})
 print('refined',idx,name)
