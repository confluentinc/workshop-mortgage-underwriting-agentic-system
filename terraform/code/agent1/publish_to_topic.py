from confluent_kafka import Producer
import json
from pathlib import Path
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Get the path to the root directory
root_dir = Path(__file__).resolve().parent.parent

properties_file = "client.properties"

def read_config():
  # reads the client configuration from client.properties
  # and returns it as a key-value map
  config = {}
  with open(properties_file) as fh:
    for line in fh:
      line = line.strip()
      if len(line) != 0 and line[0] != "#":
        parameter, value = line.strip().split('=', 1)
        config[parameter] = value.strip()
  return config

def produce(topic, data):
  # creates a new producer instance
  producer = Producer(read_config())
  
  logger.info(topic)
  logger.info(data)

  # produces a sample message
  producer.produce(topic, value=json.dumps(data))

  # send any outstanding or buffered messages to the Kafka broker
  producer.flush()