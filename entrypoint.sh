#!/bin/bash

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
PID_FILE="/run/haproxy/haproxy.pid"

haproxy -f $CONFIG_FILE -p $PID_FILE &
HAPROXY_PID=$!

reload_haproxy() {
  if haproxy -f $CONFIG_FILE -c; then
    haproxy -f $CONFIG_FILE -p $PID_FILE -sf $(cat $PID_FILE)
  fi
}

LAST_HASH=""
while true; do
  sleep 5  # Adjust polling interval
  CURRENT_HASH=$(sha256sum $CONFIG_FILE | awk '{print $1}')
  if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
    reload_haproxy
    LAST_HASH=$CURRENT_HASH
  fi
done