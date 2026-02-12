#!/bin/bash
set -e

WIDGET_ID="com.peterduffy.apiusage"
OLD_WIDGET_IDS=(
    "com.github.api-usage-widget"
    "org.kde.plasma.claudeusage"
)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
BACKEND_DIR="$HOME/.local/share/api-dashboard"
SERVICE_NAME="api-dashboard"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

echo "=== API Usage Dashboard Installer ==="

# Check dependencies
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found"
    exit 1
fi

# Remove old widget installations
for old_id in "${OLD_WIDGET_IDS[@]}"; do
    OLD_DIR="$HOME/.local/share/plasma/plasmoids/$old_id"
    if [ -d "$OLD_DIR" ]; then
        echo "Removing old widget ($old_id)..."
        rm -rf "$OLD_DIR"
    fi
done

# Stop old services
for old_svc in "claude-usage-backend"; do
    if systemctl --user is-active "$old_svc" &>/dev/null; then
        echo "Stopping old service: $old_svc"
        systemctl --user stop "$old_svc" 2>/dev/null || true
        systemctl --user disable "$old_svc" 2>/dev/null || true
    fi
done

# Install backend
echo "Installing backend to $BACKEND_DIR..."
mkdir -p "$BACKEND_DIR"
cp "$SCRIPT_DIR/backend/api_dashboard_daemon.py" "$BACKEND_DIR/"
cp "$SCRIPT_DIR/backend/requirements.txt" "$BACKEND_DIR/"

# Create venv and install deps
VENV_DIR="$BACKEND_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi
echo "Installing Python dependencies..."
"$VENV_DIR/bin/pip" install -q -r "$BACKEND_DIR/requirements.txt"

# Install systemd service
echo "Installing systemd service..."
mkdir -p "$(dirname "$SERVICE_FILE")"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=API Usage Dashboard Backend
After=network.target

[Service]
Type=simple
ExecStart=$VENV_DIR/bin/python $BACKEND_DIR/api_dashboard_daemon.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

# Install plasmoid
echo "Installing widget to $PLASMOID_DIR..."
mkdir -p "$PLASMOID_DIR"
cp -r "$SCRIPT_DIR/package/"* "$PLASMOID_DIR/"

echo ""
echo "=== Installation complete ==="
echo "Backend service: systemctl --user status $SERVICE_NAME"
echo "Add the 'API Usage Dashboard' widget to your panel."
echo ""
echo "To set API keys via keyring:"
echo "  python3 -c \"import keyring; keyring.set_password('api-dashboard', 'firecrawl', 'YOUR_KEY')\""
echo "  python3 -c \"import keyring; keyring.set_password('api-dashboard', 'serpapi', 'YOUR_KEY')\""
echo ""
echo "Or configure keys in the widget settings (right-click > Configure > Services)."
echo ""
echo "Restart Plasma to load the widget: systemctl --user restart plasma-plasmashell"
