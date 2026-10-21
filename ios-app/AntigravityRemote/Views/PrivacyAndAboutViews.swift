//
//  PrivacyAndAboutViews.swift
//  AntigravityRemote
//
//  Created for In-app Privacy Policy, Transparency & Open Source Disclosures.
//

import SwiftUI

public struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    private var isZh: Bool {
        l10n.resolvedLanguage.hasPrefix("zh")
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Badge
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isZh ? "零数据收集 · 绝对隐私" : "Zero Data Collection · Absolute Privacy")
                                .font(.headline)
                            Text(isZh ? "Antigravity Remote 端到端直连架构说明" : "Antigravity Remote Peer-to-Peer Privacy Architecture")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Section 1: Core Principles
                    policySection(
                        icon: "lock.shield",
                        title: isZh ? "1. 核心原则：零第三方中转与存储" : "1. Core Principle: Zero Third-Party Servers",
                        content: isZh
                            ? "本客户端不设任何中心化收集服务器。您的所有对话记录、思考过程、代码 Diff 与工程文件，均只在您的 iPhone/iPad 与您的个人 Mac 之间通过点对点直连（局域网 Wi-Fi 或 Tailscale 虚拟专网加密隧道）传输，我们不收集、不存储、不分析您的任何代码与个人隐私数据。"
                            : "Antigravity Remote operates entirely without centralized relay servers. All your conversations, thinking traces, code diffs, and project files travel strictly between your iOS device and your personal Mac via encrypted direct P2P connections (LAN or Tailscale). We never collect, store, or analyze your code or personal data."
                    )

                    // Section 2: Local Storage
                    policySection(
                        icon: "externaldrive",
                        title: isZh ? "2. 本地数据存储" : "2. Local Data Storage",
                        content: isZh
                            ? "所有配置参数（如 Mac 局域网 IP、Tailscale 主机地址、界面展示偏好）均通过系统标准安全沙盒仅保存在您本地设备的 UserDefaults 中，绝不上传至任何外部云服务。"
                            : "All user configuration settings (such as Mac LAN IP, Tailscale host address, and UI preferences) are stored strictly inside your local device's secure sandbox via UserDefaults. They are never uploaded to any external cloud."
                    )

                    // Section 3: System Permissions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .foregroundStyle(.blue)
                            Text(isZh ? "3. 系统权限使用目的" : "3. System Permissions Usage")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        permissionRow(
                            icon: "camera.fill",
                            name: isZh ? "相机权限 (Camera)" : "Camera",
                            desc: isZh ? "仅在您点击「扫码配对」时用于扫描 Mac 端显示的配对二维码，绝不采集或保存任何照片。" : "Used exclusively to scan pairing QR codes from your Mac screen. Never captures or stores photos."
                        )

                        permissionRow(
                            icon: "photo.fill",
                            name: isZh ? "相册权限 (Photo Library)" : "Photo Library",
                            desc: isZh ? "仅在您主动从相册选取图片或视频作为对话附件时读取，绝不在后台静默访问。" : "Accessed only when you explicitly select an image or video to attach to your prompt. Never accessed in the background."
                        )

                        permissionRow(
                            icon: "network",
                            name: isZh ? "本地网络权限 (Local Network)" : "Local Network",
                            desc: isZh ? "用于在同一 Wi-Fi 局域网下发现并连接您个人电脑上的 Antigravity 守护服务。" : "Used to discover and establish low-latency connections to your Mac daemon on the local Wi-Fi."
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Online Link Button
                    Link(destination: URL(string: "https://lilingdeveloper.github.io/antigravity-remote/privacy.html")!) {
                        HStack {
                            Image(systemName: "safari")
                            Text(isZh ? "阅读在线完整隐私政策 (Web Privacy Policy)" : "Read Full Online Privacy Policy")
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isZh ? "隐私政策与安全声明" : "Privacy Policy & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isZh ? "完成" : "Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func policySection(icon: String, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func permissionRow(icon: String, name: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.blue)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct OpenSourceLicensesView: View {
    @ObservedObject private var l10n = LocalizationManager.shared

    private var isZh: Bool {
        l10n.resolvedLanguage.hasPrefix("zh")
    }

    public init() {}

    private let licenses = [
        (
            name: "Tailscale / tsnet (TailnetKit)",
            author: "Tailscale Inc.",
            license: "BSD 3-Clause",
            desc: "Zero config VPN for building secure networks. Powers embedded P2P remote connectivity."
        ),
        (
            name: "Connect-RPC",
            author: "Buf Technologies, Inc.",
            license: "Apache License 2.0",
            desc: "Simple, reliable, interoperable gRPC and Connect protocol implementations for Swift and Node.js."
        ),
        (
            name: "Google Antigravity Desktop Engine",
            author: "Google DeepMind",
            license: "Proprietary / Development Integration",
            desc: "Connect-RPC endpoints and protocol integration for developer companion workflows."
        ),
        (
            name: "SwiftUI & Apple Swift Toolchain",
            author: "Apple Inc.",
            license: "Apache License 2.0 with Runtime Library Exception",
            desc: "Native UI framework and reactive concurrency runtime for iOS."
        )
    ]

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isZh ? "开源组件与技术致谢" : "Open Source Acknowledgements")
                        .font(.headline)
                    Text(isZh ? "Antigravity Remote 采用了以下优秀的开源软件与工程框架，感谢全球开源社区的无私奉献。" : "Antigravity Remote utilizes the following open source software and frameworks. We are grateful to the global open source community.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text(isZh ? "组件列表" : "Libraries & Frameworks")) {
                ForEach(licenses, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name)
                                .font(.body)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(item.license)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .cornerRadius(6)
                        }
                        Text(item.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(isZh ? "开源组件许可" : "Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
