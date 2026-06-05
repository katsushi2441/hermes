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

response="$(python3 - <<'PY'
import json
import os
import urllib.request
from pathlib import Path

api_url = os.environ["RQDB4AI_API_URL"].rstrip("/")
token = os.environ["RQDB4AI_API_TOKEN"]
task_path = Path("/home/kojima/exdirect/aixec/tasks/market_task.generated.json")
task = json.loads(task_path.read_text(encoding="utf-8"))

payload = {
    "queue": "ollama-192-168-0-14-worker",
    "function": "aixec_market_jobs.market_pipeline_job",
    "kwargs": {
        "dry_run": False,
        "source": "worker_auto",
        "limit": 500,
        "hits": 20,
        "pages": 3,
        "max_candidates": 600,
        "score_mode": "heuristic",
        "submit_url": "http://192.168.0.2:8081/market/register-task",
        "submit_timeout": 600,
        "task": task,
    },
    "meta": {
        "project": "aixec",
        "app": "market",
        "source": "worker_auto",
        "resource": "ollama",
        "ollama_host": "192.168.0.14",
        "ollama_model": "gemma4:e4b",
    },
    "timeout": 3600,
    "result_ttl": 86400,
    "failure_ttl": 604800,
}

req = urllib.request.Request(
    f"{api_url}/api/enqueue",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    },
    method="POST",
)
with urllib.request.urlopen(req, timeout=30) as res:
    print(res.read().decode("utf-8"))
PY
)"
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
    "name": "aixec-market-pipeline-enqueue",
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
