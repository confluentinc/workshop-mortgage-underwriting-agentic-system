terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

locals {
  flink_statement_base = {
    organization_id    = var.organization_id
    environment_id     = var.environment_id
    compute_pool_id    = var.flink_compute_pool_id
    service_account_id = var.service_account_id
    rest_endpoint      = var.flink_rest_endpoint
    api_key_id         = var.flink_api_key_id
    api_key_secret     = var.flink_api_key_secret
  }

  flink_properties = {
    "sql.current-catalog"  = var.environment_display_name
    "sql.current-database" = var.kafka_cluster_display_name
  }
}

# ------------------------------------------------------
# Statement 1: Enriched Mortgage Applications (CTAS)
# Temporal join with CDC credit score versioned table
# ------------------------------------------------------

resource "confluent_flink_statement" "enriched_mortgage_applications" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "enriched-mortgage-applications-materializer"

  statement = <<-SQL
    CREATE TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`enriched_mortgage_applications` (
      application_id STRING,
      customer_email STRING,
      borrower_name STRING,
      applicant_id STRING,
      income DOUBLE,
      payslips STRING,
      loan_amount DOUBLE,
      property_address STRING,
      property_state STRING,
      property_value DOUBLE,
      employment_status STRING,
      credit_score DOUBLE,
      credit_utilization DOUBLE,
      open_credit_accounts DOUBLE,
      recent_defaults DOUBLE,
      debt_to_income_ratio DOUBLE,
      application_ts TIMESTAMP_LTZ(3),
      WATERMARK FOR application_ts AS application_ts - INTERVAL '5' SECOND
    )
    WITH ('kafka.partitions' = '1')
    AS
    SELECT
      m.application_id,
      m.customer_email,
      m.customer_name AS borrower_name,
      m.applicant_id,
      CAST(m.income AS DOUBLE) AS income,
      m.payslips,
      CAST(m.loan_amount AS DOUBLE) AS loan_amount,
      m.property_address,
      m.property_state,
      CAST(m.property_value AS DOUBLE) AS property_value,
      m.employment_status,
      c.credit_score AS credit_score,
      c.credit_utilization AS credit_utilization,
      c.open_credit_accounts AS open_credit_accounts,
      c.public_records AS recent_defaults,
      CAST(ROUND((CAST(m.loan_amount AS DECIMAL(10, 2)) / CAST(m.income AS DECIMAL(10, 2))) * 100, 2) AS DOUBLE) AS debt_to_income_ratio,
      m.application_ts
    FROM `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_applications` m
    JOIN `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`PROD.public.applicant_credit_score` FOR SYSTEM_TIME AS OF m.`application_ts` AS c
    ON m.applicant_id = c.applicant_id;
  SQL

  properties = local.flink_properties

  stopped = false
}

# ------------------------------------------------------
# Statement 2: Applicant Payment Summary (CTAS)
# Aggregates payment history per applicant
# ------------------------------------------------------

resource "confluent_flink_statement" "applicant_payment_summary" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "applicant-payment-summary-materializer"

  statement = <<-SQL
    CREATE TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`applicant_payment_summary` (
      `applicant_id` STRING NOT NULL,
      `updated_at` TIMESTAMP_LTZ(3) NOT NULL,
      `payment_history` ARRAY<ROW(
        transaction_id STRING,
        `method` STRING,
        amount DOUBLE,
        status STRING,
        failure_reason STRING,
        payment_date STRING
      )>,
      WATERMARK FOR `updated_at` AS `updated_at` - INTERVAL '5' SECOND
    )
    WITH ('kafka.partitions' = '1')
    AS
    SELECT
      applicant_id,
      MAX(`$rowtime`) AS updated_at,
      ARRAY_AGG(
        ROW(
          transaction_id,
          `method`,
          amount,
          status,
          failure_reason,
          payment_date
        )
      ) AS payment_history
    FROM `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`payment_history`
    GROUP BY applicant_id;
  SQL

  properties = local.flink_properties

  stopped = false

  depends_on = [
    confluent_flink_statement.enriched_mortgage_applications
  ]
}

# ------------------------------------------------------
# Statement 3: Enriched Mortgage with Payments (CTAS)
# Temporal join - NO property_value filter
# ------------------------------------------------------

