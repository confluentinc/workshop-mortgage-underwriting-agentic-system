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

**Data flow**: Mortgage applications and payment history are produced to Kafka by the data generator. Credit scores are sourced from Postgres via CDC connector. The CDC table is interpreted by Flink as a versioned table (Debezium upsert mode with flattened columns). Flink SQL enriches mortgage apps with credit scores via a **temporal join** and payment history via a second temporal join. Two AI agents then process the enriched data — one for fraud/risk assessment, one for approval/rejection decisions and email notifications.

## Deployment Modes

| Mode | Directory | Datagen | Description |
|------|-----------|---------|-------------|
| **Workshop** | `terraform/workshop/` | Local Docker (`local-datagen`) | Instructor provides Postgres DB and Bedrock credentials. Participants manually create Flink SQL statements in Labs 1 & 2. |
| **Self-serve** | `terraform/self-serve/` | ECS Fargate (`ecs-datagen`) | Terraform provisions AWS infrastructure (EC2 Postgres, IAM for Bedrock) in addition to base. Participants still do labs manually. |
| **Demo** | `terraform/demo_mode/` | ECS Fargate (`ecs-datagen`) | Fully automated — provisions AWS infra, all Flink DDL statements deployed via Terraform. Data gen runs continuously. Designed for always-on operation. |

All three modes use `module.base` (`terraform/modules/base/`). Self-serve and demo additionally use `module.aws`, `module.ecs_datagen`, and `module.cdc_connector`. Workshop uses `module.local_datagen` and `module.cdc_connector`. Demo additionally uses `module.flink_statements`.

## Directory Structure

