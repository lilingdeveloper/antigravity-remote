//
//  TailnetEngineView.swift
//  AntigravityRemote
//
//  内置 Tailscale (TailnetKit) 登录与网络管理页:
//  - 始终在显眼位置展示「一键在应用内授权登录 Tailscale」与「使用 Auth Key 登录」，绝不隐藏登录入口
//  - 当检测到本机真实系统级 Tailscale 开启时，提示自动避让状态，但仍允许强制启动内置引擎
//  - 登录成功后列出所有 Tailnet 设备 (Peers)，支持一键点击连接电脑端 Antigravity
//

import SwiftUI
import SafariServices

struct TailnetEngineView: View {
    @ObservedObject var client: AntigravityClient
    @ObservedObject private var tailnet = TailnetManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var loginURL: URL?
    @State private var showSafari = false
    @State private var isStartingLogin = false
    @State private var showQRScanner = false
    @State private var authKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { tailnet.isEnabled },
                        set: { tailnet.setEnabled($0) }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(badgeColor)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("内置 Tailscale (TailnetKit)")
                                    .font(.headline)
                                Text(statusSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if tailnet.systemTailscaleActive {
                        Text("检测到本机系统级 Tailscale (\(tailnet.systemTailscaleIP ?? "utun")) 在线。软件已自动优先走系统通道；您也可以在下方手动登录内置 Tailscale 节点。")
                    } else {
                        Text("首次使用请点击下方「一键授权登录 Tailscale」，登录一次后永久保存凭证，无需在手机安装官方 Tailscale App。")
                    }
                }

                // 无论何种状态，只要内置引擎尚未处于 Running 登录态，始终醒目显示登录区块！
                if tailnet.status?.isRunning != true {
                    Section("🔑 登录内置 Tailscale 账号 (首次必点)") {
                        Button {
                            startOAuthLogin()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("一键在应用内网页授权登录 Tailscale")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("弹出官方登录页，点 Connect 即可将手机加入您的虚拟局域网")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isStartingLogin {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isStartingLogin)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("或者使用 Tailscale Auth Key 免密登录：")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack {
                                SecureField("粘贴 tskey-auth-...", text: $authKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                Button("登录") {
                                    let trimmed = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    authKey = ""
                                    tailnet.forceStartEmbeddedEngine(authKey: trimmed)
                                    tailnet.restart(authKey: trimmed)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(authKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            showQRScanner = true
                        } label: {
                            Label("扫码一键配对 (支持含 AuthKey 的二维码)", systemImage: "qrcode.viewfinder")
                        }
                    }
                }

                if let err = tailnet.lastError, !err.isEmpty {
                    Section("状态提示") {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let status = tailnet.status, status.isRunning {
                    Section("本机内置节点信息") {
                        LabeledContent("节点名称", value: status.hostname)
                        LabeledContent("内置 Tailscale IP", value: status.selfIP)
                        LabeledContent("运行状态", value: "✅ 已连接 (\(status.backendState))")
                    }

                    Section("Tailnet 在线设备 (点击一键连接 Antigravity)") {
                        ForEach(status.peers.filter { !$0.ip.isEmpty }) { peer in
                            HStack {
                                Circle()
                                    .fill(peer.online ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .font(.body.weight(.medium))
                                    HStack(spacing: 6) {
                                        Text(peer.ip)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        if peer.online {
                                            Text(peer.isDirect ? "直连" : "中继 \(peer.relay ?? "")")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background((peer.isDirect ? Color.green : Color.orange).opacity(0.16), in: Capsule())
                                                .foregroundStyle(peer.isDirect ? Color.green : Color.orange)
                                        }
                                    }
                                }
                                Spacer()
                                Button("连接此电脑") {
                                    client.serverHost = peer.ip
                                    client.saveConnectionConfig()
                                    Task { await client.refreshAll() }
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    Section {
                        Button("重新授权 / 切换 Tailscale 账号") {
                            startOAuthLogin()
                        }
                        Button("退出内置 Tailscale 登录", role: .destructive) {
                            Task { try? await tailnet.logout() }
                        }
                    }
                }

                if let macNet = client.daemonStatus?.network {
                    Section("电脑端 (Mac) Tailscale 状态") {
                        LabeledContent("Mac 主机名", value: macNet.hostname ?? "-")
                        LabeledContent("Mac 系统级 Tailscale", value: macNet.systemTailscaleActive == true ? "在线 (\(macNet.systemTailscaleInterface ?? "utun"): \(macNet.systemTailscaleIP ?? ""))" : "未开启")
                        LabeledContent("Mac 内置引擎避让", value: macNet.embeddedTailscaleSuppressedBySystem == true ? "已自动关闭内置 Tailscale" : "待命")
                    }
                }
            }
            .navigationTitle("内置 Tailscale 登录与设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSafari) {
                if let loginURL {
                    SafariLoginSheet(url: loginURL) { showSafari = false }
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { code in
                    _ = client.applyPairingCode(code)
                }
            }
            .onChange(of: tailnet.status?.isRunning) { running in
                if running == true && showSafari {
                    showSafari = false
                    client.invalidateRouteCache()
                    Task { await client.refreshAll() }
                }
            }
        }
    }

    private var badgeColor: Color {
        if tailnet.status?.isRunning == true { return .green }
        if tailnet.systemTailscaleActive { return .blue }
        guard tailnet.isEnabled else { return .gray }
        return .orange
    }

    private var statusSubtitle: String {
        if let st = tailnet.status, st.isRunning {
            return "✅ 内置引擎已登录运行中 · \(st.selfIP)"
        }
        if tailnet.systemTailscaleActive {
            return "系统级 Tailscale 在线 (\(tailnet.systemTailscaleIP ?? ""))"
        }
        guard tailnet.isEnabled else { return "已手动关闭" }
        return "⚠️ 尚未登录 Tailscale 账号，请点击下方按钮登录"
    }

    private func startOAuthLogin() {
        isStartingLogin = true
        tailnet.forceStartEmbeddedEngine()
        Task { @MainActor in
            do {
                let urlStr = try await tailnet.loginURL()
                if let url = URL(string: urlStr) {
                    loginURL = url
                    showSafari = true
                }
            } catch {
                tailnet.recordError(error.localizedDescription)
            }
            isStartingLogin = false
        }
    }
}

struct SafariLoginSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
