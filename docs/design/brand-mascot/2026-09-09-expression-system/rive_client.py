"""Scoped Rive MCP client; no edit runs on import."""
import json, urllib.request, base64, hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent

def call(name,args):
    r=urllib.request.Request('http://127.0.0.1:9791/mcp',json.dumps(dict(jsonrpc='2.0',id=50,method='tools/call',params=dict(name=name,arguments=args))).encode(),{'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
    with urllib.request.urlopen(r,timeout=120) as response: raw=json.load(response)['result']
    t=raw.get('structuredContent',{}).get('content') or next(c['text'] for c in raw['content'] if c['type']=='text')
    try:d=json.loads(t)
    except Exception:raise RuntimeError(t[:1400])
    assert d.get('success',True) and not d.get('errors') and (not d.get('warnings') or (name=='animation_editor' and args.get('command')=='deleteConditions' and all('has no conditions left' in w for w in d['warnings']))),str(d)[:1400]
    return d

def cmd(tool,command,data=None):return call(tool,dict(command=command,data={command:data or {}}))
def anim(command,data=None):return cmd('animation_editor',command,data)
def props(values):return call('set_property_values',dict(propertyValues=values))
def save(name,data): (HERE/name).write_text(json.dumps(data,indent=2)+'\n')
def hierarchy():return call('get_artboard_hierarchy',{'artboardId':'0-2','depth':6})['objects']
def group(name,parent):
    i=call('group_editor',dict(name=name,parentId=parent))['group']['id'];props({i:{'13':0,'14':0}});return i

def screenshot(path,size=512):
    r=urllib.request.Request('http://127.0.0.1:9791/mcp',json.dumps(dict(jsonrpc='2.0',id=80,method='tools/call',params=dict(name='capture_artboard',arguments=dict(artboardId='0-2',backgroundColor='#fafafa',longEdge=size)))).encode(),{'Content-Type':'application/json','Accept':'application/json, text/event-stream'})
    with urllib.request.urlopen(r,timeout=120) as q:raw=json.load(q)['result']
    im=next(c for c in raw['content'] if c['type']=='image');Path(path).write_bytes(base64.b64decode(im['data']))
