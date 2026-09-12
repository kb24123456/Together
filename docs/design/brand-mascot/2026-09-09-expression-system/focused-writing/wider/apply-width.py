"""Widen only the shared writing eyes and their horizontal separation."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent))
from rive_client import call, props

before = json.loads((HERE / 'backups/eye-properties.json').read_text())['values']
target = {'0-44': {'13': -71}, '0-50': {'13': 54},
          '0-46': {'24': -28, '87': 56 / 3},
          '0-47': {'24': 28, '85': 56 / 3},
          '0-52': {'24': -26, '87': 52 / 3},
          '0-53': {'24': 26, '85': 52 / 3}}
keys = {i: list(map(int, values)) for i, values in before.items()}
current = call('query_property_values', {'propertyKeys': keys})['values']
assert current == before, 'Current properties differ from the backup; inspect before changing.'
props(target)
after = call('query_property_values', {'propertyKeys': keys})['values']
for i, values in before.items():
    for key, old in values.items():
        expected = target.get(i, {}).get(key, old)
        actual = after[i][key]
        assert actual == expected or (isinstance(actual, (int, float)) and
                                      abs(actual - expected) < 1e-6), (i, key)
(HERE / 'eye-patch.json').write_text(json.dumps(target, indent=2) + '\n')
(HERE / 'readback.json').write_text(json.dumps({'passed': True, 'values': after,
    'changedPropertyCount': sum(map(len, target.values())),
    'otherCheckedPropertiesUnchanged': True}, indent=2) + '\n')
print('10 horizontal geometry properties updated and verified; angle, thickness, height preserved.')
