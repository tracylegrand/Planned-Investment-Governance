#!/bin/bash
# Build and deploy Investment Governance app
# Usage: ./build.sh [--no-launch]

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${PROJECT_DIR}/config/standard.json"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

# Parse config
APP_NAME=$(jq -r '.app_name' "$CONFIG_FILE")
BUNDLE_ID=$(jq -r '.bundle_id' "$CONFIG_FILE")
VERSION=$(jq -r '.version' "$CONFIG_FILE")
BUILD_NUMBER=$(jq -r '.build_number' "$CONFIG_FILE")
ICON=$(jq -r '.icon' "$CONFIG_FILE")
API_PORT=$(jq -r '.api_port' "$CONFIG_FILE")
CACHE_DB=$(jq -r '.cache_db' "$CONFIG_FILE")

APP_PATH="/Applications/${APP_NAME}.app"
INFO_PLIST_TEMPLATE="${PROJECT_DIR}/Info.plist.template"

echo "=========================================="
echo "Building: $APP_NAME v$VERSION"
echo "API Port: $API_PORT"
echo "=========================================="

# Generate Info.plist from template
GENERATED_PLIST="${PROJECT_DIR}/Info.plist"
sed -e "s/\${APP_NAME}/${APP_NAME}/g" \
    -e "s/\${BUNDLE_ID}/${BUNDLE_ID}/g" \
    -e "s/\${VERSION}/${VERSION}/g" \
    -e "s/\${BUILD_NUMBER}/${BUILD_NUMBER}/g" \
    -e "s/\${ICON}/${ICON}/g" \
    "$INFO_PLIST_TEMPLATE" > "$GENERATED_PLIST"

echo "Generated Info.plist"

# Build release
echo "Compiling Swift..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -10

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Kill existing app
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy executable
cp "${PROJECT_DIR}/.build/release/PlannedInvestmentGovernance" "$APP_PATH/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "$GENERATED_PLIST" "$APP_PATH/Contents/"

# Copy icon
ICON_FILE="${PROJECT_DIR}/Resources/${ICON}.icns"
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_PATH/Contents/Resources/"
    echo "Copied icon: $ICON_FILE"
else
    echo "Warning: Icon file not found: $ICON_FILE"
fi

# Generate runtime config
cat > "$APP_PATH/Contents/Resources/runtime_config.json" << EOF
{
    "api_port": $API_PORT,
    "cache_db": "$CACHE_DB",
    "version": "$VERSION"
}
EOF

# Copy api_server.py and config to app bundle for embedded server
cp "${PROJECT_DIR}/api_server.py" "$APP_PATH/Contents/Resources/"
mkdir -p "$APP_PATH/Contents/Resources/config"
cp "${PROJECT_DIR}/config/standard.json" "$APP_PATH/Contents/Resources/config/"

echo "=========================================="
echo "Installed: $APP_PATH"
echo "Version: $VERSION (Build $BUILD_NUMBER)"
echo "=========================================="

# Launch app
if [ "$1" != "--no-launch" ]; then
    open "$APP_PATH"
    echo "App launched"
fi
