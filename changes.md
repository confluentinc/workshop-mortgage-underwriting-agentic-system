# Unify Terraform Codebases - Task Tracker

## Overview
Merging `instructor-led/` and `self-serve/` into a single `terraform/` directory with a `mode` variable (`workshop` / `self-serve`). Both modes use Postgres. AWS resources in a conditional child module.

## Tasks

| # | Task | Status |
|---|------|--------|
| 1 | Create feature branch `unify-terraform` | Done |
| 2 | Create directory structure and copy identical files | Done |
| 3 | Create `terraform/variables.tf` with `mode` variable | Done |
| 4 | Create `terraform/providers.tf` (confluent + http only) | Done |
| 5 | Create `terraform/modules/aws/` (RDS Postgres + parameter group + IAM) | Done |
| 6 | Create `terraform/confluent.tf` with conditional module + locals | Done |
| 7 | Create `terraform/outputs.tf` with `local.db_*` references | Done |
| 8 | Copy and fix `terraform/webapp.tf` paths | Done |
| 9 | Move lab docs (`lab1/`, `lab2/`, `Demo/`) to top level | Done |
| 10 | Create `SETUP-WORKSHOP.md` and `SETUP-SELF-SERVE.md`, update root `README.md` | Done |
| 11 | Update `.gitignore` and remove `instructor-led/` + `self-serve/` | Done |
| 12 | Create `changes.md` tracking document | Done |

## Key Architecture Decisions

- **`mode` variable**: `workshop` (instructor provides DB + Bedrock keys) or `self-serve` (Terraform provisions RDS Postgres + IAM for Bedrock)
- **Conditional AWS module**: `module "aws" { count = var.mode == "self-serve" ? 1 : 0 }` — AWS provider only loaded when needed
- **RDS Postgres**: `db.t3.small`, engine `postgres 15`, with `rds.logical_replication = 1` parameter group for Debezium CDC
- **Unified locals**: `local.db_host`, `local.bedrock_access_key` etc. resolve to either user-provided vars or module outputs
- **Both modes use Postgres**: Eliminated Oracle, unified field name casing (lowercase), unified data-gen configs
