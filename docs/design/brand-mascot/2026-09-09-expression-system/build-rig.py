import math,json
from rive_client import *
assert call('session_info',{})['activeFileId']==2564580
rig={'newFace':'0-452647'}
# New zero-transform parents preserve every existing keyed coordinate.
rig['actionRoot']=group('LightActionRoot','0-2')
rig['posture']=group('ExpressionPosture',rig['actionRoot'])
call('reparent_objects',{'operations':[{'objectId':'0-14','newParentId':rig['posture']}]})
props({'0-14':{'13':256,'14':240},rig['actionRoot']:{'13':0,'14':0},rig['posture']:{'13':0,'14':0}})
rig['faceMotion']=group('FaceMotion','0-14')
rig['legacyFace']=group('LegacyFace',rig['faceMotion'])
ids=['0-318752','0-13091','0-21','0-20','0-19']
call('reparent_objects',{'operations':[{'objectId':i,'newParentId':rig['legacyFace'],'position':'end'}for i in ids]+[{'objectId':rig['newFace'],'newParentId':rig['faceMotion'],'position':'start'}]})
props({i:{'13':0,'14':0}for i in ids+[rig['newFace']]})
# parametric Body remains unchanged. A separate cubic outline is only revealed for local poke deformation.
def circle(n,r):return [(r*math.sin(2*math.pi*i/n),-r*math.cos(2*math.pi*i/n))for i in range(n)]
def commands(points):
 out=[dict(commandType='moveTo',x=points[0][0],y=points[0][1])];n=len(points)
 for j in range(1,n+1):
  a=points[(j-1)%n];b=points[j%n];pre=points[(j-2)%n];nxt=points[(j+1)%n]
  out.append(dict(commandType='cubicTo',control1X=a[0]+(b[0]-pre[0])/6,control1Y=a[1]+(b[1]-pre[1])/6,control2X=b[0]-(nxt[0]-a[0])/6,control2Y=b[1]-(nxt[1]-a[1])/6,endX=b[0],endY=b[1]))
 out.append(dict(commandType='close'));return out
shapes=[]
for name,parent,pts in [('ExpressionEyeLeft',rig['newFace'],circle(32,25)),('ExpressionEyeRight',rig['newFace'],circle(32,25)),('ExpressionMouth',rig['newFace'],circle(32,20)),('ExpressionSweat',rig['newFace'],circle(16,20)),('ExpressionTearLeft',rig['newFace'],circle(16,12)),('ExpressionTearRight',rig['newFace'],circle(16,12)),('PokeBody','0-14',circle(32,184))]:
 shapes.append(dict(name=name,parentId=parent,x=0,y=0,paths=[dict(commands=commands(pts))],paints=[dict(paintType='fill',color='#FAFAFA' if name!='PokeBody' else '#101010')]))
cmd('path_editor','createShapes',{'shapes':shapes})
h=hierarchy();by={o['id']:o for o in h};names={o['name']:o for o in h};
for a in shapes:
 o=names[a['name']]; path=next(by[c]for c in o['children'] if 'PointsPath' in by[c]['types']);paint=next(by[c]for c in o['children'] if 'Fill' in by[c]['types']);color=next(by[c] for c in paint['children'] if 'SolidColor' in by[c]['types'])
 rig[a['name']]={'id':o['id'],'path':path['id'],'vertices':path['children'],'fill':paint['id'],'color':color['id']};print(a['name'],len(path['children']))
props({rig['PokeBody']['id']:{'18':0},rig['newFace']:{'18':0}})
# Put alternative body next to the original, behind faces and existing props.
call('reparent_objects',{'operations':[{'objectId':rig['PokeBody']['id'],'newParentId':'0-14','position':'end'}]})
cmd('path_editor','setPaints',{'paintIds':[rig['PokeBody']['fill']],'gradient':{'type':'radial','startX':-85,'startY':-110,'endX':120,'endY':160,'stops':[{'color':'#101010','position':0},{'color':'#030303','position':100}]}})
save('rig.json',rig);save('rig-hierarchy.json',hierarchy());print(json.dumps(rig,indent=2))
