# my-lab

A production-grade local engineering lab — all the infrastructure an engineer reaches for daily, in one place. Databases, message brokers, object storage, and a full observability stack, all running in Docker with consistent naming, health checks, and a single script to manage everything.

---

## What's inside

| Stack | Services |
|---|---|
| **Databases** | PostgreSQL 18, MySQL 9, SQL Server 2022, MongoDB 8 (Community), Redis 7.4 + RedisInsight |
| **Messaging** | RabbitMQ 4.0, Kafka 3.8 (KRaft), Kafka UI |
| **Storage** | MinIO (S3-compatible) |
| **Observability** | Grafana, Prometheus, Loki, Tempo, OpenTelemetry Collector |

All stacks are independent — run any combination you need. The observability stack is completely optional.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin)
- Node.js (optional — for `npm run` convenience scripts)

---

## Quick start

```bash
# 1. Copy env templates and fill in credentials (or use the defaults for local dev)
cp docker/databases/databases.env.example     docker/databases/databases.env
cp docker/messaging/messaging.env.example     docker/messaging/messaging.env
cp docker/storage/storage.env.example         docker/storage/storage.env
cp docker/observability/observability.env.example docker/observability/observability.env

# 2. Start everything
./lab.sh up

# Or start individual stacks
./lab.sh up --stack databases
./lab.sh up --stack messaging
./lab.sh up --stack observability
```

---

## Port reference

All services are exposed in the `8000+` range, grouped by stack.

### Databases (8001–8006)

| Port | Service | Notes |
|---|---|---|
| 8001 | PostgreSQL | |
| 8002 | MySQL | |
| 8003 | SQL Server | Runs under Rosetta on Apple Silicon |
| 8004 | MongoDB | Community Server |
| 8005 | Redis | Also used for BullMQ |
| 8006 | RedisInsight | Web UI → `http://localhost:8006` |

### Messaging (8100–8103)

| Port | Service | Notes |
|---|---|---|
| 8100 | RabbitMQ AMQP | |
| 8101 | RabbitMQ Management | Web UI → `http://localhost:8101` |
| 8102 | Kafka | External listener for host access |
| 8103 | Kafka UI | Web UI → `http://localhost:8103` |

### Storage (8200–8201)

| Port | Service | Notes |
|---|---|---|
| 8200 | MinIO S3 API | S3 endpoint for SDKs and CLI |
| 8201 | MinIO Console | Web UI → `http://localhost:8201` |

### Observability (8300–8305)

| Port | Service | Notes |
|---|---|---|
| 8300 | Loki | Log ingestion |
| 8301 | Tempo | Trace backend |
| 8302 | Prometheus | `http://localhost:8302` |
| 8303 | Grafana | Web UI → `http://localhost:8303` |
| 8304 | OTEL Collector gRPC | OTLP gRPC endpoint |
| 8305 | OTEL Collector HTTP | OTLP HTTP endpoint |

---

## Usage

### lab.sh

```bash
./lab.sh <command> [--stack <name>] [--service <name>]
```

| Command | Description |
|---|---|
| `up` | Start services (detached) |
| `down` | Stop and remove containers |
| `restart` | Restart services |
| `logs` | Follow service logs |
| `ps` | Show running containers |
| `pull` | Pull latest images |

```bash
./lab.sh up                                        # Start all stacks
./lab.sh up --stack databases                      # Start databases only
./lab.sh up --stack databases --service postgres   # Start one service
./lab.sh down --stack messaging                    # Stop messaging stack
./lab.sh logs --stack observability --service grafana
./lab.sh ps                                        # Show all containers
```

**Available stacks:** `databases` · `messaging` · `storage` · `observability` · `all`

### npm scripts

```bash
npm run up              # Start everything
npm run down            # Stop everything
npm run db:up           # Start databases stack
npm run db:postgres     # Start only postgres
npm run msg:up          # Start messaging stack
npm run storage:up      # Start storage stack
npm run obs:up          # Start observability stack
npm run ps              # Show status
```

---

## Connecting your app

All containers are on the `my-lab` Docker network. Apps running in Docker on the same network can reach services by container name:

| Service | Internal address | Host address |
|---|---|---|
| PostgreSQL | `my-lab-postgres:5432` | `localhost:8001` |
| MySQL | `my-lab-mysql:3306` | `localhost:8002` |
| SQL Server | `my-lab-sqlserver:1433` | `localhost:8003` |
| MongoDB | `my-lab-mongodb:27017` | `localhost:8004` |
| Redis | `my-lab-redis:6379` | `localhost:8005` |
| RabbitMQ | `my-lab-rabbitmq:5672` | `localhost:8100` |
| Kafka | `kafka:9092` (internal) | `localhost:8102` (external) |
| MinIO S3 | `my-lab-minio:9000` | `localhost:8200` |
| OTEL gRPC | `my-lab-otel-collector:4317` | `localhost:8304` |
| OTEL HTTP | `my-lab-otel-collector:4318` | `localhost:8305` |

**To join the network from your app's compose file:**
```yaml
networks:
  my-lab:
    external: true
    name: my-lab
```

**Send telemetry from your app:**
```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:8304   # gRPC (from host)
OTEL_EXPORTER_OTLP_ENDPOINT=http://my-lab-otel-collector:4317  # gRPC (from Docker)
```

---

## Project structure

```
my-lab/
├── docker/
│   ├── databases/          PostgreSQL, MySQL, SQL Server, MongoDB, Redis
│   ├── messaging/          RabbitMQ, Kafka, Kafka UI
│   ├── storage/            MinIO
│   └── observability/      Grafana, Prometheus, Loki, Tempo, OTEL Collector
├── docs/
│   └── observability-integration.md   Options for wiring services into observability
├── lab.sh                  Orchestration script
├── package.json            npm convenience scripts
└── README.md               This file
```

See [`docker/README.md`](docker/README.md) for detailed documentation on each stack, config files, and credentials.

---

## Default credentials

These are development-only defaults from the env files. Change them before using on any shared network.

| Service | User | Password |
|---|---|---|
| PostgreSQL | `lab_user` | see `databases.env` |
| MySQL | `lab_user` / `root` | see `databases.env` |
| SQL Server | `sa` | see `databases.env` |
| MongoDB | `lab_admin` | see `databases.env` |
| Redis | — | see `databases.env` |
| RabbitMQ | `lab_user` | see `messaging.env` |
| MinIO | `lab_admin` | see `storage.env` |
| Grafana | `admin` | `admin` |

---

## Notes

- **Apple Silicon (M1/M2/M3):** SQL Server has no native ARM64 image and runs under Rosetta emulation. All other services have native ARM64 images.
- **PostgreSQL upgrades:** PostgreSQL does not support in-place major version upgrades via Docker image swap. If upgrading from a previous major version, drop the named volume (`docker volume rm my-lab_postgres_data`) and let Postgres re-initialise from scratch.
- **Kafka:** Uses KRaft mode — no Zookeeper required. The `CLUSTER_ID` in `messaging.env` must not change after first start.
- **BullMQ:** Uses the Redis instance at port `8005`. No separate container needed.
- **Observability is optional:** all service stacks start and run without the observability stack. See [`docs/observability-integration.md`](docs/observability-integration.md) for wiring options.
