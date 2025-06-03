# Use the AWS Lambda Python 3.12 base image
FROM public.ecr.aws/lambda/python:3.13

# Set working directory inside container
# WORKDIR /var/task

# Copy requirements.txt
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# Install dependencies into the image
RUN pip install -r requirements.txt

# Copy function code and other files
COPY credit_and_fraud_check.py ${LAMBDA_TASK_ROOT}
COPY publish_to_topic.py ${LAMBDA_TASK_ROOT}
COPY client.properties ${LAMBDA_TASK_ROOT}
# COPY .env ${LAMBDA_TASK_ROOT}

# Set the Lambda handler: <filename>.<function_name>
CMD ["credit_and_fraud_check.lambda_handler"]