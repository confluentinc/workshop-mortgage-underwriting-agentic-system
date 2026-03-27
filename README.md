# Mortgage underwriting multi-agent system workshop

This is workshop that demonstrates an end-to-end mortgage underwriting workflow on **Confluent Cloud** with **AI agents**. The solution streams mortgage applications and payment history, enriches them with credit data, and applies automated fraud/risk assessment plus decisioning — all in real time.

![Architecture](./assets/HLD.png)

## What you’ll build

- Real-time ingestion of mortgage applications and historical payments
- Enrichment with credit score data to create a unified, analytics-ready data product
- AI agents running [Confluent Streaming Agents](https://www.confluent.io/product/streaming-agents/) for fraud/risk checks and final decisioning
- A local webapp for submitting applications

## Choose your path

| Mode | Description | Setup Guide |
|------|-------------|-------------|
| **Workshop** | Instructor provides the Postgres database and Bedrock credentials | [Get started](SETUP-WORKSHOP.md) |
| **Self-serve** | Terraform provisions everything (EC2 Postgres, IAM for Bedrock) | [Get started](SETUP-SELF-SERVE.md) |
| **Demo** | Fully automated end-to-end deployment — all Flink statements, agents, and data generation are provisioned by Terraform | [Get started](terraform/demo_mode/README.md) |

## Clean-up

Once you are finished with this demo, remember to destroy the resources you created, to avoid incurring charges.

1. From the same terraform directory you deployed from (`terraform/workshop`, `terraform/self-serve`, or `terraform/demo_mode`), run:

   ```
   terraform destroy --auto-approve
   ```

