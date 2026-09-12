import sys,base64,hashlib
from rive_client import *
destination=HERE/sys.argv[1];destination.mkdir(parents=True,exist_ok=True);fmt=sys.argv[2]if len(sys.argv)>2 else 'riv'
try:d=call('export_file',dict(destination=str(destination),format=fmt))
except RuntimeError as e:
    if 'Operation not permitted' not in str(e):raise
    d=call('export_file',dict(destination=str(destination),format=fmt,inline_base64=True))
if 'data'in d:
    p=destination/d['filename']
    with p.open('xb')as f:f.write(base64.b64decode(d['data']))
else:p=Path(d['path'])
print(p);print(p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest())
