#!/bin/bash
set -e

WIDGET_ID="com.peterduffy.apiusage"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
BACKEND_DIR="$HOME/.local/share/api-dashboard"
SERVICE_NAME="api-dashboard"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

echo "=== API Usage Dashboard Uninstaller ==="

# Stop and disable service
if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
    echo "Stopping backend service..."
    systemctl --user stop "$SERVICE_NAME"
fi
if [ -f "$SERVICE_FILE" ]; then
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
fi

# Remove backend
if [ -d "$BACKEND_DIR" ]; then
    echo "Removing backend from $BACKEND_DIR..."
    rm -rf "$BACKEND_DIR"
fi

# Remove widget
if [ -d "$PLASMOID_DIR" ]; then
    echo "Removing widget from $PLASMOID_DIR..."
    rm -rf "$PLASMOID_DIR"
fi

echo "API Usage Dashboard uninstalled."
echo "Restart Plasma to complete removal: systemctl --user restart plasma-plasmashell"
