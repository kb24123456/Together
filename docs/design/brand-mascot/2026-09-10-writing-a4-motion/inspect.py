import sys,json,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim
def save(name,data): (HERE/'backups'/name).write_text(json.dumps(data,indent=2)+'\n')
assert call('open_file_editor',{'command':'getCurrentFile'})['fileId']==2564580
hier=call('query_objects',{'objectIds':['0-14'],'depth':6})
save('hierarchy.json',hier)
ids=['0-14','0-15','0-16','0-20','0-22','0-23','0-36','0-37','0-40','0-41','0-44','0-45','0-46','0-47','0-48','0-50','0-51','0-52','0-53','0-54','0-32','0-33','0-65','0-66','0-69','0-70','0-96','0-106','0-452672','0-452670','0-452671']
schema=call('query_property_keys',{'objectIds':ids})['properties'];save('property-schema.json',schema)
vals=call('query_property_values',{'propertyKeys':{i:list(v.values()) for i,v in schema.items()}})['values'];save('properties.json',vals)
timelines=anim('listLinearAnimations')['linearAnimations'];save('timelines.json',timelines)
save('state-machine.json',anim('queryStateMachine',{'stateMachineId':'0-7'}))
keys={}
for off in range(0,len(timelines),15):
 d=anim('queryKeyFrames',{'animationIds':[a['id']for a in timelines[off:off+15]]})
 keys.update(d['keyframes'])
save('all-keyframes.json',keys)
print('Backed up',len(timelines),'timelines and',sum(map(len,keys.values())),'keys')
for i in ids:
 if i not in ['0-14','0-452672','0-452670','0-452671']:
  print(i,{k:v for k,v in vals[i].items()if k in ['13','14','15','16','17','18','20','21','24','25','26','27','28','29','30','31','35','36','37','42','44','45','46','47','48','49','50']})
print('writing sample',keys['0-108'][:5])
