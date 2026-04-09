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

**Data flow**: Mortgage applications and payment history are produced to Kafka by the data generator. Credit scores are sourced from Postgres via CDC connector. Flink SQL enriches mortgage apps with credit scores and payment history using joins. Two AI agents then process the enriched data — one for fraud/risk assessment, one for approval/rejection decisions and email notifications.

## Deployment Modes

| Mode | Directory | Description |
|------|-----------|-------------|
| **Workshop** | `terraform/workshop/` | Instructor provides Postgres DB and Bedrock credentials. Participants manually create Flink SQL statements in Labs 1 & 2. |
| **Self-serve** | `terraform/self-serve/` | Terraform provisions AWS infrastructure (EC2 Postgres, IAM for Bedrock) in addition to base. Participants still do labs manually. |
| **Demo** | `terraform/demo_mode/` | Fully automated — provisions AWS infra, all Flink DDL statements deployed via Terraform. Data gen runs continuously. |

All three modes use `module.base` (`terraform/modules/base/`). Demo mode additionally uses `module.flink_statements` (`terraform/modules/flink-statements/`) and `module.aws` (`terraform/modules/aws/`). Self-serve additionally uses `module.aws`.

## Directory Structure

```
terraform/
├── modules/
│   ├── base/              # Core: env, cluster, topics, schemas, connectors, LLM model, MCP, datagen, webapp
│   ├── flink-statements/  # 8 Flink DDL statements (CTAS, CREATE AGENT, CREATE TOOL) — used by demo_mode only
│   └── aws/               # AWS infra (EC2 Postgres, IAM for Bedrock) — used by self-serve and demo_mode
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
- **Java 17**, Maven, uses Kafka Avro serializer + JavaFaker + PostgreSQL JDBC

#### Stage 1: Seed Postgres (immediate, no throttle)
- Creates `applicant_credit_score` table and inserts 702 rows:
  - 100 high credit (750-850 score, 0 public records)
  - 500 medium credit (501-750 score)
  - 100 low credit (300-500 score)
  - John Doe (`C-100000`) — score 800-850, 0 defaults, guaranteed high credit
  - Omar Soli (`C-200000`) — score 300-350, 5 defaults, guaranteed low credit

#### Stage 2: Historical Payments (immediate, no throttle)
- Preloads all applicants from Postgres into in-memory cache (thread-safe `CopyOnWriteArrayList`)
- Sends 701 payment events to Kafka `payment_history` topic with random dates up to 365 days in past
- 1 guaranteed successful payment for John Doe

#### Stage 3: Continuous Stream (3 parallel threads)

**Thread 1 — Mortgage Applications**
- Waits `MORTGAGE_APP_STARTUP_DELAY_SECONDS` (default 0) before starting
- Produces `MORTGAGE_APP_COUNT` apps (default 20, -1 = continuous)
- Interval: `MORTGAGE_APP_INTERVAL_SECONDS` (default 600)
- Picks applicants randomly from in-memory cache (999/1000 valid, 1/1000 = "-1" unmatched)
- Property values: 13/14 standard (100K-500K), 1/14 high (1M-1.5M)
- First 3 apps have payslips = "N/A", then 5/6 valid S3 URIs, 1/6 "N/A" (triggers DLQ)

**Thread 2 — Payments**
- Starts immediately, runs forever, no cap
- 1 payment every 5-10 seconds (random throttle)
- Weighted tiers: high credit (200) → 100% success, John Doe (1) → 100% success, medium (200) → 90% success, low (200) → 20% success, Omar Soli (1) → 20% success

**Thread 3 — CDC Heartbeat** (enabled by default, interval 10s)
- Controlled by `CDC_HEARTBEAT_INTERVAL_SECONDS` (default 10, 0 = disabled)
- Updates `last_heartbeat = NOW()` on applicant C-100000 (John Doe) every 5-10 seconds (random)
- Advances the CDC topic watermark without inserting new rows into Postgres
- Required for the temporal join in Statement 1 to make progress

#### Data Generator Parameters by Mode

| Parameter | Env Var | Default | Workshop/Self-serve | Demo |
|-----------|---------|---------|---------------------|------|
| Mortgage interval | `MORTGAGE_APP_INTERVAL_SECONDS` | 600 | 600 (default) | 60 |
| Mortgage count | `MORTGAGE_APP_COUNT` | 20 | 20 (default) | -1 (continuous) |
| Startup delay | `MORTGAGE_APP_STARTUP_DELAY_SECONDS` | 0 | 0 (default) | 300 |
| CDC heartbeat interval | `CDC_HEARTBEAT_INTERVAL_SECONDS` | 10 | 10 (default) | 10 (default) |

Workshop/self-serve don't pass these values — they use defaults. Demo mode sets them in `demo_mode/main.tf`. The values are passed to the container via the `.datagen.env` file generated by `modules/base/outputs.tf`.

### Flink Statements Module (`terraform/modules/flink-statements/`)
8 statements deployed sequentially via `depends_on`:
1. CTAS `enriched_mortgage_applications` — temporal join of mortgage apps with CDC credit score versioned table
2. CTAS `applicant_payment_summary` — aggregates payment history per applicant using ARRAY_AGG
3. CTAS `enriched_mortgage_with_payments` — temporal join (LEFT JOIN FOR SYSTEM_TIME AS OF), no property_value filter
4. CREATE AGENT `mortgage_risk_agent` — Flink Streaming Agent for fraud/credit risk assessment, outputs JSON with fraud_risk_score, loan_stack_risk, risk_category, agent_reasoning
5. CTAS `mortgage_validated_apps` — applies risk agent via LATERAL TABLE + AI_RUN_AGENT
6. CREATE TOOL `send_email` — MCP tool using `mcp_connection` for gmail_send_email
7. CREATE AGENT `mortgage_decisions_agent` — Flink SQL Agent for approval/rejection, uses send_email tool
8. CTAS `mortgage_decisions` — applies decision agent, extracts decision/interest_rate/explanation/letter_body, sends email to `var.email_address`

### Base Module (`terraform/modules/base/`)
- Confluent Cloud: environment, Kafka cluster (Standard, single-zone, AWS), Schema Registry (Advanced governance)
- Flink compute pool (20 max CFU)
- Service account with EnvironmentAdmin role binding
- API keys: Kafka, Schema Registry, Flink management
- Topics: `mortgage_applications`, `payment_history`, `incomplete_mortgage_applications` (DLQ)
- AVRO schemas with data quality rules (CEL validation: payslip URI must match `^s3://riverbank-payslip-bucket/[a-zA-Z0-9._/-]+$` → DLQ routing on failure)
- Postgres CDC Source Connector (Debezium v2, table `public.applicant_credit_score`, topic prefix `PROD`)
- `alter_mortgage_applications` Flink statement — adds WATERMARK on `application_ts` for temporal join support
- Bedrock connection + LLM model (`llm_textgen_model` — Claude 3.7 Sonnet, 50K max tokens)
- MCP connection (configurable endpoint + transport type) for external tool access
- Data generator Docker container (`mortgage-datagen`) — pulls from GHCR, passes env vars via `.datagen.env`
- Webapp Docker container (`mortgage-webapp`) — built locally from `webapp/Dockerfile`, port 5001→5000
- Outputs 9 values for flink-statements module: org_id, env_id, display names, flink pool, API keys, service account

