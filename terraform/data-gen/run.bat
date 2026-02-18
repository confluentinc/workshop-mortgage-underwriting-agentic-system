@echo off
setlocal

set RUNTIME=
where docker >nul 2>&1 && docker info >nul 2>&1 && set RUNTIME=docker
if not defined RUNTIME (
    where podman >nul 2>&1 && podman info >nul 2>&1 && set RUNTIME=podman
)
if not defined RUNTIME (
    echo No running container runtime found. Start Docker Desktop or Podman and retry.
    exit /b 1
)

%RUNTIME% run ^
       --rm ^
       --env-file free-trial-license-docker.env ^
       --net=host ^
       -v %cd%/root.json:/home/root.json ^
       -v %cd%/generators:/home/generators ^
       -v %cd%/connections:/home/connections ^
       shadowtraffic/shadowtraffic:1.13.4 ^
       --config /home/root.json

if %ERRORLEVEL% neq 0 (
    echo Command failed with error code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo Command completed successfully
