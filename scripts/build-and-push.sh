#!/usr/bin/env bash
set -euo pipefail

REGISTRY_IMAGE="ghcr.io/blakek96-dev/preppergrid-nomad"
LOCAL_IMAGE="preppergrid-nomad:local-arm64"
VERSION_SUFFIX="$(git describe --tags --always)"
REMOTE_LATEST="${REGISTRY_IMAGE}:arm64-latest"
REMOTE_VERSIONED="${REGISTRY_IMAGE}:arm64-${VERSION_SUFFIX}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required for ghcr.io authentication." >&2
  exit 1
fi

if [[ -z "${GITHUB_ACTOR:-}" ]]; then
  echo "GITHUB_ACTOR is required for ghcr.io authentication." >&2
  exit 1
fi

"${SCRIPT_DIR}/build-arm64.sh"

echo "Authenticating to ghcr.io as ${GITHUB_ACTOR}..."
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin >/dev/null

docker tag "${LOCAL_IMAGE}" "${REMOTE_LATEST}"
docker tag "${LOCAL_IMAGE}" "${REMOTE_VERSIONED}"

echo "Pushing ${REMOTE_LATEST}..."
if ! docker push "${REMOTE_LATEST}"; then
  echo "Failed to push ${REMOTE_LATEST}. Check GHCR package permissions and that GITHUB_TOKEN has packages:write access." >&2
  exit 1
fi

echo "Pushing ${REMOTE_VERSIONED}..."
if ! docker push "${REMOTE_VERSIONED}"; then
  echo "Failed to push ${REMOTE_VERSIONED}. Check GHCR package permissions and network connectivity." >&2
  exit 1
fi

echo "Published ${REMOTE_LATEST} and ${REMOTE_VERSIONED}."
