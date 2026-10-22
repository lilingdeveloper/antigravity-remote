const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const zlib = require('zlib');
const child_process = require('child_process');
const { AntigravityDiscovery } = require('./discovery');
const { AntigravityRpcClient } = require('./rpc-client');
const { TailscaleAndTunnelManager } = require('./tailscale-tunnel');

const PORT = Number(process.env.PORT || 8789);
const EXPLICIT_HOST = process.env.HOST ? process.env.HOST.trim() : '';
const HOST = EXPLICIT_HOST || '127.0.0.1';
const CONFIG_PATH = path.join(os.homedir(), '.gemini', 'antigravity', 'remote_control_config.json');

function loadOrCreateConfig() {
  const defaultRequireAuth = process.env.REQUIRE_AUTH !== 'false';
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
      if (cfg && cfg.accessToken) {
        cfg.requireAuth = defaultRequireAuth;
        try {
          fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf-8');
        } catch (_) {}
        return cfg;
      }
    }
  } catch (_) {}
  const cfg = {
    accessToken: crypto.randomBytes(16).toString('hex'),
    requireAuth: defaultRequireAuth,
    createdAt: new Date().toISOString()
  };
  try {
    fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf-8');
  } catch (_) {}
  return cfg;
}

const config = loadOrCreateConfig();
const discovery = new AntigravityDiscovery();
const rpcClient = new AntigravityRpcClient(discovery);
const netManager = new TailscaleAndTunnelManager({ port: PORT });
netManager.startWatcher(10000);

// MIME 类型映射
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

function sendJson(res, statusCode, data, req = null) {
  const body = Buffer.from(JSON.stringify(data), 'utf-8');
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Access-Token, If-None-Match',
    'Cache-Control': 'no-cache'
  };

  if (statusCode === 200) {
    const etag = 'W/"' + crypto.createHash('sha1').update(body).digest('hex').slice(0, 16) + '"';
    headers['ETag'] = etag;

    if (req && req.method === 'GET' && req.headers && req.headers['if-none-match'] === etag) {
      res.writeHead(304, headers);
      res.end();
      return;
    }
  }

  const acceptEncoding = String((req && req.headers && req.headers['accept-encoding']) || (req ? '' : 'gzip'));
  if (body.length > 1024 && acceptEncoding.includes('gzip')) {
    try {
      const gzipped = zlib.gzipSync(body);
      headers['Content-Encoding'] = 'gzip';
      res.writeHead(statusCode, headers);
      res.end(gzipped);
      return;
    } catch (_) {}
  }

  res.writeHead(statusCode, headers);
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf-8');
      if (!raw.trim()) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(new Error('无效的 JSON 请求体'));
      }
    });
    req.on('error', reject);
  });
}

function checkAuth(req, urlObj) {
  if (!config.requireAuth) return true;
  const authHeader = req.headers['authorization'] || '';
  const tokenHeader = req.headers['x-access-token'] || '';
  const queryToken = urlObj.searchParams.get('token') || '';
  const bearer = authHeader.replace(/^Bearer\s+/i, '').trim();
  return (
    bearer === config.accessToken ||
    tokenHeader === config.accessToken ||
    queryToken === config.accessToken
  );
}

