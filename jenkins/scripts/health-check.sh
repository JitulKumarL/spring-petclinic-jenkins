#!/usr/bin/env bash
#
# Health check script for smoke testing
# Polls URL until success or timeout
# Usage: ./health-check.sh --url <url> [--timeout 120] [--interval 5]
#

set -euo pipefail

# Defaults
URL=""
TIMEOUT=120
INTERVAL=5

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            URL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$URL" ]]; then
    echo "Error: --url is required (e.g., http://localhost:8080/actuator/health)"
    exit 1
fi

echo "=== Health Check ==="
echo "URL: ${URL}"
echo "Timeout: ${TIMEOUT}s, Interval: ${INTERVAL}s"

elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    if curl -sf "${URL}" > /dev/null 2>&1; then
        echo "Health check PASSED at ${elapsed}s"
        response=$(curl -s "${URL}")
        echo "Response: ${response}"
        exit 0
    fi
    echo "Waiting for service... (${elapsed}s/${TIMEOUT}s)"
    sleep "${INTERVAL}"
    elapsed=$((elapsed + INTERVAL))
done

echo "Health check FAILED - Service did not become healthy within ${TIMEOUT}s"
exit 1
