/**
 * WaVoIP Bridge Server - Windows Native
 *
 * Roda direto no Windows com Node.js.
 * Expoe WebSocket server pra o client conectar.
 *
 * Uso: node bridge-server.js
 * Ou com ngrok: ngrok http 3500
 */

const http = require('http');
const crypto = require('crypto');

const log = (...args) => console.log('[bridge]', ...args);

let wavoip;
try {
  wavoip = require('./wavoip.node');
  log('wavoip.node loaded successfully');
} catch (err) {
  log('Failed to load wavoip.node:', err.message);
  log('Make sure wavoip.node is in the same folder as this script');
  process.exit(1);
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('WaVoIP Bridge Server - OK');
});

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

  log('Client connected');
  let initialized = false;

  function sendToClient(obj) {
    const json = JSON.stringify(obj);
    const buf = Buffer.from(json);
    const len = buf.length;
    let frame;
    if (len < 126) {
      frame = Buffer.alloc(2 + len);
      frame[0] = 0x81;
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
        for (let i = 0; i < payloadLen; i++) payload[i] ^= mask[i % 4];
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
    try { msg = JSON.parse(raw); } catch (e) { return; }
    log('Received:', msg.type);

    switch (msg.type) {
      case 'init':
        try {
          wavoip.init(msg.jid, true, true, true, false);
          wavoip.registerEventCallback((code, t, r) => {
            log('Event:', code);
            sendToClient({ type: 'event', code, t, r });
          });
          wavoip.registerSignalingXmppCallback((callId, from, node) => {
            log('XMPP:', node[0], 'to:', from);
            sendToClient({ type: 'xmpp', callId, from, node });
          });
          wavoip.registerLoggingCallback((...args) => {
            // silent
          });
          wavoip.updateNetworkMedium(2, 0);
          wavoip.setScreenSize(1920, 1080);
          wavoip.updateAudioVideoSwitch(true);
          try {
            wavoip.selectAudio('', '', function() {
              log('Audio device selected');
            });
          } catch (e) {
            log('selectAudio skipped:', e.message);
          }
          initialized = true;
          sendToClient({ type: 'ready' });
          log('WaVoIP initialized for', msg.jid);
        } catch (err) {
          sendToClient({ type: 'error', message: err.message });
        }
        break;

      case 'startCall':
        if (!initialized) { sendToClient({ type: 'error', message: 'Not initialized' }); return; }
        try {
          wavoip.startMD(msg.targetJid, msg.deviceJids || [], msg.callId, msg.isVideo || false);
          log('Call started to', msg.targetJid);
        } catch (err) {
          log('startCall error:', err.message);
          sendToClient({ type: 'error', message: err.message });
        }
        break;

      case 'handleSignaling':
        if (!initialized) return;
        try { wavoip.handleIncomingSignalingMsg(msg.data); }
        catch (err) { sendToClient({ type: 'error', message: 'handleSignaling: ' + err.message }); }
        break;

      case 'handleOffer':
        if (!initialized) return;
        try {
          wavoip.getNumParticipantsFromCallOffer(msg.data, (x) => {
            wavoip.handleIncomingSignalingOffer(msg.data, true, 5);
          });
        } catch (err) { sendToClient({ type: 'error', message: 'handleOffer: ' + err.message }); }
        break;

      case 'handleAck':
        if (!initialized) return;
        try { wavoip.handleIncomingSignalingAck(msg.data); }
        catch (err) { sendToClient({ type: 'error', message: 'handleAck: ' + err.message }); }
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
        log('Unknown:', msg.type);
    }
  }

  socket.on('close', () => log('Client disconnected'));
  socket.on('error', (err) => log('Socket error:', err.message));
});

const PORT = process.env.PORT || 3500;
server.listen(PORT, '0.0.0.0', () => {
  log(`Server listening on port ${PORT}`);
  log(`Connect via: ws://localhost:${PORT}`);
  log('');
  log('Para expor na internet, rode em outro terminal:');
  log('  npx localtunnel --port 3500');
  log('  ou: ngrok http 3500');
});
