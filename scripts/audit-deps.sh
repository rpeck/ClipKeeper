#!/bin/zsh
# Dependency audit. Lists every pinned package with its version and commit,
# checks that Package.swift and project.yml pin the same versions as
# Package.resolved, confirms that no package uses binary targets or build
# plugins, and asks the OSV database for known vulnerabilities.
#
#   scripts/audit-deps.sh
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f Package.resolved ]] || { echo "Package.resolved is missing. Run: swift package resolve" >&2; exit 1; }

echo "Pinned packages (Package.resolved):"
set +e
python3 - <<'PY'
import json, re, sys, urllib.request
pins = json.load(open("Package.resolved"))["pins"]
manifest = open("Package.swift").read()
project = open("project.yml").read()
problems = 0
for p in sorted(pins, key=lambda p: p["identity"]):
    name, url = p["identity"], p["location"]
    version, rev = p["state"].get("version", "?"), p["state"].get("revision", "?")[:12]
    print(f"  {name:<20} {version:<8} {rev}  {url}")
    # Direct dependencies must be pinned to the same exact version in both manifests.
    m = re.search(re.escape(url) + r'",\s*exact:\s*"([^"]+)"', manifest)
    if m:
        if m.group(1) != version:
            print(f"    !! Package.swift pins {m.group(1)}, Package.resolved has {version}")
            problems += 1
        y = re.search(re.escape(url) + r"\n\s*exactVersion:\s*([\d.]+)", project)
        if not y:
            print("    !! project.yml has no exactVersion for this package")
            problems += 1
        elif y.group(1) != version:
            print(f"    !! project.yml pins {y.group(1)}, Package.resolved has {version}")
            problems += 1
    # OSV: the SwiftURL ecosystem is keyed by the repository URL.
    try:
        body = json.dumps({"package": {"name": url, "ecosystem": "SwiftURL"}, "version": version}).encode()
        req = urllib.request.Request("https://api.osv.dev/v1/query", data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as r:
            vulns = json.load(r).get("vulns", [])
        if vulns:
            problems += 1
            for v in vulns:
                print(f"    !! OSV {v.get('id')}: {v.get('summary', '')[:90]}")
        else:
            print("    OSV: no known vulnerabilities")
    except Exception as e:
        print(f"    OSV: query failed ({e})")
sys.exit(1 if problems else 0)
PY
audit_status=$?
set -e

echo
echo "Binary targets or build plugins in checked-out packages:"
found=0
for f in .build/checkouts/*/Package.swift; do
  [[ -f "$f" ]] || continue
  if grep -qE "binaryTarget|\.plugin\(" "$f"; then echo "  !! $f"; found=1; fi
done
[[ $found -eq 0 ]] && echo "  none"

exit $audit_status
