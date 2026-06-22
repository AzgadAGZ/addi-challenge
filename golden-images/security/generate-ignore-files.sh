#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: generate-ignore-files.sh <image-name>}"
EXCEPTIONS_FILE="$(dirname "$0")/cve-exceptions.json"

# Generate .trivyignore for this image
# - Rejects exceptions missing applies_to (fail-closed, not fail-open)
# - Rejects expired exceptions (forces review on expiry)
python3 -c "
import json, sys
from datetime import date

data = json.load(open(sys.argv[1]))
image = sys.argv[2]
today = date.today().isoformat()
expired = []

for exc in data.get('cve_exceptions', []):
    applies = exc.get('applies_to')
    if not applies:
        print(f'ERROR: {exc[\"cve_id\"]} missing applies_to — fail-closed', file=sys.stderr)
        sys.exit(1)
    if image not in applies:
        continue
    if exc.get('expires', '9999-12-31') < today:
        expired.append(exc['cve_id'])
        continue
    print(exc['cve_id'])

if expired:
    print(f'ERROR: {len(expired)} expired exception(s): {expired}', file=sys.stderr)
    print('Update or remove them from cve-exceptions.json', file=sys.stderr)
    sys.exit(1)
" "$EXCEPTIONS_FILE" "$IMAGE" > ".trivyignore-${IMAGE}"

# Generate compact OCI label JSON (same filters)
python3 -c "
import json, sys
from datetime import date

data = json.load(open(sys.argv[1]))
image = sys.argv[2]
today = date.today().isoformat()
label = []

for exc in data.get('cve_exceptions', []):
    applies = exc.get('applies_to')
    if not applies or image not in applies:
        continue
    if exc.get('expires', '9999-12-31') < today:
        continue
    label.append({'id': exc['cve_id'], 'pkg': exc['package'], 'sev': exc['severity'], 'status': exc['upstream_status']})

print(json.dumps(label, separators=(',', ':')))
" "$EXCEPTIONS_FILE" "$IMAGE" > ".oci-label-${IMAGE}.json"

# Generate .dockle-accept for this image (same fail-closed pattern)
python3 -c "
import json, sys

data = json.load(open(sys.argv[1]))
image = sys.argv[2]

for exc in data.get('tool_exceptions', {}).get('dockle', []):
    applies = exc.get('applies_to')
    if not applies:
        print(f'ERROR: dockle exception {exc[\"code\"]} missing applies_to', file=sys.stderr)
        sys.exit(1)
    if image in applies:
        print(exc['code'])
" "$EXCEPTIONS_FILE" "$IMAGE" > ".dockle-accept-${IMAGE}"

echo "Generated ignore files for image: ${IMAGE}"
echo "  .trivyignore-${IMAGE}"
echo "  .oci-label-${IMAGE}.json"
echo "  .dockle-accept-${IMAGE}"
