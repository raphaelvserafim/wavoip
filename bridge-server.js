/**
 * WaVoIP Bridge Server
 *
 * Runs inside Wine (Windows Node.js) to load wavoip.node natively.
 * Exposes a WebSocket server that our main app connects to.
 *
 * Protocol: JSON messages over WebSocket
 *
 * From client -> bridge:
 *   { type: "init", jid: "5566..." }
 *   { type: "startCall", targetJid: "1437...", deviceJids: [...], callId: "...", isVideo: false }
 *   { type: "handleSignaling", data: {...} }
 *   { type: "handleOffer", data: {...} }
 *   { type: "handleAck", data: {...} }
 *   { type: "acceptCall", audio: true, video: false }
 *   { type: "endCall" }
 *
 * From bridge -> client:
 *   { type: "xmpp", callId: "...", from: "...", node: [...] }
 *   { type: "event", code: number, t: any, r: any }
 *   { type: "log", args: [...] }
 *   { type: "ready" }
 *   { type: "error", message: "..." }
 */

// Wine/Electron doesn't support stdio pipes (uv_pipe_open fails).
// We must override stdout/stderr BEFORE anything tries to use them,
// including internal Node.js error handlers that write to stderr.
const fs = require('fs');
const { Writable } = require('stream');

let logFd;
try {
  fs.writeSync(1, '');
  logFd = 1;
} catch (e) {
  try {
    logFd = fs.openSync('/app/bridge.log', 'a');
  } catch (e2) {
    logFd = null;
  }
}

const noop = new Writable({ write(chunk, enc, cb) { cb(); } });
const safeStream = logFd !== null
  ? new Writable({
      write(chunk, enc, cb) {
        try { fs.writeSync(logFd, chunk); } catch (e) { /* ignore */ }
        cb();
      }
    })
  : noop;

// Replace stdout and stderr with safe streams to prevent uv_pipe_open crashes
Object.defineProperty(process, 'stdout', { value: safeStream, configurable: true });
Object.defineProperty(process, 'stderr', { value: safeStream, configurable: true });

const http = require('http');
const net = require('net');

const log = (...args) => {
  try {
    fs.writeSync(logFd || 1, args.join(' ') + '\n');
  } catch (e) {
    // silently ignore
  }
};

let wavoip;
try {
  wavoip = require('./wavoip.node');
  log('[bridge] wavoip.node loaded successfully');
} catch (err) {
  log('[bridge] Failed to load wavoip.node:', err.message);
  process.exit(1);
}

// Simple WebSocket server (minimal implementation to avoid npm deps)
const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('WaVoIP Bridge Server');
});

const crypto = require('crypto');

