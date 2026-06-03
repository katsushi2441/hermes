#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="${HERMES_HOME:-/home/kojima/.hermes}"
BACKUP_DIR="$HERMES_HOME/backups/$(date +%Y%m%d-%H%M%S)-install"

mkdir -p "$HERMES_HOME" "$BACKUP_DIR"

if [ -e "$HERMES_HOME/scripts" ] && [ ! -L "$HERMES_HOME/scripts" ]; then
  mv "$HERMES_HOME/scripts" "$BACKUP_DIR/scripts"
fi
ln -sfn "$REPO_DIR/scripts" "$HERMES_HOME/scripts"

if [ "${INSTALL_JOBS:-0}" = "1" ]; then
  mkdir -p "$HERMES_HOME/cron"
  if [ -f "$HERMES_HOME/cron/jobs.json" ]; then
    cp "$HERMES_HOME/cron/jobs.json" "$BACKUP_DIR/jobs.json"
  fi
  cp "$REPO_DIR/cron/jobs.json" "$HERMES_HOME/cron/jobs.json"
fi

echo "Hermes scripts linked: $HERMES_HOME/scripts -> $REPO_DIR/scripts"
echo "Backups: $BACKUP_DIR"
