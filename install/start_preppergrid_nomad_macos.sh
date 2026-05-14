#!/bin/bash

set -e

NOMAD_DIR="${NOMAD_DIR:-/Users/$USER/.preppergrid-nomad}"
COMPOSE_FILE="${NOMAD_DIR}/compose.yml"
ENV_FILE="${NOMAD_DIR}/compose.macos.env"

if ! docker info > /dev/null 2>&1; then
    echo "Docker Desktop is required and must be running."
    exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Compose file not found at $COMPOSE_FILE. Run the macOS installer first."
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Compose env file not found at $ENV_FILE. Run the macOS installer first."
    exit 1
fi

mkdir -p "${NOMAD_DIR}/storage/logs"

echo "Starting PrepperGrid N.O.M.A.D containers..."
docker compose -p preppergrid-nomad -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo "PrepperGrid N.O.M.A.D is starting. Open http://localhost:8080 when containers are healthy."
