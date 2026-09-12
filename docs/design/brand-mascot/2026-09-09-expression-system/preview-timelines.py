from rive_client import *
from design import *
m=json.loads((HERE/'authored.json').read_text())
def upload(name,duration,tracks):
    anim('createLinearAnimations',{'linearAnimations':[{'name':name,'fps':60,'duration':duration}]});a=next(a for a in anim('listLinearAnimations')['linearAnimations']if a['name']==name);aid=a['id'];props({aid:{'59':1}});keys=[]
    for k,vs in tracks.items():
        o,p=k.split(':');keys.extend(dict(objectId=o,propertyKey=int(p),frame=f,value=v,interpolationType='linear')for f,v in vs)
    for off in range(0,len(keys),1500):anim('modifyKeyFrames',dict(animationId=aid,add=keys[off:off+1500]))
    m['timelines'][name]={'id':aid,'duration':duration,'keys':len(keys),'previewOnly':True};save('authored.json',m);print(name,len(keys),'keys')
tracks={}
for j,(idx,name,label,src)in enumerate(PRESETS):
    p=pose(idx);base=pose(0);fade=dict(p);fade[R['newFace']+':18']=0
    for k in fade:
        if k.startswith(R['posture']+':'):fade[k]=base[k]
    for f,state in [(j*108,fade),(j*108+12,p),(j*108+90,p),(j*108+108,fade)]:
        for k,v in state.items():
            if tracks.get(k)and tracks[k][-1][0]==f:tracks[k][-1]=[f,v]
            else:tracks.setdefault(k,[]).append([f,v])
for k,v in motion_pose('Rest',0).items():tracks.setdefault(k,[[0,v]])
upload('Preview_Expressions_28',28*1.8,tracks)
tracks={}
sequence=[('Observe',1,.9),('Nod',2,.7),('Celebrate',2,1.1),('Poke',1,.8666666667)];offset=0
for kind,idx,duration in sequence:
    total=round((duration+.65)*60);movement=round(duration*60)
    for frame in range(total+1):
        p=pose(idx)|motion_pose(kind,max(0,(frame-12)/60))
        if frame<10:p[R['newFace']+':18']=frame*10
        if frame>total-9:p[R['newFace']+':18']=max(0,(total-frame)/9*100)
        for k,v in p.items():
            track=tracks.setdefault(k,[]);f=offset+frame
            if track and track[-1][0]==f:track[-1]=[f,v]
            else:track.append([f,v])
    offset+=total
# Keep endpoints of constant runs; varying curves remain sampled at 60 Hz.
for k,vs in tracks.items():tracks[k]=[a for i,a in enumerate(vs)if i in [0,len(vs)-1]or a[1]!=vs[i-1][1]or a[1]!=vs[i+1][1]]
upload('Preview_LightActions_4',offset/60,tracks)
