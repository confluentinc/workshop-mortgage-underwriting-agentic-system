#!/bin/bash

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# Install system dependencies for confluent-kafka
export CFLAGS="-I$(brew --prefix librdkafka)/include"
export LDFLAGS="-L$(brew --prefix librdkafka)/lib"

# Install Python dependencies
pip install --no-cache-dir -r requirements.txt

# Run the Flask application
export FLASK_APP=app.py
export FLASK_ENV=development
flask run 