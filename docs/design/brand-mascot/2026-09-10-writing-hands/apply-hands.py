"""Translate existing writing props from the recorded baseline; preserve every key ID and curve."""
import sys,json,pathlib
HERE=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import anim,props,call
assert call('open_file_editor',{'command':'getCurrentFile'})['fileId']==2564580
assert (HERE/'backups/before-writing-hands.rev').stat().st_size>12000000
old=json.loads((HERE/'backups/all-keyframes.json').read_text())
offsets={'0-23':{13:-52,14:22},'0-40':{13:50,14:29},'0-96':{13:-52,14:16},
 '0-32':{14:-6},'0-65':{14:-6},'0-69':{14:-6}}
changed=[]
for aid,keys in old.items():
 changes=[dict(keyframeId=k['keyframeId'],value=k['value']+offsets[k['objectId']][k['propertyKey']]) for k in keys if k['objectId'] in offsets and k['propertyKey'] in offsets[k['objectId']]]
 if changes:
  anim('modifyKeyFrames',{'animationId':aid,'change':changes})
  changed.append({'animationId':aid,'keys':len(changes)})
props({'0-23':{'13':-173,'14':155},'0-40':{'13':169,'14':166},'0-96':{'13':-105,'14':250},
 '0-32':{'14':-6},'0-65':{'14':78},'0-69':{'14':96},
 '0-169097':{'555':'#ff2c2c2c'},'0-169099':{'555':'#ff0e0e0e'},'0-169101':{'555':'#ff222222'},'0-169103':{'555':'#ff0b0b0b'},
 '0-63':{'38':'#ff2c2c2c'},'0-64':{'38':'#ff0e0e0e'},'0-169090':{'38':'#ff222222'},'0-169091':{'38':'#ff0b0b0b'}})
(HERE/'changes.json').write_text(json.dumps({'offsets':offsets,'changed':changed,'totalKeys':sum(x['keys'] for x in changed)},indent=2))
print('Updated',len(changed),'timelines;',sum(x['keys'] for x in changed),'translation keys; eye/body/shape/curve keys unchanged')
