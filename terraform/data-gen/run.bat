@echo off
setlocal

set IMAGE=ghcr.io/ahmedszamzam/datagen:latest

set RUNTIME=
where docker >nul 2>&1 && docker info >nul 2>&1 && set RUNTIME=docker
if not defined RUNTIME (
    where podman >nul 2>&1 && podman info >nul 2>&1 && set RUNTIME=podman
)
if not defined RUNTIME (
    echo No running container runtime found. Start Docker Desktop or Podman and retry.
    exit /b 1
)

%RUNTIME% pull %IMAGE%
%RUNTIME% run --rm --env-file .datagen.env %IMAGE%
