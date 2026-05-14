#!/bin/bash

set -e

NOMAD_DIR="${NOMAD_DIR:-/Users/$USER/.preppergrid-nomad}"
COMPOSE_FILE="${NOMAD_DIR}/compose.yml"
ENV_FILE="${NOMAD_DIR}/compose.macos.env"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Compose file not found at $COMPOSE_FILE. Nothing to stop."
    exit 0
fi

if ! docker info > /dev/null 2>&1; then
    echo "Docker Desktop is required and must be running to stop containers cleanly."
    exit 1
fi

echo "Stopping PrepperGrid N.O.M.A.D containers..."
if [[ -f "$ENV_FILE" ]]; then
    docker compose -p preppergrid-nomad -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
else
    docker compose -p preppergrid-nomad -f "$COMPOSE_FILE" down
fi
echo "PrepperGrid N.O.M.A.D containers stopped."