resource "confluent_flink_statement" "enriched_mortgage_with_payments" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "enriched-mortgage-payments-materializer"

  statement = <<-SQL
    CREATE TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`enriched_mortgage_with_payments`
    WITH ('changelog.mode' = 'append', 'kafka.partitions' = '1')
    AS
    SELECT
      m.application_id,
      m.customer_email,
      m.borrower_name,
      m.applicant_id,
      m.income,
      m.payslips,
      m.loan_amount,
      m.property_address,
      m.property_state,
      m.property_value,
      m.employment_status,
      m.credit_score,
      m.credit_utilization,
      m.open_credit_accounts,
      m.recent_defaults,
      m.debt_to_income_ratio,
      m.application_ts,
      p.payment_history
    FROM `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`enriched_mortgage_applications` m
    LEFT JOIN `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`applicant_payment_summary` FOR SYSTEM_TIME AS OF m.application_ts AS p
    ON m.applicant_id = p.applicant_id;
  SQL

  properties = local.flink_properties

  stopped = false

  depends_on = [
    confluent_flink_statement.enriched_mortgage_applications,
    confluent_flink_statement.applicant_payment_summary
  ]
}

# ------------------------------------------------------
# Statement 4: CREATE AGENT mortgage_risk_agent
# Fraud detection and credit risk assessment
# ------------------------------------------------------

