# docker/

Each subdirectory is a self-contained Docker Compose stack. All stacks share the `my-lab` Docker network and use the project name `my-lab`, so container names are consistent (`my-lab-<service>`).

---

## Stacks

### `databases/`

| Service | Image | Host Port | Internal Port |
|---|---|---|---|
| PostgreSQL 18 | `postgres:18-alpine` | 8001 | 5432 |
| MySQL 9 | `mysql:9` | 8002 | 3306 |
| SQL Server 2022 | `mcr.microsoft.com/mssql/server:2022-CU16` | 8003 | 1433 |
| MongoDB 8.0 | `mongodb/mongodb-community-server:8.0-ubuntu2204` | 8004 | 27017 |
| Redis 7.4 | `redis:7.4-alpine` | 8005 | 6379 |
| RedisInsight 2 | `redis/redisinsight:2.64` | 8006 | 5540 |

**Config:** `databases.env` (copy from `databases.env.example`)

**Notes:**
- PostgreSQL 18 mounts the volume at `/var/lib/postgresql` (not `/data`). This is a change from PostgreSQL 17. If upgrading from 17, drop the old volume and let Postgres re-initialise — there is no in-place upgrade path via Docker image swap.
- SQL Server has no native ARM64 image. On Apple Silicon it runs under Rosetta emulation (`platform: linux/amd64`). This is handled automatically in the compose file.
- MongoDB uses the community server image (`mongodb/mongodb-community-server`). Its init env vars use the `MONGODB_INITDB_` prefix, unlike the standard `mongo` image which uses `MONGO_INITDB_`.
- Redis also serves as the backend for **BullMQ** — connect any app on the `my-lab` network to `redis:6379`.
- **RedisInsight UI:** open `http://localhost:8006` → Add Database → Host `my-lab-redis`, Port `6379`, Password from `databases.env`.

---

### `messaging/`

| Service | Image | Host Port | Notes |
|---|---|---|---|
| RabbitMQ 4.0 | `rabbitmq:4.0-management-alpine` | 8100 (AMQP) | |
| RabbitMQ Management UI | ↑ same container | 8101 | `http://localhost:8101` |
| Kafka 3.8 | `apache/kafka:3.8.0` | 8102 | External listener |
| Kafka UI | `provectuslabs/kafka-ui:v0.7.2` | 8103 | `http://localhost:8103` |

**Config:** `messaging.env` (copy from `messaging.env.example`)

**Notes:**
- Kafka runs in **KRaft mode** — no Zookeeper. The `CLUSTER_ID` in `messaging.env` is a fixed base64-encoded UUID required for KRaft storage formatting; do not change it after first start.
- **Internal access** (container-to-container on `my-lab` network): `kafka:9092`
- **Host access** (from your IDE, tools, tests): `localhost:8102` — this is the EXTERNAL listener.
- Redis pub/sub is available via the Redis container in the `databases` stack.

---

### `storage/`

| Service | Image | Host Port | Notes |
|---|---|---|---|
| MinIO | `minio/minio:RELEASE.2024-12-18T13-15-44Z` | 8200 (S3 API) | S3-compatible |
| MinIO Console | ↑ same container | 8201 | `http://localhost:8201` |

**Config:** `storage.env` (copy from `storage.env.example`)

**Notes:**
- S3 endpoint for SDK/CLI: `http://localhost:8200`
- Region: `us-east-1` (set in `storage.env` — change to match what your SDK expects)
- Create buckets via the Console (`http://localhost:8201`) or any S3-compatible tool (AWS CLI, mc, boto3, etc.)
- **AWS CLI example:** `aws --endpoint-url http://localhost:8200 s3 mb s3://my-bucket`

---

### `observability/`

| Service | Image | Host Port | Notes |
|---|---|---|---|
| Loki | `grafana/loki:3.7.1` | 8300 | Log ingestion |
| Tempo | `grafana/tempo:2.10.5` | 8301 | Trace backend |
| Prometheus | `prom/prometheus:v3.11.2` | 8302 | Metrics |
| Grafana | `grafana/grafana:11.6.0` | 8303 | UI — `http://localhost:8303` |
| OTEL Collector gRPC | `otel/opentelemetry-collector-contrib:0.150.1` | 8304 | OTLP gRPC |
| OTEL Collector HTTP | ↑ same container | 8305 | OTLP HTTP |

**Config:** `observability.env` (copy from `observability.env.example`)

**Send telemetry from your apps:**
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:8304   # gRPC
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:8305   # HTTP
```

**Grafana login:** `admin` / `admin` (anonymous Viewer access is also enabled for convenience)

**Config files:**
| File | Purpose |
|---|---|
| `otel-collector-config.yaml` | OTEL pipelines (traces → Tempo, metrics → Prometheus, logs → Loki) |
| `prometheus.yml` | Scrape targets |
| `loki/loki-config.yaml` | Loki storage and retention |
| `tempo/tempo-config.yaml` | Tempo storage and trace retention |
| `grafana/provisioning/` | Pre-provisioned datasources and dashboards |

**Integrating other stacks with observability:** see [`../docs/observability-integration.md`](../docs/observability-integration.md).

---

### `ai/`

| Service | Image | Host Port | Notes |
|---|---|---|---|
| AI gateway (LiteLLM proxy) | `ghcr.io/berriai/litellm-non_root:v1.105.0` (digest-pinned) | 8400 | OpenAI-compatible `/v1` |

**Config:** `ai.env` (copy from `ai.env.example`) — gateway master key, provider keys (OpenAI, Gemini, Anthropic, Azure) and `REDIS_PASSWORD` (must match `databases.env`).

**Notes:**
- Requires the **databases** stack: it uses the shared Redis (`redis:6379`) on logical **DB 1** for the response cache (1 h TTL) and router state. Override with `AI_GATEWAY_REDIS_DB`.
- Call it with `Authorization: Bearer <LITELLM_MASTER_KEY>`. Apps call the aliases `fast`, `balanced`, `smart`, `embed`, `translate`; `<provider>/<model>` wildcards (e.g. `anthropic/claude-haiku-5-5`) are for scripts and evaluation.
- Health: `GET /health/liveliness`, `GET /health/readiness` (free, no provider calls). Background model health checks are off because each is a billed request.
- No database, so no admin UI, virtual keys or spend tracking. Runs as UID 102 with a read-only root filesystem.

```bash
curl -s localhost:8400/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"model":"fast","messages":[{"role":"user","content":"ping"}]}'
```

**Config files:**
| File | Purpose |
|---|---|
| `gateway/config.yaml` | Gateway policy: credentials, provider wildcards, retries, cooldowns, Redis cache |
| `gateway/aliases.yaml` | Model aliases (the only file normal changes touch) |

---

## Env files

Each stack directory contains:
- `<stack>.env` — actual config with credentials. **Gitignored.**
- `<stack>.env.example` — template committed to version control. Copy and fill in before first start.

```bash
cp docker/databases/databases.env.example docker/databases/databases.env
cp docker/messaging/messaging.env.example docker/messaging/messaging.env
cp docker/storage/storage.env.example     docker/storage/storage.env
cp docker/observability/observability.env.example docker/observability/observability.env
```

---

## Shared network and volumes

All stacks connect to the external `my-lab` Docker network. The `lab.sh` script creates this network automatically before starting any stack. If running a compose file directly (outside `lab.sh`), create it first:

```bash
docker network create my-lab
```

Named volumes follow the pattern `my-lab_<service>_data` so they are easy to identify and never conflict with other projects.
