#!/usr/bin/env bash
# Starts the stack and waits until every service is healthy, then creates the event streams
# and the buckets. Safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."

# The stack's settings: .env.development (committed) and, if it exists, .env.development.local.
export COMPOSE_ENV_FILES=".env.development$( [ -f .env.development.local ] && echo ',.env.development.local' )"

docker compose --profile infra up -d --wait
docker compose --profile infra --profile init run --rm init-nats
docker compose --profile infra --profile init run --rm init-objectstore
echo "stack is up"
