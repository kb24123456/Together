"""Three calm home faces with finite continuous transitions; no whole-face fade."""
from common import *
R=json.loads((HERE/'rig.json').read_text())
MAN=HERE/'home-clips.json'
assert not MAN.exists(), 'Home clips already authored'
def pose(kind,t=1):
    out={R['home']+':18':100,OLD_RIG['newFace']+':18':0,OLD_RIG['legacyFace']+':18':0}
    for pk,v in [(13,0),(14,0),(15,0),(16,100),(17,100)]:out[OLD_RIG['posture']+':'+str(pk)]=v
    for side,sign in [('Near',-1),('Far',1)]:
        p=R[side]['pose'];c=R[side]['Capsule']['id'];a=R[side]['Smile']['id']
        out.update({p+':13':0,p+':14':0,p+':15':0,p+':16':100,p+':17':100,c+':16':100,c+':17':100,c+':18':100,a+':16':100,a+':17':100,a+':18':0})
        if kind=='Curious':
            q=smooth([[0,0],[1,1]],t)
            out.update({p+':13':12*q,p+':14':(-9 if sign<0 else -14)*q,p+':15':(-6 if sign<0 else -8)*q,p+':17':100+(2 if sign<0 else -8)*q})
        elif kind=='Happy':
            # During the narrow-eye phase the two outlines overlap at the same
            # center. The arc is already visible before the capsule disappears,
            # so even an underlying automatic blink cannot produce a blank face.
            q=smooth([[0,0],[1,1]],t)
            close=smooth([[0,0],[.42,1],[1,1]],t)
            arcOpen=smooth([[0,.2],[.40,.2],[1,1]],t)
            alpha=smooth([[0,0],[.22,0],[.44,100],[1,100]],t)
            out.update({p+':13':sign*14*q,p+':14':-2*q,
                        c+':16':100+160*close,c+':17':100-90*close,c+':18':100-alpha,
                        a+':17':100*arcOpen,a+':18':alpha})
    if kind=='Release':out.update({R['home']+':18':0,OLD_RIG['legacyFace']+':18':100})
    return out
specs=[('Home_Calm','Calm',1,False,True),('Home_CuriousEnter','Curious',.25,False,False),('Home_CuriousHold','Curious',1,False,True),('Home_CuriousExit','Curious',.25,True,False),('Home_HappyEnter','Happy',.30,False,False),('Home_HappyHold','Happy',1,False,True),('Home_HappyExit','Happy',.30,True,False),('Home_Release','Release',.10,False,False)]
man={}
for name,kind,dur,reverse,loop in specs:
    anim('createLinearAnimations',{'linearAnimations':[{'name':name,'fps':60,'duration':dur}]})
    aid=next(a['id']for a in anim('listLinearAnimations')['linearAnimations']if a['name']==name)
    props({aid:{'59':1 if loop else 0}})
    end=round(dur*60);fs=[pose(kind,1 if loop else 1-f/end if reverse else f/end)for f in range(end+1)]
    ts={k:([[0,fs[0][k]],[end,fs[-1][k]]] if all(abs(p[k]-fs[0][k])<1e-10 for p in fs) else [[f,p[k]]for f,p in enumerate(fs)]) for k in fs[0]}
    count=write_tracks(aid,ts)
    anim('createStates',{'layerId':'0-452882','states':[{'name':name,'linearAnimationName':name,'x':1400,'y':-500+len(man)*110}]})
    layer=anim('queryStateMachineLayer',{'layerId':'0-452882'});states=layer.get('states')or layer['layer']['states'];sid=next(s['id']for s in states if s['name']==name)
    man[name]=dict(id=aid,state=sid,frames=end,keys=count)
    print(name,count,flush=True)
save('home-clips.json',man)
# Every possible existing entry clears only the added HomeFace visibility.
oldtimes=json.loads((HERE/'backups/timelines.json').read_text())['linearAnimations']
for name in ['Expr_Auto','Expr_Resolve','Expr_ReactionBlank']:
    aid=next(a['id']for a in oldtimes if a['name']==name)
    write_tracks(aid,{R['home']+':18':[[0,0]]})
save('home-pose-calm.json',pose('Calm'))
