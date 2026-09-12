"""Promote approved A4 motion into the existing four production timelines."""
import json,sys,math
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim,props
assert call('open_file_editor',{'command':'getCurrentFile'})['fileId']==2564580
assert (HERE/'backups/before-integration.rev').stat().st_size>12000000
original=json.loads((HERE/'backups/all-keyframes.json').read_text())
review=original['0-893641']
grouped={}
for k in review:grouped.setdefault((k['objectId'],k['propertyKey']),[]).append(k)
for vs in grouped.values():vs.sort(key=lambda k:k['frame'])
def at(o,p,f):
 vs=grouped[o,p]
 if f<=vs[0]['frame']:return vs[0]['value']
 for a,b in zip(vs,vs[1:]):
  if f<=b['frame']:
   t=(f-a['frame'])/(b['frame']-a['frame']);return a['value']*(1-t)+b['value']*t
 return vs[-1]['value']
layout_nodes={'0-23','0-36','0-40','0-44','0-50','0-46','0-47','0-52','0-53','0-48','0-54','0-32','0-65','0-69','0-96','0-37','0-41'}
layout={k:at(*k,0)for k in grouped if k[0]in layout_nodes and k[1]!=18}
owned=set(layout)|{(o,p)for o in ['0-14','0-20','0-22']for p in range(13,18)}
changes=[]
for aid,name,frames in [('0-108','Writing',216),('0-1033','WritingHold',240),('0-1032','WritingEnter',12),('0-1034','WritingExit',12)]:
 tracks={k:[[0,v]]for k,v in layout.items()}
 # Preserve old face/property opacity transitions and every non-owned channel.
 for k in original[aid]:
  key=k['objectId'],k['propertyKey']
  if key in owned:continue
  f=round(k['frame']*.9)if aid=='0-108'else k['frame']
  tracks.setdefault(key,[]).append([f,k['value']])
 for o in ['0-14','0-20','0-22']:
  for p,v in [(13,256 if o=='0-14'else 0),(14,240 if o=='0-14'else 0),(15,0),(16,100),(17,100)]:tracks[o,p]=[[0,v],[frames,v]]
 if name=='Writing':
  dynamic={k:[]for k in [('0-14',14),('0-14',16),('0-14',17),('0-20',16),('0-20',17),('0-22',14),('0-22',16),('0-22',17),('0-23',13),('0-23',14),('0-23',15),('0-40',14),('0-40',15)]}
  for f in range(frames+1):
   follow=at('0-15',14,f);sx=at('0-15',16,f)/100;sy=at('0-15',17,f)/100
   values=[240+follow,sx*100,sy*100,100/sx,100/sy,-follow/sy,100/sx,100/sy,at('0-23',13,f),at('0-23',14,f),at('0-23',15,f),at('0-40',14,f),at('0-40',15,f)]
   for key,v in zip(dynamic,values):dynamic[key].append([f,v])
  tracks.update(dynamic)
 elif name=='WritingHold':
  # A4 stop-typing pose: near hand lifts the pen slightly; quiet body breathing.
  tracks['0-23',14]=[[0,129],[frames,129]]
  for key in [('0-14',14),('0-22',14)]:tracks[key]=[]
  for f in range(frames+1):
   breathe=.35*(1-math.cos(2*math.pi*f/frames))/2
   tracks['0-14',14].append([f,240+breathe]);tracks['0-22',14].append([f,-breathe])
 else:
  # Keep the existing timed reveal/retract and its endpoint reset.
  tracks['0-22',14]=[[k['frame'],k['value']]for k in original[aid]if k['objectId']=='0-22'and k['propertyKey']==14]
  # At the end of retraction the invisible props return to their neutral local transform.
 adds=[]
 for (o,p),vs in tracks.items():
  unique={f:v for f,v in vs}
  adds.extend(dict(objectId=o,propertyKey=p,frame=f,value=v,interpolationType='linear')for f,v in sorted(unique.items()))
 # This is a deliberate replacement of four authorized timelines, with full native backup.
 current=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
 anim('modifyKeyFrames',{'animationId':aid,'delete':[k['keyframeId']for k in current]})
 for off in range(0,len(adds),1000):anim('modifyKeyFrames',{'animationId':aid,'add':adds[off:off+1000]})
 props({aid:{'57':frames}})
 changes.append({'id':aid,'name':name,'duration':frames/60,'oldKeys':len(original[aid]),'newKeys':len(adds)})
(HERE/'changes.json').write_text(json.dumps({'timelines':changes,'stateMachineChanged':False,'baseGeometryChanged':False,'ownership':'CharacterRoot for body follow; inverse transforms on WritingProps and WritingFace; no Body or FaceMotion animation ownership added'},indent=2)+'\n')
print(json.dumps(changes,indent=2))