```
terraform/
├── modules/
│   ├── base/              # Core: env, cluster, topics, schemas, LLM model, MCP, webapp
│   ├── local-datagen/     # Local Docker datagen container — used by workshop only
│   ├── ecs-datagen/       # ECS Fargate datagen container — used by self-serve and demo_mode
│   ├── cdc-connector/     # Postgres CDC connector + ALTER statements — used by all modes
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
- **Image**: `ghcr.io/ahmedszamzam/datagen:latest` — single multi-arch image (amd64 + arm64) for all modes
- **Java 17**, Maven, uses Kafka Avro serializer + JavaFaker + PostgreSQL JDBC
- **Deployment**: Local Docker (workshop) or ECS Fargate (self-serve/demo). ECS auto-restarts on failure. Local Docker uses `--restart on-failure`.

#### Stage 1: Seed Postgres (immediate, no throttle)
- Creates `applicant_credit_score` table with columns: `applicant_id` (PK), `applicant_name`, `credit_score`, `credit_utilization`, `open_credit_accounts`, `total_credit_limit`, `public_records`, `updated_at` (TIMESTAMP, DEFAULT NOW())
- Inserts 702 rows with `updated_at` populated (critical for CDC watermark — NULL timestamps prevent watermark advancement):
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
- Application IDs use UUIDs (`APP-<uuid>`) to avoid collisions on container restart
- Picks applicants randomly from in-memory cache (999/1000 valid, 1/1000 = "-1" unmatched)
- Property values: 13/14 standard (100K-500K), 1/14 high (1M-1.5M)
- First 3 apps have payslips = "N/A", then 9/10 valid S3 URIs, 1/10 "N/A" (triggers DLQ)

**Thread 2 — Payments**
- Starts immediately, runs forever, no cap
- 1 payment every 5-10 seconds (random throttle)
- Weighted tiers: high credit (200) → 100% success, John Doe (1) → 100% success, medium (200) → 90% success, low (200) → 20% success, Omar Soli (1) → 20% success

**Thread 3 — CDC Heartbeat** (enabled by default)
- Controlled by `CDC_HEARTBEAT_INTERVAL_SECONDS` (default 10, 0 = disabled)
- Updates `updated_at = NOW()` on a random applicant every 5-10 seconds (random sleep)
- Advances the CDC topic watermark without inserting new rows into Postgres
- Required for the temporal join in Statement 1 to make progress — without heartbeat, the CDC watermark stalls and the temporal join buffers indefinitely

#### Data Generator Parameters by Mode

| Parameter | Env Var | Default | Workshop/Self-serve | Demo |
|-----------|---------|---------|---------------------|------|
| Mortgage interval | `MORTGAGE_APP_INTERVAL_SECONDS` | 600 | 600 (default) | 60 |
| Mortgage count | `MORTGAGE_APP_COUNT` | 20 | 20 (default) | -1 (continuous) |
| Startup delay | `MORTGAGE_APP_STARTUP_DELAY_SECONDS` | 0 | 0 (default) | 0 |
| CDC heartbeat interval | `CDC_HEARTBEAT_INTERVAL_SECONDS` | 10 | 10 (default) | 10 (default) |

Workshop uses defaults via `local-datagen` module. Self-serve uses defaults via `ecs-datagen` module. Demo mode overrides values in `ecs-datagen` module call in `demo_mode/main.tf`.

### Flink Statements Module (`terraform/modules/flink-statements/`)
8 statements deployed sequentially via `depends_on`. All CTAS use `DISTRIBUTED INTO 1 BUCKETS` for single-partition output topics:
1. CTAS `enriched_mortgage_applications` — **temporal join** (`FOR SYSTEM_TIME AS OF m.application_ts`) of mortgage apps with CDC credit score versioned table. Uses flattened Debezium columns (`c.credit_score`, not `c.after.credit_score`)
2. CTAS `applicant_payment_summary` — aggregates payment history per applicant using ARRAY_AGG
3. CTAS `enriched_mortgage_with_payments` — temporal join (LEFT JOIN FOR SYSTEM_TIME AS OF), no property_value filter
4. CREATE AGENT `mortgage_risk_agent` — Flink Streaming Agent for fraud/credit risk assessment, outputs JSON with fraud_risk_score, loan_stack_risk, risk_category, agent_reasoning
5. CTAS `mortgage_validated_apps` — applies risk agent via LATERAL TABLE + AI_RUN_AGENT
6. CREATE TOOL `send_email` — MCP tool using `mcp_connection` for gmail_send_email
7. CREATE AGENT `mortgage_decisions_agent` — Flink SQL Agent for approval/rejection, uses send_email tool
8. CTAS `mortgage_decisions` — applies decision agent, extracts decision/interest_rate/explanation/letter_body, sends email to `var.email_address`

### CDC Connector Module (`terraform/modules/cdc-connector/`)
Extracted from the base module to control dependency ordering — the datagen must seed Postgres before the CDC connector starts. Contains:
- Postgres CDC Source Connector (Debezium v2, `time.precision.mode=connect`)
- `alter_credit_score_upsert` — sets `changelog.mode = 'upsert'` on CDC table
- `alter_credit_score_watermark` — adds WATERMARK on `updated_at` for temporal join

### Base Module (`terraform/modules/base/`)
Pure Confluent Cloud infrastructure — no datagen, no CDC connector:
- Confluent Cloud: environment, Kafka cluster (Standard, single-zone, AWS), Schema Registry (Advanced governance)
- Flink compute pool (20 max CFU)
- Service account with EnvironmentAdmin role binding
- API keys: Kafka, Schema Registry, Flink management
- Topics (all 1 partition): `mortgage_applications`, `payment_history`, `incomplete_mortgage_applications` (DLQ), `PROD.public.applicant_credit_score` (pre-created with `cleanup.policy=compact`)
- AVRO schemas with data quality rules (CEL validation: payslip URI must match `^s3://riverbank-payslip-bucket/[a-zA-Z0-9._/-]+$` → DLQ routing on failure)
- `alter_mortgage_applications` Flink statement — adds WATERMARK on `application_ts` for temporal join support
- Bedrock connection + LLM model (`llm_textgen_model` — Claude 3.7 Sonnet, 50K max tokens)
- MCP connection (configurable endpoint + transport type) for external tool access
- Webapp Docker container (`mortgage-webapp`) — built locally from `webapp/Dockerfile`, port 5001→5000
- Outputs credentials for datagen and CDC connector modules

### Local Datagen Module (`terraform/modules/local-datagen/`)
Runs the datagen container locally via Docker/Podman. Used by workshop mode only. Generates `.datagen.env` file and runs via `null_resource` with `--restart on-failure`.

### ECS Datagen Module (`terraform/modules/ecs-datagen/`)
Runs the datagen container on AWS ECS Fargate. Used by self-serve and demo modes. Resources: ECS cluster, task definition (512 CPU, 1024 MB), service, IAM execution role, CloudWatch log group. Env vars passed directly in task definition (no `.datagen.env` file). Uses `assign_public_ip = true` (public subnets, no NAT).

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

# Rebuild and push data generator image (always multi-arch)
cd terraform/data-gen/datagen-app
docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/ahmedszamzam/datagen:latest --push .

# Check datagen container logs (local Docker — workshop only)
docker logs mortgage-datagen

