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
& $runtime run -d --name mortgage-datagen --env-file "${path.root}/../data-gen/.datagen.env" ghcr.io/ahmedszamzam/datagen:latest
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-Command"]
    command     = "$runtime = if (Get-Command docker -ErrorAction SilentlyContinue) { \"docker\" } elseif (Get-Command podman -ErrorAction SilentlyContinue) { \"podman\" } else { \"\" }; if ($runtime) { & $runtime rm -f mortgage-datagen 2>$null }"
  }

  depends_on = [
    local_file.datagen_env,
    confluent_schema.avro-mortgage_applications,
    confluent_schema.avro-payment_history,
    confluent_kafka_topic.mortgage-application-topic,
    confluent_kafka_topic.payment-history-topic,
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
$runtime run -d --name mortgage-datagen --env-file "${path.root}/../data-gen/.datagen.env" ghcr.io/ahmedszamzam/datagen:latest
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = "if command -v docker >/dev/null 2>&1; then runtime=docker; elif command -v podman >/dev/null 2>&1; then runtime=podman; else runtime=\"\"; fi; if [ -n \"$runtime\" ]; then $runtime rm -f mortgage-datagen >/dev/null 2>&1 || true; fi"
  }

  depends_on = [
    local_file.datagen_env,
    confluent_schema.avro-mortgage_applications,
    confluent_schema.avro-payment_history,
    confluent_kafka_topic.mortgage-application-topic,
    confluent_kafka_topic.payment-history-topic,
  ]
}
