# Project: Mortgage Underwriting Agentic System

## Overview

End-to-end mortgage underwriting workflow on **Confluent Cloud** with **AI agents**. Streams mortgage applications and payment history, enriches them with credit data via CDC, and applies automated fraud/risk assessment plus decisioning using Confluent Streaming Agents powered by Claude on Amazon Bedrock.

## Architecture

```
mortgage_applications ──► enriched_mortgage_applications ──► enriched_mortgage_with_payments ──► mortgage_validated_apps ──► mortgage_decisions
                                      ▲                                    ▲
PROD.public.applicant_credit_score ──┘          applicant_payment_summary ┘
                                                            ▲
                                                 payment_history ─────────┘
```

## Deployment Modes

| Mode | Directory | Description |
|------|-----------|-------------|
| **Workshop** | `terraform/workshop/` | Instructor provides Postgres DB and Bedrock credentials. Participants manually create Flink SQL statements in Labs 1 & 2. |
| **Self-serve** | `terraform/self-serve/` | Terraform provisions AWS infrastructure (EC2 Postgres, IAM for Bedrock) in addition to base. Participants still do labs manually. |
| **Demo** | `terraform/demo_mode/` | Fully automated — all Flink DDL statements deployed via Terraform. Data gen runs continuously at 1 app/min. |

All three modes use `module.base` (`terraform/modules/base/`). Demo mode additionally uses `module.flink_statements` (`terraform/modules/flink-statements/`).

## Directory Structure

```
terraform/
├── modules/
│   ├── base/              # Core: env, cluster, topics, schemas, connectors, LLM model, MCP, datagen, webapp
│   ├── flink-statements/  # 8 Flink DDL statements (CTAS, CREATE AGENT, CREATE TOOL) — used by demo_mode only
│   └── aws/               # AWS infra (EC2 Postgres, IAM for Bedrock) — used by self-serve only
├── workshop/              # Entry point for workshop mode
├── self-serve/            # Entry point for self-serve mode
├── demo_mode/             # Entry point for demo mode
├── data-gen/              # Data generator Java app + Dockerfile
│   └── datagen-app/       # Maven project: DataGenerator.java
├── code/
│   └── FlinkTableAPI/     # Flink Table API Java app (alternative to SQL for enrichment)
└── schemas/
    └── avro/              # AVRO schemas for mortgage_applications and payment_history
webapp/                    # Flask webapp for submitting mortgage applications (port 5001)
lab1/                      # Lab 1 instructions: CDC connector + Flink SQL enrichment
lab2/                      # Lab 2 instructions: AI agents for risk assessment + decisioning
```

## Key Components

### Data Generator (`terraform/data-gen/datagen-app/`)
- **Image**: `ghcr.io/ahmedszamzam/datagen:latest` — single image for all modes, behavior controlled by env vars
- **Stage 1**: Seeds 702 credit scores into Postgres (100 high, 500 medium, 100 low + John Doe + Omar Soli)
- **Stage 2**: Produces 701 historical payment events to Kafka (no throttle)
- **Stage 3**: Two parallel threads:
  - **Mortgage apps**: Configurable via env vars `MORTGAGE_APP_INTERVAL_SECONDS` (default 600), `MORTGAGE_APP_COUNT` (default 20, -1 for continuous), `MORTGAGE_APP_STARTUP_DELAY_SECONDS` (default 0). The startup delay only applies to the mortgage application thread — payments start immediately.
  - **Payments**: Continuous, 5-10s throttle, runs indefinitely (no cap), starts immediately (no delay)
- Workshop/self-serve use defaults (20 apps, 10-min interval, no startup delay). Demo mode passes 60s interval, continuous, no startup delay.
- After any code change, rebuild and push the image to GHCR. All three modes pull the same image.

