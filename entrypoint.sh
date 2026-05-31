#!/bin/bash
set -e

# Start virtual display for Wine
Xvfb :99 -screen 0 1024x768x16 &
sleep 2

MODE="${1:-run}"

case "$MODE" in
  qr)
    echo "=== Generating QR Code ==="
    echo "Scan this QR code with WhatsApp on your phone"
    cd /app
    node ./dist/genQRCode.js
    ;;
  run)
    echo "=== Starting WA-Calls via Wine + Electron ==="
    cd /app
    wine /opt/electron/electron.exe --no-sandbox --disable-gpu ./dist/wavoip.js 2>&1
    ;;
  shell)
    exec /bin/bash
    ;;
  *)
    echo "Usage: docker run wavoip [qr|run|shell]"
    echo "  qr    - Generate QR code for WhatsApp auth"
    echo "  run   - Start the call service (default)"
    echo "  shell - Open a shell for debugging"
    ;;
esac
