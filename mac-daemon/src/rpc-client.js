const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const { AntigravityDiscovery } = require('./discovery');

const ANTIGRAVITY_DIR = path.join(os.homedir(), '.gemini', 'antigravity');
const BRAIN_DIR = path.join(ANTIGRAVITY_DIR, 'brain');
const ANNOTATIONS_DIR = path.join(ANTIGRAVITY_DIR, 'annotations');
const CONVERSATIONS_DIR = path.join(ANTIGRAVITY_DIR, 'conversations');
const SUMMARIES_DB_PATH = path.join(ANTIGRAVITY_DIR, 'conversation_summaries.db');
const PERSISTENT_CACHE_PATH = path.join(ANTIGRAVITY_DIR, 'remote-daemon-conversations-cache.json');

class AntigravityRpcClient {
  constructor(discovery = new AntigravityDiscovery()) {
    this.discovery = discovery;
    // 每个会话的待发送消息队列: cascadeId -> Array<{ id, text, model, media, createdAt }>
    this._messageQueues = new Map();
    // 记录每个会话最近一次实际向 language_server 派发消息的时间戳，防止连续快速点击发送时重叠打断
    this._lastDispatchTime = new Map();
    // 正在派发中的会话锁
    this._dispatchingSet = new Set();
    // 缓存已核实的会话真实运行状态，避免后台守护进程 (IsDaemon: true) 导致已完成的对话一直显示“正在思考/运行中”
    this._resolvedStateCache = new Map();
    // 记录最近刚派发的用户消息，填补 SendUserCascadeMessage 到 GetCascadeTrajectory 落盘之间的时间差
    this._recentDispatchedUserMessages = new Map();
    // 缓存本地 transcript.jsonl 解析结果: cascadeId -> { targetPath, mtimeMs, size, map }
    this._transcriptCache = new Map();
    // 记录新建的空会话及其自定义标题: cascadeId -> { id, title, workspaceUri, createdAt }
    this._pendingBlankConversations = new Map();
    // 记录每个会话及全局最近已知的权限执行模式 ('review' | 'auto' | 'turbo')
    this._cascadePermissionModes = new Map();
    this._lastKnownPermissionMode = 'turbo';

    // 本地持久化与多源历史索引缓存
    this._annotationsCache = { checkedAt: 0, map: new Map() };
    this._sqliteSummariesCache = { checkedAt: 0, dbMtimeMs: 0, walMtimeMs: 0, rootRows: new Map(), subtrajectoryIds: new Set() };
    this._projectsMetaCache = { checkedAt: 0, map: new Map() };
    this._brainScanCache = { checkedAt: 0, dirMtimeMs: 0, entries: new Map(), subtrajectoryIds: new Set() };
    this._persistentCache = this._loadPersistentCache();
  }

  _loadPersistentCache() {
    try {
      if (fs.existsSync(PERSISTENT_CACHE_PATH)) {
        const parsed = JSON.parse(fs.readFileSync(PERSISTENT_CACHE_PATH, 'utf-8'));
        if (parsed && typeof parsed === 'object') {
          return {
            updatedAt: parsed.updatedAt || '',
            conversations: parsed.conversations && typeof parsed.conversations === 'object' ? parsed.conversations : {},
            projects: parsed.projects && typeof parsed.projects === 'object' ? parsed.projects : {}
          };
        }
      }
    } catch (_) {}
    return { updatedAt: '', conversations: {}, projects: {} };
  }

  _savePersistentCache() {
    try {
      this._persistentCache.updatedAt = new Date().toISOString();
      fs.mkdirSync(path.dirname(PERSISTENT_CACHE_PATH), { recursive: true });
      fs.writeFileSync(PERSISTENT_CACHE_PATH, JSON.stringify(this._persistentCache, null, 2), 'utf-8');
    } catch (_) {}
  }

  _normalizeIsoTime(raw) {
    if (!raw) return '';
    const str = String(raw).trim();
    if (!str || str.startsWith('0001-01-01')) return '';
    const normalized = str.includes('T') ? str : str.replace(' ', 'T');
    const ms = Date.parse(normalized);
    if (!Number.isFinite(ms) || ms <= 0) return '';
    return new Date(ms).toISOString();
  }

  _unescapePbtxtString(raw) {
    if (!raw || typeof raw !== 'string') return '';
    if (!raw.includes('\\')) return raw;
    const bytes = [];
    for (let i = 0; i < raw.length; i++) {
      const ch = raw[i];
      if (ch === '\\' && i + 1 < raw.length) {
        const next = raw[i + 1];
        if (next >= '0' && next <= '7') {
          let oct = next;
          i++;
          if (i + 1 < raw.length && raw[i + 1] >= '0' && raw[i + 1] <= '7') {
            oct += raw[++i];
          }
          if (i + 1 < raw.length && raw[i + 1] >= '0' && raw[i + 1] <= '7') {
            oct += raw[++i];
          }
          bytes.push(parseInt(oct, 8) & 0xff);
          continue;
        }
        i++;
        if (next === 'n') bytes.push(10);
        else if (next === 'r') bytes.push(13);
        else if (next === 't') bytes.push(9);
        else if (next === '"') bytes.push(34);
        else if (next === '\\') bytes.push(92);
        else {
          const buf = Buffer.from(next, 'utf-8');
          for (const b of buf) bytes.push(b);
        }
      } else {
        const buf = Buffer.from(ch, 'utf-8');
        for (const b of buf) bytes.push(b);
      }
    }
    return Buffer.from(bytes).toString('utf-8');
  }