# Check datagen logs (ECS — self-serve/demo)
aws logs tail /ecs/<prefix>-datagen-<env_id> --follow
```

## Rules

### Cross-platform compatibility is required
All Terraform code must work on both **Windows** and **macOS**. Any `null_resource` with `local-exec` provisioners must include platform-specific variants (PowerShell for Windows, bash for Unix) with a `count` guard based on OS detection. Never use Unix-only shell syntax (e.g. `set -e`, `command -v`, `#!/bin/bash`) without a Windows equivalent. Test or verify that any new local-exec logic works on both platforms.

### Do not modify `modules/base/` unless specifically asked
Changes to `terraform/modules/base/` affect **all three deployment modes** (workshop, self-serve, demo). Only modify base when the change is intentionally shared across all modes. Mode-specific logic belongs in the entry point or in a dedicated module.

### Always rebuild and push a multi-arch Docker image after data generator changes
If any file under `terraform/data-gen/` changes (Java code, Dockerfile, pom.xml), you **must** rebuild and push a **multi-architecture** Docker image before testing. Always use `buildx` with both `linux/amd64` and `linux/arm64` platforms — a single-arch image built on Mac (ARM64) will fail on ECS Fargate (x86_64) and vice versa.
```bash
cd terraform/data-gen/datagen-app
docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/ahmedszamzam/datagen:latest --push .
```
All three modes pull the same `ghcr.io/ahmedszamzam/datagen:latest` image. If you skip this step, deployed containers will use stale code.

### Data generator defaults must match original behavior
When adding new configurable parameters to the data generator, always set defaults to match the original (pre-change) behavior. Workshop and self-serve don't pass these values — they rely on defaults. Only demo_mode explicitly overrides them.

### Flink SQL CONCAT returns NULL if any argument is NULL
In Flink SQL, `CONCAT(a, b, c)` returns NULL if any argument is NULL — unlike some SQL dialects that skip NULLs. Always wrap nullable fields with `COALESCE` when building prompts for AI agents via `AI_RUN_AGENT`. Fields extracted from agent JSON responses (`JSON_VALUE`) are especially prone to being NULL when the upstream agent fails.

### Keep lab instructions in sync with flink-statements module
`lab1/lab1-README.md`, `lab2/lab2-README.md`, and `terraform/modules/flink-statements/main.tf` contain the same Flink SQL statements. When modifying one, always update the others to keep them consistent. The only intentional difference is `WHERE m.property_value < 500000` in lab1's `enriched_mortgage_with_payments` (the flink-statements module omits this filter).

### All topics use 1 partition
All Kafka topics (both Terraform-managed and CTAS-created) use 1 partition. Terraform topics set `partitions_count = 1`. CTAS tables use `DISTRIBUTED INTO 1 BUCKETS`. This eliminates idle partition watermark issues that cause temporal joins to stall. Do NOT use the deprecated `kafka.partitions` table option — use `DISTRIBUTED INTO n BUCKETS` instead.

## Important: CDC Table Configuration for Temporal Joins

The CDC table `PROD.public.applicant_credit_score` requires configuration in the `cdc-connector` module for the temporal join to work:

1. **`changelog.mode = 'upsert'`** — Without this, the default Debezium retract mode requires `REPLICA IDENTITY FULL` on the Postgres table (full `before` images for UPDATE events). Upsert mode avoids this requirement and infers PRIMARY KEY from the Kafka message key.

2. **WATERMARK on `updated_at`** — The temporal join needs the right-side (CDC) watermark to advance. The `updated_at` column is populated via `DEFAULT NOW()` during seed and updated by the heartbeat thread. Without non-NULL timestamps in `updated_at`, the watermark stays at -infinity and the temporal join never emits. The watermark delay is set to 5 seconds (`updated_at - INTERVAL '5' SECOND`). Total latency ≈ watermark delay (5s) + heartbeat interval (5-10s) ≈ 10-15 seconds.

3. **`time.precision.mode = 'connect'`** on the CDC connector — Debezium's default `adaptive` mode maps Postgres TIMESTAMP to BIGINT (microseconds since epoch). Flink cannot use BIGINT as a watermark field. The `connect` mode uses Kafka Connect's Timestamp logical type, which Flink interprets as `TIMESTAMP_LTZ(3)`.

**Critical**: Do NOT set `changelog.mode = 'append'` on the CDC table. This exposes the raw Debezium envelope (`before`/`after` structs) instead of flattened columns, and treats every CDC record as a new INSERT — which causes duplicate join matches when the heartbeat produces update events.

