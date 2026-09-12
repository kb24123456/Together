#!/usr/bin/env python3
"""Capture native Rive direction proofs, restoring every temporary pose value."""
import base64
import importlib.util
import json
import urllib.request
from pathlib import Path

HERE=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('rive_io',HERE/'apply-motion.py')
io=importlib.util.module_from_spec(s);s.loader.exec_module(io)
m=json.loads((HERE/'motion.json').read_text())
source=io.before

def sample(v,f):
    if f<=v[0][0]:return v[0][1]
    for (a,x),(b,y) in zip(v,v[1:]):
        if f<=b:return x+(y-x)*(f-a)/(b-a)
    return v[-1][1]

def grouped(values):
    result={}
    for k,v in values.items():
        obj,key=k.split(':');result.setdefault(obj,{})[key]=v
    return result

all_keys=set(m['plans']['Idle_GazeUp']['tracks'])
query={obj:[int(k) for k in vs] for obj,vs in grouped({k:0 for k in all_keys}).items()}
original=io.call('query_property_values',{'propertyKeys':query})['values']
(HERE/'capture-original-values.json').write_text(json.dumps(original,separators=(',',':'))+'\n')
(HERE/'assets').mkdir(exist_ok=True)
try:
    for name,p in m['plans'].items():
        if 'direction' not in p:continue
        f=p['times'][2]
        base={}
        for k in source[p['source']]:base.setdefault(k['objectId']+':'+str(k['propertyKey']),[]).append([k['frame'],k['value']])
        end=max(max(x[0] for x in v) for v in base.values())
        pose={k:sample(sorted(v),f*end/p['frames']) for k,v in base.items()}
        pose.update({k:sample(v,f) for k,v in p['tracks'].items()})
        io.call('set_property_values',{'propertyValues':grouped(pose)})
        req=urllib.request.Request('http://127.0.0.1:9791/mcp',json.dumps(dict(jsonrpc='2.0',id=11,method='tools/call',params=dict(name='capture_artboard',arguments=dict(artboardId='0-2',backgroundColor='#fafafa',longEdge=512)))).encode(),{'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
        with urllib.request.urlopen(req,timeout=60) as r:raw=json.load(r)['result']
        img=next(c for c in raw['content'] if c['type']=='image')
        (HERE/'assets'/f"{p['direction']}.png").write_bytes(base64.b64decode(img['data']))
        print(p['direction'],'captured',flush=True)
finally:
    io.call('set_property_values',{'propertyValues':original})
    after=io.call('query_property_values',{'propertyKeys':query})['values']
    assert after==original,'Restore mismatch'
    print('Original design pose restored',flush=True)
