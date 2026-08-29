#!/usr/bin/env bash
set -euo pipefail

# Builds the Inbox Zero HA add-on image locally and optionally pushes it.
#
# The image is built for the host architecture by default (on Apple Silicon
# that is linux/arm64, which is what a Raspberry Pi needs). Use --platform to
# cross-build (requires buildx and QEMU).
#
# Usage:
#   ./build.sh                                # builds ghcr.io/<user>/inbox-zero-ha-addon:latest
#   IMAGE=ghcr.io/myuser/inbox-zero-ha-addon TAG=v0.1.0 ./build.sh
#   ./build.sh --push                         # build + push
#   ./build.sh --platform linux/arm64         # force arch

IMAGE="${IMAGE:-ghcr.io/smobaraki/inbox-zero-ha-addon}"
TAG="${TAG:-latest}"
PUSH=0
PLATFORM=""

for arg in "$@"; do
    case "$arg" in
        --push) PUSH=1 ;;
        --platform=*) PLATFORM="${arg#*=}" ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

cd "$(dirname "$0")"

ARGS=(-t "${IMAGE}:${TAG}" -t "${IMAGE}:${TAG%-latest}")
[ -n "$PLATFORM" ] && ARGS+=(--platform "$PLATFORM")

echo "Building ${IMAGE}:${TAG}${PLATFORM:+ ($PLATFORM)}..."
docker buildx build --load "${ARGS[@]}" .

if [ "$PUSH" = "1" ]; then
    echo "Pushing ${IMAGE}:${TAG}..."
    docker buildx build --push "${ARGS[@]}" .
fi

echo "Done: ${IMAGE}:${TAG}"
