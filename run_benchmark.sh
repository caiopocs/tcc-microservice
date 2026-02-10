#!/usr/bin/env bash
set -euo pipefail

# Prevent MSYS/Git Bash from mangling Linux paths (e.g. /tests/ -> C:/Program Files/Git/tests/)
export MSYS_NO_PATHCONV=1

# -----------------------------------------------
# Defaults
# -----------------------------------------------
THREADS="${1:-50}"
RAMP_UP="${2:-10}"
DURATION="${3:-60}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RESULTS_DIR="$SCRIPT_DIR/results"
REPORT_INDEX="$RESULTS_DIR/html_report/index.html"

# Colors
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}  TCC Microservices Benchmark Runner${NC}"
echo -e "${CYAN}=====================================${NC}"
echo "  Threads:  $THREADS"
echo "  Ramp-Up:  ${RAMP_UP}s"
echo "  Duration: ${DURATION}s per group (x3 groups = $(( DURATION * 3 ))s total)"
echo -e "${CYAN}=====================================${NC}"
echo ""

# -----------------------------------------------
# 1. Clean up previous results
# -----------------------------------------------
echo -e "${YELLOW}[1/5] Cleaning previous results...${NC}"

if [ -d "$RESULTS_DIR" ]; then
    rm -rf "$RESULTS_DIR"
    echo "      Deleted existing results/ folder."
fi

mkdir -p "$RESULTS_DIR"
echo -e "${GREEN}      Created empty results/ folder.${NC}"

# -----------------------------------------------
# 2. Build and start infrastructure
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[2/5] Building and starting infrastructure...${NC}"

docker-compose up --build -d rabbitmq processing-service api-gateway

echo -e "${GREEN}      Containers started. Waiting for services to stabilize...${NC}"

# -----------------------------------------------
# 3. Wait for services to be healthy
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[3/5] Waiting for services to be ready...${NC}"

MAX_RETRIES=30
RETRY_COUNT=0
READY=false

while [ "$READY" = false ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:5000/swagger/index.html" 2>/dev/null || true)

    if [ "$HTTP_CODE" = "200" ]; then
        READY=true
    else
        echo -e "${GRAY}      Attempt $RETRY_COUNT/$MAX_RETRIES - API Gateway not ready yet, retrying in 3s...${NC}"
        sleep 3
    fi
done

if [ "$READY" = false ]; then
    echo -e "${RED}ERROR: API Gateway did not become ready in time.${NC}"
    echo -e "${RED}       Check logs with: docker-compose logs api-gateway${NC}"
    exit 1
fi

echo -e "${GREEN}      All services are UP and responding.${NC}"

# -----------------------------------------------
# 4. Run JMeter benchmark
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[4/5] Running JMeter benchmark...${NC}"
echo -e "${GRAY}      This will take ~$(( DURATION * 3 )) seconds (3 groups x ${DURATION}s each).${NC}"
echo ""

docker-compose --profile benchmark run --rm \
    jmeter \
    -n \
    -t /tests/tcc_benchmark.jmx \
    -JBASE_HOST=api-gateway \
    -JBASE_PORT=5000 \
    "-JTHREADS=$THREADS" \
    "-JRAMP_UP=$RAMP_UP" \
    "-JDURATION=$DURATION" \
    -l /results/raw_results.jtl \
    -e -o /results/html_report || {
    echo ""
    echo -e "${RED}WARNING: JMeter exited with a non-zero code.${NC}"
    echo -e "${RED}         Check results/raw_results.jtl for details.${NC}"
}

# -----------------------------------------------
# 5. Open report
# -----------------------------------------------
echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Benchmark Finished!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

if [ -f "$REPORT_INDEX" ]; then
    echo -e "${YELLOW}[5/5] Opening HTML report in browser...${NC}"

    # Cross-platform open
    if command -v xdg-open &>/dev/null; then
        xdg-open "$REPORT_INDEX"
    elif command -v open &>/dev/null; then
        open "$REPORT_INDEX"
    else
        echo "      Could not detect browser opener. Open manually:"
        echo "      $REPORT_INDEX"
    fi

    echo ""
    echo -e "${CYAN}Results saved at:${NC}"
    echo "  Raw data:    results/raw_results.jtl"
    echo "  HTML report: results/html_report/index.html"
else
    echo -e "${RED}[5/5] HTML report not found at: $REPORT_INDEX${NC}"
    echo -e "${RED}      Check JMeter output above for errors.${NC}"
fi

echo ""
