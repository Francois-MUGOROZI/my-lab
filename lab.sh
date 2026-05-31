#!/usr/bin/env bash
# lab.sh — my-lab Docker orchestration
# Usage: ./lab.sh <command> [--stack <name>] [--service <name>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/docker"
PROJECT_NAME="my-lab"
NETWORK_NAME="my-lab"

ALL_STACKS=(databases messaging storage observability)

# ─── Colours ────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD="\033[1m"; RESET="\033[0m"
  GREEN="\033[0;32m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; RED="\033[0;31m"
else
  BOLD=""; RESET=""; GREEN=""; YELLOW=""; CYAN=""; RED=""
fi

info()    { echo -e "${CYAN}[my-lab]${RESET} $*"; }
success() { echo -e "${GREEN}[my-lab]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[my-lab]${RESET} $*"; }
error()   { echo -e "${RED}[my-lab]${RESET} $*" >&2; exit 1; }

# ─── Usage ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") <command> [options]

${BOLD}Commands:${RESET}
  up        Start services (detached)
  down      Stop and remove containers
  restart   Restart services
  logs      Follow service logs
  ps        Show running containers
  pull      Pull latest images for a stack

${BOLD}Options:${RESET}
  --stack <name>    Target stack: databases | messaging | storage | observability | all
  --service <name>  Target a specific service within a stack

${BOLD}Port Reference:${RESET}
  Databases
    8001  PostgreSQL       8002  MySQL
    8003  SQL Server       8004  MongoDB
    8005  Redis (+ BullMQ)

  Messaging
    8100  RabbitMQ AMQP    8101  RabbitMQ UI
    8102  Kafka            8103  Kafka UI

  Storage
    8200  MinIO API (S3)   8201  MinIO Console

  Observability
    8300  Loki             8301  Tempo
    8302  Prometheus       8303  Grafana
    8304  OTEL gRPC        8305  OTEL HTTP

${BOLD}Examples:${RESET}
  ./lab.sh up                              # Start everything
  ./lab.sh up --stack databases            # Start databases only
  ./lab.sh up --stack databases --service postgres
  ./lab.sh down --stack messaging
  ./lab.sh logs --stack observability --service grafana
  ./lab.sh ps
EOF
}

# ─── Helpers ────────────────────────────────────────────────────────────────
ensure_network() {
  if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    info "Creating shared network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME"
  fi
}

compose() {
  local stack="$1"; shift
  local compose_file="$DOCKER_DIR/$stack/docker-compose.yml"

  if [ ! -f "$compose_file" ]; then
    error "Compose file not found: $compose_file"
  fi

  docker compose -p "$PROJECT_NAME" -f "$compose_file" "$@"
}

validate_stack() {
  local stack="$1"
  if [ "$stack" = "all" ]; then return; fi
  for s in "${ALL_STACKS[@]}"; do
    [[ "$s" == "$stack" ]] && return
  done
  error "Unknown stack '$stack'. Valid stacks: ${ALL_STACKS[*]} | all"
}

# ─── Commands ───────────────────────────────────────────────────────────────
cmd_up() {
  local stack="$1"; local service="$2"
  ensure_network

  local stacks=()
  if [ "$stack" = "all" ]; then
    stacks=("${ALL_STACKS[@]}")
  else
    stacks=("$stack")
  fi

  for s in "${stacks[@]}"; do
    info "Starting ${BOLD}$s${RESET}..."
    if [ -n "$service" ]; then
      compose "$s" up -d "$service"
    else
      compose "$s" up -d
    fi
    success "$s is up."
  done
}

cmd_down() {
  local stack="$1"; local service="$2"

  local stacks=()
  if [ "$stack" = "all" ]; then
    # Reverse order for clean shutdown (observability last to capture final metrics)
    stacks=(storage messaging databases observability)
  else
    stacks=("$stack")
  fi

  for s in "${stacks[@]}"; do
    info "Stopping ${BOLD}$s${RESET}..."
    if [ -n "$service" ]; then
      compose "$s" stop "$service"
      compose "$s" rm -f "$service"
    else
      compose "$s" down
    fi
    success "$s stopped."
  done
}

cmd_restart() {
  local stack="$1"; local service="$2"

  local stacks=()
  if [ "$stack" = "all" ]; then
    stacks=("${ALL_STACKS[@]}")
  else
    stacks=("$stack")
  fi

  for s in "${stacks[@]}"; do
    info "Restarting ${BOLD}$s${RESET}..."
    if [ -n "$service" ]; then
      compose "$s" restart "$service"
    else
      compose "$s" restart
    fi
    success "$s restarted."
  done
}

cmd_logs() {
  local stack="$1"; local service="$2"

  if [ "$stack" = "all" ]; then
    warn "Cannot follow logs for all stacks simultaneously. Specify --stack <name>."
    exit 1
  fi

  if [ -n "$service" ]; then
    compose "$stack" logs -f "$service"
  else
    compose "$stack" logs -f
  fi
}

cmd_ps() {
  local stack="$1"

  local stacks=()
  if [ "$stack" = "all" ]; then
    stacks=("${ALL_STACKS[@]}")
  else
    stacks=("$stack")
  fi

  for s in "${stacks[@]}"; do
    echo -e "\n${BOLD}=== $s ===${RESET}"
    compose "$s" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  done
}

cmd_pull() {
  local stack="$1"

  local stacks=()
  if [ "$stack" = "all" ]; then
    stacks=("${ALL_STACKS[@]}")
  else
    stacks=("$stack")
  fi

  for s in "${stacks[@]}"; do
    info "Pulling images for ${BOLD}$s${RESET}..."
    compose "$s" pull
  done
}

# ─── Argument parsing ────────────────────────────────────────────────────────
COMMAND="${1:-}"
if [ -z "$COMMAND" ] || [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ]; then
  usage
  exit 0
fi
shift

STACK="all"
SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)    STACK="${2:-}";   shift 2 ;;
    --service)  SERVICE="${2:-}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          error "Unknown option: $1" ;;
  esac
done

validate_stack "$STACK"

# ─── Dispatch ────────────────────────────────────────────────────────────────
case "$COMMAND" in
  up)      cmd_up      "$STACK" "$SERVICE" ;;
  down)    cmd_down    "$STACK" "$SERVICE" ;;
  restart) cmd_restart "$STACK" "$SERVICE" ;;
  logs)    cmd_logs    "$STACK" "$SERVICE" ;;
  ps)      cmd_ps      "$STACK" ;;
  pull)    cmd_pull    "$STACK" ;;
  *)       error "Unknown command: $COMMAND. Run './lab.sh --help' for usage." ;;
esac
