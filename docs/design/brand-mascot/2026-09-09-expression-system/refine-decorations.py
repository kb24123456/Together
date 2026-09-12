from rive_client import *
from design import *
m=json.loads((HERE/'authored.json').read_text())
def replace(aid,tracks):
    ks=anim('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
    anim('modifyKeyFrames',{'animationId':aid,'delete':[k['keyframeId']for k in ks if k['objectId']+':'+str(k['propertyKey'])in tracks]})
    adds=[]
    for k,vs in tracks.items():
        o,p=k.split(':');adds.extend(dict(objectId=o,propertyKey=int(p),frame=f,value=v,interpolationType='linear')for f,v in vs)
    anim('modifyKeyFrames',{'animationId':aid,'add':adds})
for name in ['Embarrassed','Nervous']:
    for prefix in ['Expr_','Expr_Close_','Expr_Pulse_']:
        oid=R['ExpressionSweat']['id'];tracks={oid+':13':[[0,125]],oid+':14':[[0,-86]]}
        if prefix=='Expr_':tracks[oid+':14']=[[0,-92],[24,-86],[70,-80],[110,-85],[252,-92]]
        replace(m['timelines'][prefix+name]['id'],tracks)
tracks={}
for shift,part in [(0,'ExpressionTearLeft'),(28,'ExpressionTearRight')]:
    oid=R[part]['id'];ys=[];ops=[]
    for f in range(253):
        phase=(f+shift)%84
        alpha=100 if 8<=phase<64 else phase/8*100 if phase<8 else max(0,100-(phase-64)/8*100)
        y=10+phase/84*18
        ys.append([f,y]);ops.append([f,alpha])
    tracks[oid+':18']=ops;tracks[oid+':14']=ys
replace(m['timelines']['Expr_SmallTears']['id'],tracks)
print('Sweat kept inside silhouette; short tears staggered so emotion remains readable')
