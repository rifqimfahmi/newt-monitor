#!/bin/bash

###########################################
# Generic Tunnel Monitor
# Monitors a URL and restarts a container when it becomes unhealthy
# 
# This script is designed to be generic and work with any tunnel service
# (Newt, ngrok, Cloudflare Tunnel, etc.)
###########################################

set -e

# Configuration with sensible defaults
MONITOR_URL="${MONITOR_URL:-}"
CONTAINER_NAME="${CONTAINER_NAME:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
SUCCESS_CODES="${SUCCESS_CODES:-200,301,302}"
RESTART_DELAY="${RESTART_DELAY:-60}"
CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-5}"
MAX_TIMEOUT="${MAX_TIMEOUT:-10}"
RETRY_COUNT="${RETRY_COUNT:-3}"
MAX_RESTARTS_PER_HOUR="${MAX_RESTARTS_PER_HOUR:-0}"  # 0 = unlimited
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Internal state
RESTART_HISTORY_FILE="/tmp/restart_history.log"
SCRIPT_START_TIME=$(date +%s)

# Color codes for pretty logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###########################################
# Logging Functions
###########################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message" >&2
            ;;
        WARN)
            [[ "$LOG_LEVEL" != "ERROR" ]] && echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message"
            ;;
        INFO)
            [[ "$LOG_LEVEL" =~ ^(INFO|DEBUG)$ ]] && echo -e "${GREEN}[$timestamp] [INFO]${NC} $message"
            ;;
        DEBUG)
            [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "${BLUE}[$timestamp] [DEBUG]${NC} $message"
            ;;
    esac
}

###########################################
# Validation
###########################################

validate_config() {
    local errors=0
    
    if [[ -z "$MONITOR_URL" ]]; then
        log ERROR "MONITOR_URL is required but not set"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$CONTAINER_NAME" ]]; then
        log ERROR "CONTAINER_NAME is required but not set"
        errors=$((errors + 1))
    fi
    
    if ! command -v curl &> /dev/null; then
        log ERROR "curl is required but not installed"
        errors=$((errors + 1))
    fi
    
    if ! command -v docker &> /dev/null; then
        log ERROR "docker is required but not installed"
        errors=$((errors + 1))
    fi
    
    # Validate numeric values
    if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$CHECK_INTERVAL" -lt 5 ]]; then
        log ERROR "CHECK_INTERVAL must be a number >= 5"
        errors=$((errors + 1))
    fi
    
    if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [[ "$RETRY_COUNT" -lt 1 ]]; then
        log ERROR "RETRY_COUNT must be a number >= 1"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Configuration validation failed with $errors error(s)"
        exit 1
    fi
    
    log INFO "Configuration validated successfully"
}

###########################################
# Restart Control
###########################################

count_recent_restarts() {
    local hour_ago=$(($(date +%s) - 3600))
    
    if [[ ! -f "$RESTART_HISTORY_FILE" ]]; then
        echo 0
        return
    fi
    
    # Count restarts in the last hour
    local count=0
    while IFS= read -r timestamp; do
        if [[ "$timestamp" -ge "$hour_ago" ]]; then
            count=$((count + 1))
        fi
    done < "$RESTART_HISTORY_FILE"
    
    echo $count
}

record_restart() {
    echo "$(date +%s)" >> "$RESTART_HISTORY_FILE"
    
    # Clean up old entries (older than 1 hour)
    local hour_ago=$(($(date +%s) - 3600))
    if [[ -f "$RESTART_HISTORY_FILE" ]]; then
        grep -E "^[0-9]+$" "$RESTART_HISTORY_FILE" | \
        awk -v cutoff="$hour_ago" '$1 >= cutoff' > "${RESTART_HISTORY_FILE}.tmp" || true
        mv "${RESTART_HISTORY_FILE}.tmp" "$RESTART_HISTORY_FILE" 2>/dev/null || true
    fi
}

check_restart_limit() {
    # If MAX_RESTARTS_PER_HOUR is 0, unlimited restarts allowed
    if [[ "$MAX_RESTARTS_PER_HOUR" -eq 0 ]]; then
        return 0
    fi
    
    local recent_restarts=$(count_recent_restarts)
    
    if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
        log ERROR "Restart limit reached: $recent_restarts restarts in the last hour (max: $MAX_RESTARTS_PER_HOUR)"
        log ERROR "Possible restart loop detected. Please investigate manually."
        return 1
    fi
    
    return 0
}

###########################################
# Health Check
###########################################

