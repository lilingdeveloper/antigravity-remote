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
                    }
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

            if !client.isConnected {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    client.enterDemoMode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                        Text(L("🎮 体验交互演示模式（无需连接 Mac）"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.green.opacity(0.9), Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMacSetupGuideSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(L("📖 首次使用？点击查看「2 步极简连接 Mac 教程」"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // 当软件内置 Tailscale 尚未登录账号时，在主界面顶部直接常驻醒目的「一键登录 Tailscale」按钮条！
            if tailnet.status?.isRunning != true && !tailnet.systemTailscaleActive && !client.isDemoMode {
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
        return "选择模型"
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
                if !client.isConnected {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        client.enterDemoMode()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.headline)
                            Text(L("🎮 体验交互演示模式（无需连接 Mac）"))
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
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }

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

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

            Text(msg.summary ?? msg.toolName ?? "调用工具")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if msg.status == "CORTEX_STEP_STATUS_RUNNING" {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 结构化解析文本与代码块 (支持一键复制代码)

    private struct MessageSegment: Identifiable {
        let id: String
        let isCode: Bool
        let language: String
        let content: String
    }

    private func parseSegments(msgId: String, raw: String) -> [MessageSegment] {
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
                            .frame(width: 38, height: 38)
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
                .padding(.vertical, 9)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    let text = inputText
                    let attachments = pendingAttachments
                    inputText = ""
                    pendingAttachments.removeAll()
                    isInputFocused = false
                    Task { await client.sendMessage(text: text, attachments: attachments) }
                } label: {
                    if isQueueModeActive {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color.orange : Color.gray.opacity(0.25), in: Circle())
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 33, weight: .semibold))
                            .foregroundStyle(canSend ? Color.blue : Color.gray.opacity(0.45))
                            .frame(width: 34, height: 34)
                    }
                }
                .disabled(!canSend)
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
                    Section {
                        HStack {
                            Text(diff.filePath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button(L("复制全文")) {
                                UIPasteboard.general.string = diff.modifiedContent ?? ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            .font(.caption2.weight(.semibold))
                        }
                        ScrollView(.horizontal) {
                            Text((diff.modifiedContent ?? "").prefix(8000))
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        Label(diff.fileName, systemImage: "doc.text.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
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
                    Section {
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
                        }

                        Text(art.content ?? "（二进制或媒体文件）")
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    } header: {
                        HStack {
                            Label(art.name, systemImage: "doc.richtext.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(L("复制")) {
                                UIPasteboard.general.string = art.content ?? ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            .font(.caption2)
                        }
                    }
                }
            }
        }
        .refreshable {
            await client.fetchDiffsAndArtifacts(cascadeId: client.currentCascadeId)
        }
    }

    // MARK: - Tab 4: 底部「设置」主页面 (含思考过程展示、读取文件展示、Tailscale 登录与连接配置)

    private var settingsPane: some View {
        Form {
            Section {
                Picker(L("界面语言 / Language"), selection: $l10n.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: l10n.currentLanguage) { _ in
                    if client.isDemoMode {
                        client.enterDemoMode(scene: client.activeMarketingScene)
                    }
                }
            } header: {
                Text(L("界面语言 / Language"))
            }

            Section {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if client.isDemoMode {
                        client.exitDemoMode()
                    } else {
                        client.enterDemoMode()
                    }
                } label: {
                    HStack {
                        Image(systemName: client.isDemoMode ? "xmark.circle.fill" : "gamecontroller.fill")
                            .foregroundStyle(client.isDemoMode ? .red : .green)
                        Text(client.isDemoMode ? L("退出演示") : L("进入交互式演示模式 (Demo Mode)"))
                            .foregroundStyle(client.isDemoMode ? .red : .primary)
                        Spacer()
                        if client.isDemoMode {
                            Text("Active")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                if client.isDemoMode {
                    Button {
                        client.triggerDemoApproval()
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(L("触发审批演示"))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } header: {
                Text("交互演示模式 (Demo Mode)")
            } footer: {
                Text("供 App Store 审核员体验或离线测试全部界面与交互流程，无需实际连接 Mac 电脑。")
                    .font(.caption2)
            }

            Section {
                Toggle(isOn: $client.showThinkingProcess) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展示 AI 思考过程 (Thinking)")
                                .font(.body)
                            Text("在回复气泡上方显示 💭 思考过程折叠卡片")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                    }
                }

                if client.showThinkingProcess {
                    Toggle(isOn: $client.autoExpandThinking) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("默认自动展开思考过程")
                                    .font(.body)
                                Text("无需手动点击，直接展开完整思考内容")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundStyle(.purple)
                        }
                    }
                }

                Toggle(isOn: $client.showFileReadTools) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展示读取文件记录 (read_file)")
                                .font(.body)
                            Text("显示 Agent 读取项目源代码文件的步骤胶丸")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Toggle(isOn: $client.showOtherToolCalls) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展示命令执行与修改文件记录")
                                .font(.body)
                            Text("显示终端命令 (run_command)、修改代码 (edit_file) 等步骤")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.green)
                    }
                }

                Toggle(isOn: $client.showContextUsageBar) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展示上下文容量进度条")
                                .font(.body)
                            Text("在标题栏下方显示当前对话上下文使用百分比与 Token 容量")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "memorychip")
                            .foregroundStyle(.cyan)
                    }
                }
            } header: {
                Text("对话流展示设置")
            }

            Section {
                Toggle(isOn: $client.queueMessagesWhenBusy) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发送多条消息自动排队")
                                .font(.body)
                            Text("当 AI 正在思考或回复时，新发送的多条消息自动进入队列依次执行，绝不相互重叠打断")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Toggle(isOn: Binding(
                    get: { client.autoFollowMacConversation },
                    set: { val in
                        client.autoFollowMacConversation = val
                        UserDefaults.standard.set(val, forKey: "agy.autoFollowMac")
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动跟随电脑端新建对话")
                                .font(.body)
                            Text("仅当电脑端新建全新对话时自动切换；后台思考中的对话仅在顶部提示，绝不强制切回")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("消息队列与多端协同")
            }

            Section {
                Button {
                    triggerDirectTailscaleLogin()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(tailnet.status?.isRunning == true ? Color.green : Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tailnet.status?.isRunning == true ? "内置 Tailscale 已登录 (\(tailnet.status?.selfIP ?? ""))" : "🔑 一键登录内置 Tailscale 账号")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(tailnet.status?.isRunning == true ? "已接入虚拟局域网，支持 5G/异地直接穿透控制 Mac" : "首次异地控制请点击此处授权登录 Tailscale")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showQRScannerSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("扫码一键配对连接 (/qr)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("扫描 Mac 端二维码，自动配置 Tailscale 与局域网双通道")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMacSetupGuideSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.pages.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("📖 2 步极简连接 Mac 教程（含一键开机自启命令）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("无需安装 Node.js，一行命令自动配置 Mac 开机自启服务")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showTailnetSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(tailnetIconColor == .secondary ? Color.teal : tailnetIconColor, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tailscale 组网节点与设备列表")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("查看虚拟局域网在线设备、节点状态与内置引擎控制")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("通道与连接高级设置")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("配置访问令牌 Token、快捷切换首选 IP 与查看路由延迟")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("扫码配对、Tailscale 组网与连接设置")
            }

            Section {
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
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    client.saveConnectionConfig()
                    Task { await client.refreshAll() }
                } label: {
                    Text(L("保存地址并立即重连"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } header: {
                Text(L("Mac 桥接服务器参数"))
            }

            Section {
                Button {
                    showPrivacyPolicySheet = true
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.shield.fill")
                            .foregroundStyle(.green)
                        Text(L("隐私政策 (Privacy Policy)"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: URL(string: "https://lilingdeveloper.github.io/antigravity-remote/privacy.html")!) {
                    HStack {
                        Image(systemName: "safari.fill")
                            .foregroundStyle(.blue)
                        Text("在线隐私政策 (Web Privacy Policy)")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showOpenSourceLicensesSheet = true
                } label: {
                    HStack {
                        Image(systemName: "doc.plaintext.fill")
                            .foregroundStyle(.indigo)
                        Text(L("开源组件许可 (Open Source Licenses)"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("版本号", value: "1.0.0 (Build 3)")
            } header: {
                Text(L("隐私声明与关于"))
            } footer: {
                Text("Antigravity Remote · 专为移动端打造的 Google Antigravity 远程控制系统")
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }
}

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
                Section("🌐 内置 Tailscale 节点与一键配对") {
                    Button {
                        onOpenTailscaleLogin()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(tailnet.status?.isRunning == true ? Color.green : Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tailnet.status?.isRunning == true ? "内置 Tailscale 已登录 (\(tailnet.status?.selfIP ?? ""))" : "🔑 点击登录内置 Tailscale 账号")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(tailnet.status?.isRunning == true ? "点击查看组网设备列表或切换账号" : "首次使用点击此处，在应用内一键授权登录您的 Tailscale")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("扫码一键建立 Tailscale / 局域网连接")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("扫描 Mac 端 /qr 二维码，自动配置多路竞速通道")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Mac 桥接服务地址 (支持双通道自动竞速)") {
                    LabeledContent("主地址 (Tailscale)") {
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
                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("8789", value: $client.serverPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    SecureField("访问令牌 Token (可选)", text: $client.accessToken)
                        .textInputAutocapitalization(.never)
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

                Section("实时同步设置") {
                    Toggle("自动切换到电脑端新建/新活跃的对话", isOn: Binding(
                        get: { client.autoFollowMacConversation },
                        set: { val in
                            client.autoFollowMacConversation = val
                            UserDefaults.standard.set(val, forKey: "agy.autoFollowMac")
                        }
                    ))
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
        // 若当前全局已选中该家族下的某个模型，优先匹配其强度
        let currentId = client.selectedModelId.isEmpty ? client.activeConversationModelId : client.selectedModelId
        if let matched = family.variants.first(where: { $0.model.modelId == currentId }) {
            return matched
        }
        // 默认优先选中 High 或 Medium
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
