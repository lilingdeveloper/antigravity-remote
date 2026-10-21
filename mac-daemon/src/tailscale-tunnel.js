const os = require('os');
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

/**
 * 判断 IPv4 地址是否属于 Tailscale CGNAT 地址段 (100.64.0.0/10: 100.64.x.x ~ 100.127.x.x)
 */
function isTailscaleIPv4(ip) {
  if (!ip || typeof ip !== 'string') return false;
  const parts = ip.trim().split('.');
  if (parts.length !== 4) return false;
  const first = Number(parts[0]);
  const second = Number(parts[1]);
  if (Number.isNaN(first) || Number.isNaN(second)) return false;
  return first === 100 && second >= 64 && second <= 127;
}

/**
 * 扫描本机 utun* 接口与局域网接口
 * TailnetManager 系统级互斥逻辑：
 * - 当检测到电脑系统已开启 Tailscale (utun* 持有 100.64.0.0/10 地址) 时：
 *   自动抑制/关闭软件内置的 Tailscale 引擎 (suppressedBySystem = true)，直接复用系统级 Tailscale IP
 */
class TailscaleAndTunnelManager {
  constructor(options = {}) {
    this.port = options.port || 8788;
    this.embeddedEnabled = options.embeddedEnabled !== false;
    this.systemTailscaleActive = false;
    this.suppressedBySystem = false;
    this.systemTailscaleIP = null;
    this.systemTailscaleInterface = null;
    this.magicDNSName = null;
    this.lanIP = null;
    this.embeddedProcess = null;
    this.cloudflaredProcess = null;
    this.cloudflareTunnelUrl = null;
    this.watcherTimer = null;
  }

  /**
   * 扫描本机网卡获取系统级 Tailscale IP (utun*) 与局域网 IP (en*)
   */
  scanNetworkInterfaces() {
    const interfaces = os.networkInterfaces();
    let tailscaleIP = null;
    let tailscaleIface = null;
    let lanIP = null;

    for (const [name, addrs] of Object.entries(interfaces)) {
      if (!addrs) continue;
      for (const addr of addrs) {
        if (addr.family !== 'IPv4' || addr.internal) continue;
        if (name.startsWith('utun') && isTailscaleIPv4(addr.address)) {
          tailscaleIP = addr.address;
          tailscaleIface = name;
        } else if (
          !lanIP &&
          (name.startsWith('en') || name.startsWith('eth') || name.startsWith('wlan')) &&
          !isTailscaleIPv4(addr.address)
        ) {
          lanIP = addr.address;
        }
      }
    }

    // 尝试补充读取系统 Tailscale CLI 状态以获取主机名与 MagicDNS 名
    let magicDNS = null;
    let tailscaleHost = os.hostname();
    if (tailscaleIP) {
      const cliPaths = [
        '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
        '/usr/local/bin/tailscale',
        '/opt/homebrew/bin/tailscale'
      ];
      for (const cli of cliPaths) {
        if (fs.existsSync(cli)) {
          try {
            const raw = execSync(`"${cli}" status --json`, {
              encoding: 'utf-8',
              timeout: 1500,
              stdio: ['ignore', 'pipe', 'ignore']
            });
            const st = JSON.parse(raw);
            if (st && st.Self) {
              magicDNS = (st.Self.DNSName || '').replace(/\.$/, '') || null;
              tailscaleHost = st.Self.HostName || tailscaleHost;
            }
            break;
          } catch (_) {}
        }
      }
    }

    const prevActive = this.systemTailscaleActive;
    this.systemTailscaleIP = tailscaleIP;
    this.systemTailscaleInterface = tailscaleIface;
    this.magicDNSName = magicDNS;
    this.lanIP = lanIP;
    this.systemTailscaleActive = Boolean(tailscaleIP);

    // 核心互斥逻辑：如果电脑上开了系统级 Tailscale，立即关闭/抑制软件内置的 Tailscale 引擎
    if (this.systemTailscaleActive) {
      if (this.embeddedProcess) {
        console.log(
          `[TailnetManager] ⚠️ 检测到电脑系统级 Tailscale 上线 (${tailscaleIface}: ${tailscaleIP}) → 自动关闭软件内置 Tailscale 节点，避免双节点冲突`
        );
        this.stopEmbeddedTailscale();
      }
      this.suppressedBySystem = true;
    } else if (prevActive && !this.systemTailscaleActive) {
      console.log('[TailnetManager] 系统级 Tailscale 已下线，解除内置引擎抑制状态');
      this.suppressedBySystem = false;
    }

    return this.getStatus();
  }

