FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    wget curl gnupg2 software-properties-common \
    cabextract xvfb unzip p7zip-full \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Wine (stable)
RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js (Linux - for genQRCode and npm install)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Setup Wine prefix
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV DISPLAY=:99
ENV WINEDEBUG=-all

RUN Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    wineboot --init && \
    wineserver --wait || true

# Download Electron v12.0.0-beta.31 Windows x64
RUN wget -q -O /tmp/electron.zip \
    "https://github.com/electron/electron/releases/download/v12.0.0-beta.31/electron-v12.0.0-beta.31-win32-x64.zip" && \
    mkdir -p /opt/electron && \
    cd /opt/electron && unzip -q /tmp/electron.zip && \
    rm /tmp/electron.zip

WORKDIR /app

# Copy project files
COPY wa-calls/ /app/

# Install dependencies
RUN cd /app && npm install --ignore-scripts 2>/dev/null || true

# Copy wavoip.node
COPY wavoip.node /app/dist/wavoip.node

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

CMD ["/entrypoint.sh"]
