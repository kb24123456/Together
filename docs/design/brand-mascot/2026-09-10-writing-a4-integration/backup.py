import sys,json,shutil,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim
assert call('open_file_editor',{'command':'getCurrentFile'})['fileId']==2564580
def save(n,d):(HERE/'backups'/n).write_text(json.dumps(d,indent=2)+'\n')
native=Path('/Users/papertiger/Library/Containers/app.rive.editor/Data/Documents/writing-a4-integration-20260910/before/together_sphere_motion_study.rev')
assert native.stat().st_size>12000000
shutil.copy2(native,HERE/'backups/before-integration.rev')
shutil.copy2(ROOT/'Together/Resources/BrandMascot/together_sphere_motion_study.riv',HERE/'backups/app-before.riv')
shutil.copytree(ROOT/'Together/Assets.xcassets/BrandMascot/MascotHolding.imageset',HERE/'backups/MascotHolding.imageset',dirs_exist_ok=True)
shutil.copy2(ROOT/'Together/Features/BrandMascot/MascotPalette.swift',HERE/'backups/MascotPalette.swift')
timelines=anim('listLinearAnimations')['linearAnimations'];save('timelines.json',timelines)
allkeys={}
for off in range(0,len(timelines),15):allkeys.update(anim('queryKeyFrames',{'animationIds':[a['id']for a in timelines[off:off+15]]})['keyframes'])
save('all-keyframes.json',allkeys)
save('state-machine.json',anim('queryStateMachine',{'stateMachineId':'0-7'}))
schema=call('query_property_keys',{'objectIds':['0-108','0-1032','0-1033','0-1034']})['properties'];save('timeline-schema.json',schema)
save('timeline-properties.json',call('query_property_values',{'propertyKeys':{o:list(p.values())for o,p in schema.items()}})['values'])
save('hashes.json',{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (HERE/'backups').glob('*.riv')})
print('Full backup:',len(timelines),'timelines',sum(map(len,allkeys.values())),'keys')
print(schema['0-108'])