resource "confluent_flink_statement" "mortgage_risk_agent" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "mortgage-risk-agent-create"

  statement = <<-SQL
    CREATE AGENT `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_risk_agent`
    USING MODEL `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`llm_textgen_model`
    USING PROMPT 'You are the Credit and Fraud Risk Analyst at River Banking. Your job is to assess the applicant creditworthiness and fraud risk using the provided application data and payment history, and produce a concise, structured JSON output for downstream automation.

    # DECISION PRINCIPLES
    1. Be conservative on fraud: only flag high fraud risk if there are clear red flags.
    2. Credit risk should be based on credit score, utilization, open accounts, recent defaults, and debt-to-income ratio.
    3. Always return JSON only — no extra text.

    # CREDIT RISK GUIDELINES
    - Credit Score:
      - 750+ → Low credit risk
      - 600–749 → Moderate credit risk
      - <600 → High credit risk
    - Credit Utilization:
      - ≤30% → Healthy
      - 31–60% → Elevated
      - >60% → High risk
    - Recent Defaults:
      - 0 → Favorable
      - 1–2 → Moderate risk
      - ≥3 → High risk
    - Debt-to-Income Ratio:
      - ≤35% → Low risk
      - 36–50% → Moderate risk
      - >50% → High risk

    # FRAUD RISK GUIDELINES
    Evaluate fraud risk using these patterns:
    - High payment failure rate (>50% failed payments is a strong indicator)
    - High credit utilization (>60%) combined with recent defaults (≥3)
    - Debt-to-income ratio >100% with low credit score (<600)
    A low loan-to-income ratio or low property value relative to income is NOT a fraud indicator — it simply means the applicant is borrowing conservatively.
    A small number of payment records is NOT suspicious — it may indicate a new customer.
    Only mark fraud risk as high (score >70) if there are multiple strong indicators from the list above.

    # OUTPUT REQUIREMENTS
    Return a JSON object with the following fields:
    - fraud_risk_score: number 0–100
    - loan_stack_risk: "Low" | "Moderate" | "High"
    - risk_category: "Low" | "Moderate" | "High"
    - agent_reasoning: 1–3 sentences summarizing key factors

    # OUTPUT FORMAT
    Respond ONLY with a raw JSON object. Do NOT wrap it in markdown code blocks (no ```json or ```). Do NOT include any text, explanation, or commentary before or after the JSON object.

    Example of a valid response:
    {"fraud_risk_score": 12.0, "loan_stack_risk": "Low", "risk_category": "Moderate", "agent_reasoning": "Credit score is mid-range with elevated utilization, but payment history is stable. No strong fraud indicators detected."}

    IMPORTANT: Your entire response must be parseable as a single JSON object. Any additional text will cause a system failure.'
    COMMENT 'Credit + fraud risk assessment agent'
    WITH (
      'max_consecutive_failures' = '2',
      'MAX_ITERATIONS' = '6'
    );
  SQL

  properties = local.flink_properties

  depends_on = [
    confluent_flink_statement.enriched_mortgage_with_payments
  ]
}

# ------------------------------------------------------
# Statement 5: Mortgage Validated Apps (CTAS)
# Applies risk agent to enriched applications
# ------------------------------------------------------

resource "confluent_flink_statement" "mortgage_validated_apps" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "mortgage-risk-agent"

  statement = <<-SQL
    CREATE TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_validated_apps`
    WITH ('kafka.partitions' = '1')
    AS
    SELECT
      m.application_id,
      m.applicant_id,
      m.customer_email,
      m.borrower_name,
      m.income,
      m.payslips,
      m.loan_amount,
      m.property_address,
      m.property_state,
      m.property_value,
      m.employment_status,
      m.credit_score,
      m.credit_utilization,
      m.debt_to_income_ratio,
      CAST(JSON_VALUE(agent_result.response, '$.fraud_risk_score') AS DOUBLE) AS fraud_risk_score,
      JSON_VALUE(agent_result.response, '$.loan_stack_risk') AS loan_stack_risk,
      JSON_VALUE(agent_result.response, '$.risk_category') AS risk_category,
      JSON_VALUE(agent_result.response, '$.agent_reasoning') AS agent_reasoning,
      m.application_ts
    FROM `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`enriched_mortgage_with_payments` m,
    LATERAL TABLE(
      AI_RUN_AGENT(
        'mortgage_risk_agent',
        CONCAT(
          '# ROLE\n',
          'You are the Credit and Fraud Risk Analyst at River Banking.\n\n',
          '# INPUT DATA\n',
          'Application ID: ', m.application_id, '\n',
          'Applicant ID: ', m.applicant_id, '\n',
          'Borrower Name: ', m.borrower_name, '\n',
          'Annual Income: $', CAST(m.income AS STRING), '\n',
          'Loan Amount: $', CAST(m.loan_amount AS STRING), '\n',
          'Credit Score: ', CAST(m.credit_score AS STRING), '\n',
          'Credit Utilization: ', CAST(m.credit_utilization AS STRING), '%\n',
          'Debt-to-Income: ', CAST(m.debt_to_income_ratio AS STRING), '%\n',
          'Recent Defaults: ', CAST(m.recent_defaults AS STRING), '\n',
          'Payment History: ', COALESCE(CAST(m.payment_history AS STRING), 'No payment history available'), '\n\n',
          'Return ONLY a raw JSON object with these exact fields: fraud_risk_score (number), loan_stack_risk (string), risk_category (string), agent_reasoning (string). Do NOT wrap in markdown code blocks. Do NOT include any text before or after the JSON.'
        ),
        MAP['debug', true]
      )
    ) AS agent_result;
  SQL

  properties = local.flink_properties

  stopped = false

  depends_on = [
    confluent_flink_statement.enriched_mortgage_with_payments,
    confluent_flink_statement.mortgage_risk_agent
  ]
}

# ------------------------------------------------------
# Statement 6: CREATE TOOL send_email
# MCP tool for sending emails
# ------------------------------------------------------

resource "confluent_flink_statement" "send_email_tool" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "send-email-tool-create"

  statement = <<-SQL
    CREATE TOOL `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`send_email`
    USING CONNECTION `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mcp_connection`
    WITH (
      'type' = 'mcp',
      'allowed_tools' = 'gmail_send_email',
      'request_timeout' = '30'
    );
  SQL

  properties = local.flink_properties

  depends_on = [
    confluent_flink_statement.mortgage_validated_apps
  ]
}

# ------------------------------------------------------
# Statement 7: CREATE AGENT mortgage_decisions_agent
# Makes mortgage decisions and generates letters
# ------------------------------------------------------

resource "confluent_flink_statement" "mortgage_decisions_agent" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "mortgage-decisions-agent-create"

  statement = <<-SQL
    CREATE AGENT `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_decisions_agent`
    USING MODEL `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`llm_textgen_model`
    USING PROMPT 'You are a Credit and Fraud Risk Analyst at River Banking, a leading financial institution specializing in personalized mortgage solutions. River Banking is committed to responsible lending and fraud prevention through advanced risk analysis and data-driven decision-making.

    Your role is to assess a mortgage applicant financial and risk profile to determine loan eligibility and recommend an appropriate interest rate. You will analyze key indicators such as verified income, credit score, and fraud score. Based on these inputs, you will evaluate the applicant ability to repay the loan, identify any potential red flags, and assign a risk category that will inform underwriting decisions.'
    USING TOOLS `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`send_email`
    COMMENT 'Agent for making mortgage decisions and generating mortgage offers or rejection letters'
    WITH (
      'max_consecutive_failures' = '2',
      'MAX_ITERATIONS' = '10'
    );
  SQL

  properties = local.flink_properties

  depends_on = [
    confluent_flink_statement.mortgage_validated_apps,
    confluent_flink_statement.send_email_tool
  ]
}

