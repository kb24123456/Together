import sys
from rive_client import *
from design import *
REP=[1,2,3,6,10,17]
mode=sys.argv[1] if len(sys.argv)>1 else 'representative'
indices=REP if mode=='representative'else[i for i,_,_,_ in PRESETS if i not in REP]
man=json.loads((HERE/'authored.json').read_text()) if (HERE/'authored.json').exists()else {'timelines':{},'states':{},'expressionsLayer':'0-452882','actionsLayer':'0-452886'}

def addtrack(d,k,f,v,hold=False):d.setdefault(k,[]).append([f,v,'hold'if hold else 'linear'])
def makeclip(name,duration,static,tracks=None,loop=False):
    if name in man['timelines']:return man['timelines'][name]
    a=anim('createLinearAnimations',{'linearAnimations':[{'name':name,'fps':60,'duration':duration}]}); allanim=anim('listLinearAnimations')['linearAnimations'];aid=next(x['id'] for x in allanim if x['name']==name);props({aid:{'59':1 if loop else 0}})
    data={k:[[0,v,'linear']] for k,v in static.items()};data.update(tracks or {});keys=[]
    for k,vs in data.items():
        obj,p=k.split(':');keys.extend(dict(objectId=obj,propertyKey=int(p),frame=f,value=v,interpolationType=inter)for f,v,inter in vs)
    for off in range(0,len(keys),1500):anim('modifyKeyFrames',dict(animationId=aid,add=keys[off:off+1500]))
    man['timelines'][name]={'id':aid,'duration':duration,'keys':len(keys),'loop':loop};save('authored.json',man);return man['timelines'][name]

def state(name,clip,layer,x,y):
    if name in man['states']:return man['states'][name]
    d=anim('createStates',{'layerId':layer,'states':[{'name':name,'linearAnimationName':clip,'x':x,'y':y}]}); l=anim('queryStateMachineLayer',{'layerId':layer});
    states=l.get('states')or l.get('layer',{}).get('states')or l.get('layers',[{}])[0].get('states')
    # query shape intentionally checked by returned data below.
    if states is None:raise RuntimeError(str(l)[:1600])
    sid=next(a['id'] for a in states if a['name']==name);man['states'][name]=sid;save('authored.json',man);return sid

if mode=='representative':
    makeclip('Expr_Auto',4.2,pose(0),loop=True)
    blank=pose(0);blank[R['legacyFace']+':18']=0
    makeclip('Expr_Resolve',1/60,blank)
    makeclip('Expr_ReactionBlank',.10,blank)
    makeclip('Action_Rest',1/60,motion_pose('Rest',0))
    for name,clip in [('Expr_Auto','Expr_Auto'),('Expr_Resolve','Expr_Resolve'),('Expr_ReactionBlank','Expr_ReactionBlank'),('Expr_CelebrationBlank','Expr_ReactionBlank')]:state(name,clip,man['expressionsLayer'],0,100+80*len(man['states']))
    state('Action_Rest','Action_Rest',man['actionsLayer'],200,100)
    for index,(kind,duration) in enumerate([('Observe',.9),('Nod',.7),('Celebrate',1.1),('Poke',.8666666667)]):
        frames=round(duration*60); samples=[motion_pose(kind,f/60) for f in range(frames+1)];tracks={}
        for k in samples[0]:
            vals=[s[k]for s in samples]
            if max(vals)-min(vals)<1e-8:continue
            tracks[k]=[[f,v,'hold'if k.endswith(':18')else'linear']for f,v in enumerate(vals)]
        clip='Action_'+kind;makeclip(clip,frames/60,samples[0],tracks);state(clip,clip,man['actionsLayer'],430,100+index*110)
for idx in indices:
    _,name,label,source=next(p for p in PRESETS if p[0]==idx);p=pose(idx);tracks={}
    facekey=R['newFace']+':14'
    tracks[facekey]=[[0,0,'linear'],[70,-1.1,'linear'],[140,0.8,'linear'],[252,0,'linear']]
    if idx in [1,4,7,9,11,12,14,20,21,22,24,25,27]:
        for part in ['ExpressionEyeLeft','ExpressionEyeRight']:tracks[R[part]['id']+':17']=[[0,100,'linear'],[164,100,'linear'],[170,8,'linear'],[174,8,'linear'],[186,100,'linear'],[252,100,'linear']]
    if idx==17:
        for j,part in enumerate(['ExpressionZSmall','ExpressionZMedium','ExpressionZLarge']):
            oid=R[part]['id'];tracks[oid+':18']=[[0,0,'linear'],[12+j*13,0,'linear'],[38+j*13,75,'linear'],[102+j*13,70,'linear'],[135+j*13,0,'linear'],[252,0,'linear']];tracks[oid+':14']=[[0,5,'linear'],[170,-12,'linear'],[251,-12,'hold'],[252,5,'linear']]
    if idx in [14,27]:tracks[R['ExpressionSweat']['id']+':14']=[[0,-92,'linear'],[24,-86,'linear'],[70,-80,'linear'],[110,-85,'linear'],[252,-92,'linear']]
    if idx==20:
        for j,part in enumerate(['ExpressionTearLeft','ExpressionTearRight']):
            oid=R[part]['id'];tracks[oid+':18']=[[0,0,'linear'],[15+j*8,0,'linear'],[30+j*8,100,'linear'],[65+j*8,100,'linear'],[85+j*8,0,'linear'],[252,0,'linear']];tracks[oid+':14']=[[0,9,'linear'],[90,32,'linear'],[251,32,'hold'],[252,9,'linear']]
    makeclip('Expr_'+name,4.2,p,tracks,True)
    close={}
    for k in [R['newFace']+':18',R['legacyFace']+':18']:close[k]=[[0,p[k],'linear'],[6,0,'linear']]
    for k,v in pose(0).items():
        if k.startswith(R['posture']+':')and p[k]!=v:close[k]=[[0,p[k],'linear'],[6,v,'linear']]
    makeclip('Expr_Close_'+name,.1,p,close)
    pulse={}
    for k in [R['newFace']+':18',R['legacyFace']+':18']:pulse[k]=[[0,p[k],'linear'],[57,p[k],'linear'],[72,0,'linear']]
    pulse[facekey]=[[0,0,'linear'],[16,-2,'linear'],[42,.8,'linear'],[72,0,'linear']]
    for k,v in pose(0).items():
        if k.startswith(R['posture']+':')and p[k]!=v:pulse[k]=[[0,p[k],'linear'],[57,p[k],'linear'],[72,v,'linear']]
    if idx==17:
        for j,part in enumerate(['ExpressionZSmall','ExpressionZMedium','ExpressionZLarge']):pulse[R[part]['id']+':18']=[[0,0,'linear'],[9+j*7,0,'linear'],[21+j*7,75,'linear'],[57,60,'linear'],[72,0,'linear']]
    makeclip('Expr_Pulse_'+name,1.2,p,pulse)
    for j,(prefix,clip)in enumerate([('Hold_','Expr_'),('Close_','Expr_Close_'),('Pulse_','Expr_Pulse_')]):state(prefix+name,clip+name,man['expressionsLayer'],300+j*300,idx*110)
    print(idx,name,'authored',flush=True)
if mode=='representative':
    p=pose(0);makeclip('Expr_Close_Auto',.1,p,{R['legacyFace']+':18':[[0,100,'linear'],[6,0,'linear']]});state('Close_Auto','Expr_Close_Auto',man['expressionsLayer'],300,0)
print('batch complete')
