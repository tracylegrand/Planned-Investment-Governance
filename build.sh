#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="$SCRIPT_DIR/config/standard.json"
API_PORT=$(jq -r '.api_port' "$CONFIG_FILE")
CACHE_DB=$(jq -r '.cache_db' "$CONFIG_FILE")

echo "=== Planned Investment Governance Build ==="
echo "Script directory: $SCRIPT_DIR"
echo "Config file: $CONFIG_FILE"
echo "API Port: $API_PORT"
echo "Cache DB: $CACHE_DB"

echo ""
echo "Building Swift application..."
swift build -c release

BUILD_DIR="$SCRIPT_DIR/.build/release"
if [ -f "$BUILD_DIR/PlannedInvestmentGovernance" ]; then
    echo "Build successful!"
    echo "Executable: $BUILD_DIR/PlannedInvestmentGovernance"
else
    echo "Build failed - executable not found"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "To run the application:"
echo "  1. Start the API server: python3 api_server.py"
echo "  2. Run the app: $BUILD_DIR/PlannedInvestmentGovernance"
echo ""
echo "Or run both together:"
echo "  python3 api_server.py & $BUILD_DIR/PlannedInvestmentGovernance"
