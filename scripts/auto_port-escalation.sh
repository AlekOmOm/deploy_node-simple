#!/bin/bash
# Script for auto port escalation
# script conditional on .env.config AUTO_PORT_ESCALATE=true


# Load env variables
## have been loaded by deployment-utils.sh

# Check if port is available
check_port_availability() {
  local port=$1
  local host=${2:-"0.0.0.0"}
  
  if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":$port " || netstat -tuln | grep -q " $host:$port "; then
      return 1  # Port IS in use
    fi
  elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":$port " || ss -tuln | grep -q " $host:$port "; then
      return 1  # Port IS in use
    fi
  else
    echo "Neither netstat nor ss is available"
    return 1  # Assume port is in use to be safe
  fi
  
  return 0  # Port is available
}


set_port_range() {
  local port_range=$1
  local port_range_regex='^[0-9]+-[0-9]+$'
  if [[ $port_range =~ $port_range_regex ]]; then
    IFS='-' read -r -a port_range_array <<< "$port_range"
    if [ "${#port_range_array[@]}" -eq 2 ]; then
      PORT_RANGE_START=${port_range_array[0]}
      PORT_RANGE_END=${port_range_array[1]}
    else
      echo "Invalid port range format: $port_range"
      return 1
    fi
  else
    echo "Invalid port range format: $port_range"
    return 1
  fi
}

get_port(){

    # Check if AUTO_PORT_ESCALATE is set to true
    if [ "$AUTO_PORT_ESCALATE" != "true" ]; then
      echo "AUTO_PORT_ESCALATE is not set to true, skipping port escalation"
      exit 0
    fi

    # Add after processing .env.deploy file
    if command -v netstat &> /dev/null || command -v ss &> /dev/null; then
      PORT=$(grep -oP '^PORT=\K\d+' "$PROJECT_ROOT/config/.env.deploy" || echo "3000")
      if ! check_port_availability "$PORT" "0.0.0.0"; then
        # Find next available port
        NEW_PORT=$PORT
        while ! check_port_availability "$NEW_PORT" "0.0.0.0" && [ "$NEW_PORT" -lt "$(($PORT + 20))" ]; do
          NEW_PORT=$((NEW_PORT + 1))
        done
        
        if [ "$NEW_PORT" != "$PORT" ]; then
          echo "Port $PORT is already in use, updating to use port $NEW_PORT"
          sed -i "s/^PORT=$PORT/PORT=$NEW_PORT/" "$PROJECT_ROOT/config/.env.deploy"
        fi
      fi
    fi
}
