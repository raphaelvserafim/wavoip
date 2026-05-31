FROM node:18-bookworm

# Install Wine and audio support
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      wine64 \
      wine32 \
      wget \
      unzip \
      xvfb \
      ca-certificates \
      pulseaudio \
      alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# Set Wine to 64-bit mode
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
ENV DISPLAY=:99

# Initialize Wine prefix and set Windows 10 mode
RUN xvfb-run wineboot --init 2>/dev/null || true && \
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuildNumber /t REG_SZ /d 19041 /f 2>/dev/null || true && \
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion /t REG_SZ /d 6.3 /f 2>/dev/null || true && \
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v ProductName /t REG_SZ /d "Windows 10 Pro" /f 2>/dev/null || true

# Download Electron 12.2.3 for Windows x64 (NODE_MODULE_VERSION 87, required by wavoip.node)
RUN mkdir -p /opt/electron && \
    wget -L "https://registry.npmmirror.com/-/binary/electron/12.2.3/electron-v12.2.3-win32-x64.zip" \
         -O /tmp/electron.zip && \
    unzip -q /tmp/electron.zip -d /opt/electron && \
    rm -f /tmp/electron.zip

WORKDIR /app

COPY bridge-server.js /app/
COPY wavoip.node /app/

ENV PATH="/usr/lib/wine:${PATH}"
ENV PORT=3500

EXPOSE ${PORT}

# Start Xvfb + PulseAudio + Electron via Wine
CMD ["sh", "-c", "Xvfb :99 -screen 0 1024x768x24 & pulseaudio --start --exit-idle-time=-1 2>/dev/null; sleep 2; ELECTRON_RUN_AS_NODE=1 /usr/lib/wine/wine64 /opt/electron/electron.exe /app/bridge-server.js"]
