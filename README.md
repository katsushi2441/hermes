# Hermes Job Configuration

This repository stores the ExBridge-managed Hermes enqueue scripts and the current cron job snapshot.

## Layout

- `scripts/` - Active Hermes scripts. These are the source of truth.
- `cron/jobs.json` - Current managed job snapshot. Hermes mutates its live `~/.hermes/cron/jobs.json`, so treat this file as a reviewed baseline.
- `rqdb4ai.env.example` - Environment variable example. Do not commit real tokens.
- `install.sh` - Links `~/.hermes/scripts` to this repository and optionally copies the managed cron snapshot.

## Runtime Files Not Managed Here

The following stay under `/home/kojima/.hermes` and are not committed:

- `rqdb4ai.env`
- Hermes skills
- Hermes agent runtime
- cron output logs
- SQLite / WAL files
- update/cache files

## Rule

RQDB4AI workers run on a separate server. This server only enqueues jobs and syncs real RQDB4AI status back to the AIxEC dashboard.

RQDB4AI result handling is standardized in [RQDB4AI_RESULT_SPEC.md](RQDB4AI_RESULT_SPEC.md). Do not add worker-specific dashboard parsing. Every worker must return the common result shape.

## Dashboard

`webapps/dashboard.php` is the Hermes / RQDB4AI operations dashboard. It is not an AIxEC product dashboard; it only uses the AIxEC API endpoint as the current public API surface for worker status, schedule, and Ollama health.

`rqdb4ai-status-sync` runs every 10 minutes so dashboard rows do not remain stuck at `running` after the RQDB4AI job has finished.