# ------------------------------------------------------
# Statement 8: Mortgage Decisions (CTAS)
# Applies decision agent and sends email notifications
# ------------------------------------------------------

resource "confluent_flink_statement" "mortgage_decisions" {
  organization {
    id = local.flink_statement_base.organization_id
  }
  environment {
    id = local.flink_statement_base.environment_id
  }
  compute_pool {
    id = local.flink_statement_base.compute_pool_id
  }
  principal {
    id = local.flink_statement_base.service_account_id
  }
  rest_endpoint = local.flink_statement_base.rest_endpoint
  credentials {
    key    = local.flink_statement_base.api_key_id
    secret = local.flink_statement_base.api_key_secret
  }

  statement_name = "mortgage-decisions-agent"

  statement = <<-SQL
    CREATE TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_decisions`
    WITH ('kafka.partitions' = '1')
    AS
    SELECT
      m.application_id,
      m.applicant_id,
      m.customer_email,
      m.borrower_name,
      m.property_state,
      m.loan_amount,
      JSON_VALUE(agent_result.response, '$.final_interest_rate') AS final_interest_rate,
      JSON_VALUE(agent_result.response, '$.decision') AS decision,
      JSON_VALUE(agent_result.response, '$.explanation') AS explanation,
      JSON_VALUE(agent_result.response, '$.letter_body') AS letter_body,
      m.application_ts AS `timestamp`
    FROM `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`mortgage_validated_apps` m,
    LATERAL TABLE(
      AI_RUN_AGENT(
        'mortgage_decisions_agent',
        CONCAT(
          '# ROLE\n',
          'You are the Mortgage Underwriting and Communications Agent at River Banking. You evaluate mortgage applications, ',
          'determine eligibility, recommend risk-adjusted interest rates, and generate customer communications.\n\n',

          '# OBJECTIVE\n',
          'Analyze the applicant financial profile and risk indicators to produce:\n',
          '1. Eligibility decision (Approved or Rejected)\n',
          '2. Risk-adjusted interest rate recommendation\n',
          '3. Clear explanation of the decision\n',
          '4. Professional communication letter\n',
          '5. After you finish with all the above check that the output is JSON format based on the schema below.\n\n'

          '# DECISION CRITERIA\n\n',

          '## Credit Assessment\n',
          '- HIGH credit: Score > 750 → Lower interest rates (base rate + 0-1%)\n',
          '- MEDIUM credit: Score 500-750 → Moderate rates (base rate + 1-3%)\n',
          '- LOW credit: Score < 500 → Higher rates or rejection (base rate + 3-5%)\n\n',

          '## Financial Capacity\n',
          '- Debt-to-Income Ratio: Acceptable range is 1-600%. Ratios > 600% require strong compensating factors.\n',

          '## Risk Factors\n',
          '- fraud_risk_score: Scores > 70 require additional scrutiny or rejection.\n',
          '- loan_stack_risk: HIGH risk may lead to rejection or rate adjustment.\n',
          '- risk_category: Consider overall risk profile in final decision.\n\n',

          '## Decision Rules\n',
          '- Output ONLY "Approved" or "Rejected" (no Pending status).\n',
          '- For Rejected applications: Set final_interest_rate to -1.0\n',
          '- Base interest rate assumption: 6.5% (adjust based on risk profile)\n\n',

          '# APPLICANT DATA\n',
          'Application ID: ', m.application_id, '\n',
          'Applicant ID: ', m.applicant_id, '\n',
          'Customer Email: ', m.customer_email, '\n',
          'Borrower Name: ', m.borrower_name, '\n',
          'Property: ', m.property_address, ', ', m.property_state, '\n',
          'Property Value: $', CAST(m.property_value AS STRING), '\n',
          'Loan Amount: $', CAST(m.loan_amount AS STRING), '\n',
          'Annual Income: $', CAST(m.income AS STRING), '\n',
          'Employment: ', m.employment_status, '\n',
          'Credit Score: ', CAST(m.credit_score AS STRING), '\n',
          'Credit Utilization: ', CAST(m.credit_utilization AS STRING), '%\n',
          'Debt-to-Income: ', CAST(m.debt_to_income_ratio AS STRING), '%\n',
          'Fraud Risk Score: ', COALESCE(CAST(m.fraud_risk_score AS STRING), 'N/A'), '\n',
          'Loan Stack Risk: ', COALESCE(m.loan_stack_risk, 'N/A'), '\n',
          'Risk Category: ', COALESCE(m.risk_category, 'N/A'), '\n',
          'Risk Assessment: ', COALESCE(m.agent_reasoning, 'N/A'), '\n\n',
          'You are an API that responds with JSON only. Do not include explanations, headers, or markdown formatting.\n\n',
          'Respond ONLY with a raw JSON object like this:\n',
          '{\n'
          '"letter_body": (string) acceptace or rejection letter\n',
          '"decision": (enum) Either "Approved" or "Rejected"\n',
          '"final_interest_rate": (float) The suggested interest rate for the applicant if the application "decision" is Approved. If the application "decision" is "Rejected" suggest "-1" interest rate.  \n',
          '"explanation": (string) A brief narrative explaining the decision and interest rate logic\n',
          '}',
          'Provide only the JSON.\n\n',
          'Failure to strictly follow the output format will result in incorrect output.'

          '## Field Requirements\n',
          '- decision: Must be exactly "Approved" or "Rejected"\n',
          '- final_interest_rate: Must be a STRING (e.g., "7.5" not 7.5). Use "-1.0" for rejected applications\n',
          '- explanation: Single string with brief reasoning\n',
          '- letter_body: Single string containing the complete letter (see template below)\n\n',

          '## Letter Body Template\n',
          'Generate letter_body as plain text following this EXACT structure.\n',
          'Use \\n\\n for paragraph breaks. NO bullet points. Write in complete sentences.\n\n',

          'Dear ', m.borrower_name, ',\\n\\n',
          'Thank you for submitting your mortgage application (ID: ', m.application_id, ') for the property located at ', m.property_address, ', ', m.property_state, '.\\n\\n',

          '[IF APPROVED]\\n',
          'We are pleased to inform you that your application has been approved. We are offering you a mortgage with an interest rate of [INSERT RATE]% APR for a loan amount of $[INSERT LOAN AMOUNT]. This rate reflects [INSERT BRIEF EXPLANATION OF RATE FACTORS].\\n\\n',
          'Your next steps are as follows: First, review and sign your loan agreement within 10 business days. Second, schedule your property appraisal with our team. Third, submit any remaining documentation requested. For questions or assistance, please contact us at 1-800-RIVER-BANKING or mortgages@riverbanking.com.\\n\\n',

          '[IF REJECTED]\\n',
          'After careful review of your application, we are unable to approve your mortgage at this time. [INSERT CLEAR EXPLANATION OF REJECTION REASONS].\\n\\n',
          'Your next steps are as follows: First, review the factors that affected this decision. Second, consider taking steps to address these concerns before reapplying. Third, contact us at 1-800-RIVER-BANKING for personalized guidance on strengthening your application.\\n\\n',

          'Best regards,\\n',
          'River Banking Mortgage Team\\n',
          'Phone: 1-800-RIVER-BANKING\\n',
          'Email: mortgages@riverbanking.com\n\n',

          '---\n\n',

          '# EMAIL AUTOMATION\n',
          'After generating the JSON output, call the gmail_send_email tool with:\n',
          '- To: ${var.email_address}\n',
          '- Subject: Mortgage Decision - Application ', m.application_id, ' - ', m.borrower_name, '\n',
          '- Body: Use the exact letter_body value from your JSON output\n\n',

          'REMEMBER: Output ONLY the JSON object. Do NOT include email fields in the JSON. Do NOT add any text before or after the JSON.'
        ),
        m.application_id,
        MAP['debug', 'true']
      )
    ) AS agent_result(status, response);
  SQL

  properties = local.flink_properties

  stopped = false

  depends_on = [
    confluent_flink_statement.mortgage_validated_apps,
    confluent_flink_statement.mortgage_decisions_agent
  ]
}
