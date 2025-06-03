import logging
import boto3
from dotenv import load_dotenv
import json
import asyncio
import re
from publish_to_topic import produce

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Load environment variables from .env file
load_dotenv()

AGENT_OUTPUT_TOPIC = 'mortgage_validated_apps'
MAX_REACT_LOOPS = 6

SYSTEM_PROMPT = """You're a Credit and Fraud Risk Analyst at River Banking, a leading
    financial institution specializing in personalized mortgage solutions. River Banking
    is committed to responsible lending and fraud prevention through advanced risk
    analysis and data-driven decision-making.

    Your role is to analyze a mortgage applicant's financial profile and supporting
    documentation to produce a Credit and Fraud Risk Assessment Report. This report will
    evaluate the applicant's creditworthiness and flag potential fraud risks based on key
    indicators such as credit score, income stability, debt ratios, and account history.
    Your findings will help determine whether the applicant meets River Banking's lending
    criteria and ensure the integrity of the loan underwriting process.
    """
    
# definition of tools available
tools = [
    {
        "toolSpec": {
            "name": "get_fraud_risk_assesment",
            "description": "Gets the applicant's fraud risk assessment.",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "mortgage_application": {
                            "type": "object"
                        }
                    },
                    "required": ["mortgage_application"]
                }
            }
        }
    }
]

def call_model(message_list, tool_list=[]):
    session = boto3.Session()

    bedrock = session.client(service_name='bedrock-runtime')
    
    request_params = {
        "modelId": "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
        "messages": message_list,
        "inferenceConfig": {
            "maxTokens": 2000,
            "temperature": 0
        }
    }
    
    if tool_list:  # Only add toolConfig if tool_list is not empty
        request_params["toolConfig"] = { "tools": tool_list }
    
    response = bedrock.converse(**request_params)
    
    return response

def take_action(tool_use_block):
    tool_use_name = tool_use_block['name']

    if tool_use_name == 'get_fraud_risk_assesment':
        return get_fraud_risk_assesment(tool_use_block['input'])
    else:
        print(f"Invalid function name: {tool_use_name}")
        
def handle_response(response_message):
    response_content_blocks = response_message['content']
    follow_up_content_blocks = []
    
    for content_block in response_content_blocks:
        if 'toolUse' in content_block:
            tool_use_block = content_block['toolUse']
            
            print(tool_use_block)
            
            try:
                tool_result_value = take_action(tool_use_block)
                
                if tool_result_value is not None:
                    follow_up_content_blocks.append({
                        "toolResult": {
                            "toolUseId": tool_use_block['toolUseId'],
                            "content": [
                                { "json": { "result": tool_result_value } }
                            ]
                        }
                    })
                
            except Exception as e:
                follow_up_content_blocks.append({ 
                    "toolResult": {
                        "toolUseId": tool_use_block['toolUseId'],
                        "content": [  { "text": repr(e) } ],
                        "status": "error"
                    }
                })
        
    if len(follow_up_content_blocks) > 0:
        follow_up_message = {
            "role": "user",
            "content": follow_up_content_blocks,
        }
        
        return follow_up_message
    else:
        return None

def think(prompt, tool_list):
    loop_count = 0
    should_continue = True
    
    message_list = [
        {
            "role": "user",
            "content": [ { "text": prompt } ]
        }
    ]
    
    while should_continue:
        response = call_model(message_list, tool_list)
        
        response_message = response['output']['message']
        message_list.append(response_message)
        
        loop_count = loop_count + 1
        
        if loop_count >= MAX_REACT_LOOPS:
            print(f"Hit loop limit: {loop_count}")
            break
        
        follow_up_message = handle_response(response_message)
        
        if follow_up_message is None:
            # No remaining work to do, return final response to user
            should_continue = False 
        else:
            message_list.append(follow_up_message)
            
    return message_list
    
def get_fraud_risk_assesment(mortgage_application: object):
    """
    Gets the applicants fraud risk assessment.
    
     Arg:
        mortgage_application (dict): A dictionary with the following keys:
                customer_email (str): The customer's email.
                borrower_name (str): The customer's name.
                income (int): The customer's yearly income.
                property_address (str): The customer's email.
                property_state (str): The customer's email.
                property_value (int): The customer's email.
                employment_status (str): The customer's email.
                credit_score (float): The customer's email.
                credit_utilization (float): The customer's email.
                debt_to_income_ratio (float): The customer's email.
                open_credit_accounts (float): The customer's email.
                recent_defaults (float): The customer's email.
                payment_history (list): An array of the customer's payment history.
    """
    
    example_output = {
    "applicant_id": "C12345678",
    "assessment_timestamp": "2025-03-27T14:35:00Z",
    "risk_score": 72,
    "risk_level": "medium",
    "signals": {
        "payment_anomalies": {
            "consecutive_failures": 2,
            "late_payments_in_last_12_months": 3,
            "method_switch_pattern": ["auto_debit", "manual", "manual"],
            "high_risk_behavior": "true"
        },
        "identity_risk": {
            "email_mismatch": "false",
            "phone_number_recent_change": "true",
            "multiple_policies_same_identity": "false"
        },
        "policy_behavior": {
            "frequent_policy_cancellations": 1,
            "address_change_frequency": 3,
            "policy_lapse_days": 45
        },
        "claim_anomalies": {
            "suspicious_claims_count": 2,
            "claims_within_90_days_of_policy_start": 1
        },
        "external_data_flags": {
            "known_fraud_watchlist_hit": "false",
            "device_fingerprint_mismatch": "true"
            }
        }
    }

    prompt = f"""
      Take the mortgage application and compute the fraud risk assessment.
      Be generous in terms of fraud risk and only flag the applicant if
      their application is really bad.

      Mortgage Application:
      {mortgage_application}

      The output should look like this:
      {json.dumps(example_output)}

      Only include the output. No additional description is needed.
      Failure to strictly follow the output format will result in incorrect output.
    """

    response = call_model([
        {
            "role": "user",
            "content": [ { "text": prompt } ]
        }
    ])

    text_value = response['output']['message']['content'][0]['text']
    
    return text_value

