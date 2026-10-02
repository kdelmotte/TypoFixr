#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" "${1:-}" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

root = Path(sys.argv[1])
info = plistlib.loads((root / 'Sources/TypoFixr/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
tag = sys.argv[2] or f'v{version}'
assert re.fullmatch(r'\d+\.\d+\.\d+', version), f'Invalid version: {version}'
assert str(build).isdigit(), f'Invalid build number: {build}'
assert tag == f'v{version}', f'Tag {tag} does not match app version {version}'
assert info['CFBundleIdentifier'] == 'com.typofixr.app', 'Wrong app identity'
project = (root / 'TypoFixr.xcodeproj/project.pbxproj').read_text()
for key, expected in [('MARKETING_VERSION', version), ('CURRENT_PROJECT_VERSION', str(build))]:
    values = re.findall(rf'\b{key}\s*=\s*([^;]+);', project)
    assert values and all(value.strip().strip('"') == expected for value in values), f'{key} does not match {expected}: {values}'
notes = root / 'docs/releases' / f'{tag}.md'
assert notes.is_file() and notes.read_text().strip(), f'Missing release notes: {notes}'
print(f'Release metadata valid: {tag}, build {build}, com.typofixr.app')
PY
