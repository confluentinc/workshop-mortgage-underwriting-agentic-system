# Demo Mode — Fully Automated Mortgage Underwriting

Demo mode deploys the **entire mortgage underwriting agentic system** end-to-end with a single `terraform apply`. Unlike workshop and self-serve modes — where participants manually create Flink SQL statements — demo mode provisions all Flink DDL statements (CTAS, CREATE AGENT, CREATE TOOL) automatically via Terraform.

![Architecture](../../assets/HLD.png)

## Prerequisites

Before starting, make sure you have:

| Requirement | Check |
|-------------|-------|
| **Confluent Cloud account** with [API Keys](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/overview.html#resource-scopes) (`Cloud resource management` permissions) | [Sign up here](https://cnfl.io/dswt2026) |
| **Terraform** v1.5.7+ | `brew install terraform` or [download](https://www.terraform.io/downloads.html) |
| **Git CLI** | `brew install git` |
| **Container runtime** (Docker Desktop, Colima, or Podman) | Install one runtime |


<details>
<summary>Installing prerequisites on MAC</summary>

1. Install dependencies:
   ```bash
   brew install git terraform
   ```

2. Install a container runtime:
   ```bash
   brew install colima docker
   # brew install --cask docker       # Docker Desktop
   # brew install podman              # Podman
   ```

</details>

<details>
<summary>Installing prerequisites on Windows</summary>

1. Install dependencies:
   ```powershell
   winget install --id Git.Git -e
   winget install --id Hashicorp.Terraform -e
   ```

2. Install a container runtime:
   ```powershell
   winget install --id Docker.DockerDesktop -e
   # Alternatively, install Podman: winget install --id RedHat.Podman -e
   ```

</details>

## Setup

1. Clone the repo and change directory to the terraform demo_mode directory:
   ```
   git clone https://github.com/confluentinc/workshop-mortgage-underwriting-agentic-system.git
   cd workshop-mortgage-underwriting-agentic-system/terraform/demo_mode
   ```

2. Rename the template file and update it with your values:
   **Mac/Linux:**
   ```bash
   mv terraform.tfvars.example terraform.tfvars
   ```
   **Windows:**
   ```cmd
   ren terraform.tfvars.example terraform.tfvars
   ```
   Open `terraform.tfvars` in your editor and replace the following placeholders:

   | Variable | Where to get it |
   |----------|----------------|
   | `confluent_cloud_api_key` | Your Confluent Cloud API key |
   | `confluent_cloud_api_secret` | Your Confluent Cloud API secret |
   | `mcp_url` | Provided by your instructor |
   | `mcp_token` | Provided by your instructor |
   | `bedrock_access_key_id` | Provided by your instructor |
   | `bedrock_secret_access_key` | Provided by your instructor |
   | `db_host` | Provided by your instructor |
   | `db_name` | Provided by your instructor (e.g. `app1`, `app27`) |
   | `db_password` | Provided by your instructor |
   | `email_address` | Your email address (for mortgage decision notifications) |

> [!CAUTION]
> **Your container runtime must be running before deploying Terraform.**
> Terraform needs a running container runtime (Docker, Colima, or Podman) to build and start the webapp container. If it is not running, `terraform apply` will fail.

3. Verify your container runtime is running

   | Runtime | Check status | Start |
   |---------|-------------|-------|
   | Docker Desktop | `docker info` | Open Docker Desktop |
   | Colima | `colima status` | `colima start` |
   | Podman | `podman machine info` | `podman machine start` |

4. Initialize and deploy Terraform

   ```bash
   terraform init
   terraform apply --auto-approve
   ```

> [!IMPORTANT]
> Terraform will take around 10 minutes to deploy.

## What Gets Deployed

Terraform automatically deploys the entire pipeline — from infrastructure to AI agents — with a single `terraform apply`:

1. **Base infrastructure**: Confluent Cloud environment, Kafka cluster, Schema Registry, Flink compute pool, service accounts, API keys, topics, schemas with data quality rules.
2. **Postgres CDC Source Connector**: Streams credit score data from Postgres to Confluent Cloud.
3. **LLM model**: Claude on Amazon Bedrock, registered as a Flink SQL model.
4. **MCP connection**: For external tool access (email sending).
5. **Data generator container** (`mortgage-datagen`): Seeds historical data, then produces **1 mortgage application per minute** continuously (starting after a 10-minute delay).
6. **Webapp container**: Local webapp at http://localhost:5001 for submitting applications.
7. **The entire Flink pipeline** — All Flink DDL statements are deployed sequentially to preserve dependencies:
   - `enriched_mortgage_applications` — Joins mortgage apps with CDC credit score data
   - `applicant_payment_summary` — Aggregates payment history per applicant
   - `enriched_mortgage_with_payments` — Temporal join combining enriched apps with payments
   - `mortgage_risk_agent` — AI agent for fraud detection and credit risk assessment
   - `mortgage_validated_apps` — Applies risk agent to enriched applications
   - `send_email` — MCP tool for sending email notifications
   - `mortgage_decisions_agent` — AI agent for mortgage approval/rejection decisions
   - `mortgage_decisions` — Applies decision agent and sends email notifications

## Submit a Mortgage Application from the Website

Submit a Mortgage application for `John Doe` - an applicant with high-credit-score.

1. Open http://localhost:5001 in your browser.
2. Submit a new application using the following details:


   - **Full Name**: `John Doe`
   - **Property Value:** `200000`
   - **Loan Amount**: `150000`
   - **Annual Income:** `500000`

> [!NOTE]
> The name must be John Doe to match an existing applicant with a known high credit score.
> The loan amount must be less than or equal to the property value.

   ![Submit application](../../assets/demo1.png)

3. To verify that the data has been successfully generated, go to the [Confluent Cloud Topic UI](https://confluent.cloud/go/topics). Select your environment and cluster, then click on the `mortgage_applications`, you should see the new application there.

4. In the [Flink UI](https://confluent.cloud/go/flink), open a SQL workspace and verify John's application flows through the pipeline:

   ```sql
   SELECT * FROM enriched_mortgage_with_payments WHERE borrower_name = 'John Doe';
   ```

   ```sql
   SELECT * FROM mortgage_validated_apps WHERE borrower_name = 'John Doe';
   ```

   ```sql
   SELECT * FROM mortgage_decisions WHERE borrower_name = 'John Doe';
   ```

## Clean-up

Once you are finished with this demo, remember to destroy the resources you created, to avoid incurring charges. You can always spin it up again anytime you want.

To destroy all the resources created (including the Postgres CDC connector, data generator, and webapp containers) run the command below from the `terraform/demo_mode` directory:

```
terraform destroy --auto-approve
```
