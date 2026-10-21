const { execSync } = require('child_process');
const http = require('http');
const https = require('https');

/**
 * 动态发现本机正在运行的 Antigravity `language_server` 进程及其动态端口与 CSRF Token
 * 同时也探测 Electron 主进程的 CDP 调试端口（作为可选辅助通道）
 */
class AntigravityDiscovery {
  constructor() {
    this.cached = null;
    this.lastCheckedAt = 0;
  }

  /**
   * 同步探测 language_server 的 PID、CSRF Token、HTTP/HTTPS 监听端口
   */
  discoverSync() {
    try {
      const psOut = execSync('ps ax -o pid=,command=', { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] });
      const lines = psOut.split('\n');

      let lsLine = null;
      let mainAppPid = null;

      for (const line of lines) {
        if (line.includes('language_server') && line.includes('--csrf_token')) {
          lsLine = line.trim();
        } else if (
          line.includes('/Applications/Antigravity.app/Contents/MacOS/Antigravity') &&
          !line.includes('Antigravity Helper')
        ) {
          mainAppPid = parseInt(line.trim().split(/\s+/)[0], 10);
        }
      }

      if (!lsLine) {
        return null;
      }

      const pid = parseInt(lsLine.split(/\s+/)[0], 10);
      const csrfMatch = lsLine.match(/--csrf_token\s+([a-f0-9-]+)/i);
      const hostBridgeUrlMatch = lsLine.match(/--host_bridge_url=(\S+)/i);
      const hostBridgeTokenMatch = lsLine.match(/--host_bridge_token=(\S+)/i);
      const versionMatch = lsLine.match(/--override_ide_version\s+(\S+)/i);

      const csrfToken = csrfMatch ? csrfMatch[1] : null;
      if (!pid || !csrfToken) {
        return null;
      }

      // 通过 lsof 获取 language_server 监听的本地 TCP 端口
      const lsofOut = execSync(`lsof -Pan -p ${pid} -iTCP -sTCP:LISTEN`, {
        encoding: 'utf-8',
        stdio: ['ignore', 'pipe', 'ignore']
      });
      const ports = [];
      for (const m of lsofOut.matchAll(/127\.0\.0\.1:(\d+)\s+\(LISTEN\)/g)) {
        const p = parseInt(m[1], 10);
        if (!ports.includes(p)) ports.push(p);
      }
      ports.sort((a, b) => a - b);

      // 通常较小端口为 HTTPS (如 53692)，较大端口为 HTTP (如 53693)
      const httpsPort = ports[0] || null;
      const httpPort = ports[1] || ports[0] || null;

      // 探测主进程 CDP 端口（可选）
      let cdpPort = null;
      if (mainAppPid) {
        try {
          const appLsof = execSync(`lsof -Pan -p ${mainAppPid} -iTCP -sTCP:LISTEN`, {
            encoding: 'utf-8',
            stdio: ['ignore', 'pipe', 'ignore']
          });
          const appPorts = [];
          for (const m of appLsof.matchAll(/127\.0\.0\.1:(\d+)\s+\(LISTEN\)/g)) {
            appPorts.push(parseInt(m[1], 10));
          }
          appPorts.sort((a, b) => a - b);
          cdpPort = appPorts[0] || null;
        } catch (_) {}
      }

      const info = {
        pid,
        mainAppPid,
        csrfToken,
        httpPort,
        httpsPort,
        cdpPort,
        allPorts: ports,
        ideVersion: versionMatch ? versionMatch[1] : 'unknown',
        hostBridgeUrl: hostBridgeUrlMatch ? hostBridgeUrlMatch[1] : null,
        hostBridgeToken: hostBridgeTokenMatch ? hostBridgeTokenMatch[1] : null,
        baseUrl: httpPort ? `http://127.0.0.1:${httpPort}` : null,
        discoveredAt: new Date().toISOString()
      };

      this.cached = info;
      this.lastCheckedAt = Date.now();
      return info;
    } catch (err) {
      return null;
    }
  }

  /**
   * 获取当前可用连接信息（带缓存，失效或超过 ttlMs 时重新扫描）
   */
  getConnectionInfo(forceRefresh = false, ttlMs = 5000) {
    if (!forceRefresh && this.cached && Date.now() - this.lastCheckedAt < ttlMs) {
      return this.cached;
    }
    return this.discoverSync();
  }
}

module.exports = { AntigravityDiscovery };
