from flask import Flask, render_template, request, jsonify
from confluent_kafka import Producer
from confluent_kafka.serialization import SerializationContext, MessageField
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
import json
import os
import uuid
import time
from datetime import datetime
from dotenv import load_dotenv
import random
import string

load_dotenv()

app = Flask(__name__)

# Avro schema definition
AVRO_SCHEMA = {
    "type": "record",
    "name": "MortgageApplication",
    "fields": [
        {"name": "application_id", "type": "string"},
        {"name": "customer_email", "type": "string"},
        {"name": "customer_name", "type": "string"},
        {"name": "applicant_id", "type": "string"},
        {"name": "income", "type": "long"},
        {"name": "loan_amount", "type": "long"},
        {"name": "property_value", "type": "long"},
        {"name": "property_address", "type": "string"},
        {"name": "property_state", "type": "string"},
        {"name": "payslips", "type": "string"},
        {"name": "employment_status", "type": "string"},
        {"name": "application_ts", "type": {
            "type": "long",
            "logicalType": "local-timestamp-millis"
        }}
    ]
}

# List of US states
US_STATES = [
    "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware", "Florida", "Georgia",
    "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland",
    "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey",
    "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina",
    "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
]

# Employment status options
EMPLOYMENT_STATUSES = ["EMPLOYED", "SELF_EMPLOYED", "RETIRED", "UNEMPLOYED"]

def generate_random_email(name):
    """Generate a random email based on the name"""
    domains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com"]
    name_parts = name.lower().split()
    username = "".join(name_parts) + str(random.randint(1000, 9999))
    return f"{username}@{random.choice(domains)}"

def generate_random_address():
    """Generate a random US address"""
    street_numbers = [str(random.randint(1, 9999))]
    street_names = ["Main", "Oak", "Pine", "Maple", "Cedar", "Elm", "Washington", "Lincoln", "Jefferson"]
    street_types = ["St", "Ave", "Blvd", "Rd", "Ln", "Dr"]
    return f"{random.choice(street_numbers)} {random.choice(street_names)} {random.choice(street_types)}"

def generate_random_payslips(applicant_id):
    """Generate payslip references using applicant ID in the format s3://riverbank-payslip-bucket/[a-zA-Z0-9._/-]+"""
    return f"s3://riverbank-payslip-bucket/{applicant_id}"

# Schema Registry configuration
schema_registry_conf = {
    'url': os.getenv('SCHEMA_REGISTRY_URL'),
    'basic.auth.user.info': f"{os.getenv('SCHEMA_REGISTRY_API_KEY')}:{os.getenv('SCHEMA_REGISTRY_API_SECRET')}"
}

# Create Schema Registry client
schema_registry_client = SchemaRegistryClient(schema_registry_conf)

# Create Avro serializer
avro_serializer = AvroSerializer(
    schema_registry_client,
    json.dumps(AVRO_SCHEMA),
    lambda obj, ctx: obj
)

# Kafka configuration
kafka_config = {
    'bootstrap.servers': os.getenv('KAFKA_BOOTSTRAP_SERVERS'),
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'PLAIN',
    'sasl.username': os.getenv('KAFKA_API_KEY'),
    'sasl.password': os.getenv('KAFKA_API_SECRET')
}

producer = Producer(kafka_config)

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/submit_application', methods=['POST'])
def submit_application():
    try:
        data = request.json
        
        # Validate required fields
        required_fields = ['name', 'property_value', 'loan_amount', 'annual_income']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        # Generate unique IDs
        application_id = str(uuid.uuid4())
        
        # Set applicant_id based on customer name
        customer_name = data['name'].strip()
        if customer_name.lower() == 'john doe':
            applicant_id = 'C-100000'
            random_employment_status = 'Full-employed'
        elif customer_name.lower() == 'omar soli':
            applicant_id = 'C-200000'
            random_employment_status = 'UNEMPLOYED'
        else:
            applicant_id = f'C-3{random.randint(10000, 99999)}'
            random_employment_status = random.choice(EMPLOYMENT_STATUSES)

        # Generate random values for the specified fields
        random_email = generate_random_email(data['name'])
        random_address = generate_random_address()
        random_state = random.choice(US_STATES)
        random_payslips = generate_random_payslips(applicant_id)

        # Prepare Avro record
        avro_record = {
            "application_id": application_id,
            "customer_email": random_email,
            "customer_name": data['name'],
            "applicant_id": applicant_id,
            "income": int(data['annual_income']),
            "loan_amount": int(data['loan_amount']),
            "property_value": int(data['property_value']),
            "property_address": random_address,
            "property_state": random_state,
            "payslips": random_payslips,
            "employment_status": random_employment_status,
            "application_ts": int(datetime.now().timestamp() * 1000)
        }

        # Serialize to Avro using the Schema Registry
        serialized_value = avro_serializer(
            avro_record,
            SerializationContext('mortgage_applications', MessageField.VALUE)
        )

        # Send to Kafka topic
        producer.produce(
            'mortgage_applications',
            key=random_email.encode('utf-8'),
            value=serialized_value
        )
        producer.flush()

        return jsonify({'message': 'Application submitted successfully'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000) 