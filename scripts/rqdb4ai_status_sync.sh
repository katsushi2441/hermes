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

python3 - <<'PY'
import json
import os
import re
import urllib.request
import datetime
from pathlib import Path

api_url = os.environ["RQDB4AI_API_URL"].rstrip("/")
token = os.environ["RQDB4AI_API_TOKEN"]

name_map = {
    "oss_jobs.worker_auto_cycle_job": "url2ai-oss-enqueue",
    "finreport_jobs.worker_auto_cycle_job": "url2ai-finreport-enqueue",
    "polymarket_jobs.worker_auto_cycle_job": "url2ai-polymarket-enqueue",
    "buzblogger_jobs.worker_auto_cycle_job": "buzblogger-enqueue",
    "aixec_market_jobs.market_pipeline_job": "aixec-market-pipeline-enqueue",
    "aixec_market_jobs.register_market_worker_job": "aixec-register-market-worker-enqueue",
    "aixec_market_jobs.growth_agent_job": "aixec-growth-agent-enqueue",
    "horizon_jobs.worker_auto_cycle_job": "horizon-worker-enqueue",
}

def get_json(url):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=20) as res:
        return json.loads(res.read().decode("utf-8"))

def normalize_time(value):
    value = str(value or "")
    if not value:
        return ""
    try:
        raw = value.replace("Z", "+00:00")
        dt = datetime.datetime.fromisoformat(raw)
        if dt.tzinfo is not None:
            dt = dt.astimezone(datetime.timezone(datetime.timedelta(hours=9))).replace(tzinfo=None)
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        value = value.replace("T", " ")
        value = re.sub(r"\.\d+", "", value)
        value = re.sub(r"\+00:00$", "", value)
        value = value.rstrip("Z")
        return value[:19]

