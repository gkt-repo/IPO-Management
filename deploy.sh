#!/usr/bin/env bash
# ==============================================================================
# One-Click Production Deployment Script for Personal IPO Tracker
# Safe for side-by-side execution on Oracle Cloud VM
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[IPO DEPLOY]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || error "Docker is not installed."
command -v docker compose >/dev/null 2>&1 || error "Docker Compose plugin is not installed."

if [ ! -f .env ]; then
  if [ -f .env.oracle.example ]; then
    warn ".env not found! Creating from .env.oracle.example template..."
    cp .env.oracle.example .env
    warn "Please edit .env to set your secure passwords and encryption keys before re-running."
    exit 1
  else
    error ".env file is missing! Create one using .env.example"
  fi
fi

log "Building and starting isolated IPO Tracker containers..."
docker compose build --pull
docker compose up -d --remove-orphans

log "Waiting for PostgreSQL to become healthy..."
MAX_RETRIES=20
COUNT=0
until docker compose exec -T ipo_db pg_isready -U "${POSTGRES_USER:-ipo_user}" -d "${POSTGRES_DB:-ipo_db}" >/dev/null 2>&1; do
  COUNT=$((COUNT + 1))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    error "Postgres failed to initialize within timeout."
  fi
  sleep 2
done
success "PostgreSQL is healthy."

log "Waiting for IPO App container to initialize..."
sleep 5

log "Verifying running containers..."
docker compose ps

success "IPO Tracker successfully deployed on port ${PORT:-5000}!"
echo ""
echo "PEEK Microservice: running on internal ipo_network (isolated)"
echo "IPO Backend API: http://127.0.0.1:${PORT:-5000}"
echo "Swagger Docs: http://127.0.0.1:${PORT:-5000}/api/docs"
