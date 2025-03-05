#!/bin/bash
# Script for auto port escalation
# Only runs when AUTO_PORT_ESCALATE=true in .env.config

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utilities for logging if available
if [ -f "$SCRIPT_DIR/deployment-utils.sh" ]; then
  source "$SCRIPT_DIR/deployment-utils.sh"
else
  # Fallback logging
  log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  }
fi

# Config file path (passed as argument or use default)
ENV_CONFIG_PATH="${1:-$PROJECT_ROOT/config/.env.deploy}"

log "Auto port escalation: Checking configuration"

# Load environment variables from the env file
if [ -f "$ENV_CONFIG_PATH" ]; then
  # Extract AUTO_PORT_ESCALATE setting
  AUTO_PORT_ESCALATE=$(grep -oP '^AUTO_PORT_ESCALATE=\K.*' "$ENV_CONFIG_PATH" | tr -d '"' | tr -d "'")
  
  # Extract PORT value
  PORT=$(grep -oP '^PORT=\K\d+' "$ENV_CONFIG_PATH" || echo "")
  
  # Extract HOST value
  HOST=$(grep -oP '^HOST=\K[0-9.]+' "$ENV_CONFIG_PATH" || echo "0.0.0.0")
  
  # Extract port range 
  PORT_RANGE_START=$(grep -oP '^PORT_RANGE_START=\K\d+' "$ENV_CONFIG_PATH" || echo "$((PORT + 100))")
  PORT_RANGE_END=$(grep -oP '^PORT_RANGE_END=\K\d+' "$ENV_CONFIG_PATH" || echo "$((PORT + 200))")
else
  log "Environment file not found at $ENV_CONFIG_PATH"
  exit 1
fi

## ------------ Port Escalation Logic ------------ ##

check_port_comprehensive() {
  local port=$1
  local host=${2:-"0.0.0.0"}
  local in_use=false
  
  # Check 1: System-level port check with netstat/ss
  if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q "${host}:${port}" || netstat -tuln | grep -q ":${port} "; then
      log "Port ${port} is in use according to netstat"
      in_use=true
    fi
  elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q "${host}:${port}" || ss -tuln | grep -q ":${port} "; then
      log "Port ${port} is in use according to ss"
      in_use=true
    fi
  fi
  
  # Check 2: Docker-specific check
  if command -v docker &> /dev/null; then
    if docker ps --format '{{.Names}}:{{.Ports}}' | grep -E ":${port}(-|->)" > /dev/null; then
      CONTAINER_USING_PORT=$(docker ps --format '{{.Names}}:{{.Ports}}' | grep -E ":${port}(-|->)" | cut -d ':' -f1 | head -n1)
      log "Port ${port} is in use by Docker container: ${CONTAINER_USING_PORT}"
      in_use=true
    fi
  fi
  
  # Check 3: lsof if available (more detailed)
  if command -v lsof &> /dev/null; then
    if lsof -i:${port} > /dev/null 2>&1; then
      log "Port ${port} is in use according to lsof"
      in_use=true
    fi
  fi
  
  if [ "$in_use" = true ]; then
    return 1  # Port is in use
  else
    return 0  # Port is available
  fi
}

## ------------ Main Script ------------ ##

# Skip if not enabled or port not found
if [ "${AUTO_PORT_ESCALATE:-false}" != "true" ]; then
  log "Auto port escalation is disabled (AUTO_PORT_ESCALATE != true)"
  exit 0
fi

if [ -z "$PORT" ]; then
  log "Could not determine PORT from $ENV_CONFIG_PATH"
  exit 1
fi

## ------------ Port Availability ------------ ##

log "Auto port escalation: Checking if port $PORT is available on $HOST"
log "Using port range $PORT_RANGE_START-$PORT_RANGE_END"


# Check if current port is available using comprehensive check
if check_port_comprehensive "$PORT" "$HOST"; then
  log "Port $PORT is available, no escalation needed"
  exit 0
else
  log "Port $PORT is in use, searching for available port..."
fi

## ------------ Port Escalation ------------ ##

# Find next available port
log "Searching for available port in range $PORT_RANGE_START-$PORT_RANGE_END..."
NEW_PORT=$PORT_RANGE_START
PORT_FOUND=false

# Search through the configured range
while [ $NEW_PORT -le $PORT_RANGE_END ]; do
  # Skip the current port as we already know it's in use
  if [ "$NEW_PORT" = "$PORT" ]; then
    NEW_PORT=$((NEW_PORT + 1))
    continue
  fi
  
  # Check if new port is available
  if check_port_comprehensive "$NEW_PORT" "$HOST"; then
    PORT_FOUND=true
    break
  fi
  
  NEW_PORT=$((NEW_PORT + 1))
done


## ------------ Update Config ------------ ##
# Update config if available port found
if [ "$PORT_FOUND" = true ]; then
  log "Found available port: $NEW_PORT (original was $PORT)"
  
  # Update the config file
  sed -i "s/^PORT=$PORT/PORT=$NEW_PORT/" "$ENV_CONFIG_PATH"
  
  # Create a record of the port change
  DEPLOYMENT_ID=$(grep -oP '^DEPLOYMENT_ID=\K.*' "$ENV_CONFIG_PATH" || echo "unknown")
  echo "$(date +'%Y-%m-%d %H:%M:%S') | Port auto-escalated from $PORT to $NEW_PORT for deployment ID: $DEPLOYMENT_ID" >> "$PROJECT_ROOT/port_changes.log"
  
  # Return success
  exit 0
else
  log "Error: Could not find available port in range $PORT_RANGE_START-$PORT_RANGE_END"
  log "All ports in the configured range are in use"
  exit 1
fi