async def start_agent_flow(mortgage_application):
    example_output = {
        "application_id": "12345",
        "applicant_id": "A001",
        "customer_email": "test@gmail.com",
        "borrower_name": "John Doe",
        "income": 75000,
        "payslips":"s3_arn",
        "loan_amount": 250000,
        "property_address": "123 Demo Road",
        "property_state": "California",
        "property_value": 300000,
        "employment_status": "Full-time",
        "credit_score": 710,
        "credit_utilization": 32.5,
        "debt_to_income_ratio": 36.5,
        "fraud_risk_score": 72.0,
        "loan_stack_risk": "High",
        "risk_category": "Moderate",
        "agent_reasoning": "Applicant has a good credit score but high credit utilization. Potential loan stacking risk detected.",
        "application_ts": 1745612643302
    }

    prompt = f"""
        Using the applicant's financial profile and payment history, generate a Credit and Fraud Risk Assessment Report
        that evaluates the applicant's creditworthiness and flags any potential fraud indicators. This report will help
        River Banking make informed, responsible mortgage approval decisions that balance risk with opportunity.

        Key Responsibilities:
        - Review the applicant's payment history, income level, credit score, and overall credit utilization to determine credit risk.
        - Use credit report indicators like open accounts, recent defaults, and debt-to-income ratio to assess stability and lending reliability.
        - Run a fraud risk analysis using the dedicated Fraud Risk Assessment tool to identify anomalies or potential red flags.
        - Combine insights from creditworthiness and fraud detection to form a holistic risk profile for underwriting.
        - Flag any inconsistencies or indicators of identity manipulation, falsified documentation, or suspicious financial behavior.
        - Err on the side of giving the applicant a loan. Only deny if the application is particulary bad.

        Use dedicated tools to assess credit and fraud risk:
        - Fraud Risk Assessment Tool - Returns a JSON-formatted analysis that detects fraud risk based on provided applicant data and behavioral patterns.

        Ensure the output is concise, structured, and useful for downstream decision automation.

        Applicant's Mortgage Application and Payment History:
        {mortgage_application}

        Expected Output - Credit and Fraud Risk Assessment Report: The report should be formatted in JSON and include:
        The report should be formatted in JSON and must include the following fields populated based on the analysis:

        application_id, applicant_id, customer_email, borrower_name, income, payslips, loan_amount, property_address,
        property_state, property_value, employment_status, credit_score, credit_utilization,
        debt_to_income_ratio - These should be carried over unchanged from the input.
        fraud_risk_score - A numeric fraud risk score (e.g., 0-100) returned from the Fraud Risk Assessment tool.
        loan_stack_risk - A categorical risk level indicating the likelihood of concurrent or undisclosed loans (e.g., "Low", "Moderate", "High").
        risk_category - An overall credit and fraud risk classification (e.g., "Low", "Moderate", "High").
        agent_reasoning - A brief summary explaining the decision rationale, covering key credit or fraud-related findings.
        application_ts - From the original mortgage application.

        Output Format
            The output must be strictly formatted as JSON, with no additional text, commentary, or explanation.
            Make sure float values have decimal points for precision, e.g. 0 should be 0.0.

            The JSON should exactly match the following structure:
            {json.dumps(example_output)}
            
            Failure to strictly follow this format will result in incorrect output.
      """

    
    messages = think(prompt, tools)
    
    
    content = messages[-1]['content'][0]['text']

    json_match = re.search(r"\{.*\}", content, re.DOTALL)

    if json_match:
        fraud_risk_assessment = json_match.group()

        
        value_for_kakfa = json.loads(fraud_risk_assessment)
        
        print(f"value for kafka {value_for_kakfa}")

        # Write a message to the agent messages topic with the output from this agent
        produce(AGENT_OUTPUT_TOPIC, value_for_kakfa)
        
        print(f"wrote to kafka")
        
def lambda_handler(event, context):
    
    for record in event:

        payload = record.get("payload", {})
        mortgage_application = payload.get("value")

        if mortgage_application:
            try:
                print("Processing mortgage application:")
                print(mortgage_application)
                
                asyncio.run(start_agent_flow(mortgage_application))
            except Exception as e:
                logger.error(f"Failed to decode value: {e}")

    return {
        'statusCode': 200,
        'body': 'Processed successfully'
    }