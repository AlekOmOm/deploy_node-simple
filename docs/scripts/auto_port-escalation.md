
# Auto Port Escalation 

## Overview

feature for
- auto escalation of ports using 
    - config of 
        - port ranges
        - auto escalation flag
    - script for 
        - checking port availability
        - escalating to next available port
        - logging port changes

## relevant files

### 1. Configuration in `.env.config`

```bash
# Auto-Port Escalation (Optional)
AUTO_PORT_ESCALATE=true  # Set to false to disable automatic port escalation
# prod port range
PROD_PORT_RANGE_START=8400   
PROD_PORT_RANGE_END=8499      
# dev port range
DEV_PORT_RANGE_START=3400    
DEV_PORT_RANGE_END=3499
```

### 2. auto_port-escalation script

1. Reads all necessary values from the env file
2. Uses the exact port range specified (not incremental)
3. Starts the search at `PORT_RANGE_START` (not at the current port)
4. Includes better logging and error handling
5. Records port changes with the deployment ID for tracking

### 3. integration in deploy.sh (extended feature)

1. Loads env variables
2. Checks if auto escalation is enabled
3. Runs the auto escalation script if enabled
4. Reloads env variables to get any updated PORT value
5. Proceeds with the deployment using the potentially new port

## Flow of Port Configuration

1. `.env.config` defines ranges per environment
2. `set-env.sh` outputs ranges based on branch
3. GitHub Actions writes these to `.env.deploy`
4. `deploy.sh` loads `.env.deploy`
5. If auto escalation is enabled, `auto_port-escalation.sh` runs
6. If the port is in use, a new port is selected from the range
7. `.env.deploy` is updated with the new port
8. `deploy.sh` reloads variables and uses the new port

## Benefits of this Approach

1. **Separation of concerns**: Each script has a clear responsibility
2. **Configuration-driven**: Feature is toggleable via configuration
3. **Branch-specific ranges**: Different ranges for dev/prod environments
4. **Graceful degradation**: Falls back to manual checks if utilities missing
5. **Comprehensive logging**: Records all port changes for auditing
6. **Deployment tracking**: Uses deployment ID for better monitoring