function isLoopbackAddress(addr) {
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

// SSE 实时订阅客户端集合
const sseClients = new Set();

function broadcastEvent(eventType, payload) {
  const frame = `event: ${eventType}\ndata: ${JSON.stringify(payload)}\n\n`;
  for (const client of sseClients) {
    try {
      client.res.write(frame);
    } catch (_) {
      sseClients.delete(client);
    }
  }
}

// 后台轮询与实时状态推送器 (当有客户端连接时每 1.2s 推送增量状态)
let lastConversationsSignature = '';
const lastDetailSignatureByCascade = new Map();
let pollLoopRunning = false;

async function triggerPushForCascade(cid) {
  if (!cid) return;
  try {
    const detail = await rpcClient.getConversationDetail(cid);
    const sig = JSON.stringify({
      s: detail.stepCount,
      g: detail.isGenerating,
      mLen: (detail.messages || []).length,
      lastId: detail.messages?.[detail.messages.length - 1]?.id,
      lastLen: (detail.messages?.[detail.messages.length - 1]?.text || '').length,
      lastThinkLen: (detail.messages?.[detail.messages.length - 1]?.thinking || '').length,
      qLen: (detail.queuedMessages || []).length,
      pIdx: detail.pendingInteraction?.stepIndex
    });
    lastDetailSignatureByCascade.set(cid, sig);
    const frame = `event: conversation_update\ndata: ${JSON.stringify(detail)}\n\n`;
    const msg = JSON.stringify({ type: 'conversation_update', data: detail });

    for (const c of sseClients) {
      if (c.cascadeId === cid && c.lastDetailSig !== sig) {
        c.lastDetailSig = sig;
        try {
          c.res.write(frame);
        } catch (_) {
          sseClients.delete(c);
        }
      }
    }
    if (wss) {
      for (const ws of wss.clients) {
        if (ws.readyState === 1 && ws.cascadeId === cid && ws.lastDetailSig !== sig) {
          ws.lastDetailSig = sig;
          try {
            ws.send(msg);
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

async function startRealtimePushLoop() {
  if (pollLoopRunning) return;
  pollLoopRunning = true;
  while (pollLoopRunning) {
    await new Promise((r) => setTimeout(r, 1200));

    // 自动推进所有会话的排队消息队列 (当上一轮 AI 回复结束时自动按序发送下一条)
    try {
      await rpcClient.processMessageQueues();
    } catch (_) {}

    if (sseClients.size === 0 && (!wss || wss.clients.size === 0)) continue;

    try {
      // 收集正在被订阅的 cascadeId
      const watchedIds = new Set();
      for (const c of sseClients) {
        if (c.cascadeId) watchedIds.add(c.cascadeId);
      }
      if (wss) {
        for (const ws of wss.clients) {
          if (ws.cascadeId) watchedIds.add(ws.cascadeId);
        }
      }

      // 同步推送全局会话列表更新 (供手机端实时感知电脑端新增对话/标题变更/运行态)
      try {
        const listData = await rpcClient.listConversations();
        const convos = listData.conversations || [];
        const currentListSig = JSON.stringify(convos.map((c) => `${c.id}:${c.stepCount}:${c.isRunning}:${c.updatedAt}`));
        const listChanged = currentListSig !== lastConversationsSignature;
        if (listChanged) {
          lastConversationsSignature = currentListSig;
        }

        const listFrame = `event: conversations_update\ndata: ${JSON.stringify(listData)}\n\n`;
        for (const c of sseClients) {
          if (listChanged || !c.sentInitialList) {
            c.sentInitialList = true;
            try {
              c.res.write(listFrame);
            } catch (_) {
              sseClients.delete(c);
            }
          }
        }
      } catch (_) {}

      for (const cid of watchedIds) {
        try {
          const detail = await rpcClient.getConversationDetail(cid);
          const sig = JSON.stringify({
            s: detail.stepCount,
            g: detail.isGenerating,
            mLen: (detail.messages || []).length,
            lastId: detail.messages?.[detail.messages.length - 1]?.id,
            lastLen: (detail.messages?.[detail.messages.length - 1]?.text || '').length,
            lastThinkLen: (detail.messages?.[detail.messages.length - 1]?.thinking || '').length,
            qLen: (detail.queuedMessages || []).length,
            pIdx: detail.pendingInteraction?.stepIndex
          });
          lastDetailSignatureByCascade.set(cid, sig);

          const frame = `event: conversation_update\ndata: ${JSON.stringify(detail)}\n\n`;
          const msg = JSON.stringify({ type: 'conversation_update', data: detail });

          for (const c of sseClients) {
            if (c.cascadeId === cid && c.lastDetailSig !== sig) {
              c.lastDetailSig = sig;
              try {
                c.res.write(frame);
              } catch (_) {
                sseClients.delete(c);
              }
            }
          }
          if (wss) {
            for (const ws of wss.clients) {
              if (ws.readyState === 1 && ws.cascadeId === cid && ws.lastDetailSig !== sig) {
                ws.lastDetailSig = sig;
                try {
                  ws.send(msg);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}

const requestHandler = async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Access-Token'
    });
    res.end();
    return;
  }

  const urlObj = new URL(req.url, `http://${req.headers.host || `127.0.0.1:${PORT}`}`);
  const pathname = urlObj.pathname;

  // 1. 免鉴权探活接口 (供 iOS App 局域网/Tailscale 自动发现节点使用)
  if (pathname === '/api/v1/ping' && req.method === 'GET') {
    const net = netManager.scanNetworkInterfaces();
    const lsInfo = discovery.getConnectionInfo(false);
    return sendJson(res, 200, {
      ok: true,
      service: 'antigravity-remote-daemon',
      version: '1.0.0',
      hostname: net.hostname,
      antigravityOnline: Boolean(lsInfo && lsInfo.httpPort),
      ideVersion: lsInfo ? lsInfo.ideVersion : null,
      network: net
    });
  }

  // 1.5 专属扫码配对页 (/qr) —— 仅允许本机 (localhost) 直接访问或已携带有效 Token 访问
  if (pathname === '/qr' && req.method === 'GET') {
    const remoteAddr = (req.socket && req.socket.remoteAddress) || '';
    if (!isLoopbackAddress(remoteAddr) && !checkAuth(req, urlObj)) {
      return sendJson(res, 401, {
        ok: false,
        error: 'Unauthorized: /qr 配对页仅限本机 (127.0.0.1) 直接访问，远程访问需携带有效 Token'
      });
    }
    const net = netManager.scanNetworkInterfaces();
    const tsIp = net.systemTailscaleIp || '';
    const lanIp = net.lanIp || '';
    const tsDisplay = tsIp ? `${tsIp}:${PORT}` : '未连接 (100.x.y.z)';
    const lanDisplay = lanIp ? `${lanIp}:${PORT}` : '未检测到局域网 IP';
    const defaultPairUri = `agyremote://pair?ts=${encodeURIComponent(tsIp)}&lan=${encodeURIComponent(lanIp)}&port=${PORT}&token=${encodeURIComponent(config.accessToken)}`;
    const basePwaUrl = net.tailscaleUrl || net.lanUrl || `http://127.0.0.1:${PORT}`;
    const pwaUrl = `${basePwaUrl}/?token=${encodeURIComponent(config.accessToken)}`;
    const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Antigravity Remote 扫码一键连接</title>
  <style>
    body {
      margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: #0b0f19; color: #f8fafc; display: flex; align-items: center; justify-content: center;
      min-height: 100vh; padding: 20px; box-sizing: border-box;
    }
    .card {
      background: #131b2e; border: 1px solid rgba(255,255,255,0.1); border-radius: 22px;
      max-width: 460px; width: 100%; padding: 28px; text-align: center;
      box-shadow: 0 20px 50px rgba(0,0,0,0.5);
    }
    h1 { font-size: 20px; margin: 0 0 6px; }
    .sub { color: #94a3b8; font-size: 13px; margin-bottom: 18px; line-height: 1.5; }
    .qr-box {
      background: #fff; padding: 16px; border-radius: 18px; display: inline-block;
      margin: 8px auto 16px; box-shadow: 0 8px 24px rgba(0,0,0,0.3);
    }
    .qr-box img { width: 240px; height: 240px; display: block; }
    .tabs { display: flex; gap: 8px; justify-content: center; margin-bottom: 14px; }
    .tab-btn {
      background: #1e293b; color: #cbd5e1; border: 1px solid rgba(255,255,255,0.08);
      padding: 7px 14px; border-radius: 999px; font-size: 12px; cursor: pointer; font-weight: 600;
    }
    .tab-btn.active { background: #3b82f6; color: #fff; border-color: #3b82f6; }
    .field { text-align: left; margin-top: 12px; }
    .field label { display: block; font-size: 12px; color: #94a3b8; margin-bottom: 5px; }
    .field input {
      width: 100%; box-sizing: border-box; padding: 9px 12px; border-radius: 10px;
      border: 1px solid rgba(255,255,255,0.12); background: #0f172a; color: #f8fafc;
      font-family: ui-monospace, SFMono-Regular, monospace; font-size: 12px;
    }
    .meta {
      margin-top: 14px; background: rgba(15,23,42,0.7); border-radius: 12px; padding: 12px;
      text-align: left; font-size: 12px; color: #cbd5e1; line-height: 1.7;
      font-family: ui-monospace, SFMono-Regular, monospace;
    }
    .badge {
      display: inline-block; padding: 2px 8px; border-radius: 99px; font-size: 11px;
      background: rgba(34,197,94,0.18); color: #4ade80; font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>📱 手机扫码一键连接 Mac</h1>
    <div class="sub">使用 iPhone 上的 <b>AGY Remote</b> 右上角扫码按钮，或直接用 <b>iPhone 系统相机</b> 扫描下方二维码</div>
    <div class="tabs">
      <button class="tab-btn active" id="btnApp" onclick="switchMode('app')">AGY Remote App 专属配对码</button>
      <button class="tab-btn" id="btnPwa" onclick="switchMode('pwa')">Safari 网页版直连码</button>
    </div>
    <div class="qr-box">
      <img id="qrImg" alt="Pairing QR Code" />
    </div>
    <div class="field" id="authKeyBox">
      <label>可选：附加 Tailscale AuthKey (若手机未安装系统 Tailscale，扫码后自动激活内置节点)</label>
      <input id="authKeyInput" type="text" placeholder="tskey-auth-xxxxx (留空则直接连接 ${tsIp || '100.x.y.z'})" oninput="updateQR()" />
    </div>
    <div class="meta">
      <div>🌐 Tailscale 地址: <b>${tsDisplay}</b> <span class="badge">${net.systemTailscaleActive ? '系统 Tailscale 在线' : '待连接'}</span></div>
      <div>📶 局域网地址  : <b>${lanDisplay}</b></div>
      <div>🔑 访问 Token  : <b>${config.accessToken.slice(0, 12)}...</b></div>
    </div>
  </div>
  <script>
    const baseAppUri = ${JSON.stringify(defaultPairUri)};
    const pwaUri = ${JSON.stringify(pwaUrl)};
    let mode = 'app';
    function switchMode(m) {
      mode = m;
      document.getElementById('btnApp').className = 'tab-btn' + (m === 'app' ? ' active' : '');
      document.getElementById('btnPwa').className = 'tab-btn' + (m === 'pwa' ? ' active' : '');
      document.getElementById('authKeyBox').style.display = m === 'app' ? 'block' : 'none';
      updateQR();
    }
    function updateQR() {
      const key = document.getElementById('authKeyInput').value.trim();
      let target = mode === 'app' ? baseAppUri : pwaUri;
      if (mode === 'app' && key) {
        target += '&authkey=' + encodeURIComponent(key);
      }
      document.getElementById('qrImg').src = 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&margin=4&data=' + encodeURIComponent(target);
    }
    updateQR();
  </script>
</body>
</html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // 2. 静态资源与 iOS PWA 服务
  if (!pathname.startsWith('/api/')) {
    const publicDir = path.join(__dirname, '..', 'public');
    let relPath = pathname === '/' ? '/index.html' : pathname;
    const safePath = path.normalize(relPath).replace(/^(\.\.[/\\])+/, '');
    const filePath = path.join(publicDir, safePath);

    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      const ext = path.extname(filePath).toLowerCase();
      res.writeHead(200, {
        'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
        'Cache-Control': 'no-cache'
      });
      fs.createReadStream(filePath).pipe(res);
      return;
    }
    // SPA 回退到 index.html
    const indexHtml = path.join(publicDir, 'index.html');
    if (fs.existsSync(indexHtml)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      fs.createReadStream(indexHtml).pipe(res);
      return;
    }
  }

  // 3. 鉴权检查
  if (!checkAuth(req, urlObj)) {
    return sendJson(res, 401, { ok: false, error: 'Unauthorized: 无效的访问令牌 (Token)' });
  }

  try {
    // GET /api/v1/status (兼容 /api/status)
    if ((pathname === '/api/v1/status' || pathname === '/api/status') && req.method === 'GET') {
      const lsInfo = discovery.getConnectionInfo(true);
      const net = netManager.scanNetworkInterfaces();
      return sendJson(res, 200, {
        ok: true,
        online: Boolean(lsInfo && lsInfo.httpPort),
        languageServer: lsInfo
          ? {
              pid: lsInfo.pid,
              httpPort: lsInfo.httpPort,
              httpsPort: lsInfo.httpsPort,
              cdpPort: lsInfo.cdpPort,
              ideVersion: lsInfo.ideVersion,
              discoveredAt: lsInfo.discoveredAt
            }
          : null,
        network: net,
        pairing: {
          hostname: net.hostname,
          port: PORT,
          lanUrl: net.lanUrl,
          tailscaleUrl: net.tailscaleUrl,
          cloudflareTunnelUrl: net.cloudflareTunnelUrl,
          token: config.accessToken
        }
      }, req);
    }

    // GET /api/v1/models
    if (pathname === '/api/v1/models' && req.method === 'GET') {
      const models = await rpcClient.getModels();
      return sendJson(res, 200, { ok: true, models }, req);
    }

    // GET /api/v1/conversations (兼容 /api/conversations)
    if ((pathname === '/api/v1/conversations' || pathname === '/api/conversations') && req.method === 'GET') {
      const data = await rpcClient.listConversations();
      return sendJson(res, 200, {
        ok: true,
        success: true,
        projects: data.projects,
        conversations: data.conversations
      }, req);
    }

    // POST /api/v1/conversations (新建对话)
    if (pathname === '/api/v1/conversations' && req.method === 'POST') {
      const body = await readJsonBody(req);
      const created = await rpcClient.startConversation({
        workspaceUri: body.workspaceUri || '',
        title: body.title || '',
        text: body.text || body.message || '',
        model: body.model || '',
        media: Array.isArray(body.media) ? body.media : [],
        permissionMode: body.permissionMode || ''
      });
      return sendJson(res, 200, { ok: true, ...created }, req);
    }

    // GET /api/v1/conversations/:id
    const convoDetailMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)$/i);
    if (convoDetailMatch && req.method === 'GET') {
      const cascadeId = convoDetailMatch[1];
      const detail = await rpcClient.getConversationDetail(cascadeId);
      return sendJson(res, 200, { ok: true, ...detail }, req);
    }

    // GET /api/v1/conversations/:id/diffs
    const convoDiffsMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/diffs$/i);
    if (convoDiffsMatch && req.method === 'GET') {
      const cascadeId = convoDiffsMatch[1];
      const data = await rpcClient.getDiffsAndArtifacts(cascadeId);
      return sendJson(res, 200, { ok: true, cascadeId, ...data }, req);
    }

    // POST /api/v1/conversations/:id/messages
    const convoMsgMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/messages$/i);
    if (convoMsgMatch && req.method === 'POST') {
      const cascadeId = convoMsgMatch[1];
      const body = await readJsonBody(req);
      const result = await rpcClient.sendMessage({
        cascadeId,
        text: body.text || body.message || '',
        model: body.model || '',
        media: Array.isArray(body.media) ? body.media : [],
        artifactApprovalUri: body.artifactApprovalUri || '',
        queueIfBusy: body.queueIfBusy !== false,
        permissionMode: body.permissionMode || ''
      });
      sendJson(res, 200, {
        ok: true,
        cascadeId,
        queued: Boolean(result && result.queued),
        queuedMessages: (result && result.queuedMessages) || [],
        result
      }, req);
      setImmediate(async () => {
        try {
          await triggerPushForCascade(cascadeId);
        } catch (_) {}
      });
      return;
    }

    // POST /api/v1/conversations/:id/queue/remove (删除排队中的消息)
    const convoQueueRemoveMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/queue\/remove$/i);
    if (convoQueueRemoveMatch && req.method === 'POST') {
      const cascadeId = convoQueueRemoveMatch[1];
      const body = await readJsonBody(req);
      const queuedMessages = rpcClient.removeQueuedMessage(cascadeId, body.queueId || '');
      return sendJson(res, 200, { ok: true, cascadeId, queuedMessages });
    }

    // POST /api/v1/conversations/:id/queue/flush (立即插队发送排队中的消息)
    const convoQueueFlushMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/queue\/flush$/i);
    if (convoQueueFlushMatch && req.method === 'POST') {
      const cascadeId = convoQueueFlushMatch[1];
      const body = await readJsonBody(req);
      const resFlush = await rpcClient.flushQueuedMessage(cascadeId, body.queueId || '');
      return sendJson(res, 200, { ok: true, cascadeId, ...resFlush });
    }

    // POST /api/v1/conversations/:id/interactions (远程权限审批 / Proceed / 回答多选题)
    const convoIntMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/interactions$/i);
    if (convoIntMatch && req.method === 'POST') {
      const cascadeId = convoIntMatch[1];
      const body = await readJsonBody(req);
      const result = await rpcClient.handleInteraction({
        cascadeId,
        trajectoryId: body.trajectoryId,
        stepIndex: body.stepIndex,
        kind: body.kind,
        allow: body.allow !== false,
        commandLine: body.commandLine,
        questionResponses: body.questionResponses,
        artifactUri: body.artifactUri
      });
      return sendJson(res, 200, { ok: true, cascadeId, result });
    }

    // POST /api/v1/conversations/:id/cancel (紧急停止正在运行的 Agent)
    const convoCancelMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/cancel$/i);
    if (convoCancelMatch && req.method === 'POST') {
      const cascadeId = convoCancelMatch[1];
      const result = await rpcClient.cancelCascade(cascadeId);
      return sendJson(res, 200, { ok: true, cascadeId, result });
    }

    // POST /api/v1/conversations/:id/rename (重命名对话)
    const convoRenameMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/rename$/i);
    if (convoRenameMatch && req.method === 'POST') {
      const cascadeId = convoRenameMatch[1];
      const body = await readJsonBody(req);
      const result = await rpcClient.renameConversation(cascadeId, body.title || '');
      return sendJson(res, 200, { ok: true, cascadeId, title: body.title, result });
    }

    // POST /api/v1/conversations/:id/archive (归档对话)
    const convoArchiveMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/archive$/i);
    if (convoArchiveMatch && req.method === 'POST') {
      const cascadeId = convoArchiveMatch[1];
      const body = await readJsonBody(req);
      const archived = body.archived !== undefined ? Boolean(body.archived) : true;
      const result = await rpcClient.archiveConversation(cascadeId, archived);
      return sendJson(res, 200, { ok: true, cascadeId, archived, result });
    }

    // POST /api/v1/conversations/:id/permission (切换当前会话的权限模式)
    const convoPermissionMatch = pathname.match(/^\/api\/v1\/conversations\/([a-f0-9-]+)\/permission$/i);
    if (convoPermissionMatch && req.method === 'POST') {
      const cascadeId = convoPermissionMatch[1];
      const body = await readJsonBody(req);
      const mode = rpcClient.setConversationPermissionMode(cascadeId, body.permissionMode || '');
      return sendJson(res, 200, { ok: true, cascadeId, activePermissionMode: mode });
    }

    // GET /api/v1/terminals
    if (pathname === '/api/v1/terminals' && req.method === 'GET') {
      const cid = urlObj.searchParams.get('conversationId') || '';
      const terminals = await rpcClient.listTerminals(cid);
      return sendJson(res, 200, { ok: true, terminals });
    }

    // POST /api/v1/terminals/:id/input
    const termInputMatch = pathname.match(/^\/api\/v1\/terminals\/([^/]+)\/input$/);
    if (termInputMatch && req.method === 'POST') {
      const terminalId = decodeURIComponent(termInputMatch[1]);
      const body = await readJsonBody(req);
      const result = await rpcClient.sendTerminalInput(terminalId, body.input || '');
      return sendJson(res, 200, { ok: true, result });
    }

    // POST /api/v1/tunnel/start & stop (Cloudflare 公网穿透)
    if (pathname === '/api/v1/tunnel/start' && req.method === 'POST') {
      const result = await netManager.startCloudflareTunnel();
      return sendJson(res, 200, { ok: result.started, ...result, network: netManager.getStatus() });
    }
    if (pathname === '/api/v1/tunnel/stop' && req.method === 'POST') {
      netManager.stopCloudflareTunnel();
      return sendJson(res, 200, { ok: true, network: netManager.getStatus() });
    }

    // GET /api/v1/events (SSE 实时流)
    if (pathname === '/api/v1/events' && req.method === 'GET') {
      const cascadeId = urlObj.searchParams.get('cascadeId') || '';
      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'Access-Control-Allow-Origin': '*'
      });
      res.write(`event: connected\ndata: ${JSON.stringify({ ok: true, cascadeId })}\n\n`);
      const clientObj = { res, cascadeId, sentInitialList: false, lastDetailSig: '' };
      sseClients.add(clientObj);
      if (cascadeId) {
        setImmediate(() => {
          triggerPushForCascade(cascadeId).catch(() => {});
        });
      }
      req.on('close', () => {
        sseClients.delete(clientObj);
      });
      return;
    }

    return sendJson(res, 404, { ok: false, error: `未知接口: ${req.method} ${pathname}` });
  } catch (err) {
    console.error(`[API Error] ${req.method} ${pathname}:`, err.message);
    return sendJson(res, 500, { ok: false, error: err.message });
  }
};

const server = http.createServer(requestHandler);
let tailscaleServer = null;

// 可选挂载 WebSocket 服务 (/ws)
let wss = null;
function attachWebSocketUpgrade(httpServer) {
  if (!wss || !httpServer) return;
  httpServer.on('upgrade', (req, socket, head) => {
    try {
      const urlObj = new URL(req.url, `http://127.0.0.1:${PORT}`);
      if (urlObj.pathname !== '/ws') {
        socket.destroy();
        return;
      }
      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
      });
    } catch (_) {
      socket.destroy();
    }
  });
}

try {
  const { WebSocketServer } = require('ws');
  wss = new WebSocketServer({ noServer: true });
  wss.on('connection', (ws, req) => {
    const urlObj = new URL(req.url, `http://127.0.0.1:${PORT}`);
    if (!checkAuth(req, urlObj)) {
      ws.close(1008, 'Unauthorized');
      return;
    }
    ws.cascadeId = urlObj.searchParams.get('cascadeId') || '';
    ws.send(JSON.stringify({ type: 'connected', cascadeId: ws.cascadeId }));

    ws.on('message', async (raw) => {
      try {
        const msg = JSON.parse(raw.toString());
        if (msg.type === 'subscribe' && msg.cascadeId) {
          ws.cascadeId = msg.cascadeId;
          const detail = await rpcClient.getConversationDetail(msg.cascadeId);
          ws.send(JSON.stringify({ type: 'conversation_update', data: detail }));
        }
      } catch (_) {}
    });
  });
  attachWebSocketUpgrade(server);
} catch (_) {
  // 未安装 ws 时自动使用内置 SSE (/api/v1/events) 实时流
}

startRealtimePushLoop();

if (require.main === module) {
  let lanServer = null;
  let boundLanIp = '';
  let boundTsIp = '';

  function syncDynamicInterfaceListeners() {
    if (EXPLICIT_HOST) return;
    const net = netManager.scanNetworkInterfaces();
    const tsIp = net.systemTailscaleIp || '';
    const lanIp = net.lanIp || '';

    if (tsIp && tsIp !== '127.0.0.1' && tsIp !== boundTsIp) {
      if (tailscaleServer) {
        try { tailscaleServer.close(); } catch (_) {}
      }
      boundTsIp = tsIp;
      tailscaleServer = http.createServer(requestHandler);
      attachWebSocketUpgrade(tailscaleServer);
      tailscaleServer.on('error', (err) => {
        console.warn(`[Tailscale Listener] 绑定 ${tsIp}:${PORT} 失败: ${err.message}`);
        boundTsIp = '';
      });
      tailscaleServer.listen(PORT, tsIp);
    }

    if (lanIp && lanIp !== '127.0.0.1' && lanIp !== tsIp && lanIp !== boundLanIp) {
      if (lanServer) {
        try { lanServer.close(); } catch (_) {}
      }
      boundLanIp = lanIp;
      lanServer = http.createServer(requestHandler);
      attachWebSocketUpgrade(lanServer);
      lanServer.on('error', (err) => {
        console.warn(`[LAN Listener] 绑定 ${lanIp}:${PORT} 失败: ${err.message}`);
        boundLanIp = '';
      });
      lanServer.listen(PORT, lanIp);
    }
  }

  server.listen(PORT, HOST, () => {
    const lsInfo = discovery.getConnectionInfo(true);
    const net = netManager.scanNetworkInterfaces();

    syncDynamicInterfaceListeners();
    setInterval(syncDynamicInterfaceListeners, 5000).unref();

    console.log('\n============================================================');
    console.log('🚀 Antigravity Remote Control Daemon (iOS + PWA) 已启动');
    console.log('============================================================');
    if (lsInfo) {
      console.log(
        `✅ 已连接 Antigravity language_server (PID: ${lsInfo.pid}, HTTP Port: ${lsInfo.httpPort}, Version: ${lsInfo.ideVersion})`
      );
    } else {
      console.log('⚠️ 暂未检测到运行中的 language_server，将在后台自动探测连接');
    }
    console.log('------------------------------------------------------------');
    console.log(`🏠 本机访问地址 : http://127.0.0.1:${PORT}/?token=${encodeURIComponent(config.accessToken)}`);
    console.log(`🔗 扫码配对页面 : http://127.0.0.1:${PORT}/qr`);
    if (net.lanUrl) {
      console.log(`📶 局域网地址   : ${net.lanUrl}/?token=${encodeURIComponent(config.accessToken)}`);
    }
    if (net.systemTailscaleActive) {
      console.log(
        `🌐 Tailscale地址: ${net.tailscaleUrl}/?token=${encodeURIComponent(config.accessToken)} (系统网卡 ${net.systemTailscaleInterface} 已在线，软件内置 Tailscale 已自动关闭避让)`
      );
    } else {
      console.log('🌐 Tailscale状态: 未检测到电脑系统级 Tailscale 在线');
    }
    console.log(`🔒 鉴权保护状态 : ${config.requireAuth ? '已开启 (RequireAuth=true)' : '已关闭 (RequireAuth=false)'}`);
    console.log(`🔑 访问令牌Token: ${config.accessToken}`);
    console.log('============================================================\n');

    // 打印终端配对二维码（首选 Tailscale 地址，次选局域网地址，自动附带鉴权 Token）
    const basePairUrl = net.tailscaleUrl || net.lanUrl || `http://127.0.0.1:${PORT}`;
    const pairTargetUrl = `${basePairUrl}/?token=${encodeURIComponent(config.accessToken)}`;
    try {
      const qrcode = require('qrcode-terminal');
      console.log(`📱 iPhone Safari 或 Antigravity Remote App 扫码即连 (${pairTargetUrl}):`);
      qrcode.generate(pairTargetUrl, { small: true });
    } catch (_) {}

    // 局域网 Bonjour / mDNS 广播 (_agyremote._tcp)，供 iOS 端自动发现 Mac 守护进程
    if (process.platform === 'darwin') {
      try {
        const serviceName = 'AGY Remote (' + os.hostname() + ')';
        const bonjourProcess = child_process.spawn(
          'dns-sd',
          ['-R', serviceName, '_agyremote._tcp', 'local', String(PORT), 'port=' + PORT],
          { stdio: 'ignore' }
        );
        bonjourProcess.on('error', (err) => {
          console.warn(`[Bonjour] 局域网广播启动失败: ${err.message}`);
        });
        const cleanupBonjour = () => {
          try { bonjourProcess.kill(); } catch (_) {}
        };
        process.on('exit', cleanupBonjour);
        process.on('SIGINT', cleanupBonjour);
        process.on('SIGTERM', cleanupBonjour);
      } catch (err) {
        console.warn(`[Bonjour] 启动异常: ${err.message}`);
      }
    }
  });
}

module.exports = { server, discovery, rpcClient, netManager };
