"""Editable vector presets and separate additive motion tracks for the existing sphere."""
import math,json
from rive_client import HERE
R=json.loads((HERE/'rig.json').read_text());N=32

def resample(points,n=N):
    if points[0]!=points[-1]:points=points+[points[0]]
    ds=[0]
    for a,b in zip(points,points[1:]):ds.append(ds[-1]+math.dist(a,b))
    out=[];j=0
    for i in range(n):
        t=ds[-1]*i/n
        while j+1<len(ds)-1 and ds[j+1]<t:j+=1
        f=(t-ds[j])/(ds[j+1]-ds[j] or 1);a,b=points[j:j+2];out.append((a[0]+f*(b[0]-a[0]),a[1]+f*(b[1]-a[1])))
    return out

def ellipse(w,h,n=128):return [(w/2*math.sin(2*math.pi*i/n),-h/2*math.cos(2*math.pi*i/n))for i in range(n)]
def stroke(ps,width):
    # Closed, filled outline with round caps: all final Rive parts remain editable vectors.
    r=width/2;ang=[math.atan2(b[1]-a[1],b[0]-a[0])for a,b in zip(ps,ps[1:])];left=[];right=[]
    for i,(x,y) in enumerate(ps):
        t=ang[0] if i==0 else ang[-1] if i==len(ps)-1 else (ang[i-1]+ang[i])/2
        left.append((x+r*math.sin(t),y-r*math.cos(t)));right.append((x-r*math.sin(t),y+r*math.cos(t)))
    out=left; x,y=ps[-1];t=ang[-1]-math.pi/2
    out += [(x+r*math.cos(t+math.pi*j/16),y+r*math.sin(t+math.pi*j/16))for j in range(1,17)]
    out+=right[-2::-1];x,y=ps[0];t=ang[0]+math.pi/2
    out +=[(x+r*math.cos(t+math.pi*j/16),y+r*math.sin(t+math.pi*j/16))for j in range(1,17)]
    return out

def capsule(w=30,h=78):return stroke([(0,-(h-w)/2),(0,(h-w)/2)],w)
def arc(up=True,w=58,h=24,weight=16):return stroke([(-w/2+w*i/40,(-h if up else h)*math.sin(math.pi*i/40))for i in range(41)],weight)
def heart():
    p=[]
    for i in range(160):
        t=2*math.pi*i/160;p.append((1.9*16*math.sin(t)**3,-1.9*(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t))-4))
    # Start top-mid and follow clockwise like other eye contours.
    return p

def bowl(w=44,h=36):return [(-w/2,-h/2),(w/2,-h/2)]+[(w/2*math.cos(t),-h/2+h*math.sin(t))for t in [math.pi*i/60 for i in range(61)]]
def tear(w=25,h=42):return [(0,-h/2)]+[(w/2*math.cos(t),h*.08+h*.42*math.sin(t))for t in [(-math.pi/3)+(5*math.pi/3)*i/90 for i in range(91)]]
def angled(inward=True,side=-1,gentle=False):
    def cubic(a,b,c,d):
        return [((1-t)**3*a[0]+3*(1-t)**2*t*b[0]+3*(1-t)*t*t*c[0]+t**3*d[0],(1-t)**3*a[1]+3*(1-t)**2*t*b[1]+3*(1-t)*t*t*c[1]+t**3*d[1])for t in [i/24 for i in range(25)]]
    pts=[]
    segments=[((-17,-30),(-20,-32),(-20,-15),(-20,4)),((-20,4),(-20,22),(-14,30),(-3,30)),((-3,30),(10,30),(19,23),(19,12)),((19,12),(19,6),(19,0),(18,-3)),((18,-3),(16,-7),(-9,-24),(-17,-30))]
    if gentle:segments=[((-14,-31),(-16,-33),(-16,-14),(-16,5)),((-16,5),(-16,25),(-10,32),(0,32)),((0,32),(11,32),(16,24),(16,12)),((16,12),(16,-1),(16,-17),(15,-21)),((15,-21),(11,-24),(-8,-29),(-14,-31))]
    for args in segments:pts+=cubic(*args)[:-1]
    if (side==1)==inward:pts=[(-x,y)for x,y in pts][::-1]
    # Match the clockwise winding of the existing editable eye path. The runtime
    # contour must retain its winding across poses, including these slanted lids.
    return pts[::-1]

def geom(part,points):
    pts=resample(points,len(R[part]['vertices']));n=len(pts);out={}
    for i,(oid,(x,y)) in enumerate(zip(R[part]['vertices'],pts)):
        a,b=pts[(i-1)%n],pts[(i+1)%n];dx=(b[0]-a[0])/6;dy=(b[1]-a[1])/6
        rot=math.degrees(math.atan2(dy,dx)); expected=360*i/n
        rot+=360*round((expected-rot)/360)
        out.update({oid+':24':x,oid+':25':y,oid+':82':rot,oid+':83':math.hypot(dx,dy)})
    return out

