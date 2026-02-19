#!/usr/bin/env bash

set -e

IMAGE="ghcr.io/ahmedszamzam/datagen:latest"

runtime=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  runtime="docker"
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  runtime="podman"
else
  echo "No running container runtime found. Start Docker Desktop/Colima or Podman and retry." >&2
  exit 1
fi

$runtime pull $IMAGE
$runtime run --rm --env-file .datagen.env $IMAGE
