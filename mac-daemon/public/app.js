(() => {
  const urlParams = new URLSearchParams(window.location.search);
  const urlToken = (urlParams.get('token') || '').trim();
  if (urlToken) {
    localStorage.setItem('agy_access_token', urlToken);
  }

  const state = {
    accessToken: urlToken || localStorage.getItem('agy_access_token') || '',
    projects: [],
    conversations: [],
    currentCascadeId: localStorage.getItem('agy_cascade_id') || '',
    currentWorkspaceUri: localStorage.getItem('agy_workspace_uri') || '',
    models: [],
    selectedModel: localStorage.getItem('agy_selected_model') || '',
    detail: null,
    diffs: [],
    artifacts: [],
    status: null,
    eventSource: null
  };

  const el = {
    drawer: document.getElementById('drawer'),
    drawerBackdrop: document.getElementById('drawerBackdrop'),
    btnOpenDrawer: document.getElementById('btnOpenDrawer'),
    btnCloseDrawer: document.getElementById('btnCloseDrawer'),
    btnNewChat: document.getElementById('btnNewChat'),
    projectList: document.getElementById('projectList'),
    currentConvoTitle: document.getElementById('currentConvoTitle'),
    netDot: document.getElementById('netDot'),
    netStatusText: document.getElementById('netStatusText'),
    modelSelect: document.getElementById('modelSelect'),
    paneChat: document.getElementById('pane-chat'),
    paneDiffs: document.getElementById('pane-diffs'),
    paneArtifacts: document.getElementById('pane-artifacts'),
    paneNet: document.getElementById('pane-net'),
    approvalBanner: document.getElementById('approvalBanner'),
    composerWrap: document.getElementById('composerWrap'),
    chatInput: document.getElementById('chatInput'),
    btnSend: document.getElementById('btnSend'),
    btnStopAgent: document.getElementById('btnStopAgent'),
    tabDiffsLabel: document.getElementById('tabDiffsLabel'),
    tabArtifactsLabel: document.getElementById('tabArtifactsLabel')
  };

  function escapeHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  async function api(path, options = {}) {
    const headers = {
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    if (state.accessToken) {
      headers['Authorization'] = `Bearer ${state.accessToken}`;
      headers['X-Access-Token'] = state.accessToken;
    }
    const res = await fetch(path, {
      ...options,
      headers
    });
    return await res.json();
  }

  // 1. 加载守护进程与 Tailscale 状态
  async function loadStatus() {
    try {
      const data = await api('/api/v1/status');
      state.status = data;
      const net = data.network || {};
      if (data.online) {
        if (net.systemTailscaleActive) {
          el.netDot.className = 'status-dot blue';
          el.netStatusText.textContent = `Tailscale ${net.systemTailscaleIP} (系统级在线·内置已避让)`;
        } else {
          el.netDot.className = 'status-dot';
          el.netStatusText.textContent = `LAN ${net.lanIP || '127.0.0.1'} · PID ${data.languageServer?.pid}`;
        }
      } else {
        el.netDot.className = 'status-dot offline';
        el.netStatusText.textContent = '未检测到电脑端 Antigravity 运行';
      }
      renderNetPane();
    } catch (err) {
      el.netDot.className = 'status-dot offline';
      el.netStatusText.textContent = '连接守护进程失败';
    }
  }

  // 2. 加载模型列表
  async function loadModels() {
    try {
      const data = await api('/api/v1/models');
      state.models = data.models || [];
      el.modelSelect.innerHTML = '<option value="">保持当前模型</option>';
      for (const m of state.models) {
        const opt = document.createElement('option');
        opt.value = m.modelId;
        opt.textContent = m.label;
        if (m.modelId === state.selectedModel) opt.selected = true;
        el.modelSelect.appendChild(opt);
      }
    } catch (_) {}
  }

  // 3. 加载项目与会话列表
  async function loadConversations() {
    try {
      const data = await api('/api/v1/conversations');
      state.projects = data.projects || [];
      state.conversations = data.conversations || [];
      if (!state.currentCascadeId && state.conversations.length > 0) {
        selectConversation(state.conversations[0].id, state.conversations[0].workspaceUri);
      } else {
        renderDrawer();
      }
    } catch (_) {}
  }

  function renderDrawer() {
    el.projectList.innerHTML = '';
    for (const proj of state.projects) {
      const group = document.createElement('div');
      group.className = 'project-group';
      group.innerHTML = `<div class="project-name"><span>📁 ${escapeHtml(proj.name)}</span><span>${proj.conversations.length}</span></div>`;

      for (const c of proj.conversations) {
        const item = document.createElement('div');
        item.className = `convo-item ${c.id === state.currentCascadeId ? 'active' : ''}`;
        item.innerHTML = `
          <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(c.title)}</span>
          ${c.isRunning ? '<span class="badge-running">运行中</span>' : ''}
        `;
        item.onclick = () => {
          closeDrawer();
          selectConversation(c.id, c.workspaceUri);
        };
        group.appendChild(item);
      }
      el.projectList.appendChild(group);
    }
  }

  async function selectConversation(cascadeId, workspaceUri = '') {
    state.currentCascadeId = cascadeId;
    if (workspaceUri) {
      state.currentWorkspaceUri = workspaceUri;
      localStorage.setItem('agy_workspace_uri', workspaceUri);
    }
    localStorage.setItem('agy_cascade_id', cascadeId);
    renderDrawer();

    const found = state.conversations.find((c) => c.id === cascadeId);
    el.currentConvoTitle.textContent = found ? `[${found.projectName}] ${found.title}` : `会话 ${cascadeId.slice(0, 8)}`;

    await Promise.all([loadConversationDetail(cascadeId), loadDiffsAndArtifacts(cascadeId)]);
    subscribeRealtime(cascadeId);
  }

  async function loadConversationDetail(cascadeId) {
    if (!cascadeId) return;
    try {
      const detail = await api(`/api/v1/conversations/${cascadeId}`);
      if (detail.ok) {
        applyConversationDetail(detail);
      }
    } catch (_) {}
  }

  function applyConversationDetail(detail) {
    const prevCount = state.detail ? (state.detail.messages || []).length : 0;
    state.detail = detail;
    el.btnStopAgent.style.display = detail.isGenerating ? 'inline-flex' : 'none';

    const msgs = detail.messages || [];
    const shouldScroll = msgs.length !== prevCount;

    el.paneChat.innerHTML = msgs
      .map((m) => {
        if (m.role === 'user') {
          const tokenParam = state.accessToken ? `&token=${encodeURIComponent(state.accessToken)}` : '';
          const mediaHtml = Array.isArray(m.media) && m.media.length > 0
            ? `<div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:${m.text ? '6px' : '0'};">${m.media
                .map((item) => {
                  const rawUrl = item.url ? `${item.url}${item.url.includes('?') ? tokenParam : `?${tokenParam.slice(1)}`}` : '';
                  return `<img src="${escapeHtml(rawUrl)}" alt="${escapeHtml(item.fileName || '')}" style="width:56px;height:56px;object-fit:cover;border-radius:8px;cursor:pointer;border:1px solid rgba(255,255,255,0.16);" onclick="window.open(this.src,'_blank')" />`;
                })
                .join('')}</div>`
            : '';
          return `<div class="msg-user">${mediaHtml}${escapeHtml(m.text)}</div>`;
        }
        if (m.role === 'tool') {
          return `<div class="tool-pill">🛠️ ${escapeHtml(m.summary)}</div>`;
        }
        const thinkingHtml = m.thinking
          ? `<details class="thinking-box"><summary>💭 思考过程 (${m.thinking.length} 字)</summary><div class="thinking-content">${escapeHtml(m.thinking)}</div></details>`
          : '';
        return `
          <div class="msg-ai">
            ${thinkingHtml}
            <div style="white-space:pre-wrap;">${escapeHtml(m.text || (m.isGenerating ? '正在思考与生成...' : ''))}</div>
          </div>
        `;
      })
      .join('');

    if (shouldScroll) {
      el.paneChat.scrollTop = el.paneChat.scrollHeight;
    }

    renderApprovalBanner(detail.pendingInteraction);
  }

  function renderApprovalBanner(pending) {
    if (!pending) {
      el.approvalBanner.className = 'approval-banner';
      el.approvalBanner.innerHTML = '';
      return;
    }

    el.approvalBanner.className = 'approval-banner visible';
    if (pending.kind === 'artifact_approval') {
      el.approvalBanner.innerHTML = `
        <div class="approval-title">📐 ${escapeHtml(pending.title)}</div>
        <div style="font-size:12.5px;color:#cbd5e1;">${escapeHtml(pending.summary)}</div>
        <div class="approval-actions">
          <button class="btn-approve" id="btnApproveArtifact">✅ 批准计划并继续 (Proceed)</button>
          <button class="btn-reject" id="btnViewPlanTab">📄 查看全文</button>
        </div>
      `;
      document.getElementById('btnApproveArtifact').onclick = async () => {
        await api(`/api/v1/conversations/${pending.cascadeId}/interactions`, {
          method: 'POST',
          body: JSON.stringify({
            kind: 'artifact_approval',
            allow: true,
            artifactUri: pending.artifactUri
          })
        });
        await loadConversationDetail(pending.cascadeId);
      };
      document.getElementById('btnViewPlanTab').onclick = () => switchTab('artifacts');
      return;
    }

    if (pending.kind === 'ask_question') {
      const q = (pending.questions || [])[0] || {};
      const optsHtml = (q.options || [])
        .map(
          (o, idx) =>
            `<button class="btn-approve" style="margin-top:4px;background:#2563eb;color:#fff;" data-opt-id="${escapeHtml(o.id || String(idx + 1))}">${escapeHtml(o.text || o)}</button>`
        )
        .join('');
      el.approvalBanner.innerHTML = `
        <div class="approval-title">❓ ${escapeHtml(q.question || pending.title)}</div>
        <div style="display:flex;flex-direction:column;gap:6px;">${optsHtml}</div>
      `;
      el.approvalBanner.querySelectorAll('[data-opt-id]').forEach((btn) => {
        btn.onclick = async () => {
          const optId = btn.getAttribute('data-opt-id');
          await api(`/api/v1/conversations/${pending.cascadeId}/interactions`, {
            method: 'POST',
            body: JSON.stringify({
              trajectoryId: pending.trajectoryId,
              stepIndex: pending.stepIndex,
              kind: 'ask_question',
              questionResponses: [
                {
                  question: q.question,
                  options: q.options,
                  selectedOptionIds: [optId]
                }
              ]
            })
          });
          await loadConversationDetail(pending.cascadeId);
        };
      });
      return;
    }

    // 默认：终端命令或文件权限审批
    el.approvalBanner.innerHTML = `
      <div class="approval-title">⚡ ${escapeHtml(pending.title)}</div>
      <div class="approval-code">${escapeHtml(pending.commandLine || pending.pathUri || pending.reason || '')}</div>
      <div class="approval-actions">
        <button class="btn-approve" id="btnAllowInt">✓ 允许执行 (Approve)</button>
        <button class="btn-reject" id="btnDenyInt">✕ 拒绝 (Reject)</button>
      </div>
    `;
    document.getElementById('btnAllowInt').onclick = async () => {
      await api(`/api/v1/conversations/${pending.cascadeId}/interactions`, {
        method: 'POST',
        body: JSON.stringify({
          trajectoryId: pending.trajectoryId,
          stepIndex: pending.stepIndex,
          kind: pending.kind,
          allow: true,
          commandLine: pending.commandLine
        })
      });
      await loadConversationDetail(pending.cascadeId);
    };
    document.getElementById('btnDenyInt').onclick = async () => {
      await api(`/api/v1/conversations/${pending.cascadeId}/interactions`, {
        method: 'POST',
        body: JSON.stringify({
          trajectoryId: pending.trajectoryId,
          stepIndex: pending.stepIndex,
          kind: pending.kind,
          allow: false,
          commandLine: pending.commandLine
        })
      });
      await loadConversationDetail(pending.cascadeId);
    };
  }

  async function loadDiffsAndArtifacts(cascadeId) {
    if (!cascadeId) return;
    try {
      const data = await api(`/api/v1/conversations/${cascadeId}/diffs`);
      state.diffs = data.diffs || [];
      state.artifacts = data.artifacts || [];
      el.tabDiffsLabel.textContent = `代码变更(${state.diffs.length})`;
      el.tabArtifactsLabel.textContent = `方案文档(${state.artifacts.length})`;
      renderDiffsPane();
      renderArtifactsPane();
    } catch (_) {}
  }

  function renderDiffsPane() {
    if (!state.diffs.length) {
      el.paneDiffs.innerHTML = '<div class="info-card">当前会话暂无文件变更记录。</div>';
      return;
    }
    el.paneDiffs.innerHTML = state.diffs
      .map(
        (d) => `
        <div class="info-card">
          <div style="font-weight:600;color:#60a5fa;font-size:13.5px;">📄 ${escapeHtml(d.fileName)}</div>
          <div style="font-size:11px;color:#94a3b8;word-break:break-all;">${escapeHtml(d.filePath)}</div>
          <pre class="code-pre">${escapeHtml((d.modifiedContent || '').slice(0, 4000))}</pre>
        </div>
      `
      )
      .join('');
  }

  function renderArtifactsPane() {
    if (!state.artifacts.length) {
      el.paneArtifacts.innerHTML = '<div class="info-card">当前会话暂无 Artifact 方案文档。</div>';
      return;
    }
    el.paneArtifacts.innerHTML = state.artifacts
      .map(
        (a) => `
        <div class="info-card">
          <div style="font-weight:600;color:#c084fc;font-size:14px;">📑 ${escapeHtml(a.name)}</div>
          <pre class="code-pre">${escapeHtml(a.content || '（二进制或外部媒体文件）')}</pre>
        </div>
      `
      )
      .join('');
  }

  function renderNetPane() {
    const net = (state.status && state.status.network) || {};
    el.paneNet.innerHTML = `
      <div class="info-card">
        <div style="font-weight:700;font-size:15px;">🌐 Tailscale 智能互斥状态</div>
        <div style="font-size:13px;color:${net.systemTailscaleActive ? '#60a5fa' : '#94a3b8'};">
          ${escapeHtml(net.embeddedStatusHint || '')}
        </div>
        <div class="code-pre">主机名: ${escapeHtml(net.hostname || '-')}
系统级 Tailscale: ${net.systemTailscaleActive ? `在线 (${net.systemTailscaleInterface} · ${net.systemTailscaleIP})` : '未开启'}
MagicDNS 域名: ${escapeHtml(net.magicDNSName || '-')}
内置 tsnet 引擎: ${net.embeddedTailscaleSuppressedBySystem ? '已自动关闭避让系统 Tailscale' : '待命'}
Tailscale 直连地址: ${escapeHtml(net.tailscaleUrl || '-')}
局域网直连地址: ${escapeHtml(net.lanUrl || '-')}
Cloudflare 公网隧道: ${escapeHtml(net.cloudflareTunnelUrl || '未启动')}</div>
        <div style="display:flex;gap:8px;margin-top:4px;">
          <button class="btn-approve" id="btnStartTunnel" style="background:#3b82f6;color:#fff;">☁️ 启动 Cloudflare 临时公网隧道</button>
        </div>
      </div>
    `;
    const btnTunnel = document.getElementById('btnStartTunnel');
    if (btnTunnel) {
      btnTunnel.onclick = async () => {
        btnTunnel.textContent = '正在启动公网隧道...';
        await api('/api/v1/tunnel/start', { method: 'POST' });
        await loadStatus();
      };
    }
  }

  function subscribeRealtime(cascadeId) {
    if (state.eventSource) {
      state.eventSource.close();
    }
    const tokenParam = state.accessToken ? `&token=${encodeURIComponent(state.accessToken)}` : '';
    const es = new EventSource(`/api/v1/events?cascadeId=${encodeURIComponent(cascadeId)}${tokenParam}`);
    es.addEventListener('conversation_update', (e) => {
      try {
        const detail = JSON.parse(e.data);
        applyConversationDetail(detail);
      } catch (_) {}
    });
    es.addEventListener('conversations_update', (e) => {
      try {
        const listData = JSON.parse(e.data);
        const oldIds = new Set(state.conversations.map((c) => c.id));
        state.projects = listData.projects || [];
        state.conversations = listData.conversations || [];
        renderDrawer();
        // 若电脑端刚新建了对话，自动切换过去
        if (oldIds.size > 0) {
          const brandNew = state.conversations.find((c) => !oldIds.has(c.id));
          if (brandNew && brandNew.id !== state.currentCascadeId) {
            selectConversation(brandNew.id, brandNew.workspaceUri);
          }
        }
      } catch (_) {}
    });
    state.eventSource = es;
  }

  // 发送消息
  async function sendChatMessage() {
    const text = el.chatInput.value.trim();
    if (!text) return;
    el.chatInput.value = '';

    if (!state.currentCascadeId) {
      const created = await api('/api/v1/conversations', {
        method: 'POST',
        body: JSON.stringify({
          workspaceUri: state.currentWorkspaceUri,
          text,
          model: state.selectedModel
        })
      });
      if (created.cascadeId) {
        await loadConversations();
        await selectConversation(created.cascadeId, state.currentWorkspaceUri);
      }
      return;
    }

    // 乐观插入用户消息
    el.paneChat.insertAdjacentHTML('beforeend', `<div class="msg-user">${escapeHtml(text)}</div>`);
    el.paneChat.scrollTop = el.paneChat.scrollHeight;

    await api(`/api/v1/conversations/${state.currentCascadeId}/messages`, {
      method: 'POST',
      body: JSON.stringify({
        text,
        model: state.selectedModel
      })
    });
    await loadConversationDetail(state.currentCascadeId);
  }

  // 事件绑定
  function openDrawer() {
    el.drawer.classList.add('open');
    el.drawerBackdrop.classList.add('open');
  }
  function closeDrawer() {
    el.drawer.classList.remove('open');
    el.drawerBackdrop.classList.remove('open');
  }

  el.btnOpenDrawer.onclick = openDrawer;
  el.btnCloseDrawer.onclick = closeDrawer;
  el.drawerBackdrop.onclick = closeDrawer;

  el.btnNewChat.onclick = async () => {
    closeDrawer();
    const promptText = window.prompt('请输入新对话的首条指令：');
    if (!promptText || !promptText.trim()) return;
    const created = await api('/api/v1/conversations', {
      method: 'POST',
      body: JSON.stringify({
        workspaceUri: state.currentWorkspaceUri,
        text: promptText.trim(),
        model: state.selectedModel
      })
    });
    if (created.cascadeId) {
      await loadConversations();
      await selectConversation(created.cascadeId, state.currentWorkspaceUri);
    }
  };

  el.modelSelect.onchange = () => {
    state.selectedModel = el.modelSelect.value;
    localStorage.setItem('agy_selected_model', state.selectedModel);
  };

  el.btnSend.onclick = sendChatMessage;
  el.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendChatMessage();
    }
  });

  el.btnStopAgent.onclick = async () => {
    if (!state.currentCascadeId) return;
    await api(`/api/v1/conversations/${state.currentCascadeId}/cancel`, { method: 'POST' });
    await loadConversationDetail(state.currentCascadeId);
  };

  document.querySelectorAll('.chip[data-slash]').forEach((btn) => {
    btn.onclick = () => {
      const cmd = btn.getAttribute('data-slash');
      el.chatInput.value = cmd + el.chatInput.value;
      el.chatInput.focus();
    };
  });

  function switchTab(tabName) {
    document.querySelectorAll('.tab-btn').forEach((b) => {
      b.classList.toggle('active', b.getAttribute('data-tab') === tabName);
    });
    ['chat', 'diffs', 'artifacts', 'net'].forEach((name) => {
      const pane = document.getElementById(`pane-${name}`);
      if (pane) pane.classList.toggle('active', name === tabName);
    });
    el.composerWrap.style.display = tabName === 'chat' ? 'flex' : 'none';
    if (tabName === 'diffs' || tabName === 'artifacts') {
      loadDiffsAndArtifacts(state.currentCascadeId);
    }
  }

  document.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.onclick = () => switchTab(btn.getAttribute('data-tab'));
  });

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }

  // 初始化启动
  loadStatus();
  loadModels();
  loadConversations();
  setInterval(loadStatus, 10000);
})();