def trans(out,oid,**kv):
    for k,v in kv.items():out[oid+':'+str({'x':13,'y':14,'r':15,'sx':16,'sy':17,'o':18}[k])]=v

def posture(out,sx=1,sy=1,dy=0):trans(out,R['posture'],x=256*(1-sx),y=240*(1-sy)+dy,sx=sx*100,sy=sy*100,r=0)

PRESETS=[
(1,'Calm','待机','图1-01'),(2,'SoftHappy','柔和开心','图1-02 + 图2-05'),(3,'Laugh','大笑','图1-03'),(4,'Excited','兴奋','图1-04'),(5,'WinkSmile','单眨眼带笑','图1-05'),(6,'Love','喜爱','图1-06'),(7,'Blush','害羞·腮红','图1-07'),(8,'Smug','小得意','图1-08 + 图2-06'),(9,'CuriousOpen','好奇·张嘴','图1-09'),(10,'PuzzledOpen','疑惑·张嘴','图1-10'),(11,'ThinkingUp','思考·抬眼','图1-11'),(12,'GentleFocus','专注·轻','图1-12'),(13,'Surprised','惊讶','图1-13 + 图2-08'),(14,'Embarrassed','尴尬流汗','图1-14'),(15,'MildAngry','小生气','图1-15'),(16,'Speechless','无语','图1-16'),(17,'SleepyYawn','犯困·哈欠','图1-17'),(18,'Content','轻松满足','图1-18'),(19,'Sad','难过','图1-19'),(20,'SmallTears','委屈·短泪','图1-20'),(21,'CuriousQuiet','好奇·无嘴','图2-01'),(22,'PuzzledQuiet','思考／疑惑·无嘴','图2-02 + 图2-09'),(23,'Determined','专注·认真','图2-03'),(24,'Realization','恍然大悟','图2-04'),(25,'ShyLookAway','害羞·避开视线','图2-07'),(26,'Helpless','无奈','图2-10'),(27,'Nervous','小紧张','图2-11'),(28,'SleepyLow','犯困·趴低','图2-12')]

def pose(idx):
    out={};left=capsule();right=capsule(29,74);mouth=ellipse(18,18);mo=0;lx,ly,rx,ry=-49,-42,49,-44;lr=rr=0
    if idx==2:left=right=arc()
    elif idx==3:left=stroke([(-19,-19),(9,0),(-19,19)],16);right=stroke([(19,-19),(-9,0),(19,19)],16);mouth=bowl(65,50);mo=100
    elif idx==4:mouth=bowl();mo=100
    elif idx==5:right=stroke([(16,-15),(-10,0),(16,15)],16);mouth=arc(False,32,12,9);mo=100
    elif idx==6:left=right=heart();mouth=bowl(40,35);mo=100
    elif idx==8:left=bowl(37,22)
    elif idx in [9,21]:lx+=18;rx+=15;ly-=13;ry-=19;lr=-14;rr=-17;mouth=ellipse(18,18);mo=100 if idx==9 else 0
    elif idx==10:right=capsule(17,38);rr=90;mouth=arc(True,27,9,9);mo=100
    elif idx==11:lx+=15;rx+=12;ly-=23;ry-=30;lr=-13;rr=-15
    elif idx==12:left=capsule(30,59);right=capsule(29,55);ly+=5;ry+=5
    elif idx==13:left=ellipse(42,86);right=ellipse(40,83)
    elif idx==15:left=angled(True,-1);right=angled(True,1)
    elif idx in [16,26,28]:left=right=capsule(17,49);lr=rr=90;ly=ry=-30
    elif idx==17:left=right=bowl(41,21);mouth=ellipse(16,20);mo=100;ly=ry=-34
    elif idx==18:left=right=arc(False,48,19,15)
    elif idx==19:left=angled(False,-1);right=angled(False,1);ly=ry=-35
    elif idx==22:right=capsule(28,38);ly-=5;ry+=4;lr=rr=-8
    elif idx==23:left=angled(True,-1,True);right=angled(True,1,True);ly=ry=-28
    elif idx==24:left=capsule(28,96);right=capsule(27,93)
    elif idx==25:lx+=27;rx+=20;ly+=39;ry+=43;lr=14;rr=18;left=capsule(27,68);right=capsule(25,59)
    elif idx==27:lx=-31;rx=31;left=capsule(28,66);right=capsule(27,63)
    if idx==26:lr=85;rr=95
    if idx==28:ly=ry=62
    for part,shape,x,y,rot in [('ExpressionEyeLeft',left,lx,ly,lr),('ExpressionEyeRight',right,rx,ry,rr),('ExpressionMouth',mouth,0,44,0)]:
        out.update(geom(part,shape));trans(out,R[part]['id'],x=x,y=y,r=rot,sx=100,sy=100,o=mo if part=='ExpressionMouth' else 100)
    out.update(geom('ExpressionSweat',tear(33 if idx==14 else 23,55 if idx==14 else 38)))
    trans(out,R['ExpressionSweat']['id'],x=125,y=-86,r=0,sx=100,sy=100,o=100 if idx in [14,27]else 0)
    for part,x in [('ExpressionTearLeft',lx),('ExpressionTearRight',rx)]:
        out.update(geom(part,capsule(15,27)));trans(out,R[part]['id'],x=x,y=17,r=0,sx=100,sy=100,o=100 if idx==20 else 0)
    for name in ['BlushLeftA','BlushLeftB','BlushRightA','BlushRightB','ExpressionZSmall','ExpressionZMedium','ExpressionZLarge']:
        trans(out,R[name]['id'],x=0,y=0,sx=100,sy=100,r=0,o=(52 if name.startswith('Blush')and idx==7 else 80 if name.startswith('ExpressionZ')and idx==17 else 0))
    trans(out,R['newFace'],x=0,y=0,r=0,sx=100,sy=100,o=100 if idx else 0);trans(out,R['legacyFace'],o=0 if idx else 100)
    posture(out,1.04,.86,14)if idx==28 else posture(out,1.012,.98,3)if idx==23 else posture(out,.99,1.025,-4)if idx in [13,24]else posture(out)
    return out