### Flink Statements Module (`terraform/modules/flink-statements/`)
8 statements deployed sequentially via `depends_on`:
1. CTAS `enriched_mortgage_applications` — joins mortgage apps with credit scores
2. CTAS `applicant_payment_summary` — aggregates payment history
3. CTAS `enriched_mortgage_with_payments` — temporal join (no property_value filter in demo mode)
4. CREATE AGENT `mortgage_risk_agent` — fraud/credit risk assessment
5. CTAS `mortgage_validated_apps` — applies risk agent via AI_RUN_AGENT
6. CREATE TOOL `send_email` — MCP tool for gmail
7. CREATE AGENT `mortgage_decisions_agent` — approval/rejection decisions
8. CTAS `mortgage_decisions` — applies decision agent, sends email (uses `var.email_address`)

### Base Module (`terraform/modules/base/`)
- Confluent Cloud: environment, Kafka cluster (Standard, AWS), Schema Registry (Advanced governance)
- Flink compute pool (20 max CFU)
- Service account with EnvironmentAdmin role binding
- Topics: `mortgage_applications`, `payment_history`, `incomplete_mortgage_applications` (DLQ)
- AVRO schemas with data quality rules (payslip URI validation → DLQ routing)
- Postgres CDC Source Connector (Debezium)
- Bedrock connection + LLM model (`llm_textgen_model` — Claude 3.7 Sonnet)
- MCP connection for external tool access
- `alter_credit_score_table` statement — sets changelog mode to 'append' on CDC topic
- Data generator and webapp Docker containers

### Webapp (`webapp/`)
- Flask app on port 5000 (mapped to 5001)
- Submits mortgage applications to Kafka via Avro serializer
- Special applicants: "John Doe" → `C-100000` (high credit), "Omar Soli" → `C-200000` (low credit)

## Variable Naming Conventions

Workshop and demo_mode use the same variable names:
- `mcp_url` (not `mcp_endpoint`)
- `bedrock_access_key_id` / `bedrock_secret_access_key` (not `bedrock_access_key` / `bedrock_secret_key`)
- `db_name` has validation: must match `^app[0-9]{1,3}$`
- `mcp_transport_type` hardcoded to `""` in workshop/demo_mode entry points

Self-serve uses different names (maps internally to base module vars).

## Common Commands

```bash
# Deploy workshop mode
cd terraform/workshop && terraform init && terraform apply --auto-approve

# Deploy self-serve mode
cd terraform/self-serve && terraform init && terraform apply --auto-approve

# Deploy demo mode
cd terraform/demo_mode && terraform init && terraform apply --auto-approve

# Destroy (from the same directory you deployed from)
terraform destroy --auto-approve

# Rebuild and push data generator image
cd terraform/data-gen/datagen-app
docker build -t ghcr.io/ahmedszamzam/datagen:latest .
docker push ghcr.io/ahmedszamzam/datagen:latest

# Check datagen container logs
docker logs mortgage-datagen
```

## Rules

### Do not modify `modules/base/` unless specifically asked
Changes to `terraform/modules/base/` affect **all three deployment modes** (workshop, self-serve, demo). Only modify base when the change is intentionally shared across all modes. Mode-specific logic belongs in the entry point (`terraform/workshop/`, `terraform/self-serve/`, `terraform/demo_mode/`) or in a dedicated module like `modules/flink-statements/`.

### Always rebuild and push the Docker image after data generator changes
If any file under `terraform/data-gen/` changes (Java code, Dockerfile, pom.xml), you **must** rebuild and push the Docker image before testing:
```bash
cd terraform/data-gen/datagen-app
docker build -t ghcr.io/ahmedszamzam/datagen:latest .
docker push ghcr.io/ahmedszamzam/datagen:latest
```
All three modes pull the same `ghcr.io/ahmedszamzam/datagen:latest` image. If you skip this step, deployed containers will use stale code.

## Important: Terraform Dependency Ordering

The `flink_statements` module **must** use `depends_on = [module.base]` in the entry point (e.g., `demo_mode/main.tf`). Without this, Flink statements fail because the Kafka topics and schemas haven't been registered in the Flink catalog yet. The base module creates topics, schemas, the CDC connector, and the `alter_credit_score_table` statement — all of which must complete before any Flink DDL statement can reference these tables.

## Git Conventions

- Use `git push-external origin <branch>` instead of `git push`
- Commit messages follow conventional commits: `feat:`, `fix:`, `docs:`