### Webapp (`webapp/`)
- Flask app on port 5000 (mapped to 5001 via Docker)
- Submits mortgage applications to Kafka `mortgage_applications` topic via Avro serializer
- Uses Schema Registry for serialization (auto-register disabled, uses latest version)
- Special applicants hardcoded by name:
  - "John Doe" → `C-100000` (high credit), always `Full-employed`
  - "Omar Soli" → `C-200000` (low credit), always `self-employed`
  - Any other name → random `C-3XXXXX` ID, random employment status
- Webapp submits: application_id (UUID), customer_email (random), property_value, loan_amount, income (from form), property_address/state (random), payslips (S3 URI using applicant_id), application_ts (current millis)

## Variable Naming Conventions

Workshop uses instructor-provided variables:
- `mcp_url`, `mcp_token`, `bedrock_access_key_id` / `bedrock_secret_access_key`, `db_host` / `db_name` / `db_password`
- `db_name` has validation: must match `^app[0-9]{1,3}$`
- `mcp_transport_type` hardcoded to `""` in workshop entry point

Self-serve and demo_mode use the same variables (`zapier_token`, `email`) and provision their own AWS infra via `module.aws` (EC2 Postgres + Bedrock IAM). MCP endpoint is hardcoded to `https://mcp.zapier.com/api/v1/connect`.

The base module uses internal names: `mcp_endpoint`, `bedrock_access_key`, `bedrock_secret_key`. Each entry point maps its variable names to these.

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

### Data generator defaults must match original behavior
When adding new configurable parameters to the data generator, always set defaults to match the original (pre-change) behavior. Workshop and self-serve don't pass these values — they rely on defaults. Only demo_mode explicitly overrides them in `demo_mode/main.tf`.

### Flink SQL CONCAT returns NULL if any argument is NULL
In Flink SQL, `CONCAT(a, b, c)` returns NULL if any argument is NULL — unlike some SQL dialects that skip NULLs. Always wrap nullable fields with `COALESCE` when building prompts for AI agents via `AI_RUN_AGENT`. Fields extracted from agent JSON responses (`JSON_VALUE`) are especially prone to being NULL when the upstream agent fails.

### Keep lab instructions in sync with flink-statements module
`lab1/lab1-README.md`, `lab2/lab2-README.md`, and `terraform/modules/flink-statements/main.tf` contain the same Flink SQL statements. When modifying one, always update the others to keep them consistent.

## Important: Terraform Dependency Ordering

The `flink_statements` module **must** use `depends_on = [module.base]` in the entry point (e.g., `demo_mode/main.tf`). Without this, Flink statements fail because the Kafka topics and schemas haven't been registered in the Flink catalog yet. The base module creates topics, schemas, the CDC connector, and the `alter_mortgage_applications` statement — all of which must complete before any Flink DDL statement can reference these tables.

Within the flink-statements module, all 8 statements are chained via `depends_on` to enforce sequential execution and preserve dependencies (e.g., `enriched_mortgage_with_payments` depends on both `enriched_mortgage_applications` and `applicant_payment_summary`).

## Git Conventions

- Use `git push-external origin <branch>` instead of `git push`
- Commit messages follow conventional commits: `feat:`, `fix:`, `docs:`
