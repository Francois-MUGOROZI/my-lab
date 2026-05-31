# Observability Integration Options

This document captures the three approaches for wiring the lab's service stacks (databases, messaging, storage) into the observability stack. None of these are implemented by default — the service stacks are intentionally decoupled from observability so they can run independently.

**Core constraint:** services must start and work without the observability stack running. Any integration must have zero hard dependencies pointing from a service stack toward observability.

---

## Option 1 — OTEL native receivers (recommended for this lab)

All collection logic lives inside the observability stack. OTEL Collector uses its built-in receivers to poll each service directly over the `my-lab` network. Nothing changes in the service stacks.

```
[observability stack]
  otel-collector
    → postgresql receiver   polls my-lab-postgres:5432
    → mysql receiver        polls my-lab-mysql:3306
    → mongodb receiver      polls my-lab-mongodb:27017
    → redis receiver        polls my-lab-redis:6379
    → rabbitmq receiver     polls my-lab-rabbitmq:15672 (management API)
    → kafkametrics receiver polls my-lab-kafka:9092
    → prometheus receiver   scrapes MinIO /minio/v2/metrics/cluster
  cAdvisor                  Docker socket → all container CPU/mem/net/disk
  prometheus                scrapes cAdvisor + otel-collector self-metrics
```

**Implementation:**
- Add receivers to `docker/observability/otel-collector-config.yaml`
- Add service credentials to `docker/observability/observability.env`
- Add cAdvisor service to `docker/observability/docker-compose.yml`
- Update `docker/observability/prometheus.yml` to scrape cAdvisor

**Changes to service stacks:** None.

**If observability is not running:** Receivers log connection errors, retry on next interval. Services are completely unaffected.

**SQL Server:** The OTEL `sqlserver` receiver only works on Windows. On macOS/Linux, SQL Server metrics require Option 2's `sql_exporter` sidecar or are skipped.

**Trade-offs:**
- OTEL native receivers are less feature-rich than dedicated exporters — fewer query-level metrics for Postgres, no consumer-group lag for Kafka
- All credentials for every service live in `observability.env`
- Single config file to maintain; adding a new service = one file edit

---

## Option 2 — Co-located Prometheus exporters

Each service stack gets lightweight companion exporter containers. Exporters always run when their service runs, exposing a passive `/metrics` endpoint. Prometheus scrapes those endpoints. Services never interact with OTEL directly.

```
[databases stack]
  postgres + postgres_exporter      (bitnami/postgres-exporter)
  mysql    + mysqld_exporter        (prom/mysqld-exporter)
  mongodb  + mongodb_exporter       (percona/mongodb_exporter)
  redis    + redis_exporter         (oliver006/redis_exporter)
  sqlserver + sql_exporter          (burningalchemist/sql_exporter)

[messaging stack]
  rabbitmq  — built-in /metrics endpoint, no exporter needed
  kafka     + kafka_exporter        (danielqsj/kafka-exporter)

[storage stack]
  minio — built-in /metrics endpoint, no exporter needed

[observability stack]
  prometheus   scrapes all exporter /metrics endpoints
  cAdvisor     Docker socket → container stats
```

**Implementation:**
- Add exporter services to each stack's `docker-compose.yml`
- Exporter credentials come from the same stack's `.env` file (already present)
- Update `docker/observability/prometheus.yml` with scrape targets
- Add cAdvisor to observability stack

**Changes to service stacks:** 5–6 extra exporter containers across all stacks.

**If observability is not running:** Exporters still run, nobody scrapes them. Zero impact on services.

**Trade-offs:**
- Best metric coverage — dedicated exporters (especially `postgres_exporter`) expose far richer metrics: query stats, table bloat, lock waits, replication lag, Kafka consumer group lag
- Exporters always consume a small amount of memory even when observability is off
- Config is split across stack files rather than centralised
- More images to track and keep updated

---

## Option 3 — OTEL docker_stats receiver (minimal footprint)

Same as Option 1 but replaces cAdvisor with OTEL Collector's built-in `docker_stats` receiver. Eliminates one container and one Prometheus scrape target.

```
[observability stack]
  otel-collector
    → all service receivers (same as Option 1)
    → docker_stats receiver  Docker socket → container CPU/mem/net/disk
  prometheus   scrapes otel-collector self-metrics only
  grafana
```

**Implementation:** Same as Option 1, but configure `docker_stats` receiver in OTEL instead of adding a cAdvisor container. OTEL Collector needs the Docker socket mounted:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

**Changes to service stacks:** None.

**Trade-offs:**
- Smallest footprint — one less container, one less scrape target
- `docker_stats` exposes slightly fewer container metrics than cAdvisor
- Fewer ready-made Grafana dashboards exist for `docker_stats` vs the well-known cAdvisor dashboard set
- OTEL Collector needs Docker socket access

---

## Comparison

| | Option 1 | Option 2 | Option 3 |
|---|---|---|---|
| Changes to service stacks | **None** | 5–6 extra containers | **None** |
| Metric richness | Medium | **Highest** | Medium |
| Config location | Centralised (observability) | Split across stacks | **Centralised** |
| SQL Server metrics | Limited (Linux) | Full (`sql_exporter`) | Limited |
| cAdvisor | Yes | Yes | No (`docker_stats`) |
| Extra images to manage | Low | 5–6 exporter images | **Lowest** |
| Best suited for | This lab | Production-grade setup | Minimal footprint |

---

## cAdvisor (applies to Options 1 and 2)

cAdvisor (`gcr.io/cadvisor/cadvisor`) provides per-container CPU, memory, network, and disk I/O metrics. It needs read access to the Docker daemon and host system paths:

```yaml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:v0.49.2
  container_name: my-lab-cadvisor
  ports:
    - "8306:8080"
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
  privileged: true
  networks:
    - my-lab
```

Add this scrape target to `prometheus.yml`:
```yaml
- job_name: cadvisor
  static_configs:
    - targets: ["cadvisor:8080"]
```

The community Grafana dashboard ID `14282` (cAdvisor) provides a ready-to-import container overview.

> **macOS note:** On Docker Desktop for macOS, `/sys` and `/var/lib/docker` are inside the Linux VM. cAdvisor still works but reports VM-level metrics, not raw host metrics. This is expected and sufficient for local development.
