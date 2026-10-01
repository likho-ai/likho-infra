#!/usr/bin/env bash
# Starts the stack and waits until every service is healthy, then creates the event streams
# and the buckets. Safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose --profile infra up -d --wait
docker compose --profile infra --profile init run --rm init-nats
docker compose --profile infra --profile init run --rm init-objectstore
echo "stack is up"
