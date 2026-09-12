from rive_client import *
r=json.loads((HERE/'rig.json').read_text())
sh=[]
for name,points,w in [('BlushLeftA',[(-87,12),(-96,23)],7),('BlushLeftB',[(-71,16),(-80,27)],7),('BlushRightA',[(71,16),(62,27)],7),('BlushRightB',[(87,12),(78,23)],7),('ExpressionZSmall',[(115,-92),(131,-92),(115,-75),(131,-75)],6),('ExpressionZMedium',[(143,-117),(164,-117),(143,-94),(164,-94)],7),('ExpressionZLarge',[(178,-145),(204,-145),(178,-115),(204,-115)],8)]:
 sh.append(dict(name=name,parentId=r['newFace'],x=0,y=0,paths=[dict(commands=[dict(commandType='moveTo',x=points[0][0],y=points[0][1])]+[dict(commandType='lineTo',x=x,y=y)for x,y in points[1:]])],paints=[dict(paintType='stroke',color='#FFFFFF')]))
cmd('path_editor','createShapes',{'shapes':sh})
h=call('query_objects',dict(objectIds=[r['newFace']],depth=4))['objects'];by={o['id']:o for o in h};bn={o['name']:o for o in h};bindings=[];values={}
for a in sh:
 o=bn[a['name']];p=next(by[c]for c in o['children']if 'PointsPath'in by[c]['types']);s=next(by[c]for c in o['children']if 'Stroke'in by[c]['types']);col=by[s['children'][0]];r[a['name']]={'id':o['id'],'path':p['id'],'stroke':s['id'],'color':col['id']};w=7 if a['name'].startswith('Blush')else 6 if a['name'].endswith('Small')else 7 if a['name'].endswith('Medium')else 8
 values[o['id']]={'18':0};values[p['id']]={'32':False};values[s['id']]={'47':w,'48':1,'49':1}
 bindings.append(dict(objectId=col['id'],propertyKey=37,viewModelPropertyId='0-169112' if 'Z'in a['name'] else '0-169104'))
for name in ['ExpressionEyeLeft','ExpressionEyeRight','ExpressionMouth','ExpressionSweat','ExpressionTearLeft','ExpressionTearRight']:
 bindings.append(dict(objectId=r[name]['color'],propertyKey=37,viewModelPropertyId='0-245630'if 'Tear'in name else '0-169106'if 'Sweat'in name else '0-169104'))
bindings.extend([dict(objectId='0-452879',propertyKey=38,viewModelPropertyId='0-169092'),dict(objectId='0-452880',propertyKey=38,viewModelPropertyId='0-169094')])
props(values);cmd('viewmodel_editor','databind',dict(viewModelId='0-375',bindings=bindings));save('rig.json',r);print('components and theme bindings ready')