server.on('upgrade', (req, socket, head) => {
  const key = req.headers['sec-websocket-key'];
  const acceptKey = crypto
    .createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`
  );

  log('[bridge] Client connected');

  let initialized = false;

  function sendToClient(obj) {
    const json = JSON.stringify(obj);
    const buf = Buffer.from(json);
    const len = buf.length;
    let frame;
    if (len < 126) {
      frame = Buffer.alloc(2 + len);
      frame[0] = 0x81; // text frame
      frame[1] = len;
      buf.copy(frame, 2);
    } else if (len < 65536) {
      frame = Buffer.alloc(4 + len);
      frame[0] = 0x81;
      frame[1] = 126;
      frame.writeUInt16BE(len, 2);
      buf.copy(frame, 4);
    } else {
      frame = Buffer.alloc(10 + len);
      frame[0] = 0x81;
      frame[1] = 127;
      frame.writeBigUInt64BE(BigInt(len), 2);
      buf.copy(frame, 10);
    }
    socket.write(frame);
  }

  // Parse WebSocket frames
  let buffer = Buffer.alloc(0);
  socket.on('data', (data) => {
    buffer = Buffer.concat([buffer, data]);

    while (buffer.length >= 2) {
      const secondByte = buffer[1];
      const masked = (secondByte & 0x80) !== 0;
      let payloadLen = secondByte & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (buffer.length < 4) return;
        payloadLen = buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (buffer.length < 10) return;
        payloadLen = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }

      if (masked) {
        if (buffer.length < offset + 4 + payloadLen) return;
        const mask = buffer.slice(offset, offset + 4);
        offset += 4;
        const payload = buffer.slice(offset, offset + payloadLen);
        for (let i = 0; i < payloadLen; i++) {
          payload[i] ^= mask[i % 4];
        }
        buffer = buffer.slice(offset + payloadLen);
        handleMessage(payload.toString('utf8'));
      } else {
        if (buffer.length < offset + payloadLen) return;
        const payload = buffer.slice(offset, offset + payloadLen);
        buffer = buffer.slice(offset + payloadLen);
        handleMessage(payload.toString('utf8'));
      }
    }
  });

  function handleMessage(raw) {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (e) {
      log('[bridge] Invalid JSON:', raw);
      return;
    }

    log('[bridge] Received:', msg.type);

    switch (msg.type) {
      case 'init':
        try {
          wavoip.init(msg.jid, true, true, true, false);
          wavoip.registerEventCallback((code, t, r) => {
            log('[wavoip event]', code, JSON.stringify(t), JSON.stringify(r));
            sendToClient({ type: 'event', code, t, r });
          });
          wavoip.registerSignalingXmppCallback((callId, from, node) => {
            sendToClient({ type: 'xmpp', callId, from, node });
          });
          wavoip.registerLoggingCallback((...args) => {
            log('[wavoip log]', JSON.stringify(args));
          });
          wavoip.updateNetworkMedium(2, 0);
          wavoip.setScreenSize(1920, 1080);
          wavoip.updateAudioVideoSwitch(true);

          // NOTE: Do NOT call selectAudio() or getAVDevices() here.
          // They crash Wine with a page fault because
          // Windows.Devices.Enumeration.DeviceInformation is not implemented.
          // wavoip works fine for signaling without real audio device selection.

          initialized = true;
          sendToClient({ type: 'ready' });
          log('[bridge] WaVoIP initialized for', msg.jid);
        } catch (err) {
          sendToClient({ type: 'error', message: err.message });
        }
        break;

      case 'startCall':
        if (!initialized) {
          sendToClient({ type: 'error', message: 'Not initialized' });
          return;
        }
        try {
          log('[bridge] startMD params:');
          log('[bridge]   targetJid:', msg.targetJid);
          log('[bridge]   deviceJids:', JSON.stringify(msg.deviceJids));
          log('[bridge]   callId:', msg.callId);
          log('[bridge]   isVideo:', msg.isVideo);

          // List all wavoip functions available
          log('[bridge] wavoip methods:', Object.keys(wavoip).join(', '));

          wavoip.startMD(
            msg.targetJid,
            msg.deviceJids || [],
            msg.callId,
            msg.isVideo || false
          );
          log('[bridge] Call started to', msg.targetJid);
        } catch (err) {
          log('[bridge] startCall error:', err.message, err.stack);
          sendToClient({ type: 'error', message: err.message });
        }
        break;

      case 'handleSignaling':
        if (!initialized) return;
        try {
          wavoip.handleIncomingSignalingMsg(msg.data);
        } catch (err) {
          sendToClient({ type: 'error', message: 'handleSignaling: ' + err.message });
        }
        break;

      case 'handleOffer':
        if (!initialized) return;
        try {
          wavoip.getNumParticipantsFromCallOffer(msg.data, (x) => {
            wavoip.handleIncomingSignalingOffer(msg.data, true, 5);
          });
        } catch (err) {
          sendToClient({ type: 'error', message: 'handleOffer: ' + err.message });
        }
        break;

      case 'handleAck':
        if (!initialized) return;
        try {
          wavoip.handleIncomingSignalingAck(msg.data);
        } catch (err) {
          sendToClient({ type: 'error', message: 'handleAck: ' + err.message });
        }
        break;

      case 'acceptCall':
        if (!initialized) return;
        wavoip.acceptCall(msg.audio !== false, msg.video || false);
        break;

      case 'endCall':
        if (!initialized) return;
        wavoip.end(true, '');
        break;

      default:
        log('[bridge] Unknown message type:', msg.type);
    }
  }

  socket.on('close', () => {
    log('[bridge] Client disconnected');
  });

  socket.on('error', (err) => {
    log('[bridge] Socket error:', err.message);
  });
});

const PORT = process.env.PORT || 3500;
server.listen(PORT, '0.0.0.0', () => {
  log(`[bridge] WaVoIP bridge server listening on port ${PORT}`);
});
