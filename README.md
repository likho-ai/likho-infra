# likho-infra

The local stack and the shared CI for the Likho platform.

Likho turns Hindi, Urdu and English call recordings into text: the words in the script that was
spoken, and the same words in Hinglish. The platform is a set of small services; this repository
gives every one of them the same databases, event bus, object store, search engine and gateway
on a developer machine.

## Start

Docker Desktop must be running.

```powershell
.\stack.ps1 doctor     # checks Docker, ports, tools and free memory
.\stack.ps1 up         # starts everything and waits until it is healthy
.\stack.ps1 smoke      # 20 checks that prove it works
.\stack.ps1 ps         # state and memory use
.\stack.ps1 down       # stop, keep the data
```

On Linux or macOS: `bash scripts/up.sh` and `bash scripts/smoke.sh`.

## What runs

| Service | Image | Address on this machine | Used by |
| --- | --- | --- | --- |
| Gateway | nginx 1.30 | http://localhost:8080 | the browser; routes to services running on the host |
| PostgreSQL | postgres 17 | localhost:5433 | likho-api, likho-media, likho-language (one database and login each) |
| MongoDB | mongo 8.0 | localhost:27017 | likho-transcription (transcript documents) |
| Redis | redis 8 | localhost:6380 | likho-api (sessions, live lines) |
| NATS JetStream | nats 2.14 | nats://localhost:4222, monitor http://localhost:8222 | every service (events and the job queue) |
| Object store | SeaweedFS 4.48 (S3 API) | http://localhost:9000 | likho-media (audio, 16 kHz copies, waveforms) |
| Meilisearch | 1.54 | http://localhost:7700 | likho-search |
| Grafana, logs, traces, metrics (`.\stack.ps1 obs`) | grafana/otel-lgtm 0.34 | http://localhost:3000, OTLP 4317 / 4318 | every service |

Measured on 2026-10-01: the seven always-on containers use about **300 MB** of memory when idle.
The observability container adds about 1 GB, so it is a separate profile.

Every service serves its metrics at `GET /metrics` (Prometheus text) and pushes them to Grafana
when started with `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`. The dashboard **Likho -
jobs and services** (`grafana/dashboards`, provisioned into the container) shows the job queue,
how fast transcription runs, failures and sweeps, media, events and searches.

Ports 8080, 5433 and 6380 are used instead of 80, 5432 and 6379 because IIS, a local
PostgreSQL and a local Redis already hold those on the development machine. Change any port
in `.env.development.local` (same keys as `.env.development`).

## Local credentials

Development values only, valid on this machine only.

| What | Value |
| --- | --- |
| PostgreSQL per service | user = database = password: `likho_api`, `likho_media`, `likho_language` |
| PostgreSQL superuser | `postgres` / `likho-dev` |
| S3 | access key `likho-dev`, secret `likho-dev-secret`, path-style addressing, any region |
| Meilisearch master key | `likho-dev-master-key` |

Connection strings as the services' `.env.development` files have them:

```
DATABASE_URL=postgres://likho_api:likho_api@localhost:5433/likho_api
MONGO_URL=mongodb://localhost:27017
REDIS_URL=redis://localhost:6380
NATS_URL=nats://localhost:4222
S3_ENDPOINT=http://localhost:9000
MEILI_URL=http://localhost:7700
```

## Event streams

`nats/streams.sh` creates three JetStream streams when the stack starts; the subjects and the
consumers are documented in `likho-contracts/streams.yaml`.

| Stream | Subjects | Kept |
| --- | --- | --- |
| `LIKHO` | `likho.media.*`, `likho.transcription.*`, `likho.vocabulary.*`, `likho.insights.*`, `likho.dead` | 30 days |
| `LIKHO_LIVE` | `likho.live.*` (live transcript lines) | 1 day |
| `LIKHO_KEEP` | `likho.transcript.*` (corrections made by people) | for ever |

## Gateway routes

| Path | Goes to |
| --- | --- |
| `/graphql`, `/api/`, `/events/` | likho-api on host port 4000 (`/events/` is not buffered, for live lines) |
| `/media/` | likho-media on host port 4010 (uploads up to 1 GB, range requests) |
| `/` | the web shell on host port 5173 |
| `/healthz` | the gateway itself |

A path whose service is not running answers `502` with a JSON error body.

## Shared CI

Other repositories call these workflows instead of copying them:

```yaml
jobs:
  ci:
    uses: likho-ai/likho-infra/.github/workflows/python-ci.yml@main   # or node-ci.yml, go-ci.yml
  publish:
    needs: ci
    if: github.ref == 'refs/heads/main'
    uses: likho-ai/likho-infra/.github/workflows/docker-publish.yml@main
    permissions: { contents: read, packages: write }
```

The workflows have not run on GitHub yet; they are checked on the first push.

## Notes

* The object store is SeaweedFS because the MinIO community image is no longer published.
  Services only use the S3 API, so the store can be swapped (Google Cloud Storage in production).
* The S3 check with presigned links and range reads: `uv run --no-project --with boto3 python scripts/s3check.py`.
* Kubernetes (minikube, Helm charts, the Gateway API) is added in Wave 2.
