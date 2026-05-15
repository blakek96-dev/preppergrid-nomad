#!/bin/bash
set -euo pipefail

PROJECT_NAME="preppergrid-nomad-test"
TEMP_COMPOSE="/tmp/test-compose-$$.yml"
TEMP_ENV="/tmp/test-compose-$$.env"
TEMP_NOMAD_DIR="/tmp/preppergrid-nomad-test-$$"
failures=0

cleanup() {
  docker compose -p "$PROJECT_NAME" -f "$TEMP_COMPOSE" down -v >/dev/null 2>&1 || true
  rm -f "$TEMP_COMPOSE"
  rm -f "$TEMP_ENV"
  rm -rf "$TEMP_NOMAD_DIR"
}
trap cleanup EXIT INT TERM

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1: $2"
  failures=$((failures + 1))
}

assert_command() {
  local test_name="$1"
  shift
  if "$@"; then
    pass "$test_name"
  else
    fail "$test_name" "command failed: $*"
  fi
}

if ! docker info >/dev/null 2>&1; then
  echo "SKIP: Docker not running — skipping integration test"
  exit 0
fi

mkdir -p "${TEMP_NOMAD_DIR}/storage/logs"
cat > "$TEMP_ENV" <<EOF
NOMAD_DIR=${TEMP_NOMAD_DIR}
EOF

app_key="$(python3 -c "import secrets,string; alphabet=string.ascii_letters+string.digits; print(''.join(secrets.choice(alphabet) for _ in range(32)))")"
db_root_password="$(python3 -c "import secrets,string; alphabet=string.ascii_letters+string.digits; print(''.join(secrets.choice(alphabet) for _ in range(32)))")"
db_user_password="$(python3 -c "import secrets,string; alphabet=string.ascii_letters+string.digits; print(''.join(secrets.choice(alphabet) for _ in range(32)))")"

cat > "$TEMP_COMPOSE" <<EOF
name: ${PROJECT_NAME}
services:
  admin:
    image: ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest
    platform: linux/arm64
    pull_policy: always
    ports:
      - "8181:8080"
    env_file:
      - ${TEMP_ENV}
    volumes:
      - \${NOMAD_DIR}/storage:/app/storage
    environment:
      - NODE_ENV=production
      - PORT=8080
      - LOG_LEVEL=info
      - APP_KEY=${app_key}
      - HOST=0.0.0.0
      - URL=http://localhost:8181
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_DATABASE=nomad
      - DB_USER=nomad_user
      - DB_PASSWORD=${db_user_password}
      - DB_NAME=nomad
      - DB_SSL=false
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - DISABLE_COMPRESSION=false
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 10s
      timeout: 5s
      retries: 6
  mysql:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=${db_root_password}
      - MYSQL_DATABASE=nomad
      - MYSQL_USER=nomad_user
      - MYSQL_PASSWORD=${db_user_password}
    volumes:
      - \${NOMAD_DIR}/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 12
  redis:
    image: redis:7-alpine
    volumes:
      - \${NOMAD_DIR}/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 6
EOF

assert_command "integration compose stack starts" docker compose -p "$PROJECT_NAME" -f "$TEMP_COMPOSE" up -d

health_ok=0
start_time="$(date +%s)"
for attempt in $(seq 1 24); do
  status_code="$(python3 -c "import urllib.request, urllib.error; 
try:
    response = urllib.request.urlopen('http://localhost:8181/api/health', timeout=5)
    print(response.getcode())
except Exception:
    print(0)")"
  if [[ "$status_code" == "200" ]]; then
    health_ok=1
    break
  fi
  now="$(date +%s)"
  elapsed=$((now - start_time))
  echo "Healthcheck attempt ${attempt}/24 failed after ${elapsed}s with HTTP ${status_code}"
  sleep 5
done

if [[ "$health_ok" -eq 1 ]]; then
  pass "integration health endpoint returns HTTP 200"
else
  echo "Container diagnostics for ${PROJECT_NAME}:"
  docker compose -p "$PROJECT_NAME" -f "$TEMP_COMPOSE" ps || true
  docker compose -p "$PROJECT_NAME" -f "$TEMP_COMPOSE" logs --tail=80 || true
  fail "integration health endpoint returns HTTP 200" "timed out after 120 seconds waiting for http://localhost:8181/api/health"
fi

if docker compose -p "$PROJECT_NAME" -f "$TEMP_COMPOSE" ps --format json | python3 -c "import json,sys
raw=sys.stdin.read().strip()
items=[]
if raw:
    try:
        parsed=json.loads(raw)
        items = parsed if isinstance(parsed, list) else [parsed]
    except json.JSONDecodeError:
        items=[json.loads(line) for line in raw.splitlines() if line.strip()]
assert items, 'no compose services reported'
bad=[]
for item in items:
    state=str(item.get('State','')).lower()
    health=str(item.get('Health','')).lower()
    status=str(item.get('Status','')).lower()
    if not (state == 'running' or health == 'healthy' or 'running' in status or 'healthy' in status):
        bad.append(item)
assert not bad, bad"; then
  pass "integration compose services are running or healthy"
else
  fail "integration compose services are running or healthy" "one or more services are not running or healthy"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
