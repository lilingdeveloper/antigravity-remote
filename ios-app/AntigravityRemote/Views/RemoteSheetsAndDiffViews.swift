//
//  RemoteSheetsAndDiffViews.swift
//  AntigravityRemote
//
//  独立弹窗与功能视图抽屉 (从 MainRemoteView 模块化拆分):
//  - MacSetupGuideSheet: 2 步极简连接 Mac 教程向导弹窗
//  - ConversationListSheet: 工作区与历史会话侧边栏抽屉
//  - ConnectionSettingsSheet: 局域网 / Tailscale 连接与多路竞速设置
//  - ModelPickerSheet: 独立 AI 模型选择抽屉页 (按模型家族聚合 + 思考强度子列表 + 实时额度进度条)
//

import SwiftUI
import Combine

// MARK: - 2 步极简连接 Mac 教程向导弹窗

struct MacSetupGuideSheet: View {
    let onOpenScanner: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied: Bool = false

    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/lilingdeveloper/antigravity-remote/main/install.sh | bash"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 头部欢迎区
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer.and.iphone")
                                .font(.title.weight(.bold))
                                .foregroundStyle(.blue)
                            Text("2 步极简连接 Mac")
                                .font(.title2.weight(.bold))
                        }
                        Text("全自动配置后台开机自启服务，随时随地手机远程操控 Antigravity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    // 步骤 1
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("1")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue, in: Circle())
                            Text("在 Mac 终端运行自动配置命令")
                                .font(.headline)
                            Spacer()
                            Text("仅首次需要")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.14), in: Capsule())
                                .foregroundStyle(.blue)
                        }

                        Text("打开 Mac 上的「终端 (Terminal)」应用，运行以下一键脚本。该脚本会自动借用 Antigravity 内置环境配置 macOS 开机自启后台服务（LaunchAgent），以后开机即连，再也无需手动打开终端，且会自动在 Mac 浏览器弹出配对二维码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)

                        // 代码块与复制按钮
                        VStack(alignment: .leading, spacing: 8) {
                            Text(installCommand)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                UIPasteboard.general.string = installCommand
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isCopied = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation {
                                        isCopied = false
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                                    Text(isCopied ? "已复制！在 Mac 上直接按 ⌘V 粘贴运行" : "📋 一键复制命令（支持通用剪贴板，直接在 Mac 按 ⌘V 粘贴）")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isCopied ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // 步骤 2
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("2")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.indigo, in: Circle())
                            Text("扫描 Mac 弹出的二维码")
                                .font(.headline)
                        }

                        Text("第 1 步脚本运行完成后，Mac 会自动弹出带有配对二维码的网页（包含 Tailscale 5G 异地连接与局域网高速通道配置）。点击下方按钮打开相机扫描即可一键连接！")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onOpenScanner()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                Text("📷 打开相机扫描 Mac 二维码")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(18)
            }
            .navigationTitle("连接向导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - 从左往右滑出的工作区与会话切换侧边栏

struct ConversationListSheet: View {
    @ObservedObject var client: AntigravityClient
    var onNewChat: () -> Void
    var onClose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var renamingConversation: ConversationSummary?
    @State private var renameDraftTitle: String = ""

    private var filteredProjects: [ProjectGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return client.projects }
        return client.projects.compactMap { proj in
            if proj.name.lowercased().contains(q) { return proj }
            let matched = proj.conversations.filter { $0.title.lowercased().contains(q) }
            guard !matched.isEmpty else { return nil }
            return ProjectGroup(
                name: proj.name,
                workspaceUri: proj.workspaceUri,
                workspacePath: proj.workspacePath,
                conversations: matched
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredProjects) { project in
                    Section {
                        ForEach(project.conversations) { convo in
                            HStack(spacing: 8) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    Task {
                                        await client.selectConversation(convo)
                                        onClose()
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(convo.title)
                                                .font(.subheadline.weight(convo.id == client.currentCascadeId ? .bold : .regular))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text("\(convo.stepCount ?? 0) 步")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if convo.isRunning == true {
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .controlSize(.mini)
                                                Text("运行中")
                                                    .font(.caption2.weight(.semibold))
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.16), in: Capsule())
                                            .foregroundStyle(.green)
                                        }
                                        if convo.id == client.currentCascadeId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // 右侧竖排三点菜单 (重命名 / 归档对话)
                                Menu {
                                    Button {
                                        renameDraftTitle = convo.title
                                        renamingConversation = convo
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        Task {
                                            await client.archiveConversation(cascadeId: convo.id)
                                        }
                                    } label: {
                                        Label("归档对话", systemImage: "archivebox")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .rotationEffect(.degrees(90))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 32)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack {
                            Text("📁 \(project.name)")
                                .font(.caption.weight(.bold))
                            Spacer()
                            Button {
                                if let uri = project.workspaceUri, !uri.isEmpty {
                                    client.currentWorkspaceUri = uri
                                    UserDefaults.standard.set(uri, forKey: "agy.currentWorkspaceUri")
                                }
                                onNewChat()
                            } label: {
                                Label("在此项目新建", systemImage: "plus.circle")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索工作区或对话标题...")
            .navigationTitle("工作区 (\(client.conversations.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Image(systemName: "sidebar.left")
                            .fontWeight(.semibold)
                    }
                }
            }
            .refreshable {
                await client.fetchConversations()
            }
            .alert("重命名对话", isPresented: Binding(
                get: { renamingConversation != nil },
                set: { if !$0 { renamingConversation = nil } }
            )) {
                TextField("输入新的对话标题...", text: $renameDraftTitle)
                Button("取消", role: .cancel) {
                    renamingConversation = nil
                    renameDraftTitle = ""
                }
                Button("保存") {
                    if let target = renamingConversation {
                        let newName = renameDraftTitle
                        renamingConversation = nil
                        renameDraftTitle = ""
                        Task {
                            await client.renameConversation(cascadeId: target.id, newTitle: newName)
                        }
                    }
                }
            } message: {
                Text("重命名后将实时同步至电脑端 Antigravity")
            }
        }
    }
}

// MARK: - 连接设置页

struct ConnectionSettingsSheet: View {
    @ObservedObject var client: AntigravityClient
    var onOpenTailscaleLogin: () -> Void = {}
    @ObservedObject private var tailnet = TailnetManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Mac 桥接服务器参数")) {
                    LabeledContent("当前连接状态", value: client.isConnected ? "✅ 在线 (\(client.connectionRouteDescription))" : "⚠️ 未连接")
                    LabeledContent("Tailscale 主地址") {
                        TextField("100.x.y.z", text: $client.serverHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("局域网极速备用") {
                        TextField("192.168.x.y (可选)", text: $client.fallbackLanHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("端口") {
                        TextField("8789", value: $client.serverPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    SecureField("访问令牌 Token (可选)", text: $client.accessToken)
                        .textInputAutocapitalization(.never)
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        client.saveConnectionConfig()
                        Task { await client.refreshAll() }
                    } label: {
                        Text(L("保存地址并立即重连"))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Section("快捷切换首选通道") {
                    if let firstPeer = tailnet.status?.peers.first(where: { $0.online && !$0.ip.isEmpty }) ?? tailnet.status?.peers.first(where: { !$0.ip.isEmpty }) {
                        Button("使用已发现 Tailscale 节点 (\(firstPeer.displayName) · \(firstPeer.ip))") {
                            client.serverHost = firstPeer.ip
                            client.serverPort = 8789
                            client.saveConnectionConfig()
                            Task { await client.refreshAll() }
                        }
                    }
                    if !client.fallbackLanHost.isEmpty {
                        Button("切换首选为局域网 IP (\(client.fallbackLanHost))") {
                            client.serverHost = client.fallbackLanHost
                            client.serverPort = 8789
                            client.saveConnectionConfig()
                            Task { await client.refreshAll() }
                        }
                    }
                    Button("本地模拟器调试直连 (127.0.0.1)") {
                        client.serverHost = "127.0.0.1"
                        client.serverPort = 8789
                        client.saveConnectionConfig()
                        Task { await client.refreshAll() }
                    }
                }

                Section("当前路由与 Tailscale 互斥状态") {
                    LabeledContent("当前最优通道", value: client.connectionRouteDescription)
                    if let rtt = client.latencyMs {
                        LabeledContent("实时往返延迟", value: "\(rtt) ms")
                    }
                    LabeledContent("本机系统 Tailscale", value: tailnet.systemTailscaleActive ? "在线 (\(tailnet.systemTailscaleIP ?? ""))" : "未开启")
                    LabeledContent("软件内置 TailnetKit", value: tailnet.systemTailscaleActive ? "已自动关闭避让系统" : (tailnet.status?.isRunning == true ? "运行中" : "未运行"))
                    if let err = client.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("连接与通道设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { code in
                    _ = client.applyPairingCode(code)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存并重连") {
                        client.saveConnectionConfig()
                        Task { await client.refreshAll() }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 独立 AI 模型选择抽屉页 (按模型家族聚合 + 思考强度子列表 + 实时额度进度条展示)

struct ModelPickerSheet: View {
    @ObservedObject var client: AntigravityClient
    @Environment(\.dismiss) private var dismiss

    /// 记录每个模型家族当前在子列表中选中的思考强度 (如 "Low" / "Medium" / "High")
    @State private var selectedIntensityByFamily: [String: String] = [:]
    @State private var currentTime = Date()
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct ModelVariant: Identifiable, Equatable {
        let intensity: String
        let intensityLabel: String
        let model: AIModelItem
        var id: String { model.modelId }
    }

    struct ModelFamilyGroup: Identifiable, Equatable {
        let baseName: String
        let tagTitle: String?
        let fiveHourFraction: Double?
        let fiveHourResetTime: String?
        let fiveHourDescription: String?
        let weeklyFraction: Double?
        let weeklyResetTime: String?
        let weeklyDescription: String?
        let variants: [ModelVariant]
        var id: String { baseName }
    }

    private var activeMacModelName: String {
        if let found = client.models.first(where: { $0.modelId == client.activeConversationModelId }) {
            return found.label
        }
        return "自动继承当前会话模型"
    }

    /// 将所有模型按基础名称聚合（例如 Gemini 4 Argon (Low/Medium/High) 聚合成一个「Gemini 4 Argon」大条目）
    private var modelFamilies: [ModelFamilyGroup] {
        var order: [String] = []
        var map: [String: [ModelVariant]] = [:]
        var metaMap: [String: (
            tag: String?,
            fiveHour: Double?,
            fiveHourReset: String?,
            fiveHourDesc: String?,
            weekly: Double?,
            weeklyReset: String?,
            weeklyDesc: String?
        )] = [:]

        for item in client.models {
            let (base, intensity) = Self.parseLabel(item.label)
            if map[base] == nil {
                order.append(base)
                map[base] = []
                metaMap[base] = (
                    item.tagTitle,
                    item.fiveHourRemainingFraction ?? item.remainingFraction,
                    item.fiveHourResetTime ?? item.resetTime,
                    item.fiveHourDescription,
                    item.weeklyRemainingFraction ?? item.remainingFraction,
                    item.weeklyResetTime ?? item.resetTime,
                    item.weeklyDescription
                )
            }
            let displayIntensity = Self.formatIntensityLabel(intensity)
            map[base]?.append(ModelVariant(
                intensity: intensity,
                intensityLabel: displayIntensity,
                model: item
            ))
        }

        let rankOrder: [String: Int] = ["Low": 0, "Medium": 1, "High": 2]
        return order.compactMap { base in
            guard let vars = map[base], !vars.isEmpty else { return nil }
            let sortedVars = vars.sorted { (rankOrder[$0.intensity] ?? 9) < (rankOrder[$1.intensity] ?? 9) }
            let meta = metaMap[base]
            return ModelFamilyGroup(
                baseName: base,
                tagTitle: meta?.tag,
                fiveHourFraction: meta?.fiveHour,
                fiveHourResetTime: meta?.fiveHourReset,
                fiveHourDescription: meta?.fiveHourDesc,
                weeklyFraction: meta?.weekly,
                weeklyResetTime: meta?.weeklyReset,
                weeklyDescription: meta?.weeklyDesc,
                variants: sortedVars
            )
        }
    }

    private static func parseLabel(_ raw: String) -> (baseName: String, intensity: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for level in ["High", "Medium", "Low"] {
            let suffix = "(\(level))"
            if trimmed.hasSuffix(suffix) {
                let base = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                return (base, level)
            }
        }
        return (trimmed, "Standard")
    }

    private static func formatIntensityLabel(_ intensity: String) -> String {
        switch intensity {
        case "Low": return "Low · 轻量思考"
        case "Medium": return "Medium · 均衡思考"
        case "High": return "High · 深度思考"
        default: return intensity
        }
    }

    private func activeVariant(for family: ModelFamilyGroup) -> ModelVariant {
        if let chosenIntensity = selectedIntensityByFamily[family.baseName],
           let found = family.variants.first(where: { $0.intensity == chosenIntensity }) {
            return found
        }
        let currentId = client.selectedModelId.isEmpty ? client.activeConversationModelId : client.selectedModelId
        if let matched = family.variants.first(where: { $0.model.modelId == currentId }) {
            return matched
        }
        if let high = family.variants.first(where: { $0.intensity == "High" }) {
            return high
        }
        if let med = family.variants.first(where: { $0.intensity == "Medium" }) {
            return med
        }
        return family.variants[0]
    }

    private func quotaColor(for pct: Int) -> Color {
        if pct > 50 { return .green }
        if pct > 20 { return .orange }
        return .red
    }

    private static let isoFormatterWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 计算额度重置倒计时文案（如 "2小时13分后重置" / "3天6小时后重置"）
    private func formatResetCountdown(resetISO: String?, fraction: Double, now: Date) -> String {
        if let raw = resetISO?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let targetDate = Self.isoFormatterWithFrac.date(from: raw) ?? Self.isoFormatterStandard.date(from: raw) {
                let remainingSec = Int(targetDate.timeIntervalSince(now))
                if remainingSec > 0 {
                    let days = remainingSec / 86400
                    let hours = (remainingSec % 86400) / 3600
                    let minutes = (remainingSec % 3600) / 60
                    let seconds = remainingSec % 60
                    if days > 0 {
                        return "\(days)d \(hours)h"
                    } else if hours > 0 {
                        return "\(hours)h \(minutes)m"
                    } else if minutes > 0 {
                        return "\(minutes)m \(seconds)s"
                    } else {
                        return "\(seconds)s"
                    }
                }
            }
            return raw
        }
        return fraction >= 0.999 ? "100%" : "--"
    }

    private func quotaProgressRow(title: String, fraction: Double, resetISO: String?) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let pct = Int(round(clamped * 100))
        let color = quotaColor(for: pct)
        let countdownText = formatResetCountdown(resetISO: resetISO, fraction: clamped, now: currentTime)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * clamped))
                    }
                }
                .frame(width: 58, height: 6)

                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .frame(width: 32, alignment: .trailing)

                HStack(spacing: 2) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                    Text(countdownText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        client.selectModelForCurrentConversation("")
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L("跟随电脑端当前会话模型"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(activeMacModelName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if client.selectedModelId.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section {
                    ForEach(modelFamilies) { family in
                        let currentVar = activeVariant(for: family)
                        let isFamilyConfirmed = family.variants.contains(where: { $0.model.modelId == client.selectedModelId })
                        let isExactSelected = (client.selectedModelId == currentVar.model.modelId)

                        HStack(spacing: 10) {
                            // 左侧与主体区域：点击整个大条目即可确认选择该模型 + 当前选中的思考强度
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                client.selectModelForCurrentConversation(currentVar.model.modelId)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Text(family.baseName)
                                            .font(.subheadline.weight(isFamilyConfirmed ? .bold : .semibold))
                                            .foregroundStyle(.primary)

                                        if let tag = family.tagTitle, !tag.isEmpty {
                                            Text(tag)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(tag == "Fast" ? Color.green.opacity(0.16) : Color.purple.opacity(0.16), in: Capsule())
                                                .foregroundStyle(tag == "Fast" ? .green : .purple)
                                        }

                                        if isExactSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.subheadline)
                                                .foregroundStyle(.blue)
                                        }
                                    }

                                    // 5小时额度 与 周额度 双进度条 + 重置倒计时显示
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let frac5h = family.fiveHourFraction {
                                            quotaProgressRow(
                                                title: L("5小时额度"),
                                                fraction: frac5h,
                                                resetISO: family.fiveHourResetTime
                                            )
                                        }
                                        if let fracWeekly = family.weeklyFraction {
                                            quotaProgressRow(
                                                title: L("周额度"),
                                                fraction: fracWeekly,
                                                resetISO: family.weeklyResetTime
                                            )
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // 右侧思考模式强度子列表：点击切换该模型的思考强度，再点击整个条目即可确认选择
                            if family.variants.count > 1 {
                                Menu {
                                    ForEach(family.variants) { variant in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedIntensityByFamily[family.baseName] = variant.intensity
                                        } label: {
                                            HStack {
                                                Text(variant.intensityLabel)
                                                if variant.intensity == currentVar.intensity {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(currentVar.intensity)
                                            .font(.system(size: 12, weight: .bold))
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(.purple)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Text(currentVar.intensity)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(L("选择模型"))
                }
            }
            .navigationTitle(L("选择 AI 模型与额度"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("完成")) { dismiss() }
                }
            }
            .task {
                await client.fetchModels()
            }
            .onReceive(countdownTimer) { tick in
                currentTime = tick
            }
        }
    }
}
