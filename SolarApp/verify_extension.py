"""Check standalone artifact configuration and whitespace without a Git repository."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent
script = root / 'SolarApp.ax'
before = script.read_bytes()
subprocess.run([sys.executable, str(root / 'build_extension.py')], cwd=root, check=True)
assert script.read_bytes() == before, 'Generated source is out of sync'
for filename in ('SolarApp-TC002-Animated.ax', 'SolarApp-TC002-SourceAware.ax'):
    assert (root / filename).read_bytes() == before, f'Stale deliverable: {filename}'
digest = hashlib.sha256(before).hexdigest()
rows = [shlex.split(line[10:]) for line in script.read_text(encoding='utf-8').splitlines()
        if line.startswith('# @config ')]
keys = [row[0] for row in rows]
assert len(keys) == len(set(keys)), 'Duplicate setting key'
assert all(re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,23}', key) for key in keys)
defaults = {}
for key, kind, label, *options in rows:
    opts = dict(option.split('=', 1) for option in options)
    default = opts['default']
    assert kind in {'select', 'number', 'text', 'bool'}
    if kind == 'select':
        assert default in opts['options'].split(',')
    elif kind == 'number':
        assert float(default) >= float(opts.get('min', '-inf'))
        assert float(default) <= float(opts.get('max', 'inf'))
    elif kind == 'bool':
        assert default in {'true', 'false'}
    defaults[key] = default
result = subprocess.run(['git', '-c', 'core.autocrlf=false', 'diff', '--no-index',
                         '--check', '--', str(root / 'SolarApp.original.ax'), str(script)],
                        capture_output=True, text=True, cwd=tempfile.gettempdir())
# --no-index may exit 1 simply because the files differ. Whitespace errors print diagnostics.
assert result.returncode in (0, 1) and not result.stdout and not result.stderr, result.stdout + result.stderr
print(f'PASS: generation reproducible; {len(keys)} valid settings; no whitespace diagnostics')
print(f'Default settings JSON: {len(json.dumps(defaults))} bytes; source: {len(before)} bytes')
print('SHA256: ' + digest)
