#!/bin/bash
# Setup script - run this to prepare the Docker build context

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WACALLS_DIR="$SCRIPT_DIR/../WA-Calls-Base"

echo "=== Preparing wavoip-docker build context ==="

# Copy WA-Calls-Base project
if [ -d "$WACALLS_DIR" ]; then
    echo "Copying WA-Calls-Base..."
    rm -rf "$SCRIPT_DIR/wa-calls"
    cp -r "$WACALLS_DIR" "$SCRIPT_DIR/wa-calls"
    # Remove node_modules to keep image smaller
    rm -rf "$SCRIPT_DIR/wa-calls/node_modules"
else
    echo "ERROR: WA-Calls-Base not found at $WACALLS_DIR"
    exit 1
fi

# Copy wavoip.node
if [ -f "$WACALLS_DIR/dist/wavoip.node" ]; then
    echo "Copying wavoip.node..."
    cp "$WACALLS_DIR/dist/wavoip.node" "$SCRIPT_DIR/wavoip.node"
else
    echo "ERROR: wavoip.node not found"
    exit 1
fi

echo ""
echo "=== Build context ready ==="
echo ""
echo "Now run on your Linux server:"
echo "  1. Copy this folder to the server:"
echo "     scp -r wavoip-docker user@server:/path/"
echo ""
echo "  2. Build the Docker image:"
echo "     cd /path/wavoip-docker"
echo "     docker build -t wavoip ."
echo ""
echo "  3. Generate QR code (first time):"
echo "     docker run -it --name wavoip -v wavoip-auth:/app/auth_info_baileys wavoip node /app/dist/genQRCode.js"
echo ""
echo "  4. Run the call service:"
echo "     docker run -it --name wavoip -v wavoip-auth:/app/auth_info_baileys wavoip"
echo ""
