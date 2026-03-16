#!/usr/bin/env bash
set -euo pipefail

IMAGE="${DOCKER_IMAGE:-svenwal/leywn}"
BUILDER="leywn-multiarch"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [--no-latest]" >&2
  echo "  version     e.g. 1.0.0" >&2
  echo "  --no-latest skip tagging :latest" >&2
  echo "" >&2
  echo "Override image name via DOCKER_IMAGE env var (default: $IMAGE)" >&2
  exit 1
fi

VERSION="$1"
TAG_LATEST=true
if [[ "${2:-}" == "--no-latest" ]]; then
  TAG_LATEST=false
fi

# Ensure buildx builder with multi-arch support exists.
# The docker-container driver spawns a BuildKit container and avoids the
# QEMU segfaults that occur with Rancher Desktop's default driver when
# cross-compiling heavy Erlang/Elixir code for AMD64 on Apple Silicon.
if ! docker buildx inspect "$BUILDER" &>/dev/null; then
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt network=host --bootstrap
fi
docker buildx use "$BUILDER"

TAGS="--tag ${IMAGE}:${VERSION}"
if [[ "$TAG_LATEST" == "true" ]]; then
  TAGS="$TAGS --tag ${IMAGE}:latest"
fi

echo "Building and pushing ${IMAGE}:${VERSION} (amd64 + arm64)..."

# shellcheck disable=SC2086
docker buildx build \
  --platform linux/arm64 \
  $TAGS \
  --push \
  .
#docker buildx build \
#  --platform linux/amd64,linux/arm64 \
#  $TAGS \
#  --push \
#  .

echo ""
echo "Done: ${IMAGE}:${VERSION} pushed to Docker Hub."
if [[ "$TAG_LATEST" == "true" ]]; then
  echo "      ${IMAGE}:latest also updated."
fi
