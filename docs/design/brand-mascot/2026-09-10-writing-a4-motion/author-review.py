"""Add one isolated review timeline using the existing character parts. No production edits."""
import sys,json,math
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'2026-09-09-expression-system'))
from rive_client import call,anim,props
NAME='Review_Writing_A4'
assert call('open_file_editor',{'command':'getCurrentFile'})['fileId']==2564580
assert (HERE/'backups/before-a4-motion.rev').stat().st_size>12000000
assert not any(a['name']==NAME for a in anim('listLinearAnimations')['linearAnimations'])
old=json.loads((HERE/'backups/all-keyframes.json').read_text())
base={}
for k in sorted(old['0-108'],key=lambda k:k['frame']):base.setdefault((k['objectId'],k['propertyKey']),k['value'])
def put(o,**values):
 for p,v in values.items():base[o,int(p)]=v
def transform(o,x=0,y=0,r=0,sx=100,sy=100,opacity=100):put(o,**{'13':x,'14':y,'15':r,'16':sx,'17':sy,'18':opacity})
transform('0-14',256,240)
for o in ['0-452670','0-452671','0-452672','0-452673','0-15','0-20','0-22']:transform(o)
for o in ['0-670901','0-452647','0-19','0-21','0-13091','0-318752','0-13090','0-452842']:put(o,**{'18':0})
transform('0-23',-122,132)
transform('0-40',107,124)
transform('0-36')
transform('0-44',-82,-15,3)
transform('0-50',82,-14,-3)
for vertex,x in [('0-46',-44),('0-47',44),('0-52',-44),('0-53',44)]:
 put(vertex,**{'24':x,'25':0,'84':180 if x>0 else 0,'85':88/3 if x>0 else 0,'86':0,'87':88/3 if x<0 else 0})
put('0-48',**{'47':14});put('0-54',**{'47':14})
transform('0-32',16,-18,-24)
transform('0-65',53,66,156)
transform('0-69',60,84,156)
transform('0-96',-34,222)
put('0-37',**{'20':122,'21':122});put('0-41',**{'20':116,'21':116})
put('0-16',**{'20':368,'21':368})

# Continuous, uneven stroke timing with a short pen lift and a gentle return.
# Columns: seconds, grip horizontal offset, grip vertical offset, grip rotation.
poses=[(0,0,0,0),(.25,0,0,0),(.39,3,1.2,.7),(.55,7,-.6,-.4),
 (.69,2,1.5,.9),(.83,8,.1,-.6),(.98,4,1.4,.6),(1.16,11,-.2,-.5),
 (1.34,8,0,.2),(1.45,8,-3,-.8),(1.64,8,-3,-.8),
 (1.80,10,.8,.4),(1.94,5,1.3,.8),(2.12,13,-.4,-.6),
 (2.28,8,1.2,.7),(2.47,15,-.3,-.5),(2.68,11,.5,.2),
 (2.84,11,-3,-.6),(3.12,0,-3,0),(3.35,0,0,0),(3.60,0,0,0)]
def smooth(t):t=max(0,min(1,t));return t*t*t*(10+t*(-15+6*t))
def sample(t):
 if t<=0:return poses[0][1:]
 for a,b in zip(poses,poses[1:]):
  if t<=b[0]:
   u=smooth((t-a[0])/(b[0]-a[0]));return tuple(a[j]+(b[j]-a[j])*u for j in range(1,4))
 return poses[-1][1:]
tracks={k:[[0,v]] for k,v in base.items()}
dynamic={('0-23',13):[],('0-23',14):[],('0-23',15):[],('0-15',14):[],('0-15',16):[],('0-15',17):[],('0-452672',14):[],('0-40',14):[],('0-40',15):[]}
motion=[]
for f in range(217):
 t=f/60;dx,dy,r=sample(t);lag=sample(max(0,t-.067));envelope=math.sin(math.pi*t/3.6)**2
 follow=(lag[1]*.35+.7*math.sin(2*math.pi*t/3.6))*envelope
 values=[-122+dx,132+dy,r,follow,100+.25*envelope,100-.35*envelope,follow,124+.28*math.sin(2*math.pi*t/3.6)*envelope,.18*math.sin(2*math.pi*t/3.6)*envelope]
 for k,v in zip(dynamic,values):dynamic[k].append([f,v])
 motion.append({'frame':f,'t':t,'grip':[-122+dx,132+dy,r],'bodyFollow':follow})
tracks.update(dynamic)
anim('createLinearAnimations',{'linearAnimations':[{'name':NAME,'fps':60,'duration':3.6}]})
aid=next(a['id']for a in anim('listLinearAnimations')['linearAnimations']if a['name']==NAME)
props({aid:{'59':1}})
keys=[dict(objectId=o,propertyKey=p,frame=f,value=v,interpolationType='linear')for (o,p),vs in tracks.items()for f,v in vs]
for off in range(0,len(keys),1000):anim('modifyKeyFrames',{'animationId':aid,'add':keys[off:off+1000]})
(HERE/'review-manifest.json').write_text(json.dumps({'fileId':2564580,'artboard':'TogetherSphere','artboardId':'0-2','animation':NAME,'animationId':aid,'duration':3.6,'fps':60,'keys':len(keys),'status':'motion review only','sourceReference':'../2026-09-10-writing-concepts/writing-A4-raised-eyes.png','bodyDiameter':368,'eyeLengthIncludingCaps':102,'eyeThickness':14,'eyeCenters':[[-82,-15],[82,-14]],'handCenters':[[-122,132],[107,124]],'handDiameters':[122,116]},indent=2)+'\n')
(HERE/'motion-samples.json').write_text(json.dumps(motion)+'\n')
print('Created',NAME,aid,len(keys),'keys; original animations and base geometry untouched')
