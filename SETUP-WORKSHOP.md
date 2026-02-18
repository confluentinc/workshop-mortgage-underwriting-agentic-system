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
| **Container runtime** (Docker Desktop, Colima, or Podman) | Install one runtime |
| **Java 17+** | `brew install openjdk@17` |
| **Maven 3.9.9+** | `brew install maven` |
| **Zapier MCP token** | [Setup guide](./assets/Zapier-Setup.md) |



<details>
<summary>Installing prerequisites on MAC</summary>

Install the prerequisites by running:

```bash
brew install git terraform confluentinc/tap/cli maven openjdk@17 && brew install --cask docker
```

> If you prefer Colima or Podman, install those separately. Terraform will auto-detect the runtime.

</details>

<details>
<summary>Installing prerequisites on Windows</summary>

Install the prerequisites by running:

```powershell
winget install --id Git.Git -e
winget install --id Hashicorp.Terraform -e
winget install --id ConfluentInc.Confluent-CLI -e
winget install --id Docker.DockerDesktop -e
winget install --id Microsoft.OpenJDK.17 -e
winget install --id Apache.Maven -e
```
</details>

## Setup


1.  Clone the repo and change directory to the terraform workshop directory:
      ```
      git clone https://github.com/confluentinc/workshop-mortgage-underwriting-agentic-system.git
      cd workshop-mortgage-underwriting-agentic-system/terraform/workshop
      ```
2. In `terraform` directory, create a `terraform.tfvars` file with Confluent Cloud API keys and instructor-provided Postgres details. Replace the placeholders below with your own keys.

   <details>
   <summary>Click to expand for Mac</summary>

   ```bash
   cat > ./terraform.tfvars <<EOF
   confluent_cloud_api_key = "CONFLUENT_CLOUD_API_KEY"
   confluent_cloud_api_secret = "CONFLUENT_CLOUD_API_SECRET"
   zapier_token = "ZAPIER_TOKEN"
   bedrock_access_key_id = "AWS_ACCESS_KEY_ID"
   bedrock_secret_access_key = "AWS_SECRET_ACCESS_KEY"
   db_host = "POSTGRES_HOST"
   db_port = 5432
   db_name = "POSTGRES_DB"
   db_password = "POSTGRES_PASSWORD"
   EOF
   ```
   </details>

   <details>
   <summary>Click to expand for Windows CMD</summary>

   ```bash
   echo confluent_cloud_api_key = "CONFLUENT_CLOUD_API_KEY" > terraform.tfvars
   echo confluent_cloud_api_secret = "CONFLUENT_CLOUD_API_SECRET" >> terraform.tfvars
   echo zapier_token = "ZAPIER_TOKEN" >> terraform.tfvars
   echo bedrock_access_key_id = "AWS_ACCESS_KEY_ID" >> terraform.tfvars
   echo bedrock_secret_access_key = "AWS_SECRET_ACCESS_KEY" >> terraform.tfvars
   echo db_host = "POSTGRES_HOST" >> terraform.tfvars
   echo db_port = 5432 >> terraform.tfvars
   echo db_name = "POSTGRES_DB" >> terraform.tfvars
   echo db_password = "POSTGRES_PASSWORD" >> terraform.tfvars
   ```
   </details>

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

## Post-Deployment Steps

> [!IMPORTANT]
> Run this step in a different tab. Data gen needs to continously run.

Once the infrastructure is deployed, we can generate mortgage data. We'll use **ShadowTraffic** to send `mortgage_applications` and `historical_payments` to **Kafka**, and `credit_score` data to **Postgres**.

1. Open the repo directory in a new terminal window.
2. Change directory to `data-gen` directory:
   ```
   cd terraform/data-gen
   ```
3. Run ShadowTraffic

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

   > **Note:** Leave this terminal open all the time.


   > **Note:** Shadow Traffic is configure to generate a new mortgage application every 10 mins.

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

   > NOTE: The name must be John Doe to match an existing applicant with a known high credit score.
   >
   > The loan amount must be less than or equal to the property value.

   ![Architecture](./assets/demo1.png)

3. To verify that the data has been successfully generated, go to the [Confluent Cloud Topic UI](https://confluent.cloud/go/topics). Select your environment and cluster, then click on the `mortgage_applications`, you should see the new application there.


## Demo

> **Estimated time:** 90 minutes

This workshop includes two labs:

1. [**Lab 1 – Connecting and Pre-processing Mortgage Applications**](./lab1/lab1-README.md):
   Use the fully managed **Postgres CDC Source Connector** to stream credit score data from the instructor-provided Postgres DB to **Confluent Cloud**. Then, leverage **Confluent Cloud for Apache Flink** to transform the live stream of mortgage applications into a real-time, contextualized data product—ready to power AI agents.

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

To destroy all the resources created run the command below from the ```terraform/workshop``` directory:

```
terraform destroy --auto-approve
```
