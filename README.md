# Mortgage underwriting multi-agent system with Confluent Cloud

This repository showcases a demo for a mortgage provider that leverages **Confluent Cloud**, **AWS**, and **AI** to fully automate mortgage applications—from initial submission to final decision and offer.


![Architecture](./assets/HLD.png)

## Prerequisites

Before you begin, ensure you have the following installed:

- **Confluent Cloud API Keys** - [Cloud resource management API Keys](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/overview.html#resource-scopes) with Organisation Admin permissions are needed by Terraform to deploy the necessary Confluent resources.
- [Confluent CLI](https://docs.confluent.io/confluent-cli/current/install.html) - If on MAC run `brew install confluentinc/tap/cli`. 
- [Terraform](https://www.terraform.io/downloads.html) - v1.5.7 or later 
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [Docker](https://www.docker.com/get-started) - 28.1.1 or later
- **Java and Maven** installed on your laptop
- [Optional] [Databricks Account](https://login.databricks.com/?intent=signup) - To analyze Mortgage desisions 


## Setup

1.  Clone the repo onto your local development machine using `git clone https://github.com/confluentinc/mortgage-underwriting-multi-agent-system`.
2. Change directory to demo repository and terraform directory.

   ```
   cd mortgage-underwriting-multi-agent-system/terraform
   ```
3. Configure AWS CLI

   If you already have the AWS CLI configured on your machine, you can skip this step.

   If you're using **AWS Workshop Studio**, click on **Get AWS CLI Credentials** to retrieve the necessary access key, secret key, and region. Then, run the following command to configure the CLI:
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
4. Verify you are using the correct AWS account by running:

   ```
   aws sts get-caller-identity
   ```
   If you are using **AWS Workshop Studio**, you should have an output that looks like this:

   ```
   {
    "UserId": "AROA4AFJ7PWFSQYLGZ3YL:Participant",
    "Account": "xxxxxxxxxx",
    "Arn": "arn:aws:sts::xxxxxxxxxx:assumed-role/WSParticipantRole/Participant"
   }
   ```

5. Configure Terraform Variables byt creating a `terraform.tfvars` file with the following content:
   ```hcl
   confluent_cloud_api_key = "<your-confluent-cloud-api-key>"
   confluent_cloud_api_secret = "<your-confluent-cloud-api-secret>"
   email = "<your-email>"
   ```

5. Initialize Terraform

   ```bash
   terraform init
   ```

6. Deploy Infrastructure

   ```bash
   terraform apply
   ```

Terraform will take around 20 mins to deploy and it will deploy the following infrstructure components:

- Confluent Cloud Infrastructure components:
   1. Environment
   2. Cluster
   3. Topics and Schemas
   4. RBAC role-bindings
   5. Flink Compute pool
- AWS Infrastructure components:
   1. Oracle DB running on Amazon EC2
   2. Webapp running on Amazon Fargate
   3. Lambda function that will run Agent 1

## Post-Deployment Steps

> **Note:** The Oracle setup process takes approximately 10 minutes to complete after a successful Terraform deployment. Please wait at least 10 minutes before proceeding with the next steps.

Once the infrastructure is deployed, we can generate mortgage data. We'll use **ShadowTraffic** to send `mortgage_applications` and `historical_payments` to **Kafka**, and `credit_score` data to **Oracle**.

1. Open the repo directory in a new terminal window.
2. Change directory to `data-gen` directory:
   ```
   cd terraform/data-gen
   ```
3. Get a ShadowTraffic License Key. [Sign up for ShadowTraffic](https://shadowtraffic.io/pricing.html) to obtain a license key.

   **If you already have a license key, you can skip this step.**

4. Inside the `data-gen` directory, create a file named `license.env` and add your license variables.

   The file should look like this:
   ```
   LICENSE_ID=e2c218c6-00ef-41d3-8c93-7debea33266e
   LICENSE_EMAIL=<your_email>
   LICENSE_ORGANIZATION=<your_company>
   LICENSE_EDITION=ShadowTraffic Free Trial
   LICENSE_EXPIRATION=<date>
   LICENSE_SIGNATURE=rbnDYGuNaxk7j5HwdsNzJz4dDROlLX3Haf5tjBOwCJv7Y5rNg6D0TcJQA/gODKiQhY5f1rg9g1pPDiSuZUFfY9lUZGGx99HquZAAENDotezebIY1ILf8DVDSq9hchvYyceuL1irNgynpaSvfh+EeakeGQBbm6FtihWEJmhUMjQoJVMyckV9z9OVMhluWI3PAKLI8ryelOc3QsZiKoIwlledY5fYzvUZwOBG+GpLOps15xgTJGFVDTy206xXzPdCGMh5DTwh7hXYyHfcZepiV2DGqEk+MPGQGxuKvGuiOnE/FhPjdj2BUJWyEswo6MPpgsyl4FVcLj/lfgWAi+Gt/Pg==
   ```
5. Run ShadowTraffic
   <details>
   <summary>Click to expand for MAC</summary>

   ```
   ./run.sh
   ```

   </details>

   <details>
   <summary>Click to expand for Windows</summary>

   ```
   run.bat
   ```

   </details>

4. To verify that the data has been successfully generated, go to the [Confluent Cloud Topic UI](https://confluent.cloud/go/topics). Select your environment and cluster, then click on the `mortgage_applications` topic to confirm that data is being produced.

   ![Architecture](./assets/verify.png)



## Demo

> **Estimated time:** 90 minutes

This workshop includes two labs:

1. [**Lab 1 – Connecting and Pre-processing Mortgage Applications**](./lab1/lab1-README.md):  
   Use the fully managed **Oracle XStream CDC Source Connector** to stream credit score data from Oracle DB to **Confluent Cloud**. Then, leverage **Confluent Cloud for Apache Flink** to transform the live stream of mortgage applications into a real-time, contextualized data product—ready to power AI agents.

2. [**Lab 2 – Building AI Agents to process Mortgage Applications**](./lab2/lab2-README.md):  
   Use **Confluent Cloud for Apache Flink**, **AWS Lambda**, **Amazon Bedrock** to build three AI agents that run sequentially to fully automate the mortgage application process.



## Topics

**Next topic:** [Lab 1 - Connecting and pre-processing mortgage applications](./lab1/lab1-README.md)

## Clean-up
Once you are finished with this demo, remember to destroy the resources you created, to avoid incurring charges. You can always spin it up again anytime you want.

Before tearing down the infrastructure, delete the Oracle xstream and Lambda connector, as they were created outside of Terraform and won't be automatically removed:

```
confluent connect cluster delete <CONNECTOR_ID> --cluster <CLUSTER_ID> --environment <ENVIRONMENT_ID> --force
```

To destroy all the resources created run the command below from the ```terraform``` directory:

```
terraform destroy --auto-approve
```

