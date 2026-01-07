
# Building AI Agents to Process Mortgage Applications

In this lab, we will use AI agents powered by a **Claude model running on Amazon Bedrock** to process real-time, contextualized mortgage applications. We'll build two AI agents, each responsible for a different stage of the mortgage decision workflow:

- **Agent 1:** Runs on AWS Lambda and performs fraud detection and credit risk assessment.
- **Agent 2:** Runs on Confluent Cloud for Apache Flink using AI agents and performs the complete mortgage underwriting process: analyzes the application, determines loan eligibility with interest rate recommendation, and generates a formal approval or rejection letter—all in a single intelligent agent workflow.

By the end of this lab, the entire mortgage application process will be fully automated using intelligent, Bedrock-powered agents.

![Architecture](./assets/HLD.png)

## Prerequisites

Before starting this lab, make sure you have completed [**Lab 1 – Connecting and Pre-processing Mortgage Applications**](../lab1/lab1-README.md).

## 🔓 Enabling Claude Sonnet 3.7 on Your AWS Account

To enable **Claude 3.7 Sonnet** in your AWS account via Amazon Bedrock:

1. Open the [Amazon Bedrock Console](https://console.aws.amazon.com/bedrock/home?/overview), make sure you are in the same region.
2. In the left sidebar, under **Bedrock configuration**, click **Model access**.
3. Locate **Claude 3.7 Sonnet** in the list of available models.
4. Click **Available to request**, then select **Request model access**.
5. In the request wizard, click **Next** and follow the prompts to complete the request.

![Model Access in Bedrock Console](./assets/lab2-bedrock1.png)

⏱️ *Provisioning may take 5–10 minutes.*

Once enabled, you’ll need to retrieve the **model ID** for use in your applications.

3. In the Bedrock UI, navigate to **Anthropic**, then select the **Claude Sonnet 3.7** model.

   - In the **Details** section, locate the **Model ID**.
   - Copy this value — you’ll need it later. The Model ID should look something like:
      ```
      anthropic.claude-3-7-sonnet-20250219-v1:0
      ```
4. We’ll use this model ID to construct the endpoint for invoking the model.

   > **Note:** Prefix the `<model_id>` with `us.` for US-based regions or `eu.` for EU-based regions.  
   > Omitting the region prefix will prevent successful model invocation.
   
   Example (us-east-1):
      ```
      https://bedrock-runtime.us-east-1.amazonaws.com/model/us.anthropic.claude-3-7-sonnet-20250219-v1:0/invoke
      ```

We will use this endpoint later in the lab.

## **Agent 1: Fraud and Credit Risk Assesment**

![Architecture](./assets/lab2-lambda-hld.png)

This agent runs on AWS Lambda, so we will use the fully managed Lambda Sink Connector to stream data from `enriched_mortgage_with_payments` topic that we created in the previous lab directly to the Lambda function in realtime.

1. In the [Connectors UI](https://confluent.cloud/go/connectors), you should have an Oracle XStream CDC Source Connector running. Click **+ Add Connector**. Then choose, **AWS Lambda Sink**.
2. Choose `enriched_mortgage_with_payments` topic.

   ![Screenshot](./assets/lab2-lambdasink1.png)

3. Enter your Confluent Cluster credentials, select **Service Account**, then choose **Existing Account**. From the drop-down menu, select the service account that was created for you by Terraform. The service account name should follow this format: `<prefix>-app-manager-<random_suffix>`.

   ![Screenshot](./assets/lab2-lambdasink2.png)

4.  Enter Oracle details - Run ```terraform output lambda_connector``` from `terraform` directory to get the details. Output should look as follows:
   ![Screenshot](./assets/lab2-lambdasink3.png)

      - After you enter the details, click **Continue**


5. For Configuration, choose:

   - `AVRO` as input value format
   - In **advanced configurations** set:
      - **Invocation Type** to `async`.
      - **Batch size** to `1`.
      - **Socket Timeout** to `600000`.

   ![Screenshot](./assets/lab2-lambdasink4.png)

   - Click **Continue**

6. Follow the wizard to create the connector.

7. After a few minutes, the connector should be up and running. Data will begin flowing to the Lambda Function.

 To verify that the connector is working properly, in the Flink workspace, run this and check the risk scores for all application. 

 ```sql
 SELECT * FROM mortgage_validated_apps
 ```
 Checkout the `agent_reasoning` for John.

> ⚠️ **Note:** If you're using **AWS Workshop Studio**, be aware that **Bedrock service limits are reduced** for security reasons. As a result, some requests may be throttled.  
>  
> **Important:** The provided Lambda function does **not** include a retry mechanism, so throttled requests may be lost during the workshop. In a production environment, you should implement a robust retry strategy to handle such cases gracefully.


 ## **Agent 2: Mortgage Underwriting (Decision + Letter Generation)**

This agent runs on **Confluent Cloud for Apache Flink** using the new AI Agent framework, combining both mortgage decision-making and letter generation into a single intelligent workflow.

![Architecture](./assets/lab2-agent2-hld.png)

1. In your terminal, install `confluent-cli` by following these [instructions](https://docs.confluent.io/confluent-cli/current/install.html).
2. Configure `confluent-cli`:
   ```
   confluent login --save
   ```
   - Enter email and password

3. Configure AWS Environment variables if you are using a new terminal.

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

4. Run the following command to create a connection resource named `bedrock-claude-connection` that uses your AWS credentials.

   ```
   confluent flink connection create bedrock-claude-connection \
   --cloud AWS \
   --region <CLOUD_REGION> \
   --environment <CONFLUENT_ENV_ID> \
   --type bedrock \
   --endpoint https://bedrock-runtime.<CLOUD_REGION>.amazonaws.com/model/us.anthropic.claude-3-7-sonnet-20250219-v1:0/invoke \
   --aws-access-key $AWS_ACCESS_KEY_ID \
   --aws-secret-key $AWS_SECRET_ACCESS_KEY \
   --aws-session-token $AWS_SESSION_TOKEN
   ```

5. In the Flink workspace, create the AI agent:

   ```sql
   CREATE AGENT mortgage_underwriting_agent
   USING MODEL bedrock-claude-connection
   USING PROMPT '
   You are a Mortgage Underwriting Agent at River Banking, a leading financial institution specializing in personalized mortgage solutions. River Banking is committed to responsible lending and fraud prevention through advanced risk analysis and data-driven decision-making.
   Your role has two key responsibilities:
   1. CREDIT AND FRAUD RISK ANALYSIS: Assess a mortgage applicant''s financial and risk profile to determine loan eligibility and recommend an appropriate interest rate. Analyze key indicators such as verified income, credit score, and fraud score. Based on these inputs, evaluate the applicant''s ability to repay the loan, identify any potential red flags, and assign a risk category.
   2. DECISION COMMUNICATION: Based on your eligibility determination, generate a formal mortgage approval or rejection letter. The letter should reflect River Banking''s tone—professional, clear, and empathetic—and summarize the key reasons behind the decision.

   For approvals: Provide a congratulatory offer message that includes the approved interest rate and a brief recap of why the applicant qualified.
   For rejections: Write a polite and supportive rejection message that explains the key factors contributing to the decision without disclosing sensitive internal scoring logic.

   All responses should be formatted as JSON according to the output format guidance.
   '
   COMMENT 'Analyzes risk assessment, determines loan eligibility, and generates approval/rejection letters'
   WITH (
     'max_iterations' = '10',
     'max_consecutive_failures' = '3'
   );
   ```

6. Start Agent 2 - This agent will analyze applications, make decisions, AND generate letters in a single workflow:

> ⚠️ **Note:** If you're using **AWS Workshop Studio**, be aware that **Bedrock service limits are reduced** for security reasons. As a result, some requests may be throttled.
>
> **Important:** The Flink job may fail if the message backlog exceeds **6 messages**, due to the current **Bedrock limit of 6 requests per minute** in AWS Workshop Studio.

   ```sql
   SET 'client.statement-name' = 'mortgage-underwriting-agent-materializer';
   CREATE TABLE mortgage_final_decisions AS
   SELECT
     CAST(m.application_id AS BYTES) AS `key`,
     m.application_id,
     m.applicant_id,
     a.customer_email,
     a.customer_name AS borrower_name,
     agent_response.decision,
     agent_response.final_interest_rate,
     agent_response.explanation,
     agent_response.letter,
     m.application_ts AS `timestamp`
   FROM mortgage_validated_apps m
   JOIN mortgage_applications a
     ON m.application_id = a.application_id
   CROSS JOIN LATERAL TABLE(
     AI_RUN_AGENT(
       'mortgage_underwriting_agent',
       CONCAT(
         'You are processing a mortgage application for River Banking. Your task is to:\n',
         '1. Analyze the applicant''s financial and risk profile\n',
         '2. Determine loan eligibility and recommend an interest rate\n',
         '3. Generate a formal approval or rejection letter\n\n',
         'APPLICANT FINANCIAL AND RISK PROFILE:\n',
         '- Application ID: ', m.application_id, '\n',
         '- Applicant ID: ', m.applicant_id, '\n',
         '- Email: ', a.customer_email, '\n',
         '- Borrower Name: ', a.customer_name, '\n',
         '- Income: $', CAST(m.income AS STRING), '\n',
         '- Loan Amount: $', CAST(m.loan_amount AS STRING), '\n',
         '- Property Address: ', m.property_address, '\n',
         '- Property State: ', m.property_state, '\n',
         '- Property Value: $', CAST(m.property_value AS STRING), '\n',
         '- Employment Status: ', m.employment_status, '\n',
         '- Credit Score: ', CAST(m.credit_score AS STRING), '\n',
         '- Credit Utilization: ', CAST(m.credit_utilization AS STRING), '%\n',
         '- Debt to Income Ratio: ', CAST(m.debt_to_income_ratio AS STRING), '\n',
         '- Fraud Risk Score: ', CAST(m.fraud_risk_score AS STRING), '\n',
         '- Loan Stack Risk: ', m.loan_stack_risk, '\n',
         '- Risk Category: ', m.risk_category, '\n',
         '- Agent Reasoning (from fraud detection): ', m.agent_reasoning, '\n\n',
         'INSTRUCTIONS:\n',
         '- Assess income, loan amount, debt-to-income ratio, and employment status\n',
         '- Analyze credit score and credit utilization to determine creditworthiness\n',
         '- Lower credit scores should yield higher interest rates; high credit scores yield lower rates\n',
         '- Incorporate risk signals (fraud_risk_score, loan_stack_risk, risk_category)\n',
         '- Use agent_reasoning to interpret key patterns in the applicant''s background\n',
         '- Return a clear decision on mortgage eligibility and a fair, risk-adjusted interest rate\n',
         '- Generate a formal letter that communicates the decision clearly and professionally\n\n',
         'OUTPUT FORMAT:\n',
         'You are an API that responds with JSON only. Do not include explanations, headers, or markdown formatting.\n\n',
         'Respond ONLY with a raw JSON object like this:\n',
         '{\n',
         '  "decision": (enum) Either "Approved", "Rejected", or "Pending"\n',
         '  "final_interest_rate": (float) The suggested interest rate if Approved. Use 0.0 if Rejected or Pending\n',
         '  "explanation": (string) A brief narrative explaining the decision and interest rate logic\n',
         '  "letter": (string) A formal mortgage approval or rejection letter formatted as:\n',
         '    Subject: <Subject Line for Email>\n',
         '    Body: <Body of Email>\n',
         '}\n\n',
         'Provide only the JSON. Failure to strictly follow the output format will result in incorrect output.'
       ),
       m.application_id
     )
   ) AS agent_response(decision STRING, final_interest_rate FLOAT, explanation STRING, letter STRING);
   ```

   > **Note:** This query should run continuously and **must not be stopped or deleted**.
   > Add new cells **above or below** this one before proceeding.
   > You should now have **three cells** with queries running continuously. Two from the previous lab and this one.

7. In a new cell, check the output of `mortgage_final_decisions`:

   ```sql
   SELECT * FROM mortgage_final_decisions;
   ```

8. Check John's application details:

   ```sql
   SELECT
     application_id,
     borrower_name,
     decision,
     final_interest_rate,
     explanation,
     letter
   FROM mortgage_final_decisions
   WHERE borrower_name = 'John Doe';
   ```

You should now see the complete underwriting result: the decision, interest rate, explanation, AND the formal letter—all generated by a single AI agent!

## Topics

**Next topic:** [Demo](../Demo/demo-README.md)

**Previous topic:** [Lab 1 - Connecting and pre-processing mortgage applications](../lab1/lab1-README.md)

