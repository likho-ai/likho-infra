#!/bin/sh
# Creates the JetStream streams. Safe to run again: existing streams are updated in place.
# Subjects and consumers are documented in likho-contracts/streams.yaml.
set -eu
NATS="nats --server nats://nats:4222"

ensure() {
  name="$1"; shift
  if $NATS stream info "$name" >/dev/null 2>&1; then
    $NATS stream edit "$name" "$@" --force >/dev/null
    echo "updated stream $name"
  else
    $NATS stream add "$name" "$@" --storage file --retention limits --discard old \
      --replicas 1 --dupe-window 2m --defaults >/dev/null
    echo "created stream $name"
  fi
}

# Business events, kept 30 days.
ensure LIKHO \
  --subjects "likho.media.*,likho.transcription.*,likho.vocabulary.*,likho.insights.*,likho.import.*,likho.recording.*,likho.settings.*,likho.model.*,likho.evaluation.*,likho.dead" \
  --max-age 30d

# Live transcript lines: many small messages, only useful while a job runs.
ensure LIKHO_LIVE --subjects "likho.live.*" --max-age 1d

# Corrections made by people: training data, never expired.
ensure LIKHO_KEEP --subjects "likho.transcript.*"

$NATS stream ls
