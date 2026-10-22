//
//  MainRemoteView.swift
//  AntigravityRemote
//
//  丝滑级 iOS 远程控制主界面:
//  - 顶部灵动状态栏: 实时显示选路通道与毫秒级延迟 (如 4ms)、当前工作区、多任务并行切换条与一键新建对话
//  - 零闪烁流式对话视图:
//    * 思考过程 (Thinking) 展开状态持久化，流式刷新绝不自动折叠，折叠态实时预览最新思考行
//    * Markdown 代码块独立卡片渲染 + 一键复制代码 (带触觉反馈)
//    * 分类着色工具调用胶丸 (终端命令 / 读写文件 / 网页搜索)
//    * 交互式收起键盘 (.scrollDismissesKeyboard(.interactively)) 与一键回到底部悬浮球
//  - 远程权限审批浮层: 终端命令 Approve/Reject、Artifact 方案 Proceed、多选题一键作答
//  - 语法着色级 Diffs 视图与 Artifacts 预览器
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

public struct MainRemoteView: View {
    @StateObject private var client = AntigravityClient()
    @ObservedObject private var tailnet = TailnetManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var selectedTab: Int = 0
    @State private var inputText: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingMediaAttachment] = []
    @State private var isLoadingMedia: Bool = false
    @State private var showConversationsSheet = false
    @State private var showSettingsSheet = false
    @State private var showTailnetSheet = false
    @State private var showQRScannerSheet = false
    @State private var showModelPickerSheet = false
    @State private var showMacSetupGuideSheet = false
    @State private var showPrivacyPolicySheet = false
    @State private var showOpenSourceLicensesSheet = false
    @State private var showNewChatAlert = false
    @State private var newChatPrompt = ""
    @State private var pairToastMessage: String?
    @State private var copiedBlockId: String?
    @State private var directLoginURL: URL?
    @State private var showDirectSafariLogin = false
    @State private var isFetchingLoginURL = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var isChatAtBottom: Bool = true
    @State private var expandedToolIds: Set<String> = []
    @State private var expandedDiffIds: Set<String> = []
    @State private var expandedArtifactIds: Set<String> = []
    @State private var copiedInstallCmd: Bool = false
    @State private var singleLineInputHeight: CGFloat = 40
    @FocusState private var isInputFocused: Bool

    public init() {
        UIScrollView.appearance().scrollsToTop = false
    }

    public var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.85, 340)

            ZStack(alignment: .leading) {
                NavigationStack {
                    VStack(spacing: 0) {
                        headerStatusBanner

                        TabView(selection: $selectedTab) {
                            chatPane
                                .tag(0)
                                .tabItem {
                                    Label(L("远程对话"), systemImage: "bubble.left.and.bubble.right.fill")
                                }

                            diffsPane
                                .tag(1)
                                .tabItem {
                                    Label("\(L("代码变更")) (\(client.diffs.count))", systemImage: "doc.badge.gearshape")
                                }

                            artifactsPane
                                .tag(2)
                                .tabItem {
                                    Label("\(L("方案文档")) (\(client.artifacts.count))", systemImage: "doc.richtext")
                                }

                            settingsPane
                                .tag(3)
                                .tabItem {
                                    Label(L("设置"), systemImage: "gearshape.fill")
                                }
                        }
                        .hideTopScrollEdgeEffect()
                    }
                    .hideTopScrollEdgeEffect()
                    .background(TopScrollEdgeDisabler(selectedTab: selectedTab))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isInputFocused = false
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                    showConversationsSheet.toggle()
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .fontWeight(.semibold)
                            }
                        }

                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 6) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isInputFocused = false
                                    Task { await client.switchToAdjacentConversation(direction: -1) }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(client.conversations.count > 1 ? .primary : .tertiary)
                                        .frame(width: 26, height: 26)
                                        .background(Color(uiColor: .secondarySystemFill), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(client.conversations.count <= 1)

                                VStack(spacing: 2) {
                                    HStack(spacing: 5) {
                                        if client.isGenerating {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 6, height: 6)
                                        }
                                        Text(currentTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    Text(currentProjectSubtitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: 190)
                                .contentShape(Rectangle())
                                .onTapGesture {}

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isInputFocused = false
                                    Task { await client.switchToAdjacentConversation(direction: 1) }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(client.conversations.count > 1 ? .primary : .tertiary)
                                        .frame(width: 26, height: 26)
                                        .background(Color(uiColor: .secondarySystemFill), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(client.conversations.count <= 1)
                            }
                        }
                    }
                    .sheet(isPresented: $showQRScannerSheet) {
                        QRScannerSheet { code in
                            let msg = client.applyPairingCode(code)
                            pairToastMessage = msg
                        }
                    }
                    .sheet(isPresented: $showTailnetSheet) {
                        TailnetEngineView(client: client)
                    }
                    .sheet(isPresented: $showModelPickerSheet) {
                        ModelPickerSheet(client: client)
                            .presentationDetents([.medium, .large])
                    }
                    .sheet(isPresented: $showSettingsSheet) {
                        ConnectionSettingsSheet(client: client, onOpenTailscaleLogin: {
                            showSettingsSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showTailnetSheet = true
                            }
                        })
                    }
                    .sheet(isPresented: $showMacSetupGuideSheet) {
                        MacSetupGuideSheet(onOpenScanner: {
                            showMacSetupGuideSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showQRScannerSheet = true
                            }
                        })
                    }
                    .sheet(isPresented: $showPrivacyPolicySheet) {
                        PrivacyPolicySheet()
                    }
                    .sheet(isPresented: $showOpenSourceLicensesSheet) {
                        NavigationStack {
                            OpenSourceLicensesView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("完成") {
                                            showOpenSourceLicensesSheet = false
                                        }
                                    }
                                }
                        }
                    }
                    .onAppear {
                        if let scene = client.activeMarketingScene {
                            applyMarketingScene(scene)
                        }
                    }
                    .onChange(of: client.activeMarketingScene) { newScene in
                        if let newScene {
                            applyMarketingScene(newScene)
                        }
                    }
                    .fullScreenCover(isPresented: $showDirectSafariLogin) {
                        if let directLoginURL {
                            SafariLoginSheet(url: directLoginURL) {
                                showDirectSafariLogin = false
                            }
                            .ignoresSafeArea()
                        }
                    }
                    .onChange(of: tailnet.status?.isRunning) { running in
                        if running == true {
                            if showDirectSafariLogin { showDirectSafariLogin = false }
                            client.invalidateRouteCache()
                            Task { await client.refreshAll() }
                        }
                    }
                    .onOpenURL { url in
                        let msg = client.applyPairingCode(url.absoluteString)
                        pairToastMessage = msg
                    }
                    .onChange(of: client.shouldPromptEmbeddedTailscaleLogin) { shouldPrompt in
                        if shouldPrompt {
                            client.shouldPromptEmbeddedTailscaleLogin = false
                            showTailnetSheet = true
                        }
                    }
                    .alert("扫码配对成功", isPresented: Binding(
                        get: { pairToastMessage != nil },
                        set: { if !$0 { pairToastMessage = nil } }
                    )) {
                        Button("好的", role: .cancel) { pairToastMessage = nil }
                    } message: {
                        Text(pairToastMessage ?? "")
                    }
                    .alert("在当前工作区新建对话", isPresented: $showNewChatAlert) {
                        TextField("输入新对话的首条指令...", text: $newChatPrompt)
                        Button("取消", role: .cancel) { newChatPrompt = "" }
                        Button("创建并发送") {
                            let prompt = newChatPrompt
                            newChatPrompt = ""
                            Task { await client.startNewConversation(prompt: prompt) }
                        }
                    } message: {
                        Text("工作区: \(currentProjectSubtitle)")
                    }
                }

                // 左侧边缘右滑打开侧边栏手势感应带（在未打开侧边栏时生效）
                if !showConversationsSheet {
                    Color.clear
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                                .onChanged { value in
                                    if value.translation.width > 0 && abs(value.translation.width) > abs(value.translation.height) {
                                        sidebarDragOffset = min(drawerWidth, value.translation.width)
                                    }
                                }
                                .onEnded { value in
                                    let shouldOpen = value.translation.width > 55 || value.predictedEndTranslation.width > 120
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                        sidebarDragOffset = 0
                                        if shouldOpen {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            isInputFocused = false
                                            showConversationsSheet = true
                                        }
                                    }
                                }
                        )
                        .zIndex(1)
                }

                // 从左往右滑出的侧边栏遮罩与抽屉面板
                if showConversationsSheet || sidebarDragOffset > 0 {
                    let progress = showConversationsSheet
                        ? max(0, min(1, 1 + sidebarDragOffset / drawerWidth))
                        : max(0, min(1, sidebarDragOffset / drawerWidth))

                    Color.black
                        .opacity(0.38 * progress)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                sidebarDragOffset = 0
                                showConversationsSheet = false
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if value.translation.width < 0 {
                                        sidebarDragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    let shouldClose = value.translation.width < -55 || value.predictedEndTranslation.width < -120
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                        sidebarDragOffset = 0
                                        if shouldClose {
                                            showConversationsSheet = false
                                        }
                                    }
                                }
                        )
                        .zIndex(2)

                    ConversationListSheet(
                        client: client,
                        onNewChat: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                sidebarDragOffset = 0
                                showConversationsSheet = false
                            }
                            showNewChatAlert = true
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                sidebarDragOffset = 0
                                showConversationsSheet = false
                            }
                        }
                    )
                    .padding(.top, geo.safeAreaInsets.top)
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 24,
                            topTrailingRadius: 24,
                            style: .continuous
                        )
                    )
                    .ignoresSafeArea(edges: .vertical)
                    .shadow(color: .black.opacity(0.22), radius: 16, x: 6, y: 0)
                    .offset(x: showConversationsSheet ? min(0, sidebarDragOffset) : (-drawerWidth + sidebarDragOffset))
                    .transition(.move(edge: .leading))
                    .gesture(
                        DragGesture(minimumDistance: 14)
                            .onChanged { value in
                                if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) {
                                    sidebarDragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                let shouldClose = value.translation.width < -60 || value.predictedEndTranslation.width < -130
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                    sidebarDragOffset = 0
                                    if shouldClose {
                                        showConversationsSheet = false
                                    }
                                }
                            }
                    )
                    .zIndex(3)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 22, coordinateSpace: .global)
                    .onEnded { value in
                        // 支持在页面左半屏任意位置从左往右横滑打开侧边栏
                        guard !showConversationsSheet else { return }
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        if value.startLocation.x < 90 && horizontal > 65 && horizontal > vertical * 1.8 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isInputFocused = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                showConversationsSheet = true
                            }
                        }
                    }
            )
        }
    }

    private func applyMarketingScene(_ scene: String) {
        switch scene.lowercased() {
        case "chat":
            selectedTab = 0
            client.expandedThinkingIds.insert("step-1")
        case "approval":
            selectedTab = 0
        case "diffs":
            selectedTab = 1
        case "artifacts":
            selectedTab = 2
        case "sidebar":
            selectedTab = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showConversationsSheet = true
            }
        case "models":
            selectedTab = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showModelPickerSheet = true
            }
        case "settings":
            selectedTab = 3
        default:
            break
        }
    }

    private var currentTitle: String {
        if let found = client.conversations.first(where: { $0.id == client.currentCascadeId }) {
            return found.title
        }
        return "Antigravity Remote"
    }

    private var currentProjectSubtitle: String {
        if let found = client.conversations.first(where: { $0.id == client.currentCascadeId }) {
            return found.projectName
        }
        if !client.currentWorkspaceUri.isEmpty {
            let name = URL(string: client.currentWorkspaceUri)?.lastPathComponent ?? client.currentWorkspaceUri
            return name.removingPercentEncoding ?? name
        }
        return "未选择工作区"
    }

    private var tailnetIconColor: Color {
        if tailnet.systemTailscaleActive { return .blue }
        if tailnet.status?.isRunning == true { return .green }
        return .secondary
    }

    // MARK: - 顶部灵动状态栏 & 多任务并行切换条

    private var contextUsageBar: some View {
        let fraction = min(1.0, max(0.0, client.contextUsage?.usageFraction ?? 0.0))
        let percent = client.contextUsage?.usagePercent ?? (fraction * 100.0)
        let tintColor: Color = fraction > 0.85 ? .red : (fraction > 0.60 ? .orange : .blue)

        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tintColor)
                Text(L("上下文"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(tintColor.gradient)
                        .frame(width: max(4, geo.size.width * fraction), height: 6)
                        .animation(.easeInOut(duration: 0.25), value: fraction)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 6)

            Group {
                if let used = client.contextUsage?.usedTokens, let maxTokens = client.contextUsage?.maxTokens, maxTokens > 0 {
                    Text(String(format: "%.1f%% (%@/%@)", percent, formatTokens(used), formatTokens(maxTokens)))
                } else {
                    Text(String(format: "%.1f%%", percent))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(fraction >= 0.60 ? tintColor : .secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func formatTokens(_ count: Int?) -> String {
        guard let count = count, count >= 0 else { return "--" }
        if count >= 1_000_000 {
            let val = Double(count) / 1_000_000.0
            return val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fM", val) : String(format: "%.1fM", val)
        } else if count >= 1_000 {
            let val = Double(count) / 1_000.0
            return val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fk", val) : String(format: "%.1fk", val)
        } else {
            return "\(count)"
        }
    }

    private var headerStatusBanner: some View {
        VStack(spacing: 6) {
            if client.showContextUsageBar {
                contextUsageBar
            }

            if client.isDemoMode && client.activeMarketingScene == nil {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L("正在体验演示模式（可发送消息、审批命令、查看代码变更）"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        client.triggerDemoApproval()
                    } label: {
                        Text(L("触发审批演示"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white, in: Capsule())
                    }
                    Button {
                        client.exitDemoMode()
                    } label: {
                        Text(L("退出演示"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.yellow],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }

            HStack(spacing: 8) {
                // 连接状态与实时延迟胶囊 (点击跳转到设置页)
                Button {
                    selectedTab = 3
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 7, height: 7)
                        Text(client.isConnected ? client.connectionRouteDescription : (client.isReconnecting ? L("正在自动重连...") : L("未连接 Mac")))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // 标题栏正下方：模型与思考强度选择胶囊
                modelPickerPill

                if client.isGenerating {
                    Button {
                        Task { await client.stopRunningAgent() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(L("停止"))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                    }
                }
            }

            // 仅当从未连接过 Mac、也未处于连接状态且内置 Tailscale 未登录时提示登录
            if !client.isConnected && !client.hasEverConnectedMac && tailnet.status?.isRunning != true && !tailnet.systemTailscaleActive && !client.isDemoMode {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Text(L("内置 Tailscale 尚未登录账号 (异地/5G 穿透需登录一次)"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        triggerDirectTailscaleLogin()
                    } label: {
                        HStack(spacing: 4) {
                            if isFetchingLoginURL {
                                ProgressView()
                                    .tint(.blue)
                                    .controlSize(.mini)
                            }
                            Text(L("立即登录 →"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                    }
                    .disabled(isFetchingLoginURL)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var statusDotColor: Color {
        if !client.isConnected { return .orange }
        if tailnet.systemTailscaleActive { return .blue }
        return .green
    }

    private func triggerDirectTailscaleLogin() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isFetchingLoginURL = true
        tailnet.forceStartEmbeddedEngine()
        Task { @MainActor in
            do {
                let urlStr = try await tailnet.loginURL()
                if let u = URL(string: urlStr) {
                    directLoginURL = u
                    showDirectSafariLogin = true
                } else {
                    showTailnetSheet = true
                }
            } catch {
                showTailnetSheet = true
            }
            isFetchingLoginURL = false
        }
    }

    private var currentModelLabel: String {
        let raw: String = {
            if !client.selectedModelId.isEmpty {
                if let found = client.models.first(where: { $0.modelId == client.selectedModelId }) {
                    return found.label
                }
                return client.selectedModelId
            }
            if !client.activeConversationModelId.isEmpty,
               let found = client.models.first(where: { $0.modelId == client.activeConversationModelId }) {
                return found.label
            }
            return L("模型")
        }()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("placeholder") || trimmed == "选择模型" {
            return L("模型")
        }
        return trimmed
    }

    private var modelPickerPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showModelPickerSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(currentModelLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.14), in: Capsule())
            .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 根据「思考过程展示」与「读取文件展示」开关实时过滤对话消息

    private var visibleMessages: [ChatMessageItem] {
        client.messages.filter { msg in
            if msg.role == "tool" {
                let isReadFile = (msg.toolName == "read_file") || ((msg.summary ?? "").hasPrefix("读取文件"))
                if isReadFile {
                    return client.showFileReadTools
                } else {
                    return client.showOtherToolCalls
                }
            }
            if msg.role == "assistant" {
                let hasVisibleText = !(msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasVisibleThinking = client.showThinkingProcess && !(msg.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // 彻底过滤所有既无正文、又无可见思考过程的空白步骤，避免出现一行行的空白气泡
                return hasVisibleText || hasVisibleThinking
            }
            return true
        }
    }

    private var shouldShowWorkingIndicator: Bool {
        guard client.isGenerating else { return false }
        if let last = visibleMessages.last, last.role == "assistant", last.isGenerating == true {
            let hasVisibleThinking = client.showThinkingProcess && !(last.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasVisibleText = !(last.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasVisibleThinking && !hasVisibleText {
                return false
            }
        }
        return true
    }

    private var aiWorkingIndicatorRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.purple)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("AI 正在思考 · Working...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.purple.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Tab 1: 丝滑对话流 + 审批卡片 + 底部输入栏

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            if visibleMessages.isEmpty && !client.isGenerating {
                                emptyConversationWelcome
                                    .padding(16)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(visibleMessages) { msg in
                                        messageRow(msg)
                                            .id(msg.id)
                                    }
                                    if shouldShowWorkingIndicator {
                                        aiWorkingIndicatorRow
                                            .id("AI_WORKING_INDICATOR")
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM_ANCHOR")
                        }
                        .background(ChatScrollObserver(isAtBottom: $isChatAtBottom))
                    }
                    .hideTopScrollEdgeEffect()
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await client.refreshAll()
                    }
                    .id(client.currentCascadeId)
                    .onChange(of: client.currentCascadeId) { _ in
                        isChatAtBottom = true
                        scrollToBottom(proxy)
                    }
                    .onChange(of: client.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                        }
                    }
                    .onChange(of: client.isGenerating) { isGen in
                        if isGen {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: client.messages.last?.text) { _ in
                        if client.isGenerating {
                            proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                        }
                    }

                    // 底部居中快捷滚到底部小按钮
                    if !visibleMessages.isEmpty && !isChatAtBottom && client.activeMarketingScene == nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            scrollToBottom(proxy)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .zIndex(10)
                        .padding(.bottom, 10)
                    }
                }
            }

            if let pending = client.pendingInteraction {
                approvalCard(pending)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !client.queuedMessages.isEmpty {
                queuedMessagesTray
            }

            composerBar
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        isChatAtBottom = true
        // 第一步：直接对齐底部锚点，触发 LazyVStack 加载底层视图
        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)

        // 第二步：短延迟等待气泡渲染后，对齐最后一条消息及底部锚点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if shouldShowWorkingIndicator {
                proxy.scrollTo("AI_WORKING_INDICATOR", anchor: .bottom)
            } else if let lastMsg = visibleMessages.last {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            }
            proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
        }

        // 第三步：最终平滑收尾，确保彻底滚到最底部
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
            }
        }
    }

    // MARK: - 聊天滚动监听器 (判断是否在底部 & 禁用 scrollsToTop)

    private struct ChatScrollObserver: UIViewRepresentable {
        @Binding var isAtBottom: Bool

        func makeCoordinator() -> Coordinator {
            Coordinator(isAtBottom: $isAtBottom)
        }

        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            DispatchQueue.main.async {
                context.coordinator.attach(to: view)
            }
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            if context.coordinator.observedScrollView == nil || context.coordinator.observedScrollView?.window == nil {
                DispatchQueue.main.async {
                    context.coordinator.attach(to: uiView)
                }
            }
        }

        final class Coordinator: NSObject {
            @Binding var isAtBottom: Bool
            weak var observedScrollView: UIScrollView?
            private var offsetObservation: NSKeyValueObservation?
            private var sizeObservation: NSKeyValueObservation?

            init(isAtBottom: Binding<Bool>) {
                self._isAtBottom = isAtBottom
            }

            func attach(to view: UIView) {
                var current: UIView? = view
                while let parent = current?.superview {
                    if let sv = parent as? UIScrollView {
                        if #available(iOS 26.0, *) {
                            sv.topEdgeEffect.isHidden = true
                        }
                        if self.observedScrollView !== sv {
                            self.observedScrollView = sv
                            sv.scrollsToTop = false
                            setupObservations(for: sv)
                        }
                        break
                    }
                    current = parent
                }
            }

            private func setupObservations(for sv: UIScrollView) {
                offsetObservation = sv.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
                    self?.checkBottom(sv)
                }
                sizeObservation = sv.observe(\.contentSize, options: [.initial, .new]) { [weak self] sv, _ in
                    self?.checkBottom(sv)
                }
            }

            private func checkBottom(_ sv: UIScrollView) {
                if !sv.isDragging && !sv.isTracking && !sv.isDecelerating,
                   sv.bounds.height > 0 && sv.contentSize.height > 0 {
                    let maxOffsetY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
                    if sv.contentOffset.y > maxOffsetY + 12 {
                        sv.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
                    }
                }

                let maxOffsetY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
                let atBottom = (maxOffsetY - sv.contentOffset.y) <= 45
                if atBottom != isAtBottom {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if atBottom != self.isAtBottom {
                            self.isAtBottom = atBottom
                        }
                    }
                }
            }

            deinit {
                offsetObservation?.invalidate()
                sizeObservation?.invalidate()
            }
        }
    }

    // MARK: - 空对话欢迎面板与一键快捷指令

    private var emptyConversationWelcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 42))
                .foregroundStyle(.blue.gradient)
                .padding(18)
                .background(Color.blue.opacity(0.1), in: Circle())

            VStack(spacing: 6) {
                Text(currentTitle)
                    .font(.title3.weight(.bold))
                Text(currentProjectSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if client.shouldShowFirstTimeMacOnboarding {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer.and.iphone")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.blue)
                            Text(L("2 步极简连接 Mac"))
                                .font(.headline.weight(.bold))
                            Spacer()
                        }

                        // 第 1 步
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("1")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.blue, in: Circle())
                                Text(L("在 Mac 终端执行一键安装配置命令"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Text("curl -fsSL https://raw.githubusercontent.com/lilingdeveloper/antigravity-remote/main/install.sh | bash")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                            Button {
                                UIPasteboard.general.string = "curl -fsSL https://raw.githubusercontent.com/lilingdeveloper/antigravity-remote/main/install.sh | bash"
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                copiedInstallCmd = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    copiedInstallCmd = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: copiedInstallCmd ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    Text(copiedInstallCmd ? L("已复制到剪贴板") : L("一键复制 Mac 安装命令"))
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(copiedInstallCmd ? Color.green.opacity(0.15) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(copiedInstallCmd ? .green : .blue)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        // 第 2 步
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("2")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.blue, in: Circle())
                                Text(L("扫描 Mac 终端或浏览器配对二维码"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showQRScannerSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.headline)
                                    Text(L("打开相机扫描 Mac 二维码"))
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showMacSetupGuideSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                    Text(L("查看详细图文步骤"))
                                }
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 6)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        client.enterDemoMode()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.headline)
                            Text(L("体验交互演示模式（无需连接 Mac）"))
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.teal],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                } else {
                    Text(L("快捷远程指令"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    ForEach([
                        ("sparkles", "/plan 规划新功能方案", "先生成结构化实施计划，待手机审批后再改代码"),
                        ("bolt.fill", "/boost 深度优化当前项目", "多视角分析并改进架构、性能与 UI 细节"),
                        ("magnifyingglass", "总结当前项目的结构与最近修改", "快速了解电脑端当前工作区的最新进展"),
                        ("wrench.and.screwdriver.fill", "检查并修复当前项目的编译或运行报错", "自动运行构建测试并修复问题")
                    ], id: \.1) { icon, cmd, desc in
                        Button {
                            Task { await client.sendMessage(text: cmd) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 34, height: 34)
                                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cmd)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 消息气泡、思考过程持久化展开与代码块卡片渲染

    @ViewBuilder
    private func messageRow(_ msg: ChatMessageItem) -> some View {
        if msg.role == "user" {
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Spacer(minLength: 45)
                    Text(msg.text ?? "")
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .textSelection(.enabled)
                }

                if let fullText = msg.text, !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    copyFullMessageButton(msgId: "full-\(msg.id)", fullText: fullText)
                        .padding(.trailing, 4)
                }
            }
        } else if msg.role == "tool" {
            toolExecutionPill(msg)
        } else {
            let trimmedThinking = (msg.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedText = (msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let showThinking = client.showThinkingProcess && !trimmedThinking.isEmpty
            let showText = !trimmedText.isEmpty

            if showThinking || showText {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 10) {
                        if showThinking {
                            thinkingCard(msgId: msg.id, thinking: trimmedThinking, isStreaming: msg.isGenerating == true)
                        }

                        if showText, let rawText = msg.text {
                            formattedAssistantBody(msgId: msg.id, text: rawText)
                        }
                    }
                    .padding(13)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if showText, let fullText = msg.text {
                        copyFullMessageButton(msgId: "full-\(msg.id)", fullText: fullText)
                            .padding(.leading, 4)
                    }
                }
            }
        }
    }

    private func copyFullMessageButton(msgId: String, fullText: String) -> some View {
        let isCopied = (copiedBlockId == msgId)
        return Button {
            UIPasteboard.general.string = fullText
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            copiedBlockId = msgId
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(isCopied ? L("已复制") : L("复制"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isCopied ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.75), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func thinkingCard(msgId: String, thinking: String, isStreaming: Bool) -> some View {
        let isExpanded = client.expandedThinkingIds.contains(msgId) || client.autoExpandThinking
        let lastLine = thinking
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        client.expandedThinkingIds.remove(msgId)
                    } else {
                        client.expandedThinkingIds.insert(msgId)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    Text(isStreaming ? "\(L("思考过程")) (\(thinking.count))..." : "\(L("思考过程")) (\(thinking.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple.opacity(0.8))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(thinking)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .textSelection(.enabled)
            } else if isStreaming && !lastLine.isEmpty {
                Text(lastLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toolExecutionPill(_ msg: ChatMessageItem) -> some View {
        let name = msg.toolName ?? ""
        let isExpanded = expandedToolIds.contains(msg.id)
        let (icon, color): (String, Color) = {
            switch name {
            case "run_command", "manage_task":
                return ("terminal.fill", .green)
            case "write_file", "edit_file":
                return ("pencil.and.outline", .orange)
            case "read_file":
                return ("doc.text.fill", .blue)
            case "search_web":
                return ("globe", .purple)
            case "ask_question":
                return ("questionmark.bubble.fill", .pink)
            default:
                return ("wrench.and.screwdriver.fill", .secondary)
            }
        }()

        let detailContent: String = {
            if let t = msg.text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            if let s = msg.summary, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
            if let th = msg.thinking, !th.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return th
            }
            return msg.toolName ?? "无详细参数"
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedToolIds.remove(msg.id)
                    } else {
                        expandedToolIds.insert(msg.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 22, height: 22)
                        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

                    Text(msg.summary ?? msg.toolName ?? "调用工具")
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    if msg.status == "CORTEX_STEP_STATUS_RUNNING" {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.75))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("\(name) · #\(msg.stepIndex ?? 0)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = detailContent
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                Text("复制")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(detailContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(uiColor: .tertiarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 结构化解析文本与代码块 (带 NSCache 高性能缓存)

    private struct MessageSegment: Identifiable {
        let id: String
        let isCode: Bool
        let language: String
        let content: String
    }

    private final class SegmentsBox {
        let segments: [MessageSegment]
        init(_ segments: [MessageSegment]) { self.segments = segments }
    }

    private static let segmentsCache: NSCache<NSString, SegmentsBox> = {
        let c = NSCache<NSString, SegmentsBox>()
        c.countLimit = 400
        return c
    }()

    private func parseSegments(msgId: String, raw: String) -> [MessageSegment] {
        let cacheKey = "\(msgId):\(raw.count):\(raw.hashValue)" as NSString
        if let cached = Self.segmentsCache.object(forKey: cacheKey) {
            return cached.segments
        }

        var result: [MessageSegment] = []
        let lines = raw.components(separatedBy: "\n")
        var inCode = false
        var currentLang = ""
        var currentLines: [String] = []
        var idx = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    result.append(MessageSegment(
                        id: "\(msgId)-seg-\(idx)",
                        isCode: true,
                        language: currentLang.isEmpty ? "code" : currentLang,
                        content: currentLines.joined(separator: "\n")
                    ))
                    idx += 1
                    currentLines.removeAll()
                    currentLang = ""
                    inCode = false
                } else {
                    if !currentLines.isEmpty {
                        let prose = currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                        if !prose.isEmpty {
                            result.append(MessageSegment(
                                id: "\(msgId)-seg-\(idx)",
                                isCode: false,
                                language: "",
                                content: prose
                            ))
                            idx += 1
                        }
                        currentLines.removeAll()
                    }
                    currentLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                result.append(MessageSegment(
                    id: "\(msgId)-seg-\(idx)",
                    isCode: inCode,
                    language: currentLang.isEmpty ? "code" : currentLang,
                    content: text
                ))
            }
        }
        Self.segmentsCache.setObject(SegmentsBox(result), forKey: cacheKey)
        return result
    }

    @ViewBuilder
    private func formattedAssistantBody(msgId: String, text: String) -> some View {
        let segments = parseSegments(msgId: msgId, raw: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { seg in
                if seg.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(seg.language.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = seg.content
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                copiedBlockId = seg.id
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: copiedBlockId == seg.id ? "checkmark" : "doc.on.doc")
                                    Text(copiedBlockId == seg.id ? "已复制" : "复制")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(copiedBlockId == seg.id ? .green : .blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemBackground))

                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(seg.content)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .textSelection(.enabled)
                        }
                    }
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                } else {
                    Text(renderSafeMarkdown(seg.content))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private final class AttributedStringBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private static let markdownCache: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 400
        return cache
    }()

    /// 安全渲染 Markdown 文本：
    /// Apple 的 AttributedString(markdown:) 会把两个波浪号 `~`（例如路径 `~/Library`、`~/.gemini` 或区间 `1~5`、`~20ms`）
    /// 之间的所有文字误判为 GFM 删除线 (Strikethrough)，导致大段正常回复被划掉！
    /// 此处转义 `~` 并强制移除 strikethroughStyle，同时美化 Markdown 标题前缀，并缓存解析结果以消除前后台切换重绘卡顿。
    private func renderSafeMarkdown(_ raw: String) -> AttributedString {
        let cacheKey = raw as NSString
        if let cached = Self.markdownCache.object(forKey: cacheKey) {
            return cached.value
        }

        let cleanedLines = raw.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" {
                return "────────────────────"
            }
            if trimmed.hasPrefix("#### ") {
                return "**" + trimmed.dropFirst(5) + "**"
            }
            if trimmed.hasPrefix("### ") {
                return "**" + trimmed.dropFirst(4) + "**"
            }
            if trimmed.hasPrefix("## ") {
                return "**" + trimmed.dropFirst(3) + "**"
            }
            if trimmed.hasPrefix("# ") {
                return "**" + trimmed.dropFirst(2) + "**"
            }
            return line
        }
        // 转义波浪号 `~`，彻底阻止 AttributedString 将 `~...~` 渲染为删除线
        let safeMarkdown = cleanedLines
            .joined(separator: "\n")
            .replacingOccurrences(of: "~", with: "\\~")

        if var attr = try? AttributedString(
            markdown: safeMarkdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            attr.strikethroughStyle = nil
            Self.markdownCache.setObject(AttributedStringBox(attr), forKey: cacheKey)
            return attr
        }
        let fallback = AttributedString(raw)
        Self.markdownCache.setObject(AttributedStringBox(fallback), forKey: cacheKey)
        return fallback
    }

    // MARK: - 远程权限审批 / Proceed / 多选题卡片

    @ViewBuilder
    private func approvalCard(_ pending: PendingInteractionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.shield.fill")
                    .foregroundStyle(.orange)
                Text(L(pending.title ?? "需要您的远程确认"))
                    .font(.subheadline.weight(.bold))
                Spacer()
            }

            if pending.kind == "artifact_approval" {
                Text(pending.summary ?? "请审查生成的实现方案")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await client.respondToInteraction(pending, allow: true) }
                    } label: {
                        Text(L("批准方案并继续 (Proceed)"))
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        selectedTab = 2
                    } label: {
                        Text("查看方案")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                }
            } else if pending.kind == "ask_question", let q = pending.questions?.first {
                Text(q.question ?? "")
                    .font(.callout.weight(.medium))
                ForEach(q.options ?? [], id: \.optionId) { opt in
                    Button {
                        Task {
                            await client.respondToInteraction(
                                pending,
                                allow: true,
                                selectedOptionId: opt.id ?? opt.text
                            )
                        }
                    } label: {
                        Text(opt.text ?? "")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if let code = pending.commandLine ?? pending.pathUri ?? pending.reason, !code.isEmpty {
                    Text(code)
                        .font(.caption.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await client.respondToInteraction(pending, allow: true) }
                    } label: {
                        Text(L("批准执行 (Approve)"))
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        Task { await client.respondToInteraction(pending, allow: false) }
                    } label: {
                        Text(L("拒绝 (Reject)"))
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange, lineWidth: 1.5)
                )
        )
    }

    // MARK: - 排队消息托盘 + 底部输入栏

    private var queuedMessagesTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("待发送 (\(client.queuedMessages.count)) · 等待 AI 回复完上一条消息后自动发送")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 5) {
                ForEach(Array(client.queuedMessages.enumerated()), id: \.element.id) { index, qItem in
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.14), in: Capsule())

                        Text(qItem.text)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Button {
                            Task { await client.flushQueuedMessage(qItem) }
                        } label: {
                            Text("立即发送")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await client.removeQueuedMessage(qItem) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.95))
    }

    private var composerBar: some View {
        let isQueueModeActive = client.queueMessagesWhenBusy && (client.isGenerating || !client.queuedMessages.isEmpty)
        let canSend = (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) && !isLoadingMedia

        return VStack(spacing: 6) {
            if !pendingAttachments.isEmpty || isLoadingMedia {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pendingAttachments) { item in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let thumb = item.thumbnailImage {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        ZStack {
                                            Color(uiColor: .secondarySystemBackground)
                                            Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                                .overlay(alignment: .bottomLeading) {
                                    if item.isVideo {
                                        HStack(spacing: 2) {
                                            Image(systemName: "video.fill")
                                                .font(.system(size: 8, weight: .bold))
                                            Text("视频")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.65), in: Capsule())
                                        .padding(4)
                                    }
                                }

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    pendingAttachments.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white, Color.black.opacity(0.75))
                                }
                                .offset(x: 5, y: -5)
                            }
                            .padding(.top, 5)
                            .padding(.trailing, 5)
                        }

                        if isLoadingMedia {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在处理媒体...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 60)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 输入框左侧：上传图片或视频按钮
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: singleLineInputHeight, height: singleLineInputHeight)
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())

                        if !pendingAttachments.isEmpty {
                            Text("\(pendingAttachments.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue, in: Capsule())
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: selectedPhotoItems) { newItems in
                    guard !newItems.isEmpty else { return }
                    Task {
                        await loadPickedMediaItems(newItems)
                    }
                }

                TextField(
                    L("向电脑端 Antigravity 发送指令..."),
                    text: $inputText,
                    axis: .vertical
                )
                .focused($isInputFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: InputFieldHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: singleLineInputHeight / 2, style: .continuous)
                )

                Button {
                    let text = inputText
                    let attachments = pendingAttachments
                    inputText = ""
                    pendingAttachments.removeAll()
                    isInputFocused = false
                    Task { await client.sendMessage(text: text, attachments: attachments) }
                } label: {
                    Image(systemName: isQueueModeActive ? "clock.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary.opacity(0.55))
                        .frame(width: singleLineInputHeight, height: singleLineInputHeight)
                        .background(
                            canSend
                                ? (isQueueModeActive ? Color.orange : Color.blue)
                                : Color(uiColor: .secondarySystemBackground),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .onPreferenceChange(InputFieldHeightPreferenceKey.self) { measuredHeight in
                guard measuredHeight > 20 else { return }
                if inputText.isEmpty || measuredHeight < singleLineInputHeight {
                    let rounded = (measuredHeight * 2).rounded() / 2
                    if abs(singleLineInputHeight - rounded) > 0.1 {
                        singleLineInputHeight = rounded
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @MainActor
    private func loadPickedMediaItems(_ items: [PhotosPickerItem]) async {
        isLoadingMedia = true
        defer {
            selectedPhotoItems.removeAll()
            isLoadingMedia = false
        }

        for (idx, item) in items.enumerated() {
            let isVideo = item.supportedContentTypes.contains {
                $0.conforms(to: .movie) || $0.conforms(to: .video)
            }
            guard let rawData = try? await item.loadTransferable(type: Data.self), !rawData.isEmpty else {
                continue
            }

            if isVideo {
                let isMp4 = item.supportedContentTypes.contains { $0.conforms(to: .mpeg4Movie) }
                let ext = isMp4 ? "mp4" : "mov"
                let mime = isMp4 ? "video/mp4" : "video/quicktime"
                let fileName = "video_\(Int(Date().timeIntervalSince1970))_\(idx + 1).\(ext)"
                let thumb = generateVideoThumbnail(from: rawData, ext: ext)
                pendingAttachments.append(
                    PendingMediaAttachment(
                        mimeType: mime,
                        fileName: fileName,
                        base64Data: rawData.base64EncodedString(),
                        thumbnailImage: thumb,
                        isVideo: true
                    )
                )
            } else if let img = UIImage(data: rawData) {
                let resized = resizeImageIfNeeded(img, maxDimension: 1800)
                guard let jpegData = resized.jpegData(compressionQuality: 0.82) else { continue }
                let fileName = "photo_\(Int(Date().timeIntervalSince1970))_\(idx + 1).jpg"
                pendingAttachments.append(
                    PendingMediaAttachment(
                        mimeType: "image/jpeg",
                        fileName: fileName,
                        base64Data: jpegData.base64EncodedString(),
                        thumbnailImage: resized,
                        isVideo: false
                    )
                )
            }
        }
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func generateVideoThumbnail(from data: Data, ext: String) -> UIImage? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb_\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: tmpURL)
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            let asset = AVURLAsset(url: tmpURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            let cgImg = try gen.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImg)
        } catch {
            return nil
        }
    }

    private func shortModelName(_ full: String) -> String {
        return full
            .replacingOccurrences(of: "Gemini ", with: "G")
            .replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: " (Medium)", with: "·M")
            .replacingOccurrences(of: " (High)", with: "·H")
            .replacingOccurrences(of: " (Low)", with: "·L")
    }

    // MARK: - Tab 2 & Tab 3: 代码变更 Diffs 与 Artifacts

    private var diffsPane: some View {
        List {
            if client.diffs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L("当前对话暂无文件修改记录"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(client.diffs) { diff in
                    let isExpanded = expandedDiffIds.contains(diff.id)
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if isExpanded {
                                    expandedDiffIds.remove(diff.id)
                                } else {
                                    expandedDiffIds.insert(diff.id)
                                }
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diff.fileName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !diff.filePath.isEmpty {
                                        Text(diff.filePath)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            HStack {
                                Text(L("修改后文件内容"))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L("复制全文")) {
                                    UIPasteboard.general.string = diff.modifiedContent ?? ""
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                .font(.caption2.weight(.semibold))
                            }
                            .padding(.top, 4)

                            ScrollView(.horizontal) {
                                Text((diff.modifiedContent ?? "").prefix(8000))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .hideTopScrollEdgeEffect()
        .background(TopScrollEdgeDisabler(selectedTab: selectedTab))
        .refreshable {
            await client.fetchDiffsAndArtifacts(cascadeId: client.currentCascadeId)
        }
    }

    private var artifactsPane: some View {
        List {
            if client.artifacts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L("当前对话暂无方案文档 (Artifact)"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(client.artifacts) { art in
                    let isExpanded = expandedArtifactIds.contains(art.id)
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if isExpanded {
                                    expandedArtifactIds.remove(art.id)
                                } else {
                                    expandedArtifactIds.insert(art.id)
                                }
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(art.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let path = art.filePath, !path.isEmpty {
                                        Text(path)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            if art.name.lowercased().contains("plan"),
                               let pending = client.pendingInteraction,
                               pending.kind == "artifact_approval" {
                                Button {
                                    Task { await client.respondToInteraction(pending, allow: true) }
                                } label: {
                                    Label(L("批准方案并继续 (Proceed)"), systemImage: "checkmark.seal.fill")
                                        .font(.callout.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .padding(.vertical, 4)
                            }

                            HStack {
                                Text(L("文档内容"))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L("复制")) {
                                    UIPasteboard.general.string = art.content ?? ""
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                .font(.caption2.weight(.semibold))
                            }
                            .padding(.top, 4)

                            Text(art.content ?? "（二进制或媒体文件）")
                                .font(.system(size: 12.5, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .hideTopScrollEdgeEffect()
        .background(TopScrollEdgeDisabler(selectedTab: selectedTab))
        .refreshable {
            await client.fetchDiffsAndArtifacts(cascadeId: client.currentCascadeId)
        }
    }

    // MARK: - Tab 4: 底部「设置」主页面 (含思考过程展示、读取文件展示、Tailscale 登录与连接配置)

    private func settingsRowLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44, alignment: .leading)
    }

    private func settingsNavButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                settingsRowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsPane: some View {
        Form {
            Section {
                NavigationLink {
                    LanguagePickerView(l10n: l10n)
                } label: {
                    Text(l10n.currentLanguage.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 38, alignment: .leading)
                }
                .onChange(of: l10n.currentLanguage) { _ in
                    if client.isDemoMode {
                        client.enterDemoMode(scene: client.activeMarketingScene)
                    }
                }
            } header: {
                Text(L("界面语言 / Language"))
            }

            Section {
                Toggle(isOn: $client.showThinkingProcess) {
                    settingsRowLabel(
                        title: L("展示 AI 思考过程 (Thinking)"),
                        subtitle: L("在回复气泡上方显示思考过程折叠卡片")
                    )
                }

                if client.showThinkingProcess {
                    Toggle(isOn: $client.autoExpandThinking) {
                        settingsRowLabel(
                            title: L("默认自动展开思考过程"),
                            subtitle: L("无需手动点击，直接展开完整思考内容")
                        )
                    }
                }

                Toggle(isOn: $client.showFileReadTools) {
                    settingsRowLabel(
                        title: L("展示读取文件记录 (read_file)"),
                        subtitle: L("显示 Agent 读取项目源代码文件的步骤胶丸")
                    )
                }

                Toggle(isOn: $client.showOtherToolCalls) {
                    settingsRowLabel(
                        title: L("展示命令执行与修改文件记录"),
                        subtitle: L("显示终端命令 (run_command)、修改代码 (edit_file) 等步骤")
                    )
                }

                Toggle(isOn: $client.showContextUsageBar) {
                    settingsRowLabel(
                        title: L("展示上下文容量进度条"),
                        subtitle: L("在标题栏下方显示当前对话上下文使用百分比与 Token 容量")
                    )
                }
            } header: {
                Text("对话流展示设置")
            }

            Section {
                Toggle(isOn: $client.enableNotifications) {
                    settingsRowLabel(
                        title: L("后台完成与审批通知"),
                        subtitle: L("当离开 App 时，AI 思考结束或需要操作审批时发送系统通知")
                    )
                }
            } header: {
                Text("系统通知与提醒")
            }

            Section {
                settingsNavButton(
                    title: L("2 步极简连接 Mac 教程（含一键开机自启命令）"),
                    subtitle: L("无需安装 Node.js，一行命令自动配置 Mac 开机自启服务")
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMacSetupGuideSheet = true
                }

                settingsNavButton(
                    title: tailnet.status?.isRunning == true
                        ? "内置 Tailscale 已登录 (\(tailnet.status?.selfIP ?? ""))"
                        : L("一键登录内置 Tailscale 账号"),
                    subtitle: tailnet.status?.isRunning == true
                        ? L("已接入虚拟局域网，支持 5G/异地直接穿透控制 Mac")
                        : L("首次异地控制请点击此处授权登录 Tailscale")
                ) {
                    triggerDirectTailscaleLogin()
                }

                settingsNavButton(
                    title: L("扫码一键配对连接"),
                    subtitle: L("扫描 Mac 端二维码，自动配置 Tailscale 与局域网双通道")
                ) {
                    showQRScannerSheet = true
                }

                settingsNavButton(
                    title: L("Tailscale 组网节点与设备列表"),
                    subtitle: L("查看虚拟局域网在线设备、节点状态与内置引擎控制")
                ) {
                    showTailnetSheet = true
                }

                settingsNavButton(
                    title: L("通道与连接高级设置"),
                    subtitle: L("配置访问令牌 Token、快捷切换首选 IP 与查看路由延迟")
                ) {
                    showSettingsSheet = true
                }
            } header: {
                Text("扫码配对、Tailscale 组网与连接设置")
            }

            Section {
                Button {
                    showPrivacyPolicySheet = true
                } label: {
                    HStack {
                        Text(L("隐私政策"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showOpenSourceLicensesSheet = true
                } label: {
                    HStack {
                        Text(L("开源组件许可"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                LabeledContent("版本号", value: "1.0.0 (Build 11)")
                    .frame(minHeight: 38)
            } header: {
                Text(L("隐私声明"))
            } footer: {
                Text("\(L("如有任何问题，请联系邮箱")) \("liling" + ".developer@gmail.com")")
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .hideTopScrollEdgeEffect()
        .background(TopScrollEdgeDisabler(selectedTab: selectedTab))
    }
}

// MARK: - 隐藏 iOS 26 顶部滚动边缘模糊矩形 (UIScrollEdgeEffect)
private struct TopScrollEdgeDisabler: UIViewRepresentable {
    let selectedTab: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        scheduleDisable(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        scheduleDisable(from: uiView)
    }

    private func scheduleDisable(from view: UIView) {
        for delay in [0.0, 0.04, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let root = view.window ?? view.superview else { return }
                Self.disableTopEdgeEffectRecursively(in: root)
            }
        }
    }

    private static func disableTopEdgeEffectRecursively(in view: UIView) {
        if let sv = view as? UIScrollView {
            if #available(iOS 26.0, *) {
                sv.topEdgeEffect.isHidden = true
            }
        }
        for sub in view.subviews {
            disableTopEdgeEffectRecursively(in: sub)
        }
    }
}

private extension View {
    @ViewBuilder
    func hideTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

// MARK: - 独立语言选择二级子页面
private struct LanguagePickerView: View {
    @ObservedObject var l10n: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    l10n.currentLanguage = lang
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if l10n.currentLanguage == lang {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(L("界面语言 / Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L("界面语言 / Language"))
                    .font(.headline)
            }
        }
    }
}

// MARK: - 单行输入框高度 PreferenceKey，确保左右圆形按钮直径与输入框单行高度精准一致
private struct InputFieldHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
