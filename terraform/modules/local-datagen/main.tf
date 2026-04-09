locals {
  is_windows = length(regexall("^[A-Z]:", abspath(path.root))) > 0
}

resource "local_file" "datagen_env" {
  filename = "${path.root}/../data-gen/.datagen.env"
  content  = <<-EOT
KAFKA_BOOTSTRAP_SERVERS=${var.kafka_bootstrap_servers}
KAFKA_API_KEY=${var.kafka_api_key}
KAFKA_API_SECRET=${var.kafka_api_secret}
SCHEMA_REGISTRY_URL=${var.schema_registry_url}
SCHEMA_REGISTRY_API_KEY=${var.schema_registry_api_key}
SCHEMA_REGISTRY_API_SECRET=${var.schema_registry_api_secret}
PG_HOST=${var.pg_host}
PG_PORT=${var.pg_port}
PG_DATABASE=${var.pg_database}
PG_USERNAME=${var.pg_username}
PG_PASSWORD=${var.pg_password}
MORTGAGE_APP_INTERVAL_SECONDS=${var.mortgage_app_interval}
MORTGAGE_APP_COUNT=${var.mortgage_app_count}
MORTGAGE_APP_STARTUP_DELAY_SECONDS=${var.mortgage_app_startup_delay}
CDC_HEARTBEAT_INTERVAL_SECONDS=${var.cdc_heartbeat_interval}
  EOT
}

resource "null_resource" "datagen_container_windows" {
  count = local.is_windows ? 1 : 0

  triggers = {
    env_file_hash = local_file.datagen_env.content_md5
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
$runtime = ""
if (Get-Command docker -ErrorAction SilentlyContinue) {
  & docker info > $null 2>&1
  if ($LASTEXITCODE -eq 0) { $runtime = "docker" }
}
if (-not $runtime -and (Get-Command podman -ErrorAction SilentlyContinue)) {
  & podman info > $null 2>&1
  if ($LASTEXITCODE -eq 0) { $runtime = "podman" }
}
if (-not $runtime) { throw "No running container runtime found. Start Docker Desktop or Podman and retry." }
& $runtime rm -f mortgage-datagen 2>$null
& $runtime pull ghcr.io/ahmedszamzam/datagen:latest
& $runtime run -d --restart on-failure --name mortgage-datagen --env-file "${path.root}/../data-gen/.datagen.env" ghcr.io/ahmedszamzam/datagen:latest
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-Command"]
    command     = "$runtime = if (Get-Command docker -ErrorAction SilentlyContinue) { \"docker\" } elseif (Get-Command podman -ErrorAction SilentlyContinue) { \"podman\" } else { \"\" }; if ($runtime) { & $runtime rm -f mortgage-datagen 2>$null }"
  }

  depends_on = [
    local_file.datagen_env,
  ]
}

resource "null_resource" "datagen_container_unix" {
  count = local.is_windows ? 0 : 1

  triggers = {
    env_file_hash = local_file.datagen_env.content_md5
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<-EOT
set -e
runtime=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  runtime=docker
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  runtime=podman
else
  echo "No running container runtime found. Start Docker Desktop/Colima or Podman and retry." >&2
  exit 1
fi
$runtime rm -f mortgage-datagen >/dev/null 2>&1 || true
$runtime pull ghcr.io/ahmedszamzam/datagen:latest
$runtime run -d --restart on-failure --name mortgage-datagen --env-file "${path.root}/../data-gen/.datagen.env" ghcr.io/ahmedszamzam/datagen:latest
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = "if command -v docker >/dev/null 2>&1; then runtime=docker; elif command -v podman >/dev/null 2>&1; then runtime=podman; else runtime=\"\"; fi; if [ -n \"$runtime\" ]; then $runtime rm -f mortgage-datagen >/dev/null 2>&1 || true; fi"
  }

  depends_on = [
    local_file.datagen_env,
  ]
}