  /**
   * 读取 ~/.gemini/antigravity/annotations/<cascadeId>.pbtxt 中的标题与归档状态
   */
  _readLocalAnnotationsMap(force = false) {
    if (!force && Date.now() - this._annotationsCache.checkedAt < 1500 && this._annotationsCache.map.size > 0) {
      return this._annotationsCache.map;
    }
    const map = new Map();
    if (!fs.existsSync(ANNOTATIONS_DIR)) return map;
    try {
      const files = fs.readdirSync(ANNOTATIONS_DIR);
      for (const f of files) {
        if (!f.endsWith('.pbtxt')) continue;
        const cascadeId = f.slice(0, -6);
        try {
          const txt = fs.readFileSync(path.join(ANNOTATIONS_DIR, f), 'utf-8');
          const archivedTrue = /\barchived\s*:\s*true\b/.test(txt);
          const archivedFalse = /\barchived\s*:\s*false\b/.test(txt);
          const titleMatch = txt.match(/\btitle\s*:\s*"((?:[^"\\]|\\.)*)"/);
          const title = titleMatch ? this._unescapePbtxtString(titleMatch[1]).trim() : '';
          map.set(cascadeId, {
            title,
            archived: archivedTrue ? true : (archivedFalse ? false : false),
            hasArchivedField: archivedTrue || archivedFalse
          });
        } catch (_) {}
      }
      this._annotationsCache = { checkedAt: Date.now(), map };
    } catch (_) {}
    return map;
  }

  /**
   * 读取 ~/.gemini/antigravity/conversation_summaries.db 中持久化的历史会话索引
   * 即使电脑端 Antigravity IDE 重启后内存仅加载了 1 个会话，也能毫秒级恢复全部历史会话与工作区归属
   */
  _readSqliteSummaries() {
    if (!fs.existsSync(SUMMARIES_DB_PATH)) {
      return { rootRows: new Map(), subtrajectoryIds: new Set() };
    }
    try {
      const dbStat = fs.statSync(SUMMARIES_DB_PATH);
      const walPath = `${SUMMARIES_DB_PATH}-wal`;
      const walStat = fs.existsSync(walPath) ? fs.statSync(walPath) : null;
      const dbMtimeMs = dbStat.mtimeMs;
      const walMtimeMs = walStat ? walStat.mtimeMs : 0;

      if (
        Date.now() - this._sqliteSummariesCache.checkedAt < 3000 &&
        this._sqliteSummariesCache.dbMtimeMs === dbMtimeMs &&
        this._sqliteSummariesCache.walMtimeMs === walMtimeMs &&
        this._sqliteSummariesCache.rootRows.size > 0
      ) {
        return {
          rootRows: this._sqliteSummariesCache.rootRows,
          subtrajectoryIds: this._sqliteSummariesCache.subtrajectoryIds
        };
      }

      const sql = [
        'SELECT conversation_id, title, preview, step_count, last_modified_time,',
        'workspace_uris, status, project_id, parent_conversation_id, nesting_depth, killed',
        'FROM conversation_summaries ORDER BY last_modified_time DESC;'
      ].join(' ');

      const out = execFileSync('sqlite3', ['-json', SUMMARIES_DB_PATH, sql], {
        encoding: 'utf-8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore']
      });
      const rows = out && out.trim() ? JSON.parse(out) : [];
      const rootRows = new Map();
      const subtrajectoryIds = new Set();

      for (const r of rows) {
        const cid = r && r.conversation_id;
        if (!cid) continue;
        const depth = Number(r.nesting_depth || 0);
        const parentId = String(r.parent_conversation_id || '').trim();
        if (depth > 0 || parentId) {
          subtrajectoryIds.add(cid);
          continue;
        }
        rootRows.set(cid, r);
      }

      this._sqliteSummariesCache = {
        checkedAt: Date.now(),
        dbMtimeMs,
        walMtimeMs,
        rootRows,
        subtrajectoryIds
      };
      return { rootRows, subtrajectoryIds };
    } catch (_) {
      return {
        rootRows: this._sqliteSummariesCache.rootRows || new Map(),
        subtrajectoryIds: this._sqliteSummariesCache.subtrajectoryIds || new Set()
      };
    }
  }

  /**
   * 获取 ListProjects + ReadProjects 的项目元数据映射: projectId -> { id, name, workspaceUri, workspacePath }
   */
  async _getProjectsMetadataMap() {
    if (Date.now() - this._projectsMetaCache.checkedAt < 15000 && this._projectsMetaCache.map.size > 0) {
      return this._projectsMetaCache.map;
    }
    const map = new Map();
    try {
      const lp = await this.callRpc('ListProjects', {});
      const ids = (lp && Array.isArray(lp.projectIds) ? lp.projectIds : []).filter(Boolean);
      if (ids.length > 0) {
        const rp = await this.callRpc('ReadProjects', { ids });
        const projects = (rp && Array.isArray(rp.projects) ? rp.projects : []);
        for (const p of projects) {
          if (!p || !p.id) continue;
          const resources = (p.projectResources && Array.isArray(p.projectResources.resources))
            ? p.projectResources.resources
            : [];
          let folderUri = '';
          for (const resItem of resources) {
            if (resItem && resItem.folderUri) {
              folderUri = resItem.folderUri;
              break;
            }
            if (resItem && resItem.gitFolder && resItem.gitFolder.folderUri) {
              folderUri = resItem.gitFolder.folderUri;
              break;
            }
          }
          const workspacePath = folderUri ? decodeURIComponent(folderUri.replace(/^file:\/\//, '')) : '';
          map.set(p.id, {
            id: p.id,
            name: p.name || (workspacePath ? path.basename(workspacePath) : ''),
            workspaceUri: folderUri || '',
            workspacePath
          });
        }
      }
      if (map.size > 0) {
        this._projectsMetaCache = { checkedAt: Date.now(), map };
      }
    } catch (_) {}
    return this._projectsMetaCache.map;
  }

  _hasLocalConversationData(cascadeId) {
    if (!cascadeId || !/^[a-f0-9-]+$/i.test(cascadeId)) return false;
    const dbFile = path.join(CONVERSATIONS_DIR, `${cascadeId}.db`);
    if (fs.existsSync(dbFile)) return true;
    const brainFolder = path.join(BRAIN_DIR, cascadeId);
    if (fs.existsSync(brainFolder)) return true;
    return false;
  }

  /**
   * 扫描 ~/.gemini/antigravity/brain/<cascadeId>/.system_generated/logs/transcript.jsonl 作为兜底补充数据源
   */
  _scanBrainConversations(subtrajectoryIds = new Set()) {
    if (!fs.existsSync(BRAIN_DIR)) return new Map();
    try {
      const dirStat = fs.statSync(BRAIN_DIR);
      if (
        Date.now() - this._brainScanCache.checkedAt < 10000 &&
        this._brainScanCache.dirMtimeMs === dirStat.mtimeMs &&
        this._brainScanCache.entries.size > 0
      ) {
        return this._brainScanCache.entries;
      }

      const entries = new Map();
      const folders = fs.readdirSync(BRAIN_DIR);
      for (const cascadeId of folders) {
        if (!/^[a-f0-9-]{20,}$/i.test(cascadeId)) continue;
        if (subtrajectoryIds.has(cascadeId) || this._brainScanCache.subtrajectoryIds.has(cascadeId)) continue;

        const logsDir = path.join(BRAIN_DIR, cascadeId, '.system_generated', 'logs');
        const transcriptPath = path.join(logsDir, 'transcript.jsonl');
        if (!fs.existsSync(transcriptPath)) continue;

        try {
          const stat = fs.statSync(transcriptPath);
          const content = fs.readFileSync(transcriptPath, 'utf-8');
          if (content.includes('<subagent_reminder>')) {
            this._brainScanCache.subtrajectoryIds.add(cascadeId);
            continue;
          }
          const lines = content.split('\n');
          let stepCount = 0;
          let firstUserText = '';
          let workspacePath = '';
          let createdAt = '';
          let updatedAt = '';

          for (const line of lines) {
            if (!line.trim()) continue;
            try {
              const obj = JSON.parse(line);
              if (typeof obj.step_index === 'number' && obj.step_index + 1 > stepCount) {
                stepCount = obj.step_index + 1;
              }
              if (!createdAt && obj.created_at) createdAt = obj.created_at;
              if (obj.created_at) updatedAt = obj.created_at;

              if (!workspacePath && typeof obj.content === 'string') {
                const wsMatch = obj.content.match(/Active Workspaces:\s*\n-\s*([^\n\r]+)/);
                if (wsMatch && wsMatch[1]) {
                  workspacePath = wsMatch[1].trim();
                }
              }

              if (!firstUserText && obj.type === 'USER_INPUT' && typeof obj.content === 'string') {
                if (obj.content.includes('[Message] timestamp=') && obj.content.includes('sender=')) {
                  this._brainScanCache.subtrajectoryIds.add(cascadeId);
                  firstUserText = '__SUBAGENT__';
                  break;
                }
                const cleaned = this._cleanUserTags(obj.content);
                if (cleaned && !cleaned.startsWith('<SYSTEM_MESSAGE>')) {
                  firstUserText = cleaned.split('\n')[0].slice(0, 48).trim();
                }
              }
            } catch (_) {}
          }

          if (firstUserText === '__SUBAGENT__') continue;
          const workspaceUri = workspacePath ? `file://${encodeURI(workspacePath)}` : '';
          entries.set(cascadeId, {
            id: cascadeId,
            title: firstUserText || '',
            workspaceUri,
            workspacePath,
            stepCount,
            createdAt: this._normalizeIsoTime(createdAt) || stat.birthtime.toISOString(),
            updatedAt: this._normalizeIsoTime(updatedAt) || stat.mtime.toISOString()
          });
        } catch (_) {}
      }

      this._brainScanCache = {
        checkedAt: Date.now(),
        dirMtimeMs: dirStat.mtimeMs,
        entries,
        subtrajectoryIds: this._brainScanCache.subtrajectoryIds
      };
      return entries;
    } catch (_) {
      return new Map();
    }
  }

  /**
   * 调用 language_server 原生 Connect-RPC (HTTP/JSON) 接口
   * 若遇到端口变化导致 ECONNREFUSED，自动触发重新探测并重试一次
   */
  async callRpc(method, payload = {}, retry = true) {
    const info = this.discovery.getConnectionInfo(false);
    if (!info || !info.httpPort || !info.csrfToken) {
      const refreshed = this.discovery.getConnectionInfo(true);
      if (!refreshed || !refreshed.httpPort) {
        throw new Error('未检测到正在运行的 Antigravity language_server，请确认电脑端 Antigravity 已启动');
      }
      return this._doHttpPost(refreshed, method, payload);
    }

    try {
      return await this._doHttpPost(info, method, payload);
    } catch (err) {
      if (retry && (err.code === 'ECONNREFUSED' || err.code === 'ECONNRESET' || err.statusCode === 403)) {
        const refreshed = this.discovery.getConnectionInfo(true);
        if (refreshed && refreshed.httpPort) {
          return await this._doHttpPost(refreshed, method, payload);
        }
      }
      throw err;
    }
  }

  _doHttpPost(info, method, payload) {
    return new Promise((resolve, reject) => {
      const bodyStr = JSON.stringify(payload || {});
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port: info.httpPort,
          path: `/exa.language_server_pb.LanguageServerService/${method}`,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(bodyStr),
            'x-codeium-csrf-token': info.csrfToken,
            'Connect-Protocol-Version': '1'
          },
          timeout: 15000
        },
        (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            const raw = Buffer.concat(chunks).toString('utf-8');
            if (res.statusCode >= 200 && res.statusCode < 300) {
              try {
                resolve(raw ? JSON.parse(raw) : {});
              } catch (e) {
                resolve({ raw });
              }
            } else {
              const err = new Error(`RPC ${method} HTTP ${res.statusCode}: ${raw.slice(0, 300)}`);
              err.statusCode = res.statusCode;
              err.responseBody = raw;
              reject(err);
            }
          });
        }
      );

      req.on('error', (err) => reject(err));
      req.on('timeout', () => {
        req.destroy(new Error(`RPC ${method} timeout`));
      });
      req.write(bodyStr);
      req.end();
    });
  }

  /**
   * 获取所有项目与对话列表（按项目分组，并按最后修改时间倒序排列）
   * 融合多数据源：
   * 1. language_server 实时内存态 (GetAllCascadeTrajectories)
   * 2. 本地 SQLite 历史索引 (~/.gemini/antigravity/conversation_summaries.db) + 注解 (~/.gemini/antigravity/annotations/*.pbtxt)
   * 3. 项目元数据映射 (ListProjects / ReadProjects)
   * 4. 本地 brain 目录日志 (~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl) 与守护进程持久化缓存
   */
  async listConversations() {
    let summaries = {};
    try {
      const res = await this.callRpc('GetAllCascadeTrajectories', { excludeSubtrajectories: true });
      summaries = (res && res.trajectorySummaries) || {};
    } catch (_) {
      summaries = {};
    }

    const annotationsMap = this._readLocalAnnotationsMap();
    const { rootRows, subtrajectoryIds } = this._readSqliteSummaries();
    const projectsMetaMap = await this._getProjectsMetadataMap();
    const brainEntries = this._scanBrainConversations(subtrajectoryIds);

    const conversations = [];
    const projectsMap = new Map();
    const processedIds = new Set();
    const nextCachedConvos = {};
    const nextCachedProjects = { ...(this._persistentCache.projects || {}) };

    const addConvo = (convo) => {
      processedIds.add(convo.id);
      conversations.push(convo);
      if (!projectsMap.has(convo.projectName)) {
        projectsMap.set(convo.projectName, {
          name: convo.projectName,
          workspaceUri: convo.workspaceUri || '',
          workspacePath: convo.workspacePath || '',
          conversations: []
        });
      }
      projectsMap.get(convo.projectName).conversations.push(convo);

      nextCachedConvos[convo.id] = {
        id: convo.id,
        trajectoryId: convo.trajectoryId || '',
        title: convo.title,
        projectName: convo.projectName,
        workspaceUri: convo.workspaceUri || '',
        workspacePath: convo.workspacePath || '',
        stepCount: convo.stepCount || 0,
        createdAt: convo.createdAt || '',
        updatedAt: convo.updatedAt || '',
        archived: false
      };
      if (convo.projectName) {
        nextCachedProjects[convo.projectName] = {
          name: convo.projectName,
          workspaceUri: convo.workspaceUri || '',
          workspacePath: convo.workspacePath || ''
        };
      }
    };

    const parseFirstWsUriFromSqlRow = (sqlRow) => {
      if (!sqlRow) return '';
      if (sqlRow.workspace_uris) {
        try {
          const parsed = JSON.parse(sqlRow.workspace_uris);
          if (Array.isArray(parsed) && parsed[0]) return String(parsed[0]);
        } catch (_) {}
      }
      if (sqlRow.project_id && projectsMetaMap.has(sqlRow.project_id)) {
        return projectsMetaMap.get(sqlRow.project_id).workspaceUri || '';
      }
      return '';
    };

    // 1. 处理当前已加载在 language_server 内存中的活跃会话
    for (const [cascadeId, item] of Object.entries(summaries)) {
      if (subtrajectoryIds.has(cascadeId) || this._brainScanCache.subtrajectoryIds.has(cascadeId)) {
        continue;
      }
      const pendingMeta = this._pendingBlankConversations.get(cascadeId);
      const ann = annotationsMap.get(cascadeId);
      const sqlRow = rootRows.get(cascadeId);
      const cachedConvo = this._persistentCache.conversations && this._persistentCache.conversations[cascadeId];
      const brainEntry = brainEntries.get(cascadeId);

      const archived =
        Boolean(item.annotations && item.annotations.archived) ||
        Boolean(ann && ann.archived);
      if (archived) {
        this._pendingBlankConversations.delete(cascadeId);
        continue;
      }

      const title =
        (item.annotations && item.annotations.title) ||
        (ann && ann.title) ||
        (pendingMeta && pendingMeta.title) ||
        item.summary ||
        (sqlRow && sqlRow.title) ||
        (cachedConvo && cachedConvo.title) ||
        (brainEntry && brainEntry.title) ||
        `会话 ${cascadeId.slice(0, 8)}`;

      const workspaces = item.workspaces || [];
      const metaWsUris =
        (item.trajectoryMetadata && Array.isArray(item.trajectoryMetadata.workspaceUris))
          ? item.trajectoryMetadata.workspaceUris
          : [];
      const metaProjectId = (item.trajectoryMetadata && item.trajectoryMetadata.projectId) || '';
      const firstWsUri =
        (workspaces[0] && workspaces[0].workspaceFolderAbsoluteUri) ||
        metaWsUris[0] ||
        (metaProjectId && projectsMetaMap.get(metaProjectId)?.workspaceUri) ||
        parseFirstWsUriFromSqlRow(sqlRow) ||
        (pendingMeta && pendingMeta.workspaceUri) ||
        (cachedConvo && cachedConvo.workspaceUri) ||
        (brainEntry && brainEntry.workspaceUri) ||
        '';
      const workspacePath = firstWsUri ? decodeURIComponent(firstWsUri.replace(/^file:\/\//, '')) : '';
      const projectName = workspacePath ? path.basename(workspacePath) : '全局对话 (Scratch)';

      let statusRaw = item.status || 'CASCADE_RUN_STATUS_IDLE';
      let isRunning =
        statusRaw === 'CASCADE_RUN_STATUS_RUNNING' ||
        statusRaw === 'CASCADE_RUN_STATUS_WAITING_FOR_USER';

      // 若 language_server 报告 RUNNING，核实最新步骤是否其实早已完成（例如仅因存在 IsDaemon 守护进程而未归位 IDLE）
      if (statusRaw === 'CASCADE_RUN_STATUS_RUNNING') {
        const stepCount = item.stepCount || 0;
        const cached = this._resolvedStateCache.get(cascadeId);
        if (cached && cached.stepCount === stepCount && Date.now() - cached.checkedAt < 8000) {
          isRunning = cached.isGenerating;
          if (!isRunning) statusRaw = 'CASCADE_RUN_STATUS_IDLE';
        } else {
          try {
            const detRes = await this.callRpc('GetCascadeTrajectory', { cascadeId });
            const rawSteps = (detRes && detRes.trajectory && detRes.trajectory.steps) || [];
            const transcriptMap = this._readLocalTranscriptMap(cascadeId);
            isRunning = this._computeIsTurnGenerating(rawSteps, transcriptMap, statusRaw);
            this._resolvedStateCache.set(cascadeId, {
              stepCount: rawSteps.length || stepCount,
              isGenerating: isRunning,
              checkedAt: Date.now()
            });
            if (!isRunning) statusRaw = 'CASCADE_RUN_STATUS_IDLE';
          } catch (_) {}
        }
      }

      const createdAt =
        this._normalizeIsoTime(item.createdTime) ||
        (cachedConvo && cachedConvo.createdAt) ||
        (brainEntry && brainEntry.createdAt) ||
        this._normalizeIsoTime(item.lastModifiedTime) ||
        '';
      const updatedAt =
        this._normalizeIsoTime(item.lastModifiedTime) ||
        (sqlRow && this._normalizeIsoTime(sqlRow.last_modified_time)) ||
        createdAt;

      addConvo({
        id: cascadeId,
        trajectoryId: item.trajectoryId || (cachedConvo && cachedConvo.trajectoryId) || '',
        title,
        projectName,
        workspaceUri: firstWsUri || '',
        workspacePath,
        stepCount: item.stepCount || (sqlRow && Number(sqlRow.step_count)) || 0,
        status: statusRaw,
        isRunning,
        createdAt,
        updatedAt
      });
    }

    // 2. 合并本地 SQLite 历史索引 (conversation_summaries.db) 中尚未加载进 language_server 内存的会话
    for (const [cascadeId, sqlRow] of rootRows.entries()) {
      if (processedIds.has(cascadeId)) continue;
      if (subtrajectoryIds.has(cascadeId) || this._brainScanCache.subtrajectoryIds.has(cascadeId)) continue;

      const ann = annotationsMap.get(cascadeId);
      if (ann && ann.archived) {
        this._pendingBlankConversations.delete(cascadeId);
        continue;
      }
      if (!this._hasLocalConversationData(cascadeId) && !this._pendingBlankConversations.has(cascadeId)) {
        continue;
      }

      const pendingMeta = this._pendingBlankConversations.get(cascadeId);
      const cachedConvo = this._persistentCache.conversations && this._persistentCache.conversations[cascadeId];
      const brainEntry = brainEntries.get(cascadeId);

      const stepCount = Number(sqlRow.step_count || (cachedConvo && cachedConvo.stepCount) || (brainEntry && brainEntry.stepCount) || 0);
      const updatedAt =
        this._normalizeIsoTime(sqlRow.last_modified_time) ||
        (cachedConvo && cachedConvo.updatedAt) ||
        (brainEntry && brainEntry.updatedAt) ||
        '';
      if (stepCount === 0 && !updatedAt && !pendingMeta) {
        continue;
      }

      const firstWsUri =
        parseFirstWsUriFromSqlRow(sqlRow) ||
        (pendingMeta && pendingMeta.workspaceUri) ||
        (cachedConvo && cachedConvo.workspaceUri) ||
        (brainEntry && brainEntry.workspaceUri) ||
        '';
      const workspacePath = firstWsUri ? decodeURIComponent(firstWsUri.replace(/^file:\/\//, '')) : '';
      const projectName = workspacePath ? path.basename(workspacePath) : '全局对话 (Scratch)';

      const previewLine = sqlRow.preview ? String(sqlRow.preview).split('\n')[0].slice(0, 48).trim() : '';
      const title =
        (ann && ann.title) ||
        (sqlRow.title && String(sqlRow.title).trim()) ||
        (pendingMeta && pendingMeta.title) ||
        (cachedConvo && cachedConvo.title) ||
        (brainEntry && brainEntry.title) ||
        previewLine ||
        `会话 ${cascadeId.slice(0, 8)}`;

      const createdAt =
        (cachedConvo && cachedConvo.createdAt) ||
        (brainEntry && brainEntry.createdAt) ||
        updatedAt;

      addConvo({
        id: cascadeId,
        trajectoryId: (cachedConvo && cachedConvo.trajectoryId) || '',
        title,
        projectName,
        workspaceUri: firstWsUri,
        workspacePath,
        stepCount,
        status: 'CASCADE_RUN_STATUS_IDLE',
        isRunning: false,
        createdAt,
        updatedAt
      });
    }

    // 3. 合并持久化缓存与本地 brain 目录中存在的其他非归档主会话
    const fallbackIds = new Set([
      ...Object.keys(this._persistentCache.conversations || {}),
      ...Array.from(brainEntries.keys())
    ]);
    for (const cascadeId of fallbackIds) {
      if (processedIds.has(cascadeId)) continue;
      if (subtrajectoryIds.has(cascadeId) || this._brainScanCache.subtrajectoryIds.has(cascadeId)) continue;
      const ann = annotationsMap.get(cascadeId);
      if (ann && ann.archived) continue;
      if (!this._hasLocalConversationData(cascadeId)) continue;

      const cachedConvo = this._persistentCache.conversations && this._persistentCache.conversations[cascadeId];
      const brainEntry = brainEntries.get(cascadeId);
      const stepCount = Number((cachedConvo && cachedConvo.stepCount) || (brainEntry && brainEntry.stepCount) || 0);
      if (stepCount === 0 && !this._pendingBlankConversations.has(cascadeId)) continue;

      const firstWsUri =
        (cachedConvo && cachedConvo.workspaceUri) ||
        (brainEntry && brainEntry.workspaceUri) ||
        '';
      const workspacePath = firstWsUri ? decodeURIComponent(firstWsUri.replace(/^file:\/\//, '')) : '';
      const projectName = workspacePath ? path.basename(workspacePath) : '全局对话 (Scratch)';
      const title =
        (ann && ann.title) ||
        (cachedConvo && cachedConvo.title) ||
        (brainEntry && brainEntry.title) ||
        `会话 ${cascadeId.slice(0, 8)}`;
      const updatedAt =
        (cachedConvo && this._normalizeIsoTime(cachedConvo.updatedAt)) ||
        (brainEntry && this._normalizeIsoTime(brainEntry.updatedAt)) ||
        '';
      const createdAt =
        (cachedConvo && this._normalizeIsoTime(cachedConvo.createdAt)) ||
        (brainEntry && this._normalizeIsoTime(brainEntry.createdAt)) ||
        updatedAt;

      addConvo({
        id: cascadeId,
        trajectoryId: (cachedConvo && cachedConvo.trajectoryId) || '',
        title,
        projectName,
        workspaceUri: firstWsUri,
        workspacePath,
        stepCount,
        status: 'CASCADE_RUN_STATUS_IDLE',
        isRunning: false,
        createdAt,
        updatedAt
      });
    }

    // 4. 补充刚创建但尚未发送首条消息的空会话，确保新建命名后立即出现在工作区会话列表中
    for (const [cascadeId, pendingMeta] of this._pendingBlankConversations.entries()) {
      if (processedIds.has(cascadeId)) continue;
      const firstWsUri = pendingMeta.workspaceUri || '';
      const workspacePath = firstWsUri ? decodeURIComponent(firstWsUri.replace(/^file:\/\//, '')) : '';
      const projectName = workspacePath ? path.basename(workspacePath) : '全局对话 (Scratch)';
      const nowIso = this._normalizeIsoTime(pendingMeta.createdAt) || new Date().toISOString();
      addConvo({
        id: cascadeId,
        trajectoryId: '',
        title: pendingMeta.title || `新对话 ${cascadeId.slice(0, 6)}`,
        projectName,
        workspaceUri: firstWsUri,
        workspacePath,
        stepCount: 0,
        status: 'CASCADE_RUN_STATUS_IDLE',
        isRunning: false,
        createdAt: nowIso,
        updatedAt: nowIso
      });
    }

    // 更新并持久化本地会话缓存
    const prevConvoCount = Object.keys(this._persistentCache.conversations || {}).length;
    const nextConvoCount = Object.keys(nextCachedConvos).length;
    this._persistentCache.conversations = nextCachedConvos;
    this._persistentCache.projects = nextCachedProjects;
    if (prevConvoCount !== nextConvoCount || !this._lastCacheSaveAt || Date.now() - this._lastCacheSaveAt > 10000) {
      this._lastCacheSaveAt = Date.now();
      this._savePersistentCache();
    }

    conversations.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));
    const projects = Array.from(projectsMap.values()).map((proj) => {
      proj.conversations.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));
      proj.updatedAt = proj.conversations[0]?.updatedAt || '';
      return proj;
    });
    projects.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));

    return {
      conversations,
      projects
    };
  }

  /**
   * 获取单个对话的完整结构化消息流、思考过程、工具调用与待审批交互 (pendingInteraction)
   * 若会话尚未加载进 language_server 内存，调用 GetCascadeTrajectory 会自动触发从 conversations/<id>.db 按需加载；
   * 若 RPC 获取失败或无步骤，则自动从本地 brain/<id>/.system_generated/logs/transcript.jsonl 完整恢复历史消息。
   */
  async getConversationDetail(cascadeId) {
    let res = {};
    try {
      res = await this.callRpc('GetCascadeTrajectory', { cascadeId });
    } catch (_) {
      res = {};
    }
    const trajectory = (res && res.trajectory) || {};
    const rawSteps = trajectory.steps || [];
    const trajectoryId = trajectory.trajectoryId || '';

    // 补充从 transcript.jsonl 中读取 plannerResponse 的完整文本与思考内容
    const transcriptMap = this._readLocalTranscriptMap(cascadeId);

    const messages = [];
    let pendingInteraction = null;
    let activeModel = null;

    for (let i = 0; i < rawSteps.length; i++) {
      const step = rawSteps[i];
      const type = step.type || '';
      const status = step.status || '';
      const meta = step.metadata || {};
      const createdAt = meta.createdAt || '';
      const tStep = transcriptMap.get(i);

      if (meta.generatorModel) {
        activeModel = meta.generatorModel;
      } else if (meta.modelUsage && meta.modelUsage.model) {
        activeModel = meta.modelUsage.model;
      }

      // 0. 捕获系统错误消息步骤 (CORTEX_STEP_TYPE_ERROR_MESSAGE)
      if (type === 'CORTEX_STEP_TYPE_ERROR_MESSAGE') {
        const errObj = (step.errorMessage && step.errorMessage.error) || {};
        const errText = errObj.shortError || errObj.userErrorMessage || '执行出错';
        messages.push({
          id: `step-${i}`,
          stepIndex: i,
          role: 'assistant',
          thinking: '',
          text: `⚠️ **执行报错**: ${errText}`,
          createdAt,
          status: 'CORTEX_STEP_STATUS_ERROR',
          isGenerating: false
        });
        continue;
      }

      // 1. 用户输入步骤
      if (type === 'CORTEX_STEP_TYPE_USER_INPUT') {
        const ui = step.userInput || {};
        const cfgModel =
          (ui.userConfig && ui.userConfig.plannerConfig && ui.userConfig.plannerConfig.planModel) ||
          (ui.lastUserConfig && ui.lastUserConfig.plannerConfig && ui.lastUserConfig.plannerConfig.planModel);
        if (cfgModel) {
          activeModel = cfgModel;
        }
        let text = ui.userResponse || '';
        let slashCommand = null;

        if (!text && Array.isArray(ui.items)) {
          const parts = [];
          for (const it of ui.items) {
            if (it.text) parts.push(it.text);
            if (it.item && it.item.slashCommand && it.item.slashCommand.info) {
              slashCommand = `/${it.item.slashCommand.info.name}`;
            }
          }
          text = parts.join('\n').trim();
        }
        if (!text && tStep && tStep.content) {
          text = this._cleanUserTags(tStep.content);
        }

        // 检查是否是 Artifact 审批通过动作
        if (!text && Array.isArray(ui.artifactComments) && ui.artifactComments.length > 0) {
          const ac = ui.artifactComments[0];
          const fileName = path.basename(decodeURIComponent((ac.artifactUri || '').replace(/^file:\/\//, '')));
          text = `✅ 已批准方案文档：${fileName}`;
        }

        // 检查用户是否附带了图片或视频媒体文件
        const rawMedia = Array.isArray(ui.media) && ui.media.length > 0
          ? ui.media
          : (tStep && Array.isArray(tStep.media) ? tStep.media : []);
        if (rawMedia.length > 0) {
          const mediaLabels = rawMedia.map((m) => {
            const mime = (m.mimeType || m.mime_type || '').toLowerCase();
            const desc = m.description || path.basename(m.uri || '') || '媒体文件';
            return mime.startsWith('video/') ? `🎬 [视频: ${desc}]` : `🖼️ [图片: ${desc}]`;
          });
          const badgeLine = mediaLabels.join('  ');
          text = text ? `${badgeLine}\n${text}` : badgeLine;
        }

        if (text || slashCommand) {
          messages.push({
            id: `step-${i}`,
            stepIndex: i,
            role: 'user',
            slashCommand,
            text: slashCommand && text ? `${slashCommand} ${text}` : text || slashCommand,
            createdAt,
            status
          });
        }
        continue;
      }

      // 2. AI 回复与思考步骤
      if (type === 'CORTEX_STEP_TYPE_PLANNER_RESPONSE') {
        const pr = step.plannerResponse || {};
        const thinking =
          pr.thinking ||
          pr.thought ||
          (tStep && tStep.thinking) ||
          '';
        const text =
          pr.response ||
          pr.text ||
          (tStep && tStep.content) ||
          '';
        const toolCalls = (tStep && tStep.tool_calls) || [];

        if (thinking || text || toolCalls.length > 0 || status === 'CORTEX_STEP_STATUS_GENERATING') {
          messages.push({
            id: `step-${i}`,
            stepIndex: i,
            role: 'assistant',
            thinking,
            text,
            model: (meta.modelUsage && meta.modelUsage.model) || meta.generatorModel || '',
            createdAt,
            status,
            isGenerating: status === 'CORTEX_STEP_STATUS_GENERATING' || status === 'CORTEX_STEP_STATUS_RUNNING'
          });
        }
        continue;
      }

      // 3. 工具调用与交互式审批步骤 (run_command / ask_question / write_file / permission)
      const toolCall = meta.toolCall || {};
      let toolArgs = {};
      if (toolCall.argumentsJson) {
        try {
          toolArgs = JSON.parse(toolCall.argumentsJson);
        } catch (_) {}
      }

      // 检查是否存在未完成的阻塞式交互请求 (requestedInteraction)
      const hasCompleted = Array.isArray(step.completedInteractions) && step.completedInteractions.length > 0;
      if (step.requestedInteraction && !hasCompleted) {
        pendingInteraction = this._formatPendingInteraction(cascadeId, trajectoryId, i, step.requestedInteraction, toolCall, toolArgs);
      } else if (
        type === 'CORTEX_STEP_TYPE_ASK_QUESTION' &&
        !hasCompleted &&
        status !== 'CORTEX_STEP_STATUS_DONE'
      ) {
        pendingInteraction = {
          kind: 'ask_question',
          cascadeId,
          trajectoryId,
          stepIndex: i,
          title: 'Agent 正在向您提问',
          questions: (step.askQuestion && step.askQuestion.questions) || toolArgs.questions || []
        };
      } else if (
        type === 'CORTEX_STEP_TYPE_CODE_ACTION' &&
        toolArgs.ArtifactMetadata &&
        toolArgs.ArtifactMetadata.RequestFeedback === true &&
        i >= rawSteps.length - 3
      ) {
        // 检查后续步骤是否已经批准过该 Artifact
        const alreadyApproved = rawSteps.slice(i + 1).some((s) => s.type === 'CORTEX_STEP_TYPE_USER_INPUT');
        if (!alreadyApproved) {
          const artifactPath = toolArgs.Path || '';
          pendingInteraction = {
            kind: 'artifact_approval',
            cascadeId,
            trajectoryId,
            stepIndex: i,
            title: '请审查实施计划 (Implementation Plan)',
            summary: toolArgs.ArtifactMetadata.Summary || path.basename(artifactPath),
            artifactPath,
            artifactUri: artifactPath.startsWith('file://') ? artifactPath : `file://${artifactPath}`,
            content: toolArgs.Content || ''
          };
        }
      }

      // 将关键工具执行加入消息流或附加到最近的 assistant 消息上
      if (toolCall.name) {
        messages.push({
          id: `step-${i}`,
          stepIndex: i,
          role: 'tool',
          toolName: toolCall.name,
          summary: this._summarizeToolCall(toolCall.name, toolArgs),
          status,
          createdAt
        });
      }
    }

    // 兜底：若 GetCascadeTrajectory 返回空步骤但本地存在 transcript.jsonl，直接从本地日志恢复完整历史消息流
    if (rawSteps.length === 0 && transcriptMap.size > 0) {
      const sortedIndices = Array.from(transcriptMap.keys()).sort((a, b) => a - b);
      for (const idx of sortedIndices) {
        const tStep = transcriptMap.get(idx);
        if (!tStep) continue;
        const tType = String(tStep.type || '').toUpperCase();
        const createdAt = tStep.created_at || '';

        if (tType === 'USER_INPUT') {
          let text = this._cleanUserTags(tStep.content || '');
          if (text.startsWith('<SYSTEM_MESSAGE>')) continue;
          const rawMedia = Array.isArray(tStep.media) ? tStep.media : [];
          if (rawMedia.length > 0) {
            const mediaLabels = rawMedia.map((m) => {
              const mime = (m.mimeType || m.mime_type || '').toLowerCase();
              const desc = m.description || path.basename(m.uri || '') || '媒体文件';
              return mime.startsWith('video/') ? `🎬 [视频: ${desc}]` : `🖼️ [图片: ${desc}]`;
            });
            const badgeLine = mediaLabels.join('  ');
            text = text ? `${badgeLine}\n${text}` : badgeLine;
          }
          if (text) {
            messages.push({
              id: `step-${idx}`,
              stepIndex: idx,
              role: 'user',
              slashCommand: null,
              text,
              createdAt,
              status: 'CORTEX_STEP_STATUS_DONE'
            });
          }
        } else if (tType === 'PLANNER_RESPONSE') {
          const thinking = tStep.thinking || '';
          const text = tStep.content || '';
          const toolCalls = Array.isArray(tStep.tool_calls) ? tStep.tool_calls : [];
          if (thinking || text) {
            messages.push({
              id: `step-${idx}`,
              stepIndex: idx,
              role: 'assistant',
              thinking,
              text,
              model: activeModel || '',
              createdAt,
              status: 'CORTEX_STEP_STATUS_DONE',
              isGenerating: false
            });
          }
          for (let ti = 0; ti < toolCalls.length; ti++) {
            const tc = toolCalls[ti] || {};
            const tcName = tc.name || tc.tool_name || '';
            if (!tcName) continue;
            let tcArgs = tc.arguments || tc.args || {};
            if (typeof tcArgs === 'string') {
              try {
                tcArgs = JSON.parse(tcArgs);
              } catch (_) {
                tcArgs = {};
              }
            }
            messages.push({
              id: `step-${idx}-tool-${ti}`,
              stepIndex: idx,
              role: 'tool',
              toolName: tcName,
              summary: this._summarizeToolCall(tcName, tcArgs),
              status: 'CORTEX_STEP_STATUS_DONE',
              createdAt
            });
          }
        }
      }
    }

    const recentDispatched = this._recentDispatchedUserMessages.get(cascadeId);
    if (recentDispatched) {
      if (Date.now() - recentDispatched.dispatchedAt > 10000) {
        this._recentDispatchedUserMessages.delete(cascadeId);
      } else {
        const tailUserMsgs = messages.slice(-4).filter((m) => m.role === 'user');
        const alreadyInSteps = tailUserMsgs.some((m) => (m.text || '').trim().includes(recentDispatched.text));
        if (alreadyInSteps) {
          this._recentDispatchedUserMessages.delete(cascadeId);
        } else {
          messages.push({
            id: `pending-dispatch-${recentDispatched.dispatchedAt}`,
            stepIndex: rawSteps.length,
            role: 'user',
            text: recentDispatched.text,
            createdAt: new Date(recentDispatched.dispatchedAt).toISOString(),
            status: 'CORTEX_STEP_STATUS_DONE'
          });
        }
      }
    }

    const recentlyDispatched =
      this._dispatchingSet.has(cascadeId) ||
      Date.now() - (this._lastDispatchTime.get(cascadeId) || 0) < 5000 ||
      this._recentDispatchedUserMessages.has(cascadeId);
    const isGenerating = recentlyDispatched || this._computeIsTurnGenerating(rawSteps, transcriptMap, res.status || '');
    const resolvedStatus = isGenerating
      ? 'CASCADE_RUN_STATUS_RUNNING'
      : (pendingInteraction ? 'CASCADE_RUN_STATUS_WAITING_FOR_USER' : 'CASCADE_RUN_STATUS_IDLE');

    this._resolvedStateCache.set(cascadeId, {
      stepCount: rawSteps.length,
      isGenerating,
      checkedAt: Date.now()
    });

    // 结合 generatorMetadata 最新项确认当前会话实际模型、权限模式与上下文窗口容量
    const genMeta = Array.isArray(trajectory.generatorMetadata) ? trajectory.generatorMetadata : [];
    let gmPermissionMode = '';
    if (genMeta.length > 0) {
      const lastGen = genMeta[genMeta.length - 1];
      const genModel =
        (lastGen && lastGen.plannerConfig && lastGen.plannerConfig.planModel) ||
        (lastGen && lastGen.chatModel && lastGen.chatModel.model);
      if (genModel) {
        activeModel = genModel;
      }
      for (let i = genMeta.length - 1; i >= 0; i--) {
        const tc = genMeta[i] && genMeta[i].plannerConfig && genMeta[i].plannerConfig.toolConfig;
        if (!tc) continue;
        const preset = tc.permissionConfig && tc.permissionConfig.effectivePermissionPreset;
        const policy = tc.runCommand && tc.runCommand.autoCommandConfig && tc.runCommand.autoCommandConfig.autoExecutionPolicy;
        const mapped = this._mapPolicyToPermissionMode(preset) || this._mapPolicyToPermissionMode(policy);
        if (mapped) {
          gmPermissionMode = mapped;
          this._lastKnownPermissionMode = mapped;
          break;
        }
      }
    }

    let stepPermissionMode = '';
    for (let i = rawSteps.length - 1; i >= 0; i--) {
      const ui = rawSteps[i] && rawSteps[i].userInput;
      if (!ui) continue;
      const uc = ui.userConfig || ui.lastUserConfig;
      const tc = uc && uc.plannerConfig && uc.plannerConfig.toolConfig;
      if (!tc) continue;
      const preset = tc.permissionConfig && tc.permissionConfig.effectivePermissionPreset;
      const policy = tc.runCommand && tc.runCommand.autoCommandConfig && tc.runCommand.autoCommandConfig.autoExecutionPolicy;
      const mapped = this._mapPolicyToPermissionMode(preset) || this._mapPolicyToPermissionMode(policy);
      if (mapped) {
        stepPermissionMode = mapped;
        break;
      }
    }

    const activePermissionMode =
      this._cascadePermissionModes.get(cascadeId) ||
      gmPermissionMode ||
      stepPermissionMode ||
      this._lastKnownPermissionMode ||
      'turbo';

    // 若当前轮次刚刚完成且该会话有排队待发送的消息，立即触发自动发送
    if (!isGenerating && !pendingInteraction && (this._messageQueues.get(cascadeId) || []).length > 0) {
      setImmediate(() => {
        this.processMessageQueues().catch(() => {});
      });
    }

    // 计算当前对话的上下文窗口容量使用情况 (usedTokens / maxTokens / usageFraction / usagePercent)
    let usedTokens = 0;
    let maxTokens = 256000;
    for (let i = genMeta.length - 1; i >= 0; i--) {
      const cm = genMeta[i] && genMeta[i].chatModel;
      if (!cm) continue;
      const cw = cm.chatStartMetadata && cm.chatStartMetadata.contextWindowMetadata;
      if (cw) {
        const est = Number(
          cw.estimatedTokensUsed ||
          (cw.tokenBreakdown && cw.tokenBreakdown.totalTokens) ||
          0
        );
        const max = Number(cw.maxContextTokens || 256000);
        if (est > 0) {
          usedTokens = est;
          if (max > 0) maxTokens = max;
          break;
        }
      }
      if (cm.usage) {
        const u =
          Number(cm.usage.inputTokens || 0) +
          Number(cm.usage.cacheReadTokens || 0) +
          Number(cm.usage.outputTokens || 0);
        if (u > 0) {
          usedTokens = u;
          if (cw && Number(cw.maxContextTokens) > 0) {
            maxTokens = Number(cw.maxContextTokens);
          }
          break;
        }
      }
    }
    const usageFraction = maxTokens > 0 ? Math.min(1, Math.max(0, usedTokens / maxTokens)) : 0;
    const usagePercent = Math.round(usageFraction * 1000) / 10;
    const contextUsage = {
      usedTokens,
      maxTokens,
      usageFraction,
      usagePercent
    };

    return {
      cascadeId,
      trajectoryId,
      status: resolvedStatus,
      isGenerating,
      stepCount: rawSteps.length || transcriptMap.size,
      activeModel,
      activePermissionMode,
      contextUsage,
      pendingInteraction,
      queuedMessages: this.getQueuedMessages(cascadeId),
      messages
    };
  }

  /**
   * 精准判断当前对话轮次是否真的正在思考/生成中：
   * 1. 若最后一个步骤已经是完成的 PLANNER_RESPONSE (DONE) 且没有未执行的工具调用，说明 AI 本轮回复已彻底结束，
   *    即使历史步骤中存在后台守护进程 (IsDaemon: true, status=RUNNING)，也绝不能误判为“AI 正在思考”。
   * 2. 仅检查最新一轮用户输入之后的步骤状态。
   */
  _computeIsTurnGenerating(rawSteps, transcriptMap, topStatus = '') {
    if (!Array.isArray(rawSteps) || rawSteps.length === 0) return false;

    const lastIdx = rawSteps.length - 1;
    const lastStep = rawSteps[lastIdx];
    const lastType = lastStep.type || '';
    const lastStatus = lastStep.status || '';

    // 如果最后一步已经是错误或取消，则肯定不在生成中
    if (
      lastType === 'CORTEX_STEP_TYPE_ERROR_MESSAGE' ||
      lastStatus === 'CORTEX_STEP_STATUS_CANCELED' ||
      lastStatus === 'CORTEX_STEP_STATUS_ERROR'
    ) {
      return false;
    }

    // 如果最后一步是 AI 回复 (PLANNER_RESPONSE)
    if (lastType === 'CORTEX_STEP_TYPE_PLANNER_RESPONSE') {
      if (lastStatus === 'CORTEX_STEP_STATUS_GENERATING' || lastStatus === 'CORTEX_STEP_STATUS_RUNNING') {
        return true;
      }
      if (lastStatus === 'CORTEX_STEP_STATUS_DONE') {
        // 检查该已完成步骤是否刚刚发起了工具调用且尚未追加工具步骤 (仅在 3 秒过渡期内视为运行中)
        const tLast = transcriptMap ? transcriptMap.get(lastIdx) : null;
        const hasToolCalls = Boolean(tLast && Array.isArray(tLast.tool_calls) && tLast.tool_calls.length > 0);
        if (hasToolCalls) {
          const createdMs = Date.parse((lastStep.metadata && lastStep.metadata.createdAt) || '') || 0;
          if (createdMs > 0 && Date.now() - createdMs < 3500) {
            return true;
          }
        }
        return false;
      }
    }

    // 如果最后一步本身正在 GENERATING / RUNNING / WAITING
    if (
      lastStatus === 'CORTEX_STEP_STATUS_GENERATING' ||
      lastStatus === 'CORTEX_STEP_STATUS_RUNNING' ||
      lastStatus === 'CORTEX_STEP_STATUS_WAITING'
    ) {
      return true;
    }

    // 如果最后一步刚完成 (例如 USER_INPUT 或工具步骤刚 DONE，正在等待下一轮 PLANNER_RESPONSE 创建)
    const createdMs = Date.parse((lastStep.metadata && lastStep.metadata.createdAt) || '') || 0;
    if (topStatus === 'CASCADE_RUN_STATUS_RUNNING' && createdMs > 0 && Date.now() - createdMs < 12000) {
      return true;
    }

    return false;
  }

  _formatPendingInteraction(cascadeId, trajectoryId, stepIndex, reqInt, toolCall, toolArgs) {
    if (reqInt.askQuestion) {
      return {
        kind: 'ask_question',
        cascadeId,
        trajectoryId,
        stepIndex,
        title: 'Agent 请求您的确认/选择',
        questions: reqInt.askQuestion.questions || []
      };
    }
    if (reqInt.runCommand) {
      return {
        kind: 'run_command',
        cascadeId,
        trajectoryId,
        stepIndex,
        title: '请求执行终端命令',
        commandLine:
          reqInt.runCommand.proposedCommandLine ||
          toolArgs.CommandLine ||
          '',
        cwd: reqInt.runCommand.cwd || ''
      };
    }
    if (reqInt.filePermission) {
      return {
        kind: 'file_permission',
        cascadeId,
        trajectoryId,
        stepIndex,
        title: '请求访问工作区外文件',
        pathUri: reqInt.filePermission.absolutePathUri || '',
        reason: reqInt.filePermission.blockReason || ''
      };
    }
    if (reqInt.permission) {
      return {
        kind: 'permission',
        cascadeId,
        trajectoryId,
        stepIndex,
        title: reqInt.permission.actionDescription || '请求工具执行权限',
        reason: reqInt.permission.reason || ''
      };
    }
    return {
      kind: 'generic_interaction',
      cascadeId,
      trajectoryId,
      stepIndex,
      title: '等待用户确认操作',
      raw: reqInt
    };
  }

  _summarizeToolCall(name, args) {
    switch (name) {
      case 'run_command':
        return `${args.toolSummary || '执行命令'}: \`${(args.CommandLine || '').slice(0, 80)}\``;
      case 'read_file':
        return `读取文件: ${path.basename(args.Path || '')}`;
      case 'write_file':
        return `写入文件: ${path.basename(args.Path || '')}`;
      case 'edit_file':
        return `修改文件: ${path.basename(args.Path || '')}`;
      case 'ask_question':
        return `向用户提问 (${(args.questions || []).length} 个问题)`;
      case 'search_web':
        return `搜索网页: ${args.query || ''}`;
      default:
        return `调用工具: ${name}`;
    }
  }

  _cleanUserTags(raw) {
    if (!raw || typeof raw !== 'string') return '';
    const m = raw.match(/<USER_REQUEST>\s*([\s\S]*?)\s*<\/USER_REQUEST>/i);
    return (m ? m[1] : raw).trim();
  }

  /**
   * 读取 ~/.gemini/antigravity/brain/<cascadeId>/.system_generated/logs/transcript.jsonl
   * 以便拿到完整的思考过程与实时流式文本
   */
  _readLocalTranscriptMap(cascadeId) {
    const map = new Map();
    if (!cascadeId || !/^[a-f0-9-]+$/i.test(cascadeId)) return map;
    const fullPath = path.join(BRAIN_DIR, cascadeId, '.system_generated', 'logs', 'transcript_full.jsonl');
    const compactPath = path.join(BRAIN_DIR, cascadeId, '.system_generated', 'logs', 'transcript.jsonl');
    const targetPath = fs.existsSync(fullPath) ? fullPath : compactPath;
    if (!fs.existsSync(targetPath)) return map;

    try {
      const stat = fs.statSync(targetPath);
      const cached = this._transcriptCache.get(cascadeId);
      if (cached && cached.targetPath === targetPath && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
        return cached.map;
      }

      const content = fs.readFileSync(targetPath, 'utf-8');
      const lines = content.split('\n');
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const obj = JSON.parse(line);
          if (typeof obj.step_index === 'number') {
            map.set(obj.step_index, obj);
          }
        } catch (_) {}
      }
      this._transcriptCache.set(cascadeId, { targetPath, mtimeMs: stat.mtimeMs, size: stat.size, map });
    } catch (_) {}
    return map;
  }

  /**
   * 构造完整的 Antigravity CascadeConfig 与 CustomAgentSpec
   * 关键修复：SendUserCascadeMessageRequest 必须携带完整的 cascadeConfig (含 declarativeMixinConfig、tools、hooks 以及非空的 plannerConfig.planModel)
   * 否则电脑端 AgentExecutor 会报错: "failed to construct executor: plan model not specified; you must specify a valid model"
   */
  _buildDefaultCascadeConfig(planModel = 'MODEL_PLACEHOLDER_M418') {
    return {
      plannerConfig: {
        declarativeMixinConfig: {
          promptSections: [
            { builtinName: 'identity' },
            { builtinName: 'terminal_sandbox' },
            { builtinName: 'artifacts' },
            { builtinName: 'conversation_transcript' },
            { builtinName: 'guidelines' },
            { builtinName: 'communication_style' },
            { builtinName: 'slash_commands' },
            { builtinName: 'messaging' },
            { builtinName: 'mcp_servers' },
            { builtinName: 'subagents' },
            { builtinName: 'user_rules' },
            { builtinName: 'skills' },
            { builtinName: 'user_information' },
            { builtinName: 'subagent_reminder' }
          ],
          tools: [
            { name: 'read_file', builtin: true },
            { name: 'rewrite_run_command', builtin: true },
            { name: 'rewrite_manage_task', builtin: true },
            { name: 'rewrite_send_message', builtin: true },
            { name: 'rewrite_schedule', builtin: true },
            { name: 'rewrite_invoke_subagent', builtin: true },
            { name: 'rewrite_define_subagent', builtin: true },
            { name: 'rewrite_manage_subagents', builtin: true },
            { name: 'write_file', builtin: true },
            { name: 'edit_file', builtin: true },
            { name: 'rewrite_search_web', builtin: true },
            { name: 'ask_question', builtin: true }
          ],
          preInvocationHooks: [
            { name: 'message_delivery', builtin: true },
            { name: 'context_summary', builtin: true }
          ],
          postInvocationHooks: [
            { name: 'command_assessor', builtin: true },
            { name: 'message_continue_check', builtin: true },
            { name: 'terminal_step_check', builtin: true },
            { name: 'max_generator_invocations_check', builtin: true },
            { name: 'empty_output_continuation_check', builtin: true },
            { name: 'force_invocation', builtin: true },
            { name: 'no_tool_call_check', builtin: true }
          ],
          preToolHooks: [
            { name: 'battle_mode_tool_args', builtin: true },
            { name: 'command_assessor', builtin: true },
            { name: 'timeout_long_running_search_command', builtin: true },
            { name: 'auto_run_safety_gate', builtin: true }
          ],
          postToolHooks: [
            { name: 'command_assessor', builtin: true }
          ],
          stopHooks: [
            { name: 'goal_stop', builtin: true },
            { name: 'idle_subagent_guard', builtin: true }
          ],
          toolDecorators: [
            { name: 'output_truncation', builtin: true }
          ],
          forceDisableFundamentalComponents: true
        },
        customizationDiscoveryConfig: {
          skills: {
            builtinSkillNames: [
              'agy-customizations',
              'antigravity_guide',
              'automation',
              'generative_ui',
              'migrate-workflows',
              'plugin',
              'ui-plugin-navigation'
            ]
          },
          agents: {
            builtinAgentNames: [
              'self',
              'research',
              'browser',
              'teamwork_preview',
              'DeepCoder',
              'DeepInvestigator',
              'image-generator'
            ]
          }
        },
        toolConfig: {
          runCommand: {
            autoCommandConfig: {
              autoExecutionPolicy: 'CASCADE_COMMANDS_AUTO_EXECUTION_EAGER'
            }
          },
          notifyUser: {}
        },
        planModel: planModel || 'MODEL_PLACEHOLDER_M418',
        useAiCredits: false,
        supportsLatexRendering: true
      },
      executorConfig: {
        useCoreDirect: true
      },
      conversationHistoryConfig: {}
    };
  }

  _buildDefaultAgentSpec() {
    return {
      builtinAgent: {
        defaultAgent: {
          isGoogle: false,
          isInteractive: true,
          surface: 'AGENT_SURFACE_HUB'
        }
      }
    };
  }

  _mapPolicyToPermissionMode(rawVal = '') {
    const raw = String(rawVal || '').trim().toUpperCase();
    if (!raw) return '';
    if (raw.includes('TURBO') || raw.includes('EAGER') || raw.includes('ALWAYS')) {
      return 'turbo';
    }
    if (raw.includes('OFF') || raw.includes('DISABLED') || raw.includes('REVIEW') || raw.includes('CAUTIOUS')) {
      return 'review';
    }
    if (raw.includes('AUTO')) {
      return 'auto';
    }
    return '';
  }

  _mapPermissionModeToPolicy(permissionMode = '') {
    const mode = String(permissionMode || '').trim().toLowerCase();
    if (mode === 'review' || mode === 'off' || mode === 'disabled') {
      return 'CASCADE_COMMANDS_AUTO_EXECUTION_OFF';
    }
    if (mode === 'auto') {
      return 'CASCADE_COMMANDS_AUTO_EXECUTION_AUTO';
    }
    if (mode === 'turbo' || mode === 'eager') {
      return 'CASCADE_COMMANDS_AUTO_EXECUTION_EAGER';
    }
    return '';
  }

  _mapPermissionModeToPreset(permissionMode = '') {
    const mode = String(permissionMode || '').trim().toLowerCase();
    if (mode === 'review' || mode === 'off' || mode === 'disabled') {
      return 'AGENT_PERMISSION_PRESET_REVIEW';
    }
    if (mode === 'auto') {
      return 'AGENT_PERMISSION_PRESET_AUTO';
    }
    if (mode === 'turbo' || mode === 'eager') {
      return 'AGENT_PERMISSION_PRESET_TURBO';
    }
    return '';
  }

  setConversationPermissionMode(cascadeId, permissionMode = '') {
    const clean = this._mapPolicyToPermissionMode(permissionMode);
    if (!clean) return this._lastKnownPermissionMode || 'turbo';
    this._lastKnownPermissionMode = clean;
    if (cascadeId) {
      this._cascadePermissionModes.set(cascadeId, clean);
    }
    return clean;
  }

  /**
   * 从目标会话历史步骤中提取最近一次有效的 userConfig 与 userAgentSpec，
   * 若会话刚创建尚无历史步骤，则回退使用标准完整配置模板。
   */
  async _resolveCascadeConfigAndAgentSpec(cascadeId, requestedModel = '', permissionMode = '') {
    let baseConfig = null;
    let baseAgentSpec = null;
    try {
      const traj = await this.callRpc('GetCascadeTrajectory', { cascadeId });
      const steps = (traj && traj.trajectory && traj.trajectory.steps) || [];
      for (let i = steps.length - 1; i >= 0; i--) {
        const ui = steps[i].userInput;
        if (ui && (ui.userConfig || ui.lastUserConfig)) {
          const candidate = ui.userConfig || ui.lastUserConfig;
          if (candidate && candidate.plannerConfig && candidate.plannerConfig.declarativeMixinConfig) {
            baseConfig = JSON.parse(JSON.stringify(candidate));
          }
          if (ui.userAgentSpec) {
            baseAgentSpec = JSON.parse(JSON.stringify(ui.userAgentSpec));
          }
          if (baseConfig) break;
        }
      }
    } catch (_) {}

    if (!baseConfig) {
      baseConfig = this._buildDefaultCascadeConfig(requestedModel || 'MODEL_PLACEHOLDER_M418');
    }

    if (!baseConfig.plannerConfig) {
      baseConfig.plannerConfig = {};
    }
    if (requestedModel && requestedModel.trim()) {
      baseConfig.plannerConfig.planModel = requestedModel.trim();
    } else if (!baseConfig.plannerConfig.planModel) {
      baseConfig.plannerConfig.planModel = 'MODEL_PLACEHOLDER_M418';
    }

    const effectiveMode = permissionMode || this._cascadePermissionModes.get(cascadeId) || this._lastKnownPermissionMode || 'turbo';
    const mappedPolicy = this._mapPermissionModeToPolicy(effectiveMode);
    const mappedPreset = this._mapPermissionModeToPreset(effectiveMode);
    if (mappedPolicy) {
      if (!baseConfig.plannerConfig.toolConfig) {
        baseConfig.plannerConfig.toolConfig = { notifyUser: {} };
      }
      if (!baseConfig.plannerConfig.toolConfig.runCommand) {
        baseConfig.plannerConfig.toolConfig.runCommand = {};
      }
      if (!baseConfig.plannerConfig.toolConfig.runCommand.autoCommandConfig) {
        baseConfig.plannerConfig.toolConfig.runCommand.autoCommandConfig = {};
      }
      baseConfig.plannerConfig.toolConfig.runCommand.autoCommandConfig.autoExecutionPolicy = mappedPolicy;
      if (mappedPreset && baseConfig.plannerConfig.toolConfig.permissionConfig) {
        baseConfig.plannerConfig.toolConfig.permissionConfig.effectivePermissionPreset = mappedPreset;
      }
    }

    if (!baseAgentSpec) {
      baseAgentSpec = this._buildDefaultAgentSpec();
    }

    return {
      cascadeConfig: baseConfig,
      customAgentSpec: baseAgentSpec
    };
  }

  /**
   * 获取指定会话当前排队中的消息列表
   */
  getQueuedMessages(cascadeId) {
    if (!cascadeId) return [];
    return [...(this._messageQueues.get(cascadeId) || [])];
  }

  /**
   * 检查指定会话当前是否正在运行/思考或等待用户审批
   */
  async _isCascadeCurrentlyRunning(cascadeId) {
    if (this._dispatchingSet.has(cascadeId)) return true;
    const lastSent = this._lastDispatchTime.get(cascadeId) || 0;
    if (Date.now() - lastSent < 3500) {
      return true;
    }
    try {
      const res = await this.callRpc('GetCascadeTrajectory', { cascadeId });
      const status = (res && res.status) || '';
      if (status === 'CASCADE_RUN_STATUS_WAITING_FOR_USER') {
        return true;
      }
      const steps = (res && res.trajectory && res.trajectory.steps) || [];
      const transcriptMap = this._readLocalTranscriptMap(cascadeId);
      if (this._computeIsTurnGenerating(steps, transcriptMap, status)) {
        return true;
      }
      for (let i = Math.max(0, steps.length - 5); i < steps.length; i++) {
        const hasCompleted = Array.isArray(steps[i].completedInteractions) && steps[i].completedInteractions.length > 0;
        if (steps[i].requestedInteraction && !hasCompleted) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /**
   * 将手机端上传的媒体文件保存到会话的 .user_uploaded 目录，并返回整理后的 Media 数组与本地路径
   */
  _prepareUploadedMedia(cascadeId, mediaList) {
    if (!Array.isArray(mediaList) || mediaList.length === 0) {
      return { protoMedia: [], savedPaths: [] };
    }
    const uploadDir = path.join(BRAIN_DIR, cascadeId, '.user_uploaded');
    try {
      fs.mkdirSync(uploadDir, { recursive: true });
    } catch (_) {}

    const protoMedia = [];
    const savedPaths = [];

    for (const item of mediaList) {
      const rawBase64 = (item.inlineData || item.data || '').replace(/^data:[^;]+;base64,/, '');
      if (!rawBase64) continue;
      const mimeType = item.mimeType || 'image/jpeg';
      const origName = item.fileName || item.description || '';
      let ext = path.extname(origName);
      if (!ext) {
        if (mimeType.includes('png')) ext = '.png';
        else if (mimeType.includes('gif')) ext = '.gif';
        else if (mimeType.includes('webp')) ext = '.webp';
        else if (mimeType.includes('mp4')) ext = '.mp4';
        else if (mimeType.includes('quicktime') || mimeType.includes('mov')) ext = '.mov';
        else ext = '.jpg';
      }
      const safeFileName = `media_${Date.now()}_${Math.random().toString(16).slice(2, 10)}${ext}`;
      const fullPath = path.join(uploadDir, safeFileName);
      try {
        fs.writeFileSync(fullPath, Buffer.from(rawBase64, 'base64'));
        savedPaths.push(fullPath);
      } catch (_) {}

      protoMedia.push({
        mimeType,
        description: origName || safeFileName,
        inlineData: rawBase64
      });
    }

    return { protoMedia, savedPaths };
  }

  /**
   * 立即向 language_server 派发消息（内部底层方法，支持图片与视频附件）
   */
  async _dispatchMessageNow({ cascadeId, text, model, media, artifactApprovalUri, permissionMode }) {
    this._dispatchingSet.add(cascadeId);
    this._lastDispatchTime.set(cascadeId, Date.now());
    const rawCleanText = (text || '').trim();
    if (rawCleanText || (Array.isArray(media) && media.length > 0)) {
      this._recentDispatchedUserMessages.set(cascadeId, {
        text: rawCleanText || '请查看我上传的图片/视频',
        dispatchedAt: Date.now()
      });
    }
    try {
      const { cascadeConfig, customAgentSpec } = await this._resolveCascadeConfigAndAgentSpec(
        cascadeId,
        model,
        permissionMode
      );
      const { protoMedia, savedPaths } = this._prepareUploadedMedia(cascadeId, media);

      const payload = {
        cascadeId,
        items: [],
        cascadeConfig,
        customAgentSpec
      };

      if (artifactApprovalUri) {
        payload.artifactComments = [
          {
            artifactUri: artifactApprovalUri.startsWith('file://')
              ? artifactApprovalUri
              : `file://${artifactApprovalUri}`,
            fullFile: {},
            approvalStatus: 'ARTIFACT_APPROVAL_STATUS_APPROVED'
          }
        ];
      }

      const cleanText = (text || '').trim();
      if (cleanText) {
        payload.items.push({ text: cleanText });
      } else if (protoMedia.length > 0) {
        payload.items.push({ text: '请查看我上传的图片/视频' });
      }

      if (protoMedia.length > 0) {
        payload.media = protoMedia;
      }

      let rpcRes;
      try {
        rpcRes = await this.callRpc('SendUserCascadeMessage', payload);
      } catch (err) {
        // 如果某些视频格式通过 inlineData 直接传给模型被拒，自动回退为本地文件引用方式发送
        if (protoMedia.length > 0 && savedPaths.length > 0) {
          delete payload.media;
          const fallbackNote = `\n\n[用户已上传媒体文件至电脑端路径，请直接调用 read_file 查看：\n${savedPaths.map((p) => `- ${p}`).join('\n')}\n]`;
          payload.items = [{ text: (cleanText || '请查看我上传的媒体文件') + fallbackNote }];
          rpcRes = await this.callRpc('SendUserCascadeMessage', payload);
        } else {
          throw err;
        }
      }

      this._lastDispatchTime.set(cascadeId, Date.now());
      const pendingEntry = this._recentDispatchedUserMessages.get(cascadeId);
      if (pendingEntry) {
        pendingEntry.dispatchedAt = Date.now();
      }
      // 若该会话是新建时预设了自定义名称的空会话，在首条消息落盘后同步持久化标题注解
      const pendingBlank = this._pendingBlankConversations.get(cascadeId);
      if (pendingBlank && pendingBlank.title) {
        try {
          await this.renameConversation(cascadeId, pendingBlank.title);
        } catch (_) {}
      }
      return { queued: false, queuedMessages: this.getQueuedMessages(cascadeId), rpcRes };
    } finally {
      this._dispatchingSet.delete(cascadeId);
    }
  }

  /**
   * 向现有对话发送用户消息（支持自动排队与图片/视频上传，避免多条消息重叠打断）
   */
  async sendMessage({ cascadeId, text, model, media, artifactApprovalUri, queueIfBusy = true, permissionMode = '' }) {
    if (!cascadeId) throw new Error('缺少 cascadeId');

    const hasMedia = Array.isArray(media) && media.length > 0;

    // Artifact 审批或强制立即发送时直接派发
    if (artifactApprovalUri || queueIfBusy === false) {
      return await this._dispatchMessageNow({
        cascadeId,
        text,
        model,
        media,
        artifactApprovalUri,
        permissionMode
      });
    }

    const cleanText = (text || '').trim();
    if (!cleanText && !hasMedia) return { queued: false, queuedMessages: this.getQueuedMessages(cascadeId) };

    const existingQueue = this._messageQueues.get(cascadeId) || [];
    const isBusy = existingQueue.length > 0 || (await this._isCascadeCurrentlyRunning(cascadeId));

    if (isBusy) {
      const item = {
        id: `q-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        text: cleanText || (hasMedia ? `[已附带 ${media.length} 个媒体文件]` : ''),
        model: model || '',
        permissionMode: permissionMode || '',
        media: hasMedia ? media : undefined,
        createdAt: new Date().toISOString()
      };
      existingQueue.push(item);
      this._messageQueues.set(cascadeId, existingQueue);
      return {
        queued: true,
        queuedItem: { id: item.id, text: item.text, model: item.model, createdAt: item.createdAt },
        queuedMessages: this.getQueuedMessages(cascadeId)
      };
    }

    return await this._dispatchMessageNow({ cascadeId, text: cleanText, model, media, permissionMode });
  }

  /**
   * 后台队列推进器：当会话上一轮回复完成变为空闲时，自动按顺序发送队列中的下一条消息
   */
  async processMessageQueues() {
    for (const [cascadeId, queue] of this._messageQueues.entries()) {
      if (!queue || queue.length === 0) continue;
      if (this._dispatchingSet.has(cascadeId)) continue;
      const busy = await this._isCascadeCurrentlyRunning(cascadeId);
      if (!busy) {
        const nextItem = queue.shift();
        if (queue.length === 0) {
          this._messageQueues.delete(cascadeId);
        }
        try {
          await this._dispatchMessageNow({
            cascadeId,
            text: nextItem.text,
            model: nextItem.model,
            media: nextItem.media,
            permissionMode: nextItem.permissionMode
          });
        } catch (err) {
          console.error(`[QueueProcessor] 自动派发排队消息失败 (${cascadeId}):`, err.message);
        }
      }
    }
  }

  /**
   * 从排队队列中删除某条尚未发送的消息
   */
  removeQueuedMessage(cascadeId, queueId) {
    if (!cascadeId) return [];
    const queue = this._messageQueues.get(cascadeId) || [];
    const filtered = queueId ? queue.filter((item) => item.id !== queueId) : [];
    if (filtered.length > 0) {
      this._messageQueues.set(cascadeId, filtered);
    } else {
      this._messageQueues.delete(cascadeId);
    }
    return this.getQueuedMessages(cascadeId);
  }

  /**
   * 立即插队发送队列中的指定消息（或首条消息）
   */
  async flushQueuedMessage(cascadeId, queueId = '') {
    if (!cascadeId) throw new Error('缺少 cascadeId');
    const queue = this._messageQueues.get(cascadeId) || [];
    if (queue.length === 0) return { flushed: false, queuedMessages: [] };

    let idx = 0;
    if (queueId) {
      const found = queue.findIndex((item) => item.id === queueId);
      if (found !== -1) idx = found;
    }
    const [target] = queue.splice(idx, 1);
    if (queue.length === 0) {
      this._messageQueues.delete(cascadeId);
    }
    await this._dispatchMessageNow({
      cascadeId,
      text: target.text,
      model: target.model,
      media: target.media
    });
    return {
      flushed: true,
      flushedItem: target,
      queuedMessages: this.getQueuedMessages(cascadeId)
    };
  }

  /**
   * 创建新对话：支持仅设置对话名称（不作为消息发送），或同时发送首条消息
   */
  async startConversation({ workspaceUri, title, text, model, media, permissionMode }) {
    const startPayload = {
      source: 'CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT',
      trajectoryType: 'CORTEX_TRAJECTORY_TYPE_CASCADE'
    };
    let normalizedWsUri = '';
    if (workspaceUri) {
      normalizedWsUri = workspaceUri.startsWith('file://') ? workspaceUri : `file://${workspaceUri}`;
      startPayload.workspaceUris = [normalizedWsUri];
    }

    const res = await this.callRpc('StartCascade', startPayload);
    const cascadeId = res && res.cascadeId;
    const cleanTitle = String(title || '').trim();
    if (cascadeId) {
      this._pendingBlankConversations.set(cascadeId, {
        id: cascadeId,
        title: cleanTitle || `新对话 ${cascadeId.slice(0, 6)}`,
        workspaceUri: normalizedWsUri,
        createdAt: new Date().toISOString()
      });
      if (cleanTitle) {
        try {
          await this.renameConversation(cascadeId, cleanTitle);
        } catch (_) {}
      }
    }
    const hasMedia = Array.isArray(media) && media.length > 0;
    if (cascadeId && ((text && text.trim()) || hasMedia)) {
      await this.sendMessage({
        cascadeId,
        text: (text || '').trim(),
        model,
        media,
        permissionMode
      });
    }
    return { cascadeId, title: cleanTitle, ...res };
  }

  /**
   * 远程处理权限审批、终端命令确认或回答 ask_question 多选题
   */
  async handleInteraction({
    cascadeId,
    trajectoryId,
    stepIndex,
    kind,
    allow = true,
    commandLine,
    questionResponses,
    artifactUri
  }) {
    if (kind === 'artifact_approval' || artifactUri) {
      return await this.sendMessage({
        cascadeId,
        artifactApprovalUri: artifactUri,
        text: allow ? '' : '请根据我的反馈修改方案。'
      });
    }

    const interaction = {
      trajectoryId,
      stepIndex: Number(stepIndex)
    };

    if (kind === 'run_command') {
      interaction.runCommand = {
        confirm: Boolean(allow),
        proposedCommandLine: commandLine || '',
        submittedCommandLine: commandLine || ''
      };
    } else if (kind === 'file_permission') {
      interaction.filePermission = {
        allow: Boolean(allow)
      };
    } else if (kind === 'ask_question') {
      interaction.askQuestion = {
        responses: questionResponses || []
      };
    } else {
      interaction.permission = {
        allow: Boolean(allow)
      };
    }

    return await this.callRpc('HandleCascadeUserInteraction', {
      cascadeId,
      interaction
    });
  }

  /**
   * 立即停止/中断正在运行的 Agent
   */
  async cancelCascade(cascadeId) {
    return await this.callRpc('CancelCascadeInvocation', {
      cascadeId,
      killBackgroundTasks: false
    });
  }

  /**
   * 重命名指定对话 (同步更新电脑端 Antigravity 的 ConversationAnnotations.title 与本地持久化缓存)
   */
  async renameConversation(cascadeId, title) {
    if (!cascadeId) throw new Error('缺少 cascadeId');
    const cleanTitle = String(title || '').trim();
    if (!cleanTitle) throw new Error('标题不能为空');
    const pendingBlank = this._pendingBlankConversations.get(cascadeId);
    if (pendingBlank) {
      pendingBlank.title = cleanTitle;
    }
    if (this._persistentCache.conversations && this._persistentCache.conversations[cascadeId]) {
      this._persistentCache.conversations[cascadeId].title = cleanTitle;
      this._savePersistentCache();
    }
    let res;
    try {
      res = await this.callRpc('UpdateConversationAnnotations', {
        cascadeId,
        annotations: { title: cleanTitle },
        mergeAnnotations: true
      });
    } catch (err) {
      // 若该历史会话尚未加载进 language_server 内存，先触发 GetCascadeTrajectory 加载再更新注解
      await this.callRpc('GetCascadeTrajectory', { cascadeId }).catch(() => {});
      res = await this.callRpc('UpdateConversationAnnotations', {
        cascadeId,
        annotations: { title: cleanTitle },
        mergeAnnotations: true
      });
    }
    this._annotationsCache.checkedAt = 0;
    return res;
  }

  /**
   * 归档/取消归档指定对话 (同步更新电脑端 Antigravity 的 ConversationAnnotations.archived 与本地持久化缓存)
   */
  async archiveConversation(cascadeId, archived = true) {
    if (!cascadeId) throw new Error('缺少 cascadeId');
    if (archived) {
      this._pendingBlankConversations.delete(cascadeId);
      if (this._persistentCache.conversations && this._persistentCache.conversations[cascadeId]) {
        delete this._persistentCache.conversations[cascadeId];
        this._savePersistentCache();
      }
    }
    let res;
    try {
      res = await this.callRpc('UpdateConversationAnnotations', {
        cascadeId,
        annotations: { archived: Boolean(archived) },
        mergeAnnotations: true
      });
    } catch (err) {
      await this.callRpc('GetCascadeTrajectory', { cascadeId }).catch(() => {});
      res = await this.callRpc('UpdateConversationAnnotations', {
        cascadeId,
        annotations: { archived: Boolean(archived) },
        mergeAnnotations: true
      });
    }
    this._annotationsCache.checkedAt = 0;
    return res;
  }

  /**
   * 获取可用模型列表与配额状态 (含 RetrieveUserQuotaSummary 的 5小时额度 与 周额度)
   */
  async getModels() {
    const [modelsRes, quotaRes] = await Promise.allSettled([
      this.callRpc('GetCascadeModelConfigData', {}),
      this.callRpc('RetrieveUserQuotaSummary', {})
    ]);

    const configs =
      modelsRes.status === 'fulfilled' && modelsRes.value && Array.isArray(modelsRes.value.clientModelConfigs)
        ? modelsRes.value.clientModelConfigs
        : [];

    const quotaGroups =
      quotaRes.status === 'fulfilled' &&
      quotaRes.value &&
      quotaRes.value.response &&
      Array.isArray(quotaRes.value.response.groups)
        ? quotaRes.value.response.groups
        : [];

    const bucketMap = new Map();
    for (const grp of quotaGroups) {
      for (const b of grp.buckets || []) {
        if (b && b.bucketId) {
          bucketMap.set(b.bucketId, b);
        }
      }
    }

    return configs
      .filter((c) => Boolean(c && c.label && String(c.label).trim()))
      .map((c) => {
      const label = c.label || '';
      const isGemini = label.toLowerCase().includes('gemini');
      const b5h = bucketMap.get(isGemini ? 'gemini-5h' : '3p-5h');
      const bWeekly = bucketMap.get(isGemini ? 'gemini-weekly' : '3p-weekly');
      const fallbackFrac = c.quotaInfo && typeof c.quotaInfo.remainingFraction === 'number' ? c.quotaInfo.remainingFraction : 1;

      const fiveHourFrac =
        b5h && typeof b5h.remainingFraction === 'number' ? b5h.remainingFraction : fallbackFrac;
      const weeklyFrac =
        bWeekly && typeof bWeekly.remainingFraction === 'number' ? bWeekly.remainingFraction : fallbackFrac;

      return {
        label,
        modelId: (c.modelOrAlias && (c.modelOrAlias.model || c.modelOrAlias.alias)) || '',
        isRecommended: Boolean(c.isRecommended),
        supportsImages: Boolean(c.supportsImages),
        tagTitle: c.tagTitle || '',
        remainingFraction: fiveHourFrac,
        resetTime: (b5h && b5h.resetTime) || (c.quotaInfo ? c.quotaInfo.resetTime : null),
        fiveHourRemainingFraction: fiveHourFrac,
        fiveHourResetTime: (b5h && b5h.resetTime) || null,
        fiveHourDescription: (b5h && b5h.description) || '',
        weeklyRemainingFraction: weeklyFrac,
        weeklyResetTime: (bWeekly && bWeekly.resetTime) || null,
        weeklyDescription: (bWeekly && bWeekly.description) || ''
      };
    });
  }

  /**
   * 获取指定会话的文件变更 Diff 与生成的 Artifacts
   */
  async getDiffsAndArtifacts(cascadeId) {
    const [diffsRes, artifactsRes] = await Promise.allSettled([
      this.callRpc('GetTrajectoryFileDiffs', { conversationId: cascadeId }),
      this.callRpc('GetArtifactSnapshots', { cascadeId })
    ]);

    const diffs =
      diffsRes.status === 'fulfilled' && Array.isArray(diffsRes.value.diffs)
        ? diffsRes.value.diffs.map((d) => ({
            uri: d.uri || '',
            filePath: decodeURIComponent((d.uri || '').replace(/^file:\/\//, '')),
            fileName: path.basename(decodeURIComponent((d.uri || '').replace(/^file:\/\//, ''))),
            originalContent: d.originalContent || '',
            modifiedContent: d.modifiedContent || ''
          }))
        : [];

    const artifacts =
      artifactsRes.status === 'fulfilled' && Array.isArray(artifactsRes.value.artifactSnapshots)
        ? artifactsRes.value.artifactSnapshots.map((a) => {
            const filePath = decodeURIComponent((a.artifactAbsoluteUri || '').replace(/^file:\/\//, ''));
            let content = '';
            if (filePath && fs.existsSync(filePath) && /\.(md|txt|json|html)$/i.test(filePath)) {
              try {
                content = fs.readFileSync(filePath, 'utf-8');
              } catch (_) {}
            }
            return {
              name: a.artifactName || path.basename(filePath),
              uri: a.artifactAbsoluteUri || '',
              filePath,
              lastEdited: a.lastEdited || '',
              content
            };
          })
        : [];

    // 补充扫描 ~/.gemini/antigravity/brain/<cascadeId> 下的 .md / .html 文件
    const brainFolder = path.join(BRAIN_DIR, cascadeId);
    if (fs.existsSync(brainFolder)) {
      try {
        const files = fs.readdirSync(brainFolder);
        for (const f of files) {
          if (/\.(md|html)$/i.test(f)) {
            const full = path.join(brainFolder, f);
            if (!artifacts.some((a) => a.filePath === full)) {
              artifacts.push({
                name: f,
                uri: `file://${full}`,
                filePath: full,
                lastEdited: fs.statSync(full).mtime.toISOString(),
                content: fs.readFileSync(full, 'utf-8')
              });
            }
          }
        }
      } catch (_) {}
    }

    return { diffs, artifacts };
  }

  /**
   * 获取后台终端列表与发送终端输入
   */
  async listTerminals(conversationId = '') {
    const res = await this.callRpc('ListTerminals', conversationId ? { conversationId } : {});
    return (res && res.terminals) || [];
  }

  async sendTerminalInput(terminalId, input) {
    return await this.callRpc('SendTerminalInput', {
      terminalId,
      input
    });
  }
}

module.exports = { AntigravityRpcClient };