**Critical**: Do NOT set `value.format = 'avro-registry'` on the CDC table. This tells Flink to treat the data as generic Avro (not Debezium), preventing changelog interpretation and PRIMARY KEY inference.

## Important: Temporal Join Latency

In a temporal join (`FOR SYSTEM_TIME AS OF`), the join emits a result only when the **right-side** (versioned table) watermark advances past the left-side record's event time. The left-side watermark is NOT the bottleneck — even though the mortgage app has arrived, the join waits for the CDC watermark to confirm it has all updates up to that time.

Total latency = CDC watermark delay + heartbeat interval. With 5s watermark delay and 5-10s heartbeat, expect ~10-15 seconds from mortgage app production to enriched output. To reduce latency: decrease the watermark delay or increase heartbeat frequency. Do NOT set watermark delay to 0 — some tolerance is needed for processing jitter.

## Important: CDC Topic Compaction

The `PROD.public.applicant_credit_score` topic is pre-created with `cleanup.policy=compact` in the base module. This ensures the latest credit score per applicant is retained forever (not deleted after 7-day default retention). Without compaction, a Flink job restart after retention expiry would lose credit scores and the temporal join would produce no matches.

The topic is created before the CDC connector starts. The connector detects the existing topic and uses it as-is, preserving the compaction config.

## Important: Terraform Dependency Ordering

The modules are chained via `depends_on` in each entry point to enforce correct ordering:

```
Workshop:
  module.base → module.local_datagen → module.cdc_connector

Self-serve:
  module.aws + module.base → module.ecs_datagen → module.cdc_connector

Demo:
  module.aws + module.base → module.ecs_datagen → module.cdc_connector → module.flink_statements
```

**Why datagen before CDC connector**: The datagen seeds the `applicant_credit_score` table in Postgres. The CDC connector with `publication.autocreate.mode = "filtered"` fails if the table doesn't exist when the connector starts (empty publication capture list). The datagen must run first.

**Why CDC connector before flink_statements**: The flink_statements module's temporal join reads from the CDC table, which must have upsert mode and watermark configured via the ALTER statements in the cdc-connector module.

Within the flink-statements module, all 8 statements are chained via `depends_on` to enforce sequential execution.

## Important: Debugging ECS + CDC Connector Failures

If the CDC connector fails with "capture list is empty", **always check the ECS task status and logs first** before adding sleep/retry workarounds. The datagen container may be crashing (wrong architecture, missing env vars, Postgres unreachable) rather than simply being slow to seed.

```bash
# Check ECS task status
aws ecs list-tasks --cluster <cluster-name> --region us-east-1
aws ecs describe-tasks --cluster <cluster-name> --tasks <task-id> --region us-east-1

# Check container logs
aws logs tail /ecs/<log-group> --follow
```

Common failures:
- `exec format error` — wrong architecture (ARM64 image on x86_64 or vice versa). Fix: rebuild multi-arch image.
- `Connection refused` — Postgres EC2 not ready yet. ECS service auto-restarts, so this self-heals.
- Exit code 255 — check logs for the actual error before assuming it's a timing issue.

## Important: Confluent Cloud Flink Property Names

Confluent Cloud Flink uses **hyphenated** property names, not dot-separated. For example:
- `sql.state-ttl` (correct) — NOT `sql.state.ttl`
- `sql.tables.scan.idle-timeout` (correct)

Using dot-separated names causes "Unsupported configuration options" errors.

## Important: Flink Table API and Temporal Joins

The Flink Table API (`terraform/code/FlinkTableAPI/`) does not have native temporal join syntax. The `MortgageEnrichment.java` file uses `env.executeSql()` with SQL for the temporal join, while keeping `env.createTable()` with `ConfluentTableDescriptor` for table creation. Mixing Table API and SQL in the same program is officially supported by Confluent.

## Important: Transaction Commit Markers

Confluent Cloud Flink uses transactional writes (exactly-once). Each transaction produces a commit marker record that takes a Kafka offset. With low-throughput topics (1 record per transaction), you'll see alternating offsets (0, 2, 4, 6...) — the odd offsets are commit markers. This is normal Kafka transactional behavior. Consumers with `read_committed` isolation automatically skip markers.

## Git Conventions

- Use `git push-external origin <branch>` instead of `git push`
- Commit messages follow conventional commits: `feat:`, `fix:`, `docs:`
