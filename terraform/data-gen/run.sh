#!/usr/bin/env bash

set -e

docker run \
       --rm \
       --env-file license.env \
       --net=host \
       -v $(pwd)/root.json:/home/root.json \
       -v $(pwd)/generators:/home/generators \
       -v $(pwd)/connections:/home/connections \
       shadowtraffic/shadowtraffic:1.0.8 \
       --config /home/root.json