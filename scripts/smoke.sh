#!/usr/bin/env bash
# Proves the stack works, not only that it started. Run after: docker compose --profile infra up -d --wait
# Works in Git Bash on Windows and on Linux CI. Exits non-zero on the first failed check.
set -euo pipefail
cd "$(dirname "$0")/.."

# The stack's settings: .env.development (committed) and, if it exists, .env.development.local.
export COMPOSE_ENV_FILES=".env.development$( [ -f .env.development.local ] && echo ',.env.development.local' )"

GATEWAY_PORT="${GATEWAY_PORT:-8080}"
MEILI_PORT="${MEILI_PORT:-7700}"
S3_PORT="${S3_PORT:-9000}"
MEILI_MASTER_KEY="${MEILI_MASTER_KEY:-likho-dev-master-key}"

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; exit 1; }
nats() { docker run --rm --network likho natsio/nats-box:0.20.0 nats --server nats://nats:4222 "$@"; }
psql_as() { docker compose exec -T -e PGPASSWORD="$1" postgres psql -h 127.0.0.1 -U "$1" -d "$2" -tAc "$3"; }

echo "gateway"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${GATEWAY_PORT}/healthz")" = "200" ] && pass "healthz answers 200" || fail "gateway healthz"
curl -s "http://localhost:${GATEWAY_PORT}/api/v1/ping" | grep -q service_unavailable && pass "a path with no service answers a JSON 502" || fail "gateway error body"

echo "postgres"
for db in likho_api likho_media likho_language; do
  [ "$(psql_as "$db" "$db" 'select current_database()')" = "$db" ] && pass "$db: own login works" || fail "$db login"
done
psql_as likho_api likho_media 'select 1' >/dev/null 2>&1 && fail "likho_api can read likho_media" || pass "one service cannot open another service's database"

echo "mongo / redis"
docker compose exec -T mongo mongosh --quiet --eval "db.adminCommand('ping').ok" | grep -q 1 && pass "mongo ping" || fail "mongo"
docker compose exec -T redis redis-cli ping | grep -q PONG && pass "redis ping" || fail "redis"

echo "nats"
for s in LIKHO LIKHO_LIVE LIKHO_KEEP; do nats stream info "$s" >/dev/null 2>&1 && pass "stream $s exists" || fail "stream $s"; done
before="$(nats stream info LIKHO --json | grep -o '"messages": *[0-9]*' | head -1 | grep -o '[0-9]*$')"
id="smoke-$(date +%s)"
nats pub likho.media.ready '{"smoke":true}' -H "Nats-Msg-Id:${id}" >/dev/null 2>&1
nats pub likho.media.ready '{"smoke":true}' -H "Nats-Msg-Id:${id}" >/dev/null 2>&1
after="$(nats stream info LIKHO --json | grep -o '"messages": *[0-9]*' | head -1 | grep -o '[0-9]*$')"
[ "$((after - before))" = "1" ] && pass "the same event published twice is stored once" || fail "de-duplication (stored $((after - before)))"

echo "object store"
buckets="$(echo 's3.bucket.list' | docker compose exec -T objectstore weed shell -master=127.0.0.1:9333 2>/dev/null)"
# Write, read and remove an object in every bucket. A bucket that exists but cannot be written
# to (the store out of volumes) makes a service hang, so existing is not enough.
s3() { curl -s --max-time 15 --aws-sigv4 "aws:amz:us-east-1:s3" --user "likho-dev:likho-dev-secret" "$@"; }
for b in likho-audio likho-normalized likho-peaks likho-models; do
  if ! echo "$buckets" | grep -q "$b"; then fail "bucket $b"; continue; fi
  object="http://localhost:${S3_PORT}/${b}/smoke/check-$$.txt"
  put="$(s3 -o /dev/null -w '%{http_code}' -X PUT --data-binary "likho smoke $b" "$object")"
  got="$(s3 "$object")"
  s3 -o /dev/null -X DELETE "$object"
  [ "$put" = "200" ] && [ "$got" = "likho smoke $b" ] && pass "bucket $b: write and read" || fail "bucket $b: write and read (PUT $put)"
done
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${S3_PORT}/likho-audio/nothing")" = "403" ] && pass "anonymous read is refused" || fail "anonymous S3 access"

echo "meilisearch"
curl -s "http://localhost:${MEILI_PORT}/health" | grep -q available && pass "health" || fail "meilisearch health"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${MEILI_PORT}/indexes")" = "401" ] && pass "requests without the key are refused" || fail "meilisearch is open"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${MEILI_MASTER_KEY}" "http://localhost:${MEILI_PORT}/indexes")" = "200" ] && pass "the master key works" || fail "meilisearch key"

echo "all checks passed"
