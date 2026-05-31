FROM node:18-bookworm

# Install Wine, audio support, and mingw for stub DLL
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
      pulseaudio-utils \
      alsa-utils \
      gcc-mingw-w64-x86-64 \
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

WORKDIR /app

# Copy stub DLL source and compile it
COPY stub.c /tmp/stub.c
RUN mkdir -p /root/.wine/drive_c/windows/system32 && \
    x86_64-w64-mingw32-gcc -shared -o /root/.wine/drive_c/windows/system32/windows.devices.enumeration.dll \
        /tmp/stub.c -Wl,--export-all-symbols -lkernel32 -lntdll && \
    rm /tmp/stub.c

# Replace winedbg with a no-op as fallback safety
RUN mv /usr/lib/wine/x86_64-unix/winedbg.so /usr/lib/wine/x86_64-unix/winedbg.so.bak 2>/dev/null || true && \
    rm -f /root/.wine/drive_c/windows/system32/winedbg.exe 2>/dev/null || true && \
    echo '#!/bin/true' > /usr/bin/winedbg && chmod +x /usr/bin/winedbg

# Configure crash handling
RUN xvfb-run wine64 reg add "HKCU\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f 2>/dev/null || true && \
    xvfb-run wine64 reg add "HKCU\\Software\\Wine\\WineDbg" /v AutoCloseOnCrash /t REG_DWORD /d 1 /f 2>/dev/null || true

# Download Electron 12.2.3 for Windows x64 (NODE_MODULE_VERSION 87, required by wavoip.node)
RUN mkdir -p /opt/electron && \
    wget -L "https://registry.npmmirror.com/-/binary/electron/12.2.3/electron-v12.2.3-win32-x64.zip" \
         -O /tmp/electron.zip && \
    unzip -q /tmp/electron.zip -d /opt/electron && \
    rm -f /tmp/electron.zip

COPY bridge-server.js /app/
COPY wavoip.node /app/

ENV PATH="/usr/lib/wine:${PATH}"
ENV PORT=8080

EXPOSE ${PORT}

# Use our native stub DLL for device enumeration
ENV WINEDLLOVERRIDES="windows.devices.enumeration=n"
ENV WINEDEBUG="-all"

# Start Xvfb + PulseAudio + Electron via Wine
CMD ["sh", "-c", "rm -f /tmp/.X99-lock /tmp/.X11-unix/X99; Xvfb :99 -screen 0 1024x768x24 & pulseaudio --start --exit-idle-time=-1 2>/dev/null; sleep 2; ELECTRON_RUN_AS_NODE=1 wine64 /opt/electron/electron.exe /app/bridge-server.js"]
