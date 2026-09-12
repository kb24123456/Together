"""Add four editable eye shapes only. Original hierarchy/geometry is untouched."""
from common import *
assert call('session_info',{})['activeFileId']==2564580
assert not (HERE/'rig.json').exists(), 'Do not duplicate the home rig'
R={'home':group('HomeFace',OLD_RIG['faceMotion'])}
props({R['home']:{'18':0}})
shapes=[]
for side,sign in [('Near',-1),('Far',1)]:
    R[side]={'gaze':group('Home'+side+'Gaze',R['home'])}
    R[side]['pose']=group('Home'+side+'Pose',R[side]['gaze'])
    x,y,w,h,r=eye_parameters(.15,.2,sign)
    props({R[side]['gaze']:{'13':x,'14':y,'15':r}})
    capsule=cmds_for_vertices(local_eye(x,y,w,h,r))
    # Approved mouthless smile contour, centered on the eye's own origin.
    points=resample([(x,y+12) for x,y in arc(w=62,h=24,weight=16)],32)
    vertices=[]
    for i,(x,y) in enumerate(points):
        a,b=points[(i-1)%32],points[(i+1)%32];dx,dy=(b[0]-a[0])/6,(b[1]-a[1])/6
        angle=math.degrees(math.atan2(dy,dx));d=math.hypot(dx,dy)
        vertices.append(dict(x=x,y=y,inr=angle+180,ind=d,outr=angle,outd=d))
    for kind,commands in [('Capsule',capsule),('Smile',cmds_for_vertices(vertices))]:
        shapes.append(dict(name='Home'+side+kind,parentId=R[side]['pose'],x=0,y=0,paths=[dict(commands=commands)],paints=[dict(paintType='fill',color='#FAFAFA')]))
cmd('path_editor','createShapes',{'shapes':shapes})
objects=call('query_objects',{'objectIds':[R['home']],'depth':6})['objects'];by={o['id']:o for o in objects};bn={o['name']:o for o in objects};bindings=[]
for side in ['Near','Far']:
    for kind in ['Capsule','Smile']:
        o=bn['Home'+side+kind];path=next(by[c] for c in o['children'] if 'PointsPath' in by[c]['types']);fill=next(by[c] for c in o['children'] if 'Fill' in by[c]['types']);color=next(by[c] for c in fill['children'] if 'SolidColor' in by[c]['types'])
        R[side][kind]={'id':o['id'],'path':path['id'],'vertices':path['children'],'color':color['id']}
        bindings.append(dict(objectId=color['id'],propertyKey=37,viewModelPropertyId='0-169104'))
        props({o['id']:{'18':0 if kind=='Smile' else 100}})
cmd('viewmodel_editor','databind',dict(viewModelId='0-375',bindings=bindings))
save('rig.json',R);save('rig-objects.json',objects)
print(json.dumps(R))
