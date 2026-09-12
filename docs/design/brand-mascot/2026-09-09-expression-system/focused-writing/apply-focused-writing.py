"""Change only the existing shared writing-eye geometry after a verified backup."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from rive_client import call, props

before = json.loads((HERE / 'backups/eye-properties.json').read_text())['values']
target = {'0-44': {'13': -59, '15': 12}, '0-50': {'13': 42, '15': -12}}
for first, last, length in [('0-46', '0-47', 46), ('0-52', '0-53', 42)]:
    target[first] = {'24': -length / 2, '25': 0, '84': 0, '85': 0,
                     '86': 0, '87': length / 3}
    target[last] = {'24': length / 2, '25': 0, '84': 180, '85': length / 3,
                    '86': 0, '87': 0}
keys = {i: list(map(int, p)) for i, p in before.items()}
current = call('query_property_values', {'propertyKeys': keys})['values']
for i, values in before.items():
    for key, old in values.items():
        actual = current[i][key]
        desired = target.get(i, {}).get(key, old)
        assert actual in (old, desired) or (
            isinstance(actual, (int, float)) and
            min(abs(actual - old), abs(actual - desired)) < 1e-6
        ), (i, key, 'Unexpected external edit', actual, old)
props(target)
after = call('query_property_values', {'propertyKeys': keys})['values']
for i, values in before.items():
    for key, old in values.items():
        expected = target.get(i, {}).get(key, old)
        actual = after[i][key]
        assert actual == expected or (
            isinstance(actual, (int, float)) and abs(actual - expected) < 1e-6
        ), (i, key, actual, expected)
(HERE / 'eye-patch.json').write_text(json.dumps(target, indent=2) + '\n')
(HERE / 'readback.json').write_text(json.dumps({
    'passed': True, 'values': after,
    'scope': 'Six existing nodes; shared straight path geometry and eye x/rotation only.',
    'strokeWidthRoundCapsYPositionAndOtherPropertiesUnchanged': True
}, indent=2) + '\n')
print('Shared writing eye geometry changed and read back; 6 existing nodes.')
