#!/usr/bin/env bash
set -euo pipefail

# Dockerfile ARM64 findings:
# - Inspected ./Dockerfile before creating this script.
# - No FROM --platform=linux/amd64 directive was found.
# - No hardcoded amd64/x86_64 download URLs were found.
# - No uname -m, arch, or architecture-switching checks were found.
# - Base image node:22-slim is expected to be multi-arch, and apt packages are
#   resolved from Debian repositories for the requested linux/arm64 platform.
# - Conclusion: Dockerfile appears ARM64-clean. Native npm dependencies still
#   depend on their upstream packages supporting linux/arm64 during npm ci.

IMAGE_LOCAL="preppergrid-nomad:local-arm64"
VERSION_SUFFIX="$(git describe --tags --always)"
IMAGE_VERSIONED="preppergrid-nomad:local-arm64-${VERSION_SUFFIX}"
BUILD_LOG="$(mktemp -t preppergrid-nomad-arm64-build.XXXXXX.log)"

cleanup() {
  rm -f "${BUILD_LOG}"
}

print_failure_log() {
  echo "ARM64 Docker build failed. Last 50 lines of build log:" >&2
  tail -n 50 "${BUILD_LOG}" >&2 || true
}

trap cleanup EXIT

echo "Building ${IMAGE_LOCAL} and ${IMAGE_VERSIONED} for linux/arm64..."

if ! docker buildx build \
  --platform linux/arm64 \
  --tag "${IMAGE_LOCAL}" \
  --tag "${IMAGE_VERSIONED}" \
  --load \
  . > "${BUILD_LOG}" 2>&1; then
  print_failure_log
  exit 1
fi

architecture="$(docker inspect "${IMAGE_LOCAL}" --format '{{.Architecture}}')"
if [[ "${architecture}" != "arm64" ]]; then
  echo "Post-build verification failed: expected architecture arm64, got ${architecture}" >&2
  exit 1
fi

docker inspect "${IMAGE_LOCAL}" --format '{{.Id}} {{.Size}}'
