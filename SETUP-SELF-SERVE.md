# Mortgage underwriting multi-agent system with Confluent Cloud

This repository showcases a demo for a mortgage provider that leverages **Confluent Cloud**, **AWS**, and **AI** to fully automate mortgage applications—from initial submission to final decision and offer.


![Architecture](./assets/HLD.png)

## Prerequisites

Before starting, make sure you have:

| Requirement | Check |
|-------------|-------|
| **Confluent Cloud account** with [API Keys](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/overview.html#resource-scopes) (`Cloud resource management` permissions) | [Sign up here](https://www.confluent.io/get-started/) |
| **Terraform** v1.5.7+ | `brew install terraform` or [download](https://www.terraform.io/downloads.html) |
| **Git CLI** | `brew install git` |
| **AWS account** with credentials set | Set AWS env variables or run `aws configure` |
| **Container runtime** (Docker Desktop, Colima, or Podman) | Install one runtime; Terraform auto-detects |
| **Zapier MCP token** | [Setup guide](./assets/Zapier-Setup.md) |



<details>
<summary>Installing prerequisites on MAC</summary>

1. Install dependencies:
   ```bash
   brew install git terraform awscli
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
   winget install --id Amazon.AWSCLI -e
   ```

2. Install a container runtime:
   ```powershell
   winget install --id Docker.DockerDesktop -e
   # Alternatively, install Podman: winget install --id RedHat.Podman -e
   ```

</details>

## Bedrock model access

> [!IMPORTANT]
> **Enable Bedrock model access first**
>
> Request model access before you begin the Terraform steps below. Approval can take a few minutes, and starting early avoids delays later.

<details>
<summary>Enable Claude 3.7 Sonnet in Amazon Bedrock</summary>

To enable Claude 3.7 Sonnet in your AWS account via Amazon Bedrock:

1. Open the Amazon Bedrock Console (`https://console.aws.amazon.com/bedrock/home?/overview`) and ensure you are in the same region you will deploy.
2. In the left sidebar, under Bedrock configuration, click Model access.
3. Locate Claude 3.7 Sonnet in the list of available models.
4. Click Available to request, then select Request model access.
5. In the request wizard, click Next and follow the prompts to complete the request.

![Model Access in Bedrock Console](./assets/bedrock1.png)

Provisioning may take 2-5 minutes.

</details>

## Setup

1.  Clone the repo and change directory to the terraform self-serve directory:
      ```
      git clone https://github.com/confluentinc/workshop-mortgage-underwriting-agentic-system.git
      cd workshop-mortgage-underwriting-agentic-system/terraform/self-serve
      ```
2. Configure AWS CLI

   If you already have the AWS CLI configured on your machine and pointing to the correct AWS account, you can skip this step.

   Otherwise, set your AWS environment variables (or run `aws configure`) before continuing:
   <details>
   <summary>Click to expand for MAC</summary>

   ```
   export AWS_DEFAULT_REGION="<cloud_region>"
   export AWS_ACCESS_KEY_ID="<AWS_API_KEY>"
   export AWS_SECRET_ACCESS_KEY="<AWS_SECRET>"
   export AWS_SESSION_TOKEN="<AWS_SESSION_TOKEN>"
   ```

   </details>

   <details>
   <summary>Click to expand for Windows CMD</summary>

   ```
   set AWS_DEFAULT_REGION="<cloud_region>"
   set AWS_ACCESS_KEY_ID="<AWS_API_KEY>"
   set AWS_SECRET_ACCESS_KEY="<AWS_SECRET>"
   set AWS_SESSION_TOKEN="<AWS_SESSION_TOKEN>"
   ```


   </details>

3. Rename the template file and update it with your values:
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
   | `email` | Your email address |
   | `zapier_token` | From [Zapier MCP setup](./assets/Zapier-Setup.md) |

> [!CAUTION]
> **Your container runtime must be running before deploying Terraform.**
> Terraform needs a running container runtime (Docker, Colima, or Podman) to build and start the webapp container. If it is not running, `terraform apply` will fail.

4. Verify your container runtime is running

   | Runtime | Check status | Start |
   |---------|-------------|-------|
   | Docker Desktop | `docker info` | Open Docker Desktop |
   | Colima | `colima status` | `colima start` |
   | Podman | `podman machine info` | `podman machine start` |

5. Initialize and deploy Terraform

   ```bash
   terraform init
   terraform apply --auto-approve
   ```

> [!IMPORTANT]
> Terraform will take around 10 minutes to deploy.

## Post-Deployment Steps

> [!IMPORTANT]
> Run this step in a different tab. Data gen needs to continously run.

Once the infrastructure is deployed, we can generate mortgage data. The data generator sends `mortgage_applications` and `historical_payments` to **Kafka**, and `credit_score` data to **Postgres**.

1. Open a new terminal window and navigate to the data-gen directory from the repo root:
   ```
   cd workshop-mortgage-underwriting-agentic-system/terraform/data-gen
   ```
3. Run the data generator

   <details>
   <summary>Click to expand for MAC</summary>

   ```
   ./run.sh
   ```

   </details>

   <details>
   <summary>Click to expand for Windows</summary>

   ```
   .\run.bat
   ```

   </details>

> [!CAUTION]
> **Do not stop the data generator.** It must run continuously to advance Flink watermarks. Stopping it will break the labs.

> **Note:** The data generator produces a new mortgage application every 10 minutes.

5. To verify that the data has been successfully generated, go to the [Confluent Cloud Topic UI](https://confluent.cloud/go/topics). Select your environment and cluster, then click on the `payment_history` topic to confirm that data is being produced.

   ![Architecture](./assets/verify.png)


### Submit a Mortgage Application from the Website

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

   ![Architecture](./assets/demo1.png)

3. To verify that the data has been successfully generated, go to the [Confluent Cloud Topic UI](https://confluent.cloud/go/topics). Select your environment and cluster, then click on the `mortgage_applications`, you should see the new application there.


## Demo

> **Estimated time:** 90 minutes

This workshop includes two labs:

1. [**Lab 1 – Connecting and Pre-processing Mortgage Applications**](./lab1/lab1-README.md):
   Use the fully managed **Postgres CDC Source Connector** to stream credit score data from Postgres DB to **Confluent Cloud**. Then, leverage **Confluent Cloud for Apache Flink** to transform the live stream of mortgage applications into a real-time, contextualized data product—ready to power AI agents.

2. [**Lab 2 – Building AI Agents to process Mortgage Applications**](./lab2/lab2-README.md):
   Use **Confluent Cloud for Apache Flink** and **Amazon Bedrock** to build two AI agents that run sequentially to fully automate the mortgage application process.


After completing Labs 1 and 2, you can run an end-to-end [demo](./Demo/demo-README.md) by submitting an application for a high-credit customer.


## Topics

**Next topic:** [Lab 1 - Connecting and pre-processing mortgage applications](./lab1/lab1-README.md)

## Clean-up
Once you are finished with this demo, remember to destroy the resources you created, to avoid incurring charges. You can always spin it up again anytime you want.

Before tearing down the infrastructure, delete the Postgres CDC connector, as it was created outside of Terraform and won't be automatically removed:

```
confluent connect cluster delete <CONNECTOR_ID> --cluster <CLUSTER_ID> --environment <ENVIRONMENT_ID> --force
```

To destroy all the resources created run the command below from the ```terraform/self-serve``` directory:

```
terraform destroy --auto-approve
```