def motion_pose(kind,t):
    out={};dx=dy=rot=0;sx=sy=1;fx=fy=fr=0;fsx=fsy=1;dent=0
    def sample(knots):
        if t>=knots[-1][0]:return knots[-1][1]
        for (a,x),(b,y)in zip(knots,knots[1:]):
            if a<=t<=b:
                f=(t-a)/(b-a);f=f*f*(3-2*f);return x+(y-x)*f
        return knots[0][1]
    if kind=='Observe':
        fx=sample([(0,0),(.1,19),(.38,20),(.55,15),(.76,0),(.9,0)]);fy=sample([(0,0),(.12,-9),(.48,-8),(.8,0),(.9,0)]);dx=sample([(0,0),(.10,0),(.27,7),(.52,7),(.84,0),(.9,0)]);rot=sample([(0,0),(.1,0),(.28,-1.4),(.55,-1.4),(.86,0),(.9,0)])
    elif kind=='Nod':
        dy=sample([(0,0),(.18,6),(.29,7),(.46,-1.5),(.7,0)]);sy=sample([(0,1),(.18,.962),(.29,.968),(.46,1.014),(.7,1)]);sx=1+(1-sy)*.5;fy=sample([(0,0),(.14,13),(.26,14),(.42,-3),(.7,0)])
    elif kind=='Celebrate':
        dy=sample([(0,0),(.14,9),(.33,-25),(.42,-27),(.65,6),(.78,2),(.92,-1),(1.1,0)]);sy=sample([(0,1),(.14,.935),(.27,1.055),(.43,1.018),(.65,.955),(.81,1.015),(1.1,1)]);sx=1+(1-sy)*.6;fy=sample([(0,0),(.14,5),(.30,-5),(.5,-4),(.65,4),(1.1,0)])
    elif kind=='Poke':
        dent=sample([(0,0),(.14,25),(.24,25),(.39,-3),(.56,2),(.72,0),(.86,0)]);dx=sample([(0,0),(.14,4),(.24,5),(.40,-4),(.6,1),(.86,0)]);fx=sample([(0,0),(.11,8),(.24,7),(.41,-6),(.62,1),(.86,0)]);fr=sample([(0,0),(.17,2),(.4,-1.5),(.86,0)]);fsy=sample([(0,1),(.12,.9),(.3,.96),(.5,1),(.86,1)])
    rad=math.radians(rot);trans(out,R['actionRoot'],x=256-(256*sx*math.cos(rad)-240*sy*math.sin(rad))+dx,y=240-(256*sx*math.sin(rad)+240*sy*math.cos(rad))+dy,r=rot,sx=sx*100,sy=sy*100)
    trans(out,R['faceMotion'],x=fx,y=fy,r=fr,sx=fsx*100,sy=fsy*100)
    pts=[]
    for i in range(32):
        a=2*math.pi*i/32;x=184*math.sin(a);y=-184*math.cos(a)
        if x<0:x+=dent*math.exp(-(y/40)**2)
        pts.append((x,y))
    out.update(geom('PokeBody',pts)); trans(out,R['PokeBody']['id'],o=100 if kind=='Poke'and 0<t<.80 else 0);trans(out,'0-15',o=0 if kind=='Poke'and 0<t<.80 else 100)
    return out

if __name__=='__main__':
    (HERE/'presets.json').write_text(json.dumps([dict(value=i,name=n,label=l,source=s)for i,n,l,s in PRESETS],ensure_ascii=False,indent=2))
    (HERE/'poses.json').write_text(json.dumps({str(i):pose(i)for i in range(29)}))