def post_report(name, status, items, note, reported_at=""):
    payload = json.dumps({
        "name": name,
        "status": status,
        "items": items,
        "note": note[:200],
        "reported_at": reported_at,
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:8081/worker/report",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        res.read()

def first_int(*values):
    for value in values:
        if isinstance(value, bool):
            continue
        if isinstance(value, int):
            return value
        if isinstance(value, str) and value.strip().isdigit():
            return int(value.strip())
    return 0

def nested_dict(value, *keys):
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return {}
        current = current.get(key)
    return current if isinstance(current, dict) else {}

def extract_items_and_metrics(result):
    metrics = result.get("metrics") if isinstance(result.get("metrics"), dict) else {}
    submit_result = nested_dict(result, "submit", "response", "result")
    api_result = result.get("api_result") if isinstance(result.get("api_result"), dict) else {}
    response_result = nested_dict(result, "response", "result")
    counts = result.get("counts") if isinstance(result.get("counts"), dict) else {}

    items = first_int(
        result.get("items"),
        metrics.get("items"),
        metrics.get("registered"),
        metrics.get("created"),
        result.get("registered"),
        result.get("created"),
        result.get("success_count"),
        result.get("selected"),
        submit_result.get("items"),
        submit_result.get("registered"),
        submit_result.get("created"),
        api_result.get("items"),
        api_result.get("registered"),
        api_result.get("created"),
        response_result.get("items"),
        response_result.get("registered"),
        response_result.get("created"),
        counts.get("selected"),
    )
    if items == 0:
        stdout_tail = str(result.get("stdout_tail") or "")
        if "AIxSNS posted id=" in stdout_tail or "posted id=" in stdout_tail or "はてなブログ投稿: ok" in stdout_tail:
            items = 1

    merged = dict(metrics)
    for source in (result, submit_result, api_result, response_result, counts):
        if not isinstance(source, dict):
            continue
        for key in (
            "created",
            "registered",
            "updated",
            "skipped",
            "failed",
            "selected",
            "top_n",
            "success_count",
            "youtube_uploaded",
            "videos_created",
            "articles_created",
        ):
            if key not in merged and isinstance(source.get(key), int):
                merged[key] = source.get(key)

    return items, merged

queues = get_json(f"{api_url}/api/queues").get("queues") or []
active_queue_names = {q.get("name") for q in queues if q.get("name")}

jobs = get_json(f"{api_url}/api/jobs?limit=100").get("jobs") or []
latest = {}
def job_ts(job):
    return str(job.get("ended_at") or job.get("started_at") or job.get("created_at") or "")
for job in jobs:
    task = job.get("task") or {}
    fn = task.get("name") or ""
    if fn not in name_map:
        continue
    if fn not in latest or job_ts(job) > job_ts(latest[fn]):
        latest[fn] = job

status_path = Path("/home/kojima/exdirect/aixec/storage/worker_status.json")
current_status_records = {}
if status_path.exists():
    try:
        current = json.loads(status_path.read_text(encoding="utf-8"))
        current_status_records = current if isinstance(current, dict) else {}
    except Exception:
        current = {}
    reverse_name_map = {v: k for k, v in name_map.items()}
    for dashboard_name, record in current.items():
        fn = reverse_name_map.get(dashboard_name)
        if not fn or fn in latest:
            continue
        note = str((record or {}).get("note") or "")
        match = re.search(r"job=([0-9a-f-]{36})", note)
        if not match:
            continue
        try:
            detail = get_json(f"{api_url}/api/jobs/{match.group(1)}")
            job = detail.get("job") or detail
            if (job.get("task") or {}).get("name") == fn:
                latest[fn] = job
        except Exception:
            pass

for fn, job in latest.items():
    try:
        detail = get_json(f"{api_url}/api/jobs/{job.get('id')}")
        job = detail.get("job") or job
    except Exception:
        pass
    result = job.get("result")
    if not isinstance(result, dict):
        result = {}
    rq_status = job.get("status") or ""
    err = job.get("error") or {}

    queue_name = job.get("queue") or ""
    result_status = str(result.get("status") or "")
    result_reason = str(result.get("reason") or "")

    if rq_status in ("failed", "stopped", "canceled"):
        status = "down"
    elif rq_status == "finished" and result_status in ("skipped", "failed", "error"):
        status = "down"
    elif rq_status in ("queued", "deferred", "scheduled") and queue_name and queue_name not in active_queue_names:
        status = "down"
    elif rq_status in ("queued", "deferred", "scheduled"):
        status = "queued"
    elif rq_status in ("started", "running"):
        status = "running"
    elif rq_status == "finished" and result.get("ok", True):
        status = "ok"
    else:
        status = "down"

    items, metrics = extract_items_and_metrics(result)

    actual_time = normalize_time(job.get("ended_at") or job.get("started_at") or job.get("created_at"))
    current_record = current_status_records.get(name_map[fn]) if isinstance(current_status_records, dict) else None
    if (
        rq_status == "finished"
        and items == 0
        and result.get("trigger_started")
        and isinstance(current_record, dict)
        and int(current_record.get("items") or 0) > 0
        and not str(current_record.get("note") or "").startswith("rq=finished")
    ):
        print(name_map[fn], "keep-current", current_record.get("items"), current_record.get("note", ""))
        continue
    bits = [f"rq={rq_status}", f"job={job.get('id', '')}"]
    if queue_name:
        bits.append(f"queue={queue_name}")
    if rq_status in ("queued", "deferred", "scheduled") and queue_name and queue_name not in active_queue_names:
        bits.append("orphan_queue")
    for key in ("created", "registered", "updated", "skipped", "failed", "selected", "top_n", "youtube_uploaded", "videos_created", "articles_created"):
        if key in metrics:
            bits.append(f"{key}={metrics.get(key)}")
    if result.get("note"):
        bits.append(str(result.get("note"))[:120])
    if result_status:
        bits.append(f"result={result_status}")
    if result_reason:
        bits.append(f"reason={result_reason}"[:80])
    if err.get("message"):
        bits.append("error=" + str(err.get("message"))[:80])
    elif job.get("ended_at"):
        bits.append("ended=" + str(job.get("ended_at"))[:19])

    post_report(name_map[fn], status, items, " ".join(bits), actual_time)
    print(name_map[fn], status, items, " ".join(bits))
PY