  /**
   * 启动周期性网络接口监控 (每 10 秒检查一次系统级 Tailscale 状态变化)
   */
  startWatcher(intervalMs = 10000) {
    this.scanNetworkInterfaces();
    if (this.watcherTimer) clearInterval(this.watcherTimer);
    this.watcherTimer = setInterval(() => {
      this.scanNetworkInterfaces();
    }, intervalMs);
  }

  stopEmbeddedTailscale() {
    if (this.embeddedProcess) {
      try {
        this.embeddedProcess.kill('SIGTERM');
      } catch (_) {}
      this.embeddedProcess = null;
    }
  }

  /**
   * 按需启动 Cloudflare Quick Tunnel (供无 Tailscale 环境下的 4G/5G 外网应急连接)
   */
  async startCloudflareTunnel() {
    if (this.cloudflaredProcess && this.cloudflareTunnelUrl) {
      return { started: true, url: this.cloudflareTunnelUrl };
    }
    return new Promise((resolve) => {
      let resolved = false;
      try {
        const proc = spawn('cloudflared', ['tunnel', '--url', `http://127.0.0.1:${this.port}`], {
          stdio: ['ignore', 'pipe', 'pipe']
        });
        this.cloudflaredProcess = proc;

        const onData = (chunk) => {
          const text = chunk.toString();
          const m = text.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/i);
          if (m && !resolved) {
            resolved = true;
            this.cloudflareTunnelUrl = m[0];
            resolve({ started: true, url: this.cloudflareTunnelUrl });
          }
        };

        proc.stdout.on('data', onData);
        proc.stderr.on('data', onData);
        proc.on('error', (err) => {
          this.cloudflaredProcess = null;
          if (!resolved) {
            resolved = true;
            resolve({ started: false, error: `未找到 cloudflared 命令 (${err.message})` });
          }
        });
        proc.on('exit', () => {
          this.cloudflaredProcess = null;
          this.cloudflareTunnelUrl = null;
        });

        setTimeout(() => {
          if (!resolved) {
            resolved = true;
            resolve({
              started: Boolean(this.cloudflareTunnelUrl),
              url: this.cloudflareTunnelUrl,
              error: this.cloudflareTunnelUrl ? null : '等待 Cloudflare Tunnel 分配域名超时'
            });
          }
        }, 8000);
      } catch (err) {
        resolve({ started: false, error: err.message });
      }
    });
  }

  stopCloudflareTunnel() {
    if (this.cloudflaredProcess) {
      try {
        this.cloudflaredProcess.kill('SIGTERM');
      } catch (_) {}
      this.cloudflaredProcess = null;
      this.cloudflareTunnelUrl = null;
    }
  }

  getStatus() {
    return {
      hostname: os.hostname(),
      port: this.port,
      lanIP: this.lanIP,
      lanIp: this.lanIP,
      lanUrl: this.lanIP ? `http://${this.lanIP}:${this.port}` : null,
      systemTailscaleActive: this.systemTailscaleActive,
      systemTailscaleInterface: this.systemTailscaleInterface,
      systemTailscaleIP: this.systemTailscaleIP,
      systemTailscaleIp: this.systemTailscaleIP,
      magicDNSName: this.magicDNSName,
      tailscaleUrl: this.systemTailscaleIP ? `http://${this.systemTailscaleIP}:${this.port}` : null,
      embeddedTailscaleEnabled: this.embeddedEnabled,
      embeddedTailscaleSuppressedBySystem: this.suppressedBySystem,
      embeddedTailscaleRunning: Boolean(this.embeddedProcess),
      embeddedStatusHint: this.systemTailscaleActive
        ? `检测到电脑系统级 Tailscale 在线 (${this.systemTailscaleInterface}: ${this.systemTailscaleIP})，软件内置 Tailscale 已自动关闭避让`
        : '系统级 Tailscale 未开启，可使用内置 TailnetKit 引擎或局域网连接',
      cloudflareTunnelUrl: this.cloudflareTunnelUrl
    };
  }
}

module.exports = {
  TailscaleAndTunnelManager,
  isTailscaleIPv4
};
