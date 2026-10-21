const assert = require('assert');
const { AntigravityDiscovery } = require('../src/discovery');
const { AntigravityRpcClient } = require('../src/rpc-client');
const { TailscaleAndTunnelManager, isTailscaleIPv4 } = require('../src/tailscale-tunnel');

async function main() {
  console.log('=== 1. 测试 Tailscale CGNAT (100.64.0.0/10) 识别与系统级互斥逻辑 ===');
  assert.strictEqual(isTailscaleIPv4('100.64.0.1'), true, '100.64.0.1 应识别为 Tailscale IP');
  assert.strictEqual(isTailscaleIPv4('100.127.255.254'), true, '100.127.255.254 应识别为 Tailscale IP');
  assert.strictEqual(isTailscaleIPv4('100.63.255.255'), false, '100.63.255.255 不应识别为 Tailscale IP');
  assert.strictEqual(isTailscaleIPv4('192.168.1.1'), false, '192.168.1.1 不应识别为 Tailscale IP');

  const netMgr = new TailscaleAndTunnelManager({ port: 8789 });
  const netStatus = netMgr.scanNetworkInterfaces();
  console.log('网络与 Tailscale 状态:', JSON.stringify(netStatus, null, 2));
  if (netStatus.systemTailscaleActive) {
    assert.strictEqual(
      netStatus.embeddedTailscaleSuppressedBySystem,
      true,
      '当电脑系统开启 Tailscale 时，软件内置 Tailscale 必须自动处于抑制/关闭状态'
    );
    console.log(
      `✅ 验证通过: 检测到系统级 Tailscale (${netStatus.systemTailscaleInterface}: ${netStatus.systemTailscaleIP})，已自动关闭内置 Tailscale`
    );
  }

  console.log('\n=== 2. 测试 Antigravity language_server 动态端口与 CSRF 探测 ===');
  const discovery = new AntigravityDiscovery();
  const info = discovery.getConnectionInfo(true);
  assert(info && info.pid && info.httpPort && info.csrfToken, '未能探测到正在运行的 language_server');
  console.log(`✅ 成功发现 language_server: PID=${info.pid}, HTTP Port=${info.httpPort}, Version=${info.ideVersion}`);

  console.log('\n=== 3. 测试原生 Connect-RPC 接口调用 ===');
  const rpc = new AntigravityRpcClient(discovery);

  const models = await rpc.getModels();
  assert(Array.isArray(models) && models.length > 0, '模型列表不应为空');
  console.log(`✅ 获取可用模型成功: 共 ${models.length} 个模型 (首推: ${models[0].label})`);

  const { projects, conversations } = await rpc.listConversations();
  assert(Array.isArray(conversations) && conversations.length > 0, '会话列表不应为空');
  console.log(`✅ 获取项目与会话成功: 共 ${projects.length} 个项目, ${conversations.length} 个会话`);

  const latestConvo = conversations[0];
  console.log(`正在读取最新会话详情: [${latestConvo.projectName}] ${latestConvo.title} (${latestConvo.id})`);
  const detail = await rpc.getConversationDetail(latestConvo.id);
  assert(detail && Array.isArray(detail.messages), '会话消息列表格式错误');
  console.log(`✅ 读取会话消息流成功: 共 ${detail.stepCount} 步, 解析出 ${detail.messages.length} 条结构化消息`);

  const { diffs, artifacts } = await rpc.getDiffsAndArtifacts(latestConvo.id);
  console.log(`✅ 读取文件变更与产出物成功: Diffs=${diffs.length}, Artifacts=${artifacts.length}`);

  console.log('\n🎉 全部核心接口与 Tailscale 智能互斥验证通过！');
}

main().catch((err) => {
  console.error('❌ 验证失败:', err);
  process.exit(1);
});
