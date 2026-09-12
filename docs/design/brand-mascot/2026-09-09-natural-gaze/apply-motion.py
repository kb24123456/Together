#!/usr/bin/env python3
"""Apply the scoped, reviewed motion.json to the identified open Rive file.

Run deliberately while the editor is stopped. Reads back every written key and
compares all non-target tracks with source-keyframes.json. No App files touched.
"""
import json
import urllib.request
from pathlib import Path

HERE=Path(__file__).resolve().parent
motion=json.loads((HERE/'motion.json').read_text())
before=json.loads((HERE/'source-keyframes.json').read_text())['keyframes']

def call(name,args):
    request=urllib.request.Request('http://127.0.0.1:9791/mcp',json.dumps(dict(jsonrpc='2.0',id=10,
        method='tools/call',params=dict(name=name,arguments=args))).encode(),
        {'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
    with urllib.request.urlopen(request,timeout=120) as response: raw=json.load(response)['result']
    text=raw.get('structuredContent',{}).get('content') or next(c['text'] for c in raw['content'] if c['type']=='text')
    result=json.loads(text)
    assert result.get('success',True) and not result.get('errors'), result
    return result

def animation(command,data): return call('animation_editor',dict(command=command,data={command:data}))

def main():
    session=call('session_info',{})
    assert session['activeFileId']==motion['fileId']
    call('set_property_values',{'propertyValues':{'0-18430':{'57':1668,'59':1}}})
    checks=[]
    for name,plan in motion['plans'].items():
        aid=plan['id']; current=animation('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
        targets=set(plan['tracks'])
        doomed=[k['keyframeId'] for k in current if plan['complete'] or k['objectId']+':'+str(k['propertyKey']) in targets]
        if doomed:animation('modifyKeyFrames',dict(animationId=aid,delete=doomed))
        added=[]
        for key, values in plan['tracks'].items():
            obj,prop=key.split(':')
            added.extend(dict(objectId=obj,propertyKey=int(prop),frame=frame,value=value,interpolationType='linear') for frame,value in values)
        for offset in range(0,len(added),1500):animation('modifyKeyFrames',dict(animationId=aid,add=added[offset:offset+1500]))
        actual=animation('queryKeyFrames',{'animationIds':[aid]})['keyframes'][aid]
        norm=lambda k:(k['objectId'],k['propertyKey'],k['frame'],k['value'],k['interpolationType'])
        expected=sorted(map(norm,added)); observed=sorted(norm(k) for k in actual if k['objectId']+':'+str(k['propertyKey']) in targets)
        assert len(expected)==len(observed), name+' keyframe count'
        assert all(a[:3]==b[:3] and a[4]==b[4] and abs(a[3]-b[3])<1e-9
                   for a,b in zip(expected,observed)), name+' keyframe readback'
        untouched=plan['complete'] or [k for k in actual if k['objectId']+':'+str(k['propertyKey']) not in targets]==[k for k in before[aid] if k['objectId']+':'+str(k['propertyKey']) not in targets]
        assert untouched, name+' untouched tracks'
        checks.append(dict(name=name,id=aid,keys=len(added),readback=True,untouchedTracks=True))
        print(name,len(added),'verified',flush=True)
    ids=list(before)
    all_after=animation('queryKeyFrames',{'animationIds':ids})['keyframes']
    changed_ids={p['id'] for p in motion['plans'].values()}
    preserved=[aid for aid in ids if aid not in changed_ids]
    assert all(all_after[aid]==before[aid] for aid in preserved)
    result=dict(passed=True,checks=checks,untouchedTimelineCount=len(preserved),untouchedTimelineIds=preserved)
    (HERE/'verification-readback.json').write_text(json.dumps(result,indent=2)+'\n')
    print('All scoped keyframes and unrelated timelines verified',flush=True)

if __name__=='__main__':main()
