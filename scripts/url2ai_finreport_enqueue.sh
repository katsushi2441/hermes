#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE=/home/kojima/.hermes/rqdb4ai.env
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

export RQDB4AI_API_URL="${RQDB4AI_API_URL:-http://192.168.0.3:18300}"

cd /home/kojima/exdirect/url2ai
git pull origin main >/dev/null 2>&1 || echo "git pull skipped; using current url2ai checkout" >&2
response="$(scripts/enqueue_finreport_auto_cycle.sh)"
echo "$response"

python3 - "$response" <<'PY'
import json
import sys
import urllib.request

response = json.loads(sys.argv[1])
job = response.get("job") or {}
job_id = job.get("id") or ""
queue = job.get("queue") or ""
status = job.get("status") or ""
ok = bool(response.get("ok"))

payload = json.dumps({
    "name": "url2ai-finreport-enqueue",
    "status": "queued" if ok else "down",
    "items": 0,
    "note": f"RQDB4AI enqueue {status} job={job_id} queue={queue}"[:200],
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8081/worker/report",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as res:
        res.read()
except Exception as exc:
    print(f"worker/report failed: {exc}", file=sys.stderr)
PY
# Refresh dashboard with actual RQDB4AI job status when possible.
"$SCRIPT_DIR/rqdb4ai_status_sync.sh" || true
