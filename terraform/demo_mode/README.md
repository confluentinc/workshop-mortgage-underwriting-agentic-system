# Demo Mode

Demo mode provides a **fully automated, end-to-end** deployment of the mortgage underwriting agentic system. Unlike the workshop and self-serve modes — where participants manually create Flink SQL statements — demo mode provisions everything via Terraform, including all Flink DDL statements (CTAS, CREATE AGENT, CREATE TOOL).

## What gets deployed

1. **Base infrastructure** (shared with workshop/self-serve):
   - Confluent Cloud environment, Kafka cluster, Schema Registry
   - Flink compute pool, service accounts, API keys
   - Kafka topics (`mortgage_applications`, `payment_history`, `incomplete_mortgage_applications`)
   - AVRO schemas with data quality rules
   - Postgres CDC Source connector
   - LLM model (Claude on Amazon Bedrock) and MCP connection
   - Data generator container (1 mortgage app/minute, continuous)
   - Webapp container

2. **Flink statements** (demo mode only):
   - `enriched_mortgage_applications` — Joins mortgage apps with CDC credit score data
   - `applicant_payment_summary` — Aggregates payment history per applicant
   - `enriched_mortgage_with_payments` — Temporal join combining enriched apps with payments
   - `mortgage_risk_agent` — AI agent for fraud detection and credit risk assessment
   - `mortgage_validated_apps` — Applies risk agent to enriched applications
   - `send_email` — MCP tool for sending email notifications
   - `mortgage_decisions_agent` — AI agent for mortgage approval/rejection decisions
   - `mortgage_decisions` — Applies decision agent and sends email notifications

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0)
- [Docker](https://docs.docker.com/get-docker/) or [Podman](https://podman.io/getting-started/installation)
- [Confluent Cloud account](https://confluent.cloud) with an API key
- AWS account with Bedrock access (Claude model enabled)
- PostgreSQL database with CDC enabled
- MCP server endpoint (e.g., Zapier MCP)

## Setup

1. Navigate to the demo mode directory:

   ```bash
   cd terraform/demo_mode
   ```

2. Copy the example variables file and fill in your values:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit `terraform.tfvars` with your credentials:

   | Variable | Description |
   |----------|-------------|
   | `confluent_cloud_api_key` | Confluent Cloud API key |
   | `confluent_cloud_api_secret` | Confluent Cloud API secret |
   | `cloud_region` | AWS region (default: `us-east-1`) |
   | `mcp_endpoint` | MCP server URL |
   | `mcp_token` | MCP authentication token |
   | `db_host` | PostgreSQL hostname |
   | `db_name` | PostgreSQL database name |
   | `db_password` | PostgreSQL password |
   | `bedrock_access_key` | AWS access key for Bedrock |
   | `bedrock_secret_key` | AWS secret key for Bedrock |
   | `email_address` | Email to receive mortgage decision notifications |

4. Initialize and apply:

   ```bash
   terraform init
   terraform apply
   ```

## What to expect

After `terraform apply` completes:

1. **Immediately**: Base infrastructure is provisioned — Kafka cluster, topics, schemas, connectors, and the data generator container start.
2. **Within ~2 minutes**: Historical payment data (701 events) and credit scores (702 rows) are seeded.
3. **After 10 minutes**: The data generator begins producing mortgage applications at a rate of **1 application per minute**, continuously.
4. **Flink statements** deploy sequentially. As mortgage applications flow in, they are enriched, assessed by the risk agent, and processed by the decision agent.
5. **Mortgage decision emails** are sent to the configured `email_address` for each processed application.

## Clean-up

To destroy all resources:

```bash
terraform destroy --auto-approve
```
