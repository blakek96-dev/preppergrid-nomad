#!/bin/bash

set -e

NOMAD_DIR="${NOMAD_DIR:-/Users/$USER/.preppergrid-nomad}"
COMPOSE_FILE="${NOMAD_DIR}/compose.yml"
ENV_FILE="${NOMAD_DIR}/compose.macos.env"
NOMAD_IMAGE="${NOMAD_IMAGE:-ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest}"

read -p "This script will update PrepperGrid N.O.M.A.D. No data loss is expected, but you should back up important data before proceeding. Continue? (y/N): " choice
case "$choice" in
    y|Y )
        echo "Updating PrepperGrid N.O.M.A.D..."
        ;;
    * )
        echo "Update canceled."
        exit 0
        ;;
esac

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

if grep -q '^NOMAD_IMAGE=' "$ENV_FILE"; then
    sed -i '' "s|^NOMAD_IMAGE=.*|NOMAD_IMAGE=${NOMAD_IMAGE}|g" "$ENV_FILE"
else
    printf '\nNOMAD_IMAGE=%s\n' "$NOMAD_IMAGE" >> "$ENV_FILE"
fi

docker compose -p preppergrid-nomad -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
docker compose -p preppergrid-nomad -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --force-recreate

echo "PrepperGrid N.O.M.A.D update complete."
