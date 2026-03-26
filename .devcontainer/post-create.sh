#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing workshop dependencies via Homebrew..."
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

echo "==> Verifying installations..."
git --version
terraform --version
docker --version

echo "==> Setting up terraform.tfvars template..."
TFVARS_DIR="terraform/workshop"
if [ ! -f "$TFVARS_DIR/terraform.tfvars" ] && [ -f "$TFVARS_DIR/terraform.tfvars.example" ]; then
  cp "$TFVARS_DIR/terraform.tfvars.example" "$TFVARS_DIR/terraform.tfvars"
  echo "    Created terraform.tfvars from template. Edit it with your values before running terraform."
fi

echo "==> Workshop environment ready!"
