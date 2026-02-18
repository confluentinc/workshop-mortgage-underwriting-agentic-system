# Unify Terraform Codebases - Task Tracker

## Overview
Merged `instructor-led/` and `self-serve/` into a single `terraform/` directory with two thin entry points (`workshop/` and `self-serve/`) sharing common modules. Workshop users never download the AWS provider.

## Tasks

| # | Task | Status |
|---|------|--------|
| 1 | Create feature branch `unify-terraform` | Done |
| 2 | Create directory structure and copy identical files | Done |
| 3 | Create `terraform/modules/base/` (Confluent resources, webapp, data-gen) | Done |
| 4 | Update `terraform/modules/aws/` (EC2 Postgres + Debezium CDC + IAM) | Done |
| 5 | Create `terraform/workshop/` entry point | Done |
| 6 | Create `terraform/self-serve/` entry point | Done |
| 7 | Remove old root-level terraform files | Done |
| 8 | Move lab docs (`lab1/`, `lab2/`, `Demo/`) to top level | Done |
| 9 | Create `SETUP-WORKSHOP.md` and `SETUP-SELF-SERVE.md`, update root `README.md` | Done |
| 10 | Update `.gitignore` and remove `instructor-led/` + `self-serve/` | Done |

## Key Architecture Decisions

- **Two entry points**: `terraform/workshop/` and `terraform/self-serve/` — users `cd` into the right one
- **Shared modules**: `modules/base/` (Confluent, webapp, data-gen) and `modules/aws/` (EC2 Postgres, IAM)
- **No AWS provider for workshop**: AWS provider is only declared inside `modules/aws/`, which is only called by `self-serve/main.tf`
- **EC2 Postgres with Debezium CDC**: Docker Postgres 15 with `wal_level=logical`, replication slots, and `pg_hba.conf` for remote CDC
- **All AWS resources tagged**: `var.email` via provider `default_tags`, random suffix in all resource names
- **Both modes use Postgres**: Eliminated Oracle, unified field name casing (lowercase), unified data-gen configs
