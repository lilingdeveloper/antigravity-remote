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
    @State private var showSettingsPageSheet = false
    @State private var showSettingsSheet = false
    @State private var showTailnetSheet = false
    @State private var showQRScannerSheet = false
    @State private var showModelPickerSheet = false
    @State private var showMacSetupGuideSheet = false
    @State private var showPrivacyPolicySheet = false
    @State private var showOpenSourceLicensesSheet = false
    @State private var showDiffsSheet = false
    @State private var showArtifactsSheet = false
    @State private var selectedDiffForCard: FileDiffItem?
    @State private var selectedArtifactForCard: ArtifactItem?
    @State private var showNewChatAlert = false
    @State private var newChatPrompt = ""
    @State private var pairToastMessage: String?
    @State private var copiedBlockId: String?
    @State private var directLoginURL: URL?
    @State private var showDirectSafariLogin = false
    @State private var isFetchingLoginURL = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var isChatAtBottom: Bool = true
    @StateObject private var chatScrollBridge = ChatScrollBridge()
    @State private var expandedToolIds: Set<String> = []
    @State private var expandedUserTurnIds: Set<String> = []
    @State private var expandedPlanCodeTurnIds: Set<String> = []
    @State private var expandedDiffIds: Set<String> = []
    @State private var expandedArtifactIds: Set<String> = []
    @State private var copiedInstallCmd: Bool = false
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

                        chatPane
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
                                    .font(.system(size: 16, weight: .semibold))
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

                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isInputFocused = false
                                showSettingsPageSheet = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .sheet(isPresented: $showSettingsPageSheet) {
                        NavigationStack {
                            settingsPane
                                .navigationTitle(L("设置"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button(L("完成")) {
                                            showSettingsPageSheet = false
                                        }
                                    }
                                }
                        }
                        .presentationDragIndicator(.visible)
                    }
                    .sheet(item: $selectedArtifactForCard) { artifact in
                        artifactCardModalView(artifact)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(item: $selectedDiffForCard) { diff in
                        diffCardModalView(diff)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showArtifactsSheet) {
                        NavigationStack {
                            artifactsPane
                                .navigationTitle(L("方案文档"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button(L("完成")) {
                                            showArtifactsSheet = false
                                        }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showDiffsSheet) {
                        NavigationStack {
                            diffsPane
                                .navigationTitle(L("代码变更"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button(L("完成")) {
                                            showDiffsSheet = false
                                        }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
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
                    .alert("新建对话", isPresented: $showNewChatAlert) {
                        TextField("输入新对话名称（可选）...", text: $newChatPrompt)
                        Button("取消", role: .cancel) { newChatPrompt = "" }
                        Button("创建") {
                            let title = newChatPrompt
                            newChatPrompt = ""
                            Task {
                                await client.createNewBlankConversation(title: title)
                            }
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
            client.expandedThinkingIds.insert("step-1")
        case "approval":
            break
        case "diffs":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let first = client.diffs.first {
                    selectedDiffForCard = first
                } else {
                    showDiffsSheet = true
                }
            }
        case "artifacts":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let first = client.artifacts.first {
                    selectedArtifactForCard = first
                } else {
                    showArtifactsSheet = true
                }
            }
        case "sidebar":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showConversationsSheet = true
            }
        case "models":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showModelPickerSheet = true
            }
        case "settings":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showSettingsPageSheet = true
            }
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

            HStack(spacing: 6) {
                // 连接状态与实时延迟胶囊 (点击弹出设置页)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSettingsPageSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 7, height: 7)
                        Text(compactRouteCapsuleText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)

                // 当前选择模型的「5 小时额度」与「1 周额度」胶囊（紧挨局域网胶囊右侧，充分利用空间）
                if let activeModel = currentActiveModelItem {
                    let frac5h = activeModel.fiveHourRemainingFraction ?? activeModel.remainingFraction ?? 1.0
                    let frac1w = activeModel.weeklyRemainingFraction ?? activeModel.remainingFraction ?? 1.0
                    headerQuotaCapsule(title: L("5小时额度"), fraction: frac5h)
                    headerQuotaCapsule(title: L("1周额度"), fraction: frac1w)
                }

                Spacer(minLength: 2)

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

    private var compactRouteCapsuleText: String {
        guard client.isConnected else {
            return client.isReconnecting ? L("正在重连...") : L("未连接 Mac")
        }
        if client.isDemoMode {
            return client.connectionRouteDescription
        }
        let rttSuffix = client.latencyMs.map { " · \($0)ms" } ?? ""
        switch client.routeKind {
        case .lanDirect:
            return "\(L("局域网"))\(rttSuffix)"
        case .systemTailscale, .embeddedTailnet:
            return "Tailscale\(rttSuffix)"
        case .customTunnel:
            return "\(L("公网隧道"))\(rttSuffix)"
        case .probing:
            return client.connectionRouteDescription
        }
    }

    private var currentActiveModelItem: AIModelItem? {
        if !client.selectedModelId.isEmpty,
           let found = client.models.first(where: { $0.modelId == client.selectedModelId }) {
            return found
        }
        if !client.activeConversationModelId.isEmpty,
           let found = client.models.first(where: { $0.modelId == client.activeConversationModelId }) {
            return found
        }
        return client.models.first
    }

    private func headerQuotaCapsule(title: String, fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let pct = Int(round(clamped * 100))
        let color: Color = pct > 50 ? .green : (pct > 20 ? .orange : .red)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showModelPickerSheet = true
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !client.isGenerating {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 22, height: 5)
                        Capsule()
                            .fill(color)
                            .frame(width: max(3, 22 * clamped), height: 5)
                    }
                }

                Text("\(pct)%")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
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
            if let first = client.models.first {
                return first.label
            }
            return L("模型")
        }()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("placeholder") || trimmed == "选择模型" {
            return L("模型")
        }
        return trimmed
    }

    /// 拆分模型显示名为「主名称 + 思考等级后缀」（如 ("Gemini 3.1 Pro", "High")）以对齐 Antigravity Remote Control 底部栏样式
    private var composerModelParts: (baseName: String, tier: String?) {
        let full = currentModelLabel
        if let openIdx = full.lastIndex(of: "("),
           let closeIdx = full.lastIndex(of: ")"),
           openIdx < closeIdx {
            let base = String(full[..<openIdx]).trimmingCharacters(in: .whitespaces)
            let tier = String(full[full.index(after: openIdx)..<closeIdx]).trimmingCharacters(in: .whitespaces)
            if !base.isEmpty && !tier.isEmpty {
                return (base, tier)
            }
        }
        return (full, nil)
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

    // MARK: - 按「用户每轮提问」分组并支持滚动吸顶置顶 (Sticky Turn Headers)

    private struct ChatTurnGroup: Identifiable {
        let id: String
        let userMessage: ChatMessageItem?
        var responseItems: [ChatMessageItem]
        var fileModificationTools: [ChatMessageItem]
    }

    private func isFileModificationTool(_ msg: ChatMessageItem) -> Bool {
        guard msg.role == "tool" else { return false }
        let name = msg.toolName ?? ""
        let sum = msg.summary ?? ""
        return name == "write_file" || name == "edit_file" || sum.hasPrefix("写入文件") || sum.hasPrefix("修改文件")
    }

    private var chatTurnGroups: [ChatTurnGroup] {
        var groups: [ChatTurnGroup] = []
        for msg in visibleMessages {
            if msg.role == "user" {
                groups.append(
                    ChatTurnGroup(
                        id: "turn-\(msg.id)",
                        userMessage: msg,
                        responseItems: [],
                        fileModificationTools: []
                    )
                )
            } else {
                let isFileMod = isFileModificationTool(msg)
                if groups.isEmpty {
                    groups.append(
                        ChatTurnGroup(
                            id: "turn-leading-\(msg.id)",
                            userMessage: nil,
                            responseItems: isFileMod ? [] : [msg],
                            fileModificationTools: isFileMod ? [msg] : []
                        )
                    )
                } else {
                    if isFileMod {
                        groups[groups.count - 1].fileModificationTools.append(msg)
                    } else {
                        groups[groups.count - 1].responseItems.append(msg)
                    }
                }
            }
        }
        return groups
    }

    // MARK: - Tab 1: 丝滑对话流 (每轮用户消息吸顶置顶) + 审批卡片 + 底部输入栏

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
                                let turns = chatTurnGroups
                                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                    ForEach(Array(turns.enumerated()), id: \.element.id) { idx, turn in
                                        let isLastTurn = (idx == turns.count - 1)
                                        Section {
                                            VStack(alignment: .leading, spacing: 14) {
                                                ForEach(turn.responseItems) { item in
                                                    turnResponseItemRow(item)
                                                        .id(item.id)
                                                }
                                                if (isLastTurn && (!client.artifacts.isEmpty || !client.diffs.isEmpty || !turn.fileModificationTools.isEmpty)) ||
                                                   (!isLastTurn && !turn.fileModificationTools.isEmpty) {
                                                    turnPlanAndCodeCategoryCard(turn: turn, isLatestTurn: isLastTurn)
                                                        .id("PLAN_CODE_CATEGORY_\(turn.id)")
                                                }
                                                if isLastTurn && shouldShowWorkingIndicator {
                                                    aiWorkingIndicatorRow
                                                        .id("AI_WORKING_INDICATOR")
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 22)
                                        } header: {
                                            if let userMsg = turn.userMessage {
                                                stickyUserTurnHeader(userMsg)
                                                    .id(userMsg.id)
                                            }
                                        }
                                    }
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM_ANCHOR")
                        }
                        .background(
                            ChatScrollObserver(
                                isAtBottom: $isChatAtBottom,
                                bridge: chatScrollBridge
                            )
                        )
                        .onAppear {
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                    .trackChatScrollAtBottom($isChatAtBottom, bridge: chatScrollBridge)
                    .environment(\.openURL, OpenURLAction { url in
                        handleChatLinkTap(url)
                    })
                    .hideTopScrollEdgeEffect()
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await client.refreshAll()
                    }
                    .id(client.currentCascadeId)
                    .onChange(of: client.currentCascadeId) { _ in
                        isChatAtBottom = true
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: client.messages.count) { oldCount, newCount in
                        if oldCount == 0 || abs(newCount - oldCount) > 1 || chatScrollBridge.isScrollingToBottomProgrammatically {
                            scrollToBottom(proxy, animated: false)
                        } else if isChatAtBottom {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                    .onChange(of: client.isGenerating) { isGen in
                        if isGen && isChatAtBottom {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                    .onChange(of: client.messages.last?.text) { _ in
                        if client.isGenerating && isChatAtBottom {
                            scrollToBottom(proxy, animated: false)
                        }
                    }

                    // 底部居中快捷滚到底部小按钮
                    if !visibleMessages.isEmpty && !isChatAtBottom && client.activeMarketingScene == nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            scrollToBottom(proxy, animated: true)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(.regularMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                                )
                                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .zIndex(20)
                        .padding(.bottom, 12)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        isChatAtBottom = true
        guard !visibleMessages.isEmpty || shouldShowWorkingIndicator else {
            chatScrollBridge.resetToTop()
            return
        }

        if animated {
            chatScrollBridge.beginProgrammaticScrollToBottom(duration: 0.40)
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
            }
            chatScrollBridge.scrollToBottom(animated: true)

            for delay in [0.10, 0.24, 0.36] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard !chatScrollBridge.isUserInteracting else { return }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                    }
                    chatScrollBridge.clampOverscrollAndSnapToBottom()
                }
            }
        } else {
            chatScrollBridge.beginProgrammaticScrollToBottom(duration: 0.42)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
            }
            chatScrollBridge.clampOverscrollAndSnapToBottom()

            for delay in [0.02, 0.07, 0.16, 0.28, 0.38] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard !chatScrollBridge.isUserInteracting else { return }
                    guard !visibleMessages.isEmpty || shouldShowWorkingIndicator else {
                        chatScrollBridge.resetToTop()
                        return
                    }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                    }
                    chatScrollBridge.clampOverscrollAndSnapToBottom()
                }
            }
        }
    }

    // MARK: - 聊天滚动监听器 (判断是否在底部、防止切换对话过滚空白 & 禁用 scrollsToTop)

    private struct ChatScrollObserver: UIViewRepresentable {
        @Binding var isAtBottom: Bool
        let bridge: ChatScrollBridge

        func makeCoordinator() -> Coordinator {
            Coordinator(isAtBottom: $isAtBottom, bridge: bridge)
        }

        func makeUIView(context: Context) -> ScrollProbeUIView {
            let view = ScrollProbeUIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.onAttachCheck = { [weak coordinator = context.coordinator] probe in
                coordinator?.attach(to: probe)
            }
            DispatchQueue.main.async {
                context.coordinator.attach(to: view)
            }
            return view
        }

        func updateUIView(_ uiView: ScrollProbeUIView, context: Context) {
            uiView.onAttachCheck = { [weak coordinator = context.coordinator] probe in
                coordinator?.attach(to: probe)
            }
            if context.coordinator.observedScrollView == nil || context.coordinator.observedScrollView?.window == nil {
                DispatchQueue.main.async {
                    context.coordinator.attach(to: uiView)
                }
            }
        }

        final class Coordinator: NSObject {
            @Binding var isAtBottom: Bool
            let bridge: ChatScrollBridge
            weak var observedScrollView: UIScrollView?
            private var offsetObservation: NSKeyValueObservation?
            private var sizeObservation: NSKeyValueObservation?
            private var boundsObservation: NSKeyValueObservation?
            private var isClampingOffset: Bool = false

            init(isAtBottom: Binding<Bool>, bridge: ChatScrollBridge) {
                self._isAtBottom = isAtBottom
                self.bridge = bridge
            }

            func attach(to view: UIView) {
                guard view.window != nil else { return }
                var current: UIView? = view
                while let parent = current?.superview {
                    if let sv = parent as? UIScrollView {
                        if #available(iOS 26.0, *) {
                            sv.topEdgeEffect.isHidden = true
                        }
                        sv.scrollsToTop = false
                        bridge.scrollView = sv
                        if self.observedScrollView !== sv {
                            self.observedScrollView = sv
                            setupObservations(for: sv)
                        }
                        checkBottom(sv)
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
                boundsObservation = sv.observe(\.bounds, options: [.initial, .new]) { [weak self] sv, _ in
                    self?.checkBottom(sv)
                }
            }

            private func checkBottom(_ sv: UIScrollView) {
                guard !isClampingOffset else { return }
                guard sv.bounds.height > 0 else { return }

                if sv.isTracking || sv.isDragging {
                    bridge.cancelProgrammaticScroll()
                }

                let minOffsetY = -sv.adjustedContentInset.top
                let maxOffsetY = max(minOffsetY, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)

                if !sv.isDragging && !sv.isTracking && !sv.isDecelerating {
                    if bridge.isScrollingToBottomProgrammatically {
                        if abs(sv.contentOffset.y - maxOffsetY) > 0.5 {
                            isClampingOffset = true
                            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: maxOffsetY), animated: false)
                            isClampingOffset = false
                        }
                    } else if sv.contentOffset.y > maxOffsetY + 1 {
                        isClampingOffset = true
                        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: maxOffsetY), animated: false)
                        isClampingOffset = false
                    } else if sv.contentOffset.y < minOffsetY - 1 {
                        isClampingOffset = true
                        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: minOffsetY), animated: false)
                        isClampingOffset = false
                    }
                }

                let distanceFromBottom = maxOffsetY - sv.contentOffset.y
                let atBottom = bridge.isScrollingToBottomProgrammatically ? true : (distanceFromBottom <= 50)
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
                boundsObservation?.invalidate()
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

    // MARK: - 吸顶用户消息栏 (Sticky User Turn Header) 与全宽文档流式回复渲染

    @ViewBuilder
    private func stickyUserTurnHeader(_ msg: ChatMessageItem) -> some View {
        let rawText = (msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedUserTurnIds.contains(msg.id)
        let isLong = rawText.count > 72 || rawText.contains("\n")

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(rawText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? 14 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLong {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard isLong else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedUserTurnIds.remove(msg.id)
                    } else {
                        expandedUserTurnIds.insert(msg.id)
                    }
                }
            }
            .contextMenu {
                if !rawText.isEmpty {
                    Button {
                        UIPasteboard.general.string = rawText
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(L("复制提问内容"), systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(uiColor: .systemBackground).opacity(0.96))
    }

    @ViewBuilder
    private func turnResponseItemRow(_ msg: ChatMessageItem) -> some View {
        if msg.role == "tool" {
            toolExecutionPill(msg)
        } else {
            let trimmedThinking = (msg.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedText = (msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let showThinking = client.showThinkingProcess && !trimmedThinking.isEmpty
            let showText = !trimmedText.isEmpty

            if showThinking || showText {
                VStack(alignment: .leading, spacing: 12) {
                    if showThinking {
                        thinkingCard(msgId: msg.id, thinking: trimmedThinking, isStreaming: msg.isGenerating == true)
                    }

                    if showText, let rawText = msg.text {
                        formattedAssistantBody(msgId: msg.id, text: rawText)
                            .lineSpacing(4)

                        HStack(spacing: 14) {
                            Spacer()
                            copyFullMessageButton(msgId: "full-\(msg.id)", fullText: rawText)
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                if isCopied {
                    Text(L("已复制"))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(isCopied ? Color.green : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
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

    private func extractTargetFileToken(from msg: ChatMessageItem) -> String {
        let candidates = [msg.summary ?? "", msg.text ?? ""]
        for raw in candidates where !raw.isEmpty {
            for prefix in ["写入文件:", "修改文件:", "读取文件:", "write_file:", "edit_file:", "read_file:"] {
                if let range = raw.range(of: prefix) {
                    let tail = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    let token = tail.split(whereSeparator: { $0.isWhitespace || $0 == "`" }).first.map(String.init) ?? tail
                    if !token.isEmpty { return token }
                }
            }
        }
        return ""
    }

    private func matchedArtifactForTool(_ msg: ChatMessageItem) -> ArtifactItem? {
        let name = msg.toolName ?? ""
        let sum = msg.summary ?? ""
        guard name == "write_file" || name == "edit_file" || sum.hasPrefix("写入文件") || sum.hasPrefix("修改文件") else {
            return nil
        }
        let token = extractTargetFileToken(from: msg)
        guard !token.isEmpty else { return nil }
        let base = (token as NSString).lastPathComponent.lowercased()
        return client.artifacts.first { art in
            let artName = art.name.lowercased()
            let artBase = ((art.filePath ?? "") as NSString).lastPathComponent.lowercased()
            return artName == base || artBase == base || artName.contains(base)
        }
    }

    private func matchedDiffForTool(_ msg: ChatMessageItem) -> FileDiffItem? {
        let name = msg.toolName ?? ""
        let sum = msg.summary ?? ""
        guard name == "write_file" || name == "edit_file" || sum.hasPrefix("写入文件") || sum.hasPrefix("修改文件") else {
            return nil
        }
        let token = extractTargetFileToken(from: msg)
        guard !token.isEmpty else { return nil }
        let base = (token as NSString).lastPathComponent.lowercased()
        return client.diffs.first { diff in
            diff.fileName.lowercased() == base || diff.filePath.lowercased().hasSuffix(base)
        }
    }

    private func handleChatLinkTap(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == "file" {
            let rawPath = url.path
            let fileName = url.lastPathComponent.lowercased()
            if !fileName.isEmpty {
                if let art = client.artifacts.first(where: {
                    $0.name.lowercased() == fileName ||
                    (($0.filePath ?? "") as NSString).lastPathComponent.lowercased() == fileName ||
                    ($0.filePath ?? "") == rawPath
                }) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedArtifactForCard = art
                    return .handled
                }
                if let diff = client.diffs.first(where: {
                    $0.fileName.lowercased() == fileName ||
                    $0.filePath == rawPath ||
                    $0.filePath.lowercased().hasSuffix(fileName)
                }) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedDiffForCard = diff
                    return .handled
                }
                if fileName.hasSuffix(".md"), let firstArt = client.artifacts.first {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedArtifactForCard = firstArt
                    return .handled
                }
                if let firstDiff = client.diffs.first {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedDiffForCard = firstDiff
                    return .handled
                }
            }
            return .discarded
        }
        return .systemAction
    }

    private func toolExecutionPill(_ msg: ChatMessageItem) -> some View {
        let name = msg.toolName ?? ""
        let isExpanded = expandedToolIds.contains(msg.id)
        let matchedArtifact = matchedArtifactForTool(msg)
        let matchedDiff = (matchedArtifact == nil) ? matchedDiffForTool(msg) : nil
        let (icon, color): (String, Color) = {
            if matchedArtifact != nil {
                return ("doc.richtext.fill", .indigo)
            }
            if matchedDiff != nil {
                return ("chevron.left.forwardslash.chevron.right", .orange)
            }
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
            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let art = matchedArtifact {
                        selectedArtifactForCard = art
                        return
                    }
                    if let diff = matchedDiff {
                        selectedDiffForCard = diff
                        return
                    }
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

                        if matchedArtifact != nil {
                            HStack(spacing: 3) {
                                Text(L("查看方案"))
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        } else if matchedDiff != nil {
                            HStack(spacing: 3) {
                                Text(L("查看变更"))
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }

                        if msg.status == "CORTEX_STEP_STATUS_RUNNING" {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green.opacity(0.75))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

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

    // MARK: - 对话流内嵌「方案规划与代码修改」总类别卡片（默认折叠收缩，保持高消息密度，点击条目弹出卡片窗口）

    @ViewBuilder
    private func turnPlanAndCodeCategoryCard(turn: ChatTurnGroup, isLatestTurn: Bool) -> some View {
        let isExpanded = expandedPlanCodeTurnIds.contains(turn.id)
        let showSessionItems = isLatestTurn && (!client.artifacts.isEmpty || !client.diffs.isEmpty)
        let artifactCount = showSessionItems ? client.artifacts.count : 0
        let diffCount = showSessionItems ? client.diffs.count : turn.fileModificationTools.count
        let summaryLabel: String = {
            if artifactCount > 0 && diffCount > 0 {
                return "\(artifactCount) 份方案 · \(diffCount) 个文件"
            } else if artifactCount > 0 {
                return "\(artifactCount) 份方案"
            } else {
                return "\(diffCount) 处代码修改"
            }
        }()

        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedPlanCodeTurnIds.remove(turn.id)
                    } else {
                        expandedPlanCodeTurnIds.insert(turn.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text(L("方案规划与代码修改"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(summaryLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    if showSessionItems {
                        ForEach(client.artifacts) { art in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedArtifactForCard = art
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(art.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(artifactPreviewSnippet(art))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 6)

                                    Text(L("方案"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06), in: Capsule())

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemBackground))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(client.diffs) { diff in
                            let stats = computeDiffLineStats(diff)
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedDiffForCard = diff
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(diff.fileName)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if !diff.filePath.isEmpty {
                                            Text(diff.filePath)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 6)

                                    HStack(spacing: 5) {
                                        if stats.added > 0 {
                                            Text("+\(stats.added)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.green)
                                        }
                                        if stats.removed > 0 {
                                            Text("-\(stats.removed)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.red)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemBackground))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(turn.fileModificationTools) { item in
                            toolExecutionPill(item)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func artifactPreviewSnippet(_ art: ArtifactItem) -> String {
        guard let raw = art.content, !raw.isEmpty else {
            return art.filePath ?? L("点击以卡片窗口查看文档")
        }
        for line in raw.split(separator: "\n") {
            let clean = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && !clean.hasPrefix("---") && !clean.hasPrefix("```") {
                return clean
            }
        }
        return art.filePath ?? L("点击以卡片窗口查看文档")
    }

    private func computeDiffLineStats(_ diff: FileDiffItem) -> (added: Int, removed: Int) {
        let orig = (diff.originalContent ?? "")
        let mod = (diff.modifiedContent ?? "")
        if orig.isEmpty && mod.isEmpty { return (0, 0) }
        let origLines = orig.isEmpty ? [] : orig.components(separatedBy: "\n")
        let modLines = mod.isEmpty ? [] : mod.components(separatedBy: "\n")
        if origLines.isEmpty {
            return (modLines.count, 0)
        }
        if origLines.count + modLines.count <= 1200 {
            let diffResult = modLines.difference(from: origLines)
            var addCount = 0
            var remCount = 0
            for change in diffResult {
                switch change {
                case .insert: addCount += 1
                case .remove: remCount += 1
                }
            }
            return (addCount, remCount)
        }
        let delta = modLines.count - origLines.count
        return delta >= 0 ? (max(1, delta), 0) : (0, abs(delta))
    }

    // MARK: - 方案文档与代码变更弹窗卡片视图 (Card Sheet Windows)

    @ViewBuilder
    private func artifactCardModalView(_ artifact: ArtifactItem) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                if client.artifacts.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(client.artifacts) { item in
                                let isSelected = (item.id == artifact.id)
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedArtifactForCard = item
                                } label: {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.primary.opacity(isSelected ? 0.14 : 0.06), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let path = artifact.filePath, !path.isEmpty {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let content = artifact.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            formattedAssistantBody(msgId: "card-art-\(artifact.id)", text: content)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else {
                            Text(L("（暂无可预览的文本内容）"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let pending = client.pendingInteraction, pending.kind == "artifact_approval" {
                    Divider()
                    HStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedArtifactForCard = nil
                            Task { await client.respondToInteraction(pending, allow: true) }
                        } label: {
                            Text(L("批准方案并继续"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.blue)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground))
                }
            }
            .navigationTitle(artifact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = artifact.content ?? ""
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Text(L("复制"))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) {
                        selectedArtifactForCard = nil
                    }
                }
            }
        }
    }

    private struct DiffDisplayLine: Identifiable {
        let id: Int
        let prefix: String
        let text: String
        let kind: Int // 0 = context, 1 = added, -1 = removed
    }

    private func buildDiffDisplayLines(_ diff: FileDiffItem) -> [DiffDisplayLine] {
        let orig = diff.originalContent ?? ""
        let mod = diff.modifiedContent ?? ""
        let origLines = orig.isEmpty ? [] : orig.components(separatedBy: "\n")
        let modLines = mod.isEmpty ? [] : mod.components(separatedBy: "\n")

        if !origLines.isEmpty && origLines != modLines && (origLines.count + modLines.count <= 1200) {
            let difference = modLines.difference(from: origLines)
            var removedOffsets = Set<Int>()
            var insertedByOffset: [Int: [String]] = [:]
            for change in difference {
                switch change {
                case let .remove(offset, _, _):
                    removedOffsets.insert(offset)
                case let .insert(offset, element, _):
                    insertedByOffset[offset, default: []].append(element)
                }
            }
            var result: [DiffDisplayLine] = []
            var nextId = 0
            var modIdx = 0
            for origIdx in 0..<origLines.count {
                while let insList = insertedByOffset[modIdx] {
                    for line in insList {
                        result.append(DiffDisplayLine(id: nextId, prefix: "+", text: line, kind: 1))
                        nextId += 1
                        modIdx += 1
                    }
                }
                if removedOffsets.contains(origIdx) {
                    result.append(DiffDisplayLine(id: nextId, prefix: "-", text: origLines[origIdx], kind: -1))
                    nextId += 1
                } else {
                    result.append(DiffDisplayLine(id: nextId, prefix: " ", text: origLines[origIdx], kind: 0))
                    nextId += 1
                    modIdx += 1
                }
            }
            while modIdx < modLines.count {
                if let insList = insertedByOffset[modIdx] {
                    for line in insList {
                        result.append(DiffDisplayLine(id: nextId, prefix: "+", text: line, kind: 1))
                        nextId += 1
                        modIdx += 1
                    }
                } else {
                    result.append(DiffDisplayLine(id: nextId, prefix: "+", text: modLines[modIdx], kind: 1))
                    nextId += 1
                    modIdx += 1
                }
            }
            return Array(result.prefix(600))
        }

        return Array(modLines.prefix(600).enumerated().map { idx, line in
            DiffDisplayLine(id: idx, prefix: "\(idx + 1)", text: line, kind: 0)
        })
    }

    @ViewBuilder
    private func diffCardModalView(_ diff: FileDiffItem) -> some View {
        let stats = computeDiffLineStats(diff)
        let lines = buildDiffDisplayLines(diff)

        NavigationStack {
            VStack(spacing: 0) {
                if client.diffs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(client.diffs) { item in
                                let isSelected = (item.id == diff.id)
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedDiffForCard = item
                                } label: {
                                    Text(item.fileName)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.primary.opacity(isSelected ? 0.14 : 0.06), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider()
                }

                HStack(spacing: 8) {
                    Text(diff.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if stats.added > 0 {
                        Text("+\(stats.added)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if stats.removed > 0 {
                        Text("-\(stats.removed)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                Divider()

                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.prefix)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(
                                        line.kind == 1 ? Color.green :
                                        (line.kind == -1 ? Color.red : Color.secondary.opacity(0.6))
                                    )
                                    .frame(width: 24, alignment: .trailing)

                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(
                                        line.kind == 1 ? Color.green :
                                        (line.kind == -1 ? Color.red : Color.primary)
                                    )
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                line.kind == 1 ? Color.green.opacity(0.10) :
                                (line.kind == -1 ? Color.red.opacity(0.10) : Color.clear)
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(diff.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = diff.modifiedContent ?? ""
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Text(L("复制"))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) {
                        selectedDiffForCard = nil
                    }
                }
            }
        }
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

    // MARK: - 极简排版级远程权限确认 / 方案确认 / 多选题卡片 (无 Emoji)

    @ViewBuilder
    private func approvalCard(_ pending: PendingInteractionItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if pending.kind == "ask_question", let questions = pending.questions, !questions.isEmpty {
                ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("请选择一项以继续"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(q.question ?? "")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 8) {
                            ForEach(Array((q.options ?? []).enumerated()), id: \.element.optionId) { idx, opt in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    Task {
                                        await client.respondToInteraction(
                                            pending,
                                            allow: true,
                                            selectedOptionId: opt.id ?? opt.text
                                        )
                                    }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .leading)

                                        Text(opt.text ?? "")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(.primary)
                                            .lineSpacing(2.5)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(uiColor: .tertiarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if pending.kind == "artifact_approval" {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(pending.title ?? "方案确认"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(pending.summary ?? "请审阅实现方案后决定是否继续")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                HStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let first = client.artifacts.first {
                            selectedArtifactForCard = first
                        } else {
                            showArtifactsSheet = true
                        }
                    } label: {
                        Text(L("查看方案"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await client.respondToInteraction(pending, allow: true) }
                    } label: {
                        Text(L("批准并继续"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L(pending.title ?? "需要操作确认"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let code = pending.commandLine ?? pending.pathUri ?? pending.reason, !code.isEmpty {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                            )
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await client.respondToInteraction(pending, allow: false) }
                    } label: {
                        Text(L("拒绝"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await client.respondToInteraction(pending, allow: true) }
                    } label: {
                        Text(L("允许执行"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
        let modelParts = composerModelParts

        return VStack(alignment: .leading, spacing: 10) {
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
                                            Color(uiColor: .tertiarySystemBackground)
                                            Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(width: 56, height: 56)
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
                                        .font(.system(size: 16))
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
                            .frame(height: 56)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
            }

            // 第一行：全宽无边框多行输入框
            TextField(
                L("向电脑端 Antigravity 发送指令..."),
                text: $inputText,
                axis: .vertical
            )
            .focused($isInputFocused)
            .font(.system(size: 15.5))
            .lineLimit(1...6)
            .padding(.horizontal, 14)
            .padding(.top, (!pendingAttachments.isEmpty || isLoadingMedia) ? 2 : 14)
            .padding(.bottom, 10)

            // 第二行：左侧「+ 添加媒体/附件」+「模型切换器」+「权限模式（审核/自动/Turbo）」，整体贴近输入框底部边缘
            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())

                        if !pendingAttachments.isEmpty {
                            Text("\(pendingAttachments.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue, in: Capsule())
                                .offset(x: 5, y: -3)
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

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showModelPickerSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(modelParts.baseName)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let tier = modelParts.tier, !tier.isEmpty {
                            Text(tier)
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 权限模式选择器（审核 / 自动 / Turbo），紧挨模型选择右侧，与电脑端实时双向同步
                Menu {
                    ForEach(AgentPermissionMode.allCases) { mode in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            client.selectPermissionModeForCurrentConversation(mode)
                        } label: {
                            HStack {
                                Text("\(mode.displayTitle) — \(mode.subtitle)")
                                if client.permissionMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(client.permissionMode.displayTitle)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Button {
                    let text = inputText
                    let attachments = pendingAttachments
                    inputText = ""
                    pendingAttachments.removeAll()
                    isInputFocused = false
                    Task { await client.sendMessage(text: text, attachments: attachments) }
                } label: {
                    Image(systemName: isQueueModeActive ? "clock.fill" : "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(
                            canSend
                                ? (isQueueModeActive ? Color.orange : Color.blue)
                                : Color.primary.opacity(0.08),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
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

    // MARK: - 右上角「设置」弹窗页面 (含思考过程展示、读取文件展示、Tailscale 登录与连接配置)

    private func presentSheetFromSettings(_ action: @escaping () -> Void) {
        if showSettingsPageSheet {
            showSettingsPageSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                action()
            }
        } else {
            action()
        }
    }

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
                    presentSheetFromSettings { showMacSetupGuideSheet = true }
                }

                settingsNavButton(
                    title: tailnet.status?.isRunning == true
                        ? "内置 Tailscale 已登录 (\(tailnet.status?.selfIP ?? ""))"
                        : L("一键登录内置 Tailscale 账号"),
                    subtitle: tailnet.status?.isRunning == true
                        ? L("已接入虚拟局域网，支持 5G/异地直接穿透控制 Mac")
                        : L("首次异地控制请点击此处授权登录 Tailscale")
                ) {
                    presentSheetFromSettings { triggerDirectTailscaleLogin() }
                }

                settingsNavButton(
                    title: L("扫码一键配对连接"),
                    subtitle: L("扫描 Mac 端二维码，自动配置 Tailscale 与局域网双通道")
                ) {
                    presentSheetFromSettings { showQRScannerSheet = true }
                }

                settingsNavButton(
                    title: L("Tailscale 组网节点与设备列表"),
                    subtitle: L("查看虚拟局域网在线设备、节点状态与内置引擎控制")
                ) {
                    presentSheetFromSettings { showTailnetSheet = true }
                }

                settingsNavButton(
                    title: L("通道与连接高级设置"),
                    subtitle: L("配置访问令牌 Token、快捷切换首选 IP 与查看路由延迟")
                ) {
                    presentSheetFromSettings { showSettingsSheet = true }
                }
            } header: {
                Text("扫码配对、Tailscale 组网与连接设置")
            }

            Section {
                Button {
                    presentSheetFromSettings { showPrivacyPolicySheet = true }
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
                    presentSheetFromSettings { showOpenSourceLicensesSheet = true }
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

                LabeledContent("版本号", value: "1.0.0 (Build 18)")
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

// MARK: - 聊天滚动桥接器与探测视图 (保障切换对话零过滚 & 历史回底按钮实时浮现)
private final class ChatScrollBridge: ObservableObject {
    weak var scrollView: UIScrollView?
    var isScrollingToBottomProgrammatically: Bool = false
    private var programmaticScrollResetWorkItem: DispatchWorkItem?

    var isUserInteracting: Bool {
        guard let sv = scrollView else { return false }
        return sv.isTracking || sv.isDragging || sv.isDecelerating
    }

    func beginProgrammaticScrollToBottom(duration: TimeInterval) {
        isScrollingToBottomProgrammatically = true
        programmaticScrollResetWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.isScrollingToBottomProgrammatically = false
        }
        programmaticScrollResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func cancelProgrammaticScroll() {
        isScrollingToBottomProgrammatically = false
        programmaticScrollResetWorkItem?.cancel()
        programmaticScrollResetWorkItem = nil
    }

    func resetToTop() {
        guard let sv = scrollView else { return }
        let minOffsetY = -sv.adjustedContentInset.top
        if abs(sv.contentOffset.y - minOffsetY) > 0.5 {
            sv.setContentOffset(CGPoint(x: 0, y: minOffsetY), animated: false)
        }
    }

    func scrollToBottom(animated: Bool) {
        guard let sv = scrollView else { return }
        sv.layoutIfNeeded()
        guard sv.bounds.height > 0 else { return }
        let minOffsetY = -sv.adjustedContentInset.top
        let maxOffsetY = max(minOffsetY, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
        if abs(sv.contentOffset.y - maxOffsetY) > 0.5 {
            sv.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: animated)
        }
    }

    func clampOverscrollAndSnapToBottom() {
        guard let sv = scrollView, !isUserInteracting else { return }
        sv.layoutIfNeeded()
        guard sv.bounds.height > 0 else { return }
        let minOffsetY = -sv.adjustedContentInset.top
        let maxOffsetY = max(minOffsetY, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
        if abs(sv.contentOffset.y - maxOffsetY) > 0.5 {
            sv.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
            sv.layoutIfNeeded()
            let updatedMaxY = max(minOffsetY, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
            if abs(sv.contentOffset.y - updatedMaxY) > 0.5 {
                sv.setContentOffset(CGPoint(x: 0, y: updatedMaxY), animated: false)
            }
        }
    }
}

private final class ScrollProbeUIView: UIView {
    var onAttachCheck: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachCheck?(self)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        onAttachCheck?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onAttachCheck?(self)
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

    @ViewBuilder
    func trackChatScrollAtBottom(_ isAtBottom: Binding<Bool>, bridge: ChatScrollBridge) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                let visibleHeight = geo.containerSize.height - geo.contentInsets.top - geo.contentInsets.bottom
                guard visibleHeight > 0, geo.contentSize.height > visibleHeight else { return true }
                let distanceFromBottom = geo.contentSize.height - (geo.contentOffset.y + geo.containerSize.height - geo.contentInsets.bottom)
                return distanceFromBottom <= 50
            } action: { _, newValue in
                if bridge.isScrollingToBottomProgrammatically && !bridge.isUserInteracting {
                    if !isAtBottom.wrappedValue {
                        isAtBottom.wrappedValue = true
                    }
                    return
                }
                if isAtBottom.wrappedValue != newValue {
                    isAtBottom.wrappedValue = newValue
                }
            }
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
