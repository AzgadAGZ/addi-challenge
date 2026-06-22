#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: generate-ignore-files.sh <image-name>}"
EXCEPTIONS_FILE="$(dirname "$0")/cve-exceptions.json"

# Generate .trivyignore for this image
python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
image = sys.argv[2]
for exc in data.get('cve_exceptions', []):
    if not exc.get('applies_to') or image in exc['applies_to']:
        print(exc['cve_id'])
" "$EXCEPTIONS_FILE" "$IMAGE" > ".trivyignore-${IMAGE}"

# Generate compact OCI label JSON
python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
image = sys.argv[2]
label = []
for exc in data.get('cve_exceptions', []):
    if not exc.get('applies_to') or image in exc['applies_to']:
        label.append({'id': exc['cve_id'], 'pkg': exc['package'], 'sev': exc['severity'], 'status': exc['upstream_status']})
print(json.dumps(label, separators=(',', ':')))
" "$EXCEPTIONS_FILE" "$IMAGE" > ".oci-label-${IMAGE}.json"

# Generate .dockle-accept for this image
python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
image = sys.argv[2]
for exc in data.get('tool_exceptions', {}).get('dockle', []):
    if not exc.get('applies_to') or image in exc['applies_to']:
        print(exc['code'])
" "$EXCEPTIONS_FILE" "$IMAGE" > ".dockle-accept-${IMAGE}"

echo "Generated ignore files for image: ${IMAGE}"
echo "  .trivyignore-${IMAGE}"
echo "  .oci-label-${IMAGE}.json"
echo "  .dockle-accept-${IMAGE}"
