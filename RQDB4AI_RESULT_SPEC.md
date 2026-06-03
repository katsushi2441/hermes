# RQDB4AI Common Result Spec

RQDB4AI must not contain project-specific business logic.

Every job, task, and worker must return the same result shape. Hermes dashboard
and status sync read only this common shape. They must not guess counts from
stdout, API response details, worker names, or project-specific fields.

## Standard Result

```json
{
  "ok": true,
  "status": "ok",
  "items": 1,
  "metrics": {
    "created": 1,
    "updated": 0,
    "skipped": 0,
    "failed": 0
  },
  "note": "short human-readable summary",
  "artifacts": [
    {
      "type": "url",
      "label": "result",
      "url": "https://example.com/result"
    }
  ],
  "error": null
}
```

## Required Fields

- `ok`: boolean. True only when the business process completed normally.
- `status`: one of `ok`, `warn`, `down`.
- `items`: integer. The primary business result count shown on the dashboard.
- `metrics`: object. Worker-specific details are allowed here, but keys should be stable.
- `note`: short text for dashboard display.
- `artifacts`: list of generated URLs/files. Empty list is allowed.
- `error`: null on success, short object/string on failure.

## Status Rules

- Enqueue success is not business success.
- External worker start success is not business success.
- RQ `finished` is not enough unless the result has `ok=true` and terminal business status.
- A job that starts another process must wait for that process to finish and return its final result.
- A job that cannot wait must return `status=warn`, `ok=false`, and explain why.
- New item count, uploaded video count, created report count, or registered product count must be in `items`.

## Dashboard Rules

- Dashboard status sync reads only:
  - RQ status
  - `result.ok`
  - `result.status`
  - `result.items`
  - `result.metrics`
  - `result.note`
  - `result.error`
- No worker-name-specific parsing.
- No stdout regex count extraction.
- No special cases for Horizon, AIxEC, OSS, Polymarket, FinReport, or BuzBlogger.

## Worker Migration Rule

Each project-specific job wrapper must convert its local result into the standard
result before returning to RQDB4AI.

Old fields such as `created`, `registered`, `success_count`, `selected`,
`completion_scope`, `business_status`, and `response` may remain temporarily for
debugging, but the dashboard must not depend on them. Put dashboard counts in
`items` and details in `metrics`.

## Examples

### OSS

```json
{
  "ok": true,
  "status": "ok",
  "items": 3,
  "metrics": {"created": 3, "top_n": 3, "period": "daily"},
  "note": "OSS reports created=3 period=daily",
  "artifacts": [],
  "error": null
}
```

### AIxEC Register Market

```json
{
  "ok": true,
  "status": "ok",
  "items": 11,
  "metrics": {"created": 11, "updated": 489, "skipped": 0},
  "note": "register_market complete created=11 updated=489 skipped=0",
  "artifacts": [],
  "error": null
}
```

### Horizon

```json
{
  "ok": true,
  "status": "ok",
  "items": 1,
  "metrics": {"articles_created": 1, "videos_created": 1, "youtube_uploaded": 1},
  "note": "Horizon complete youtube_uploaded=1",
  "artifacts": [{"type": "url", "label": "youtube", "url": "https://youtu.be/..."}],
  "error": null
}
```
