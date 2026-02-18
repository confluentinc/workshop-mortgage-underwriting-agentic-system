resource "null_resource" "webapp_container_windows" {
  count = local.is_windows ? 1 : 0

  triggers = {
    dockerfile_hash  = filemd5(join("/", [path.module, "..", "webapp", "Dockerfile"]))
    app_hash         = filemd5(join("/", [path.module, "..", "webapp", "app.py"]))
    requirements_hash = filemd5(join("/", [path.module, "..", "webapp", "requirements.txt"]))
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
if (-not $runtime) { throw "No running container runtime found. Start Docker Desktop/Colima or Podman and retry." }
$envFile = Join-Path "${path.module}" ".webapp.env"
@'
KAFKA_BOOTSTRAP_SERVERS=${confluent_kafka_cluster.standard.bootstrap_endpoint}
KAFKA_API_KEY=${confluent_api_key.app-manager-kafka-api-key.id}
KAFKA_API_SECRET=${confluent_api_key.app-manager-kafka-api-key.secret}
SCHEMA_REGISTRY_URL=${data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint}
SCHEMA_REGISTRY_API_KEY=${confluent_api_key.app-manager-schema-registry-api-key.id}
SCHEMA_REGISTRY_API_SECRET=${confluent_api_key.app-manager-schema-registry-api-key.secret}
'@ | Set-Content -Path $envFile -NoNewline
& $runtime rm -f mortgage-webapp 2>$null
& $runtime build -t mortgage-webapp:local "${path.module}/../webapp"
& $runtime run -d --name mortgage-webapp -p 5001:5000 --env-file $envFile mortgage-webapp:local
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-Command"]
    command     = "$runtime = if (Get-Command docker -ErrorAction SilentlyContinue) { \"docker\" } elseif (Get-Command podman -ErrorAction SilentlyContinue) { \"podman\" } else { \"\" }; if ($runtime) { & $runtime rm -f mortgage-webapp 2>$null }; $envFile = Join-Path \"${path.module}\" \".webapp.env\"; if (Test-Path $envFile) { Remove-Item -Force $envFile }"
  }
}

resource "null_resource" "webapp_container_unix" {
  count = local.is_windows ? 0 : 1

  triggers = {
    dockerfile_hash   = filemd5(join("/", [path.module, "..", "webapp", "Dockerfile"]))
    app_hash          = filemd5(join("/", [path.module, "..", "webapp", "app.py"]))
    requirements_hash = filemd5(join("/", [path.module, "..", "webapp", "requirements.txt"]))
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
env_file="${path.module}/.webapp.env"
cat > "$env_file" <<'EOF'
KAFKA_BOOTSTRAP_SERVERS=${confluent_kafka_cluster.standard.bootstrap_endpoint}
KAFKA_API_KEY=${confluent_api_key.app-manager-kafka-api-key.id}
KAFKA_API_SECRET=${confluent_api_key.app-manager-kafka-api-key.secret}
SCHEMA_REGISTRY_URL=${data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint}
SCHEMA_REGISTRY_API_KEY=${confluent_api_key.app-manager-schema-registry-api-key.id}
SCHEMA_REGISTRY_API_SECRET=${confluent_api_key.app-manager-schema-registry-api-key.secret}
EOF
$runtime rm -f mortgage-webapp >/dev/null 2>&1 || true
$runtime build -t mortgage-webapp:local "${path.module}/../webapp"
$runtime run -d --name mortgage-webapp -p 5001:5000 --env-file "$env_file" mortgage-webapp:local
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = "if command -v docker >/dev/null 2>&1; then runtime=docker; elif command -v podman >/dev/null 2>&1; then runtime=podman; else runtime=\"\"; fi; if [ -n \"$runtime\" ]; then $runtime rm -f mortgage-webapp >/dev/null 2>&1 || true; fi; env_file=\"${path.module}/.webapp.env\"; [ -f \"$env_file\" ] && rm -f \"$env_file\""
  }
}

output "webapp_endpoint" {
  description = "Local webapp URL"
  value       = "http://localhost:5001"
}