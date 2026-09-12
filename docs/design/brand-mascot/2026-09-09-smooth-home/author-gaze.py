"""Softer acceleration, 18% larger glances, modestly shorter quiet intervals.

Both old and home capsules use the same spherical projection. Home smile is a
separate vector contour and does not inherit the capsule's blink geometry.
"""
from common import *
R=json.loads((HERE/'rig.json').read_text())
specs={
 'Idle':('0-6',336,[-.7704,.7428],[-.6996,.8136],[40,86,126,154,181,231],5),
 'Idle_QuietMedium':('0-8762',276,[.7046,-.6614],[.7754,-.6024],[32,78,107,133,150,201],-4),
 'Idle_Look':('0-5972',120,[-.617,-.4844],[-.5698,-.5316],[4,38,48,60,68,108],3),
 'Idle_GazeUp':('0-359913',252,[.0084,.9906],[-.0624,.908],[22,68,97,125,144,194],-5),
 'Idle_GazeDown':('0-359914',264,[-.1686,-.8856],[-.0742,-.803],[40,88,111,139,159,211],-6),
 'Idle_GazeUpRight':('0-359915',300,[.6574,.6012],[.7282,.672],[51,97,139,164,189,238],6),
 'Idle_QuietShort':('0-5971',162,[.15,.2],[.15,.2],[0,1,2,3,4,5],0),
 'Idle_Select':('0-5973',1,[.15,.2],[.15,.2],[0,1,2,3,4,5],0),
}
plans={}
for name,(aid,end,target,correction,times,lag) in specs.items():
    original=tracks(aid); oldend=max(v[-1][0] for v in original.values())
    a,b,c,d,e,f=times
    yaw=[[0,.15],[a,.15],[b,target[0]],[c,target[0]],[d,correction[0]],[e,correction[0]],[f,.15],[max(end,f+1),.15]]
    pitch=[[0,.2],[max(0,a+lag),.2],[b+lag,target[1]],[c+lag,target[1]],[d+lag,correction[1]],[e+lag,correction[1]],[f+lag,.2],[max(end,f+lag+1),.2]]
    frames=[]
    for frame in range(end+1):
        source={k:sample(v,frame*oldend/end) for k,v in original.items()}
        yy,pp=(.15,.2) if name in ['Idle_QuietShort','Idle_Select'] else (smooth(yaw,frame),smooth(pitch,frame))
        for side,sign,oldpath,oldname in [('Near',-1,'0-25','SphereEyeNear'),('Far',1,'0-29','SphereEyeFar')]:
            x,y,w,h,r=eye_parameters(yy,pp,sign)
            blink=source.get(oldpath+':21',V6['neutral'][oldpath+':21'])/V6['neutral'][oldpath+':21']
            oldpoints=H.as_rive_properties(H.project_eye(x,y,w,h*blink,r))
            for oid,vals in zip(V6['sphereEyeRig'][oldname]['vertices'],oldpoints): source.update({oid+':'+k:v for k,v in vals.items()})
            source.update({R[side]['gaze']+':13':x,R[side]['gaze']+':14':y,R[side]['gaze']+':15':r})
            for oid,vals in zip(R[side]['Capsule']['vertices'],H.as_rive_properties(local_eye(x,y,w,h*blink,r))):source.update({oid+':'+k:v for k,v in vals.items()})
        frames.append(source)
    def reduce(points,tolerance=.025):
        if len(points)<3:return points
        a,x=points[0];b,y=points[-1]
        error,j=max((abs(v-(x+(y-x)*(f-a)/(b-a))),j)for j,(f,v)in enumerate(points[1:-1],1))
        return [points[0],points[-1]] if error<=tolerance else reduce(points[:j+1],tolerance)[:-1]+reduce(points[j:],tolerance)
    # 60fps authoring with bounded linear reduction. 0.025 artboard units is
    # <0.004pt at the largest 56pt in-app body, preserving smooth curves cheaply.
    ts={k:reduce([[f,frame[k]]for f,frame in enumerate(frames)])for k in frames[0]}
    for vertices in [V6['sphereEyeRig'][n]['vertices']for n in ['SphereEyeNear','SphereEyeFar']]+[R[s]['Capsule']['vertices']for s in ['Near','Far']]:
        for a,b in [(0,1),(2,3),(4,5),(6,7)]:
            ks=[vertices[i]+':'+pk for i in [a,b]for pk in ['24','25']]
            times=sorted({f for k in ks for f,_ in ts[k]})
            for k in ks:ts[k]=[[f,frames[f][k]]for f in times]
    props({aid:{'57':end}})
    count=write_tracks(aid,ts)
    plans[name]=dict(id=aid,frames=end,oldFrames=oldend,target=target,correction=correction,yaw=yaw,pitch=pitch,keys=count)
    print(name,count,'keys',flush=True)
save('gaze-plans.json',plans)
