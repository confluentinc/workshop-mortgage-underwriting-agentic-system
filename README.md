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
- **Self-serve mode** — Terraform provisions everything (RDS Postgres, IAM for Bedrock).
  Start here: [SETUP-SELF-SERVE.md](SETUP-SELF-SERVE.md)