check_health() {
    local url=$1
    local http_code
    
    log DEBUG "Checking health: $url"
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$CONNECTION_TIMEOUT" \
        --max-time "$MAX_TIMEOUT" \
        "$url" 2>/dev/null || echo "000")
    
    log DEBUG "HTTP response code: $http_code"
    
    # Check if the HTTP code is in the success codes list
    IFS=',' read -ra CODES <<< "$SUCCESS_CODES"
    for code in "${CODES[@]}"; do
        if [[ "$http_code" == "$code" ]]; then
            return 0
        fi
    done
    
    return 1
}

###########################################
# Container Management
###########################################

restart_container() {
    local container=$1
    
    log WARN "Attempting to restart container: $container"
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        log ERROR "Container '$container' not found"
        return 1
    fi
    
    # Restart the container
    if docker restart "$container" &>/dev/null; then
        log INFO "Successfully restarted container: $container"
        record_restart
        return 0
    else
        log ERROR "Failed to restart container: $container"
        return 1
    fi
}

###########################################
# Notifications
###########################################

send_notification() {
    local status=$1
    local message=$2
    
    if [[ -z "$NOTIFY_WEBHOOK" ]]; then
        return 0
    fi
    
    local payload=$(cat <<EOF
{
  "status": "$status",
  "message": "$message",
  "container": "$CONTAINER_NAME",
  "url": "$MONITOR_URL",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$(hostname)"
}
EOF
)
    
    log DEBUG "Sending notification to webhook"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$NOTIFY_WEBHOOK" &>/dev/null || \
        log WARN "Failed to send notification to webhook"
}

###########################################
# Main Monitor Loop
###########################################

monitor_loop() {
    local consecutive_failures=0
    local total_checks=0
    local total_restarts=0
    
    while true; do
        total_checks=$((total_checks + 1))
        
        if check_health "$MONITOR_URL"; then
            if [[ $consecutive_failures -gt 0 ]]; then
                log INFO "Service recovered after $consecutive_failures consecutive failures"
                send_notification "recovered" "Service is now healthy"
            else
                log INFO "Service is healthy (HTTP check passed)"
            fi
            consecutive_failures=0
        else
            consecutive_failures=$((consecutive_failures + 1))
            log WARN "Health check failed (attempt $consecutive_failures/$RETRY_COUNT)"
            
            if [[ $consecutive_failures -ge $RETRY_COUNT ]]; then
                log ERROR "Service is unhealthy after $consecutive_failures consecutive failures"
                
                if check_restart_limit; then
                    send_notification "unhealthy" "Service is down, attempting restart"
                    
                    if restart_container "$CONTAINER_NAME"; then
                        total_restarts=$((total_restarts + 1))
                        log INFO "Container restart initiated (total restarts: $total_restarts)"
                        log INFO "Waiting ${RESTART_DELAY}s for service to stabilize..."
                        sleep "$RESTART_DELAY"
                    else
                        send_notification "critical" "Failed to restart container"
                    fi
                else
                    send_notification "critical" "Restart limit exceeded - manual intervention required"
                    log ERROR "Restart limit exceeded. Pausing automatic restarts for safety."
                    sleep 300 # Wait 5 minutes before resuming checks
                fi
                
                consecutive_failures=0
            fi
        fi
        
        # Status update every 10 checks
        if [[ $((total_checks % 10)) -eq 0 ]]; then
            local uptime=$(($(date +%s) - SCRIPT_START_TIME))
            log DEBUG "Status: $total_checks checks performed, $total_restarts restarts, uptime: ${uptime}s"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

###########################################
# Graceful Shutdown
###########################################

cleanup() {
    log INFO "Received shutdown signal, cleaning up..."
    send_notification "stopped" "Monitor stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

###########################################
# Main Entry Point
###########################################

main() {
    log INFO "════════════════════════════════════════════════════════════"
    log INFO "  Generic Tunnel Monitor v1.0.1"
    log INFO "════════════════════════════════════════════════════════════"
    log INFO "Configuration:"
    log INFO "  URL to monitor: $MONITOR_URL"
    log INFO "  Container name: $CONTAINER_NAME"
    log INFO "  Check interval: ${CHECK_INTERVAL}s"
    log INFO "  Success codes: $SUCCESS_CODES"
    log INFO "  Retry count: $RETRY_COUNT"
    log INFO "  Max restarts/hour: $MAX_RESTARTS_PER_HOUR"
    log INFO "  Log level: $LOG_LEVEL"
    log INFO "════════════════════════════════════════════════════════════"
    
    validate_config
    
    log INFO "Starting monitoring loop..."
    monitor_loop
}

# Run main function
main
