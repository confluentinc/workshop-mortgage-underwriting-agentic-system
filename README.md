# Mortgage underwriting multi-agent system workshop

This is workshop that demonstrates an end-to-end mortgage underwriting workflow on **Confluent Cloud** with **AI agents**. The solution streams mortgage applications and payment history, enriches them with credit data, and applies automated fraud/risk assessment plus decisioning — all in real time.

![Architecture](./assets/HLD.png)

## What you’ll build

- Real-time ingestion of mortgage applications and historical payments
- Enrichment with credit score data to create a unified, analytics-ready data product
- AI agents running [Confluent Streaming Agents](https://www.confluent.io/product/streaming-agents/) for fraud/risk checks and final decisioning
- A local webapp for submitting applications

## Choose your path

- **Workshop mode** — Use an instructor-provided Postgres database and Bedrock credentials.
  Start here: [SETUP-WORKSHOP.md](SETUP-WORKSHOP.md)
- **Self-serve mode** — Terraform provisions everything (EC2 Postgres, IAM for Bedrock).
  Start here: [SETUP-SELF-SERVE.md](SETUP-SELF-SERVE.md)

## Clean-up

Once you are finished with this demo, remember to destroy the resources you created, to avoid incurring charges.

1. Delete the Postgres CDC connector, as it was created outside of Terraform and won't be automatically removed:

   ```
   confluent connect cluster delete <CONNECTOR_ID> --cluster <CLUSTER_ID> --environment <ENVIRONMENT_ID> --force
   ```

2. From the same terraform directory you deployed from (`terraform/workshop` or `terraform/self-serve`), run:

   ```
   terraform destroy --auto-approve
   ```

