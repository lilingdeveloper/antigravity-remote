//
//  AntigravityClient.swift
//  AntigravityRemote
//
//  丝滑级远程控制通信引擎:
//  1. 多路并发竞速路由 (Happy Eyeballs):
//     - 同时探测「系统级 Tailscale 直连」、「局域网 LAN 极速直连」与「内置 TailnetKit 穿透转发」，谁最快用谁，并缓存最优路由 (0ms 开销复用)。
//     - 当网络切换 (Wi-Fi <-> 5G) 或请求失败时，毫秒级无感切换到可用通道。
//  2. 双擎实时同步 (原生 SSE 实时流 + 自适应高频轮询):
//     - 通过 URLSession.bytes 订阅 Mac 端 /api/v1/events，思考流、工具调用、新增对话毫秒级推送；
//     - 配合无缓存轮询兜底，实时测量往返延迟 (latencyMs)。
//  3. 零闪烁乐观消息合并 (Flicker-Free Diffing):
//     - 发送消息后保持乐观气泡直至服务端落盘，且仅在数据真正变化时触发 @Published 刷新。
//

import Foundation
import Combine
import UIKit
import Network
import Darwin
import UserNotifications

public enum RouteChannelKind: String {
    case systemTailscale = "Tailscale 直连"
    case embeddedTailnet = "内置 Tailscale 穿透"
    case lanDirect = "局域网极速直连"
    case customTunnel = "公网隧道直连"
    case probing = "正在智能选路..."
}

public enum AgentPermissionMode: String, CaseIterable, Identifiable {
    case review = "review"
    case auto = "auto"
    case turbo = "turbo"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .review: return "审核"
        case .auto: return "自动"
        case .turbo: return "Turbo"
        }
    }

    public var subtitle: String {
        switch self {
        case .review: return "每次执行命令与敏感操作前均需手动确认"
        case .auto: return "常规安全命令自动运行，高风险操作需确认"
        case .turbo: return "全速自动执行所有命令与权限操作"
        }
    }
}

public struct PendingMediaAttachment: Identifiable, Equatable {
    public let id: String
    public let mimeType: String
    public let fileName: String
    public let base64Data: String
    public let thumbnailImage: UIImage?
    public let isVideo: Bool

    public init(
        id: String = UUID().uuidString,
        mimeType: String,
        fileName: String,
        base64Data: String,
        thumbnailImage: UIImage?,
        isVideo: Bool
    ) {
        self.id = id
        self.mimeType = mimeType
        self.fileName = fileName
        self.base64Data = base64Data
        self.thumbnailImage = thumbnailImage
        self.isVideo = isVideo
    }

    public static func == (lhs: PendingMediaAttachment, rhs: PendingMediaAttachment) -> Bool {
        lhs.id == rhs.id && lhs.fileName == rhs.fileName && lhs.mimeType == rhs.mimeType
    }
}

@MainActor
public final class AntigravityClient: ObservableObject {

    @Published public var serverHost: String =
        UserDefaults.standard.string(forKey: "agy.serverHost") ?? ""
    @Published public var fallbackLanHost: String =
        UserDefaults.standard.string(forKey: "agy.fallbackLanHost") ?? ""
    @Published public var serverPort: Int = {
        let p = UserDefaults.standard.integer(forKey: "agy.serverPort")
        return p > 0 ? p : 8789
    }()
    @Published public var accessToken: String =
        UserDefaults.standard.string(forKey: "agy.accessToken") ?? ""
    @Published public var shouldPromptEmbeddedTailscaleLogin: Bool = false

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isReconnecting: Bool = false
    @Published public private(set) var hasEverConnectedMac: Bool =
        UserDefaults.standard.bool(forKey: "agy.hasEverConnectedMac")
    @Published public private(set) var routeKind: RouteChannelKind = .probing
    @Published public private(set) var connectionRouteDescription: String = "正在智能选路..."
    @Published public private(set) var latencyMs: Int?
    @Published public private(set) var lastError: String?

    @Published public private(set) var daemonStatus: DaemonStatusResponse?
    @Published public private(set) var models: [AIModelItem] = []
    @Published public var selectedModelId: String = ""
    /// 当前对话在电脑端实际正在使用的模型 ID (如 MODEL_PLACEHOLDER_M418)
    @Published public private(set) var activeConversationModelId: String = ""

    @Published public private(set) var projects: [ProjectGroup] = []
    @Published public private(set) var conversations: [ConversationSummary] = []
    @Published public var currentCascadeId: String =
        UserDefaults.standard.string(forKey: "agy.currentCascadeId") ?? ""
    @Published public var currentWorkspaceUri: String =
        UserDefaults.standard.string(forKey: "agy.currentWorkspaceUri") ?? ""

    /// 自动跟随电脑端新建/新活跃的对话 (默认开启)
    @Published public var autoFollowMacConversation: Bool = {
        if UserDefaults.standard.object(forKey: "agy.autoFollowMac") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.autoFollowMac")
    }() {
        didSet { UserDefaults.standard.set(autoFollowMacConversation, forKey: "agy.autoFollowMac") }
    }

    /// 是否在对话流中显示 AI 思考过程 (默认开启)
    @Published public var showThinkingProcess: Bool = {
        if UserDefaults.standard.object(forKey: "agy.showThinkingProcess") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.showThinkingProcess")
    }() {
        didSet { UserDefaults.standard.set(showThinkingProcess, forKey: "agy.showThinkingProcess") }
    }

    /// 是否默认自动展开 AI 思考过程 (默认关闭，仅显示折叠摘要)
    @Published public var autoExpandThinking: Bool = {
        if UserDefaults.standard.object(forKey: "agy.autoExpandThinking") == nil { return false }
        return UserDefaults.standard.bool(forKey: "agy.autoExpandThinking")
    }() {
        didSet { UserDefaults.standard.set(autoExpandThinking, forKey: "agy.autoExpandThinking") }
    }

    /// 是否在对话流中显示「读取文件 (read_file)」工具调用记录 (默认开启)
    @Published public var showFileReadTools: Bool = {
        if UserDefaults.standard.object(forKey: "agy.showFileReadTools") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.showFileReadTools")
    }() {
        didSet { UserDefaults.standard.set(showFileReadTools, forKey: "agy.showFileReadTools") }
    }

    /// 是否在对话流中显示其他工具调用记录 (如终端命令、修改文件等，默认开启)
    @Published public var showOtherToolCalls: Bool = {
        if UserDefaults.standard.object(forKey: "agy.showOtherToolCalls") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.showOtherToolCalls")
    }() {
        didSet { UserDefaults.standard.set(showOtherToolCalls, forKey: "agy.showOtherToolCalls") }
    }

    /// 是否在顶部标题栏下方显示当前对话上下文容量进度条 (默认开启)
    @Published public var showContextUsageBar: Bool = {
        if UserDefaults.standard.object(forKey: "agy.showContextUsageBar") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.showContextUsageBar")
    }() {
        didSet { UserDefaults.standard.set(showContextUsageBar, forKey: "agy.showContextUsageBar") }
    }

    /// 当 AI 正在思考/回复时，新发送的多条消息是否自动排队依次执行（默认开启，避免相互重叠打断）
    @Published public var queueMessagesWhenBusy: Bool = {
        if UserDefaults.standard.object(forKey: "agy.queueMessagesWhenBusy") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.queueMessagesWhenBusy")
    }() {
        didSet { UserDefaults.standard.set(queueMessagesWhenBusy, forKey: "agy.queueMessagesWhenBusy") }
    }

    /// 后台任务完成与待审批远程本地通知 (默认开启)
    @Published public var enableNotifications: Bool = {
        if UserDefaults.standard.object(forKey: "agy.enableNotifications") == nil { return true }
        return UserDefaults.standard.bool(forKey: "agy.enableNotifications")
    }() {
        didSet { UserDefaults.standard.set(enableNotifications, forKey: "agy.enableNotifications") }
    }

    /// 权限执行模式（审核 / 自动 / Turbo，默认与电脑端一致为 Turbo）
    @Published public var permissionMode: AgentPermissionMode = {
        let raw = UserDefaults.standard.string(forKey: "agy.permissionMode_v2") ?? "turbo"
        return AgentPermissionMode(rawValue: raw) ?? .turbo
    }() {
        didSet {
            UserDefaults.standard.set(permissionMode.rawValue, forKey: "agy.permissionMode_v2")
            if permissionMode == .turbo,
               let pending = pendingInteraction,
               pending.kind != "ask_question" && pending.kind != "artifact_approval" {
                Task { await respondToInteraction(pending, allow: true) }
            }
        }
    }

    @Published public private(set) var messages: [ChatMessageItem] = []
    @Published public private(set) var queuedMessages: [QueuedMessageItem] = []
    @Published public private(set) var isGenerating: Bool = false
    @Published public private(set) var pendingInteraction: PendingInteractionItem?
    @Published public private(set) var diffs: [FileDiffItem] = []
    @Published public private(set) var artifacts: [ArtifactItem] = []
    @Published public private(set) var contextUsage: ContextUsageInfo?

    /// 交互式演示模式（供 App Store 审核与营销截图使用，离线体验全部功能）
    @Published public var isDemoMode: Bool = false
    @Published public var activeMarketingScene: String? = nil

    /// 已展开的思考过程步骤 ID 集合（保持展开态，防止流式刷新折叠）
    @Published public var expandedThinkingIds: Set<String> = []

    private var conversationContextUsageCache: [String: ContextUsageInfo] = [:]
    private var conversationActiveModelCache: [String: String] = [:]
    private var userManualModelOverrideByCascadeId: [String: String] = [:]
    private var conversationActivePermissionCache: [String: AgentPermissionMode] = [:]
    private var userManualPermissionOverrideByCascadeId: [String: AgentPermissionMode] = [:]
    private var conversationDiffsCache: [String: [FileDiffItem]] = [:]
    private var conversationArtifactsCache: [String: [ArtifactItem]] = [:]
    private var pollTask: Task<Void, Never>?
    private var sseTask: Task<Void, Never>?
    private var sseConnectedCascadeId: String = ""

    private var cachedBaseURL: URL?
    private var lastRouteVerifiedAt: Date?
    private var sseConnectedBaseURL: URL?

    // ETag 增量传输与 304 零拷贝缓存
    private enum HTTPNotModifiedSignal: Error { case notModified }
    private var etagByPath: [String: String] = [:]

    // SSE 运行态追踪与自适应轮询计数
    private var isSSEActive: Bool = false
    private var pollTickCount: Int = 0

    // 局域网 Bonjour 自动发现
    private var bonjourBrowser: NWBrowser?

    // 通知与后台任务宽限
    private var lastNotifiedInteractionStepIndex: Int?
    private var wasGenerating: Bool = false
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var saveSnapshotTask: Task<Void, Never>?

    // 网络接口与链路动态监控
    private let netPathMonitor = NWPathMonitor()
    private let netMonitorQueue = DispatchQueue(label: "app.antigravity.client.netpath", qos: .utility)
    private var lastNetworkSignature: String = ""
    private var isNetMonitorRunning = false
    private var networkSwitchTask: Task<Void, Never>?
    private var lastLanUpgradeProbeAt: Date?
    private var lanFailureStartedAt: Date?
    private var consecutiveLanFailures: Int = 0
    private let lanStickinessGraceSeconds: TimeInterval = 10.0
    private let lanMinFailuresBeforeFallback: Int = 3
    private var activeProbeTask: Task<URL?, Never>?
    private var foregroundRecoveryTask: Task<Void, Never>?
    private var lastForegroundTriggerAt: Date?
    private var didBecomeActiveObserver: NSObjectProtocol?

    private var pendingOptimisticMessages: [ChatMessageItem] = []
    private var lastMessageSentAt: Date?
    private var optimisticBaselineStepIndex: Int = -1
    private var conversationMessagesCache: [String: [ChatMessageItem]] = [:]
    private var lastPendingStepIndex: Int?
    private var knownConversationIds: Set<String> = []
    private var lastSyncedStepCount: Int = -1

    private var fastSession: URLSession = AntigravityClient.makeFastSession()
    private var lastSessionRebuildAt: Date?

    private static func makeFastSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    private func rebuildFastSession(force: Bool = false) {
        if !force, let last = lastSessionRebuildAt, Date().timeIntervalSince(last) < 3.0 {
            return
        }
        lastSessionRebuildAt = Date()
        let oldSession = fastSession
        fastSession = Self.makeFastSession()
        oldSession.finishTasksAndInvalidate()
    }

    // MARK: - 0ms 本地离线快照持久化 (秒开首屏)

    private struct OfflineSnapshot: Codable {
        let projects: [ProjectGroup]
        let conversations: [ConversationSummary]
        let messagesByCascadeId: [String: [ChatMessageItem]]
        let contextUsageByCascadeId: [String: ContextUsageInfo]
        let activeModelByCascadeId: [String: String]
        let lastCascadeId: String
        let models: [AIModelItem]?
    }

    private static var offlineSnapshotURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("AntigravityRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("offline_snapshot_v1.json")
    }

    private func loadOfflineSnapshot() {
        guard !isDemoMode else { return }
        let url = Self.offlineSnapshotURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(OfflineSnapshot.self, from: data) else {
            return
        }
        if self.projects.isEmpty { self.projects = snap.projects }
        if self.conversations.isEmpty { self.conversations = snap.conversations }
        if self.models.isEmpty, let cachedModels = snap.models, !cachedModels.isEmpty {
            self.models = cachedModels
        }
        for (k, v) in snap.messagesByCascadeId {
            if self.conversationMessagesCache[k] == nil {
                self.conversationMessagesCache[k] = v
            }
        }
        for (k, v) in snap.contextUsageByCascadeId {
            if self.conversationContextUsageCache[k] == nil {
                self.conversationContextUsageCache[k] = v
            }
        }
        for (k, v) in snap.activeModelByCascadeId {
            if self.conversationActiveModelCache[k] == nil {
                self.conversationActiveModelCache[k] = v
            }
        }
        if self.currentCascadeId.isEmpty && !snap.lastCascadeId.isEmpty {
            self.currentCascadeId = snap.lastCascadeId
        }
        if !self.currentCascadeId.isEmpty && self.messages.isEmpty {
            self.messages = self.conversationMessagesCache[self.currentCascadeId] ?? []
            self.contextUsage = self.conversationContextUsageCache[self.currentCascadeId]
            if let cachedModel = self.conversationActiveModelCache[self.currentCascadeId] {
                self.activeConversationModelId = cachedModel
                if self.selectedModelId.isEmpty { self.selectedModelId = cachedModel }
            }
        }
    }

    private func scheduleSaveOfflineSnapshot() {
        guard !isDemoMode else { return }
        saveSnapshotTask?.cancel()
        saveSnapshotTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.saveOfflineSnapshotNow()
        }
    }

    private func saveOfflineSnapshotNow() {
        guard !isDemoMode else { return }
        let recentIds = Array(conversations.prefix(5).map(\.id))
        var recentMessages: [String: [ChatMessageItem]] = [:]
        var recentContext: [String: ContextUsageInfo] = [:]
        for id in recentIds {
            if let msgs = conversationMessagesCache[id] {
                recentMessages[id] = msgs
            }
            if let cu = conversationContextUsageCache[id] {
                recentContext[id] = cu
            }
        }
        if !currentCascadeId.isEmpty {
            recentMessages[currentCascadeId] = messages
            if let cu = contextUsage { recentContext[currentCascadeId] = cu }
        }

        let snap = OfflineSnapshot(
            projects: self.projects,
            conversations: self.conversations,
            messagesByCascadeId: recentMessages,
            contextUsageByCascadeId: recentContext,
            activeModelByCascadeId: self.conversationActiveModelCache,
            lastCascadeId: self.currentCascadeId,
            models: self.models
        )

        let targetURL = Self.offlineSnapshotURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snap) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    // MARK: - 局域网 Bonjour / mDNS 自动发现 (_agyremote._tcp)

    private func startBonjourBrowser() {
        guard bonjourBrowser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_agyremote._tcp", domain: "local."), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBonjourResults(results)
            }
        }
        browser.start(queue: DispatchQueue(label: "app.antigravity.bonjour", qos: .utility))
        bonjourBrowser = browser
    }

    private func restartBonjourBrowser() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        startBonjourBrowser()
    }

    private func handleBonjourResults(_ results: Set<NWBrowser.Result>) {
        guard !isDemoMode else { return }
        for res in results {
            guard case .service(_, _, _, _) = res.endpoint else { continue }
            let conn = NWConnection(to: res.endpoint, using: .tcp)
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn else { return }
                if case .ready = state {
                    if case .hostPort(let host, let port) = conn.currentPath?.remoteEndpoint {
                        conn.cancel()
                        let hostStr: String
                        switch host {
                        case .ipv4(let ip):
                            hostStr = "\(ip)"
                        default:
                            hostStr = ""
                        }
                        if !hostStr.isEmpty && !hostStr.hasPrefix("127.") {
                            Task { @MainActor in
                                await self.evaluateBonjourDiscoveredHost(hostStr, port: Int(port.rawValue))
                            }
                        }
                    }
                }
            }
            conn.start(queue: DispatchQueue(label: "app.antigravity.bonjour.resolve", qos: .utility))
        }
    }

    private func evaluateBonjourDiscoveredHost(_ ip: String, port: Int) async {
        guard !ip.isEmpty, !isDemoMode else { return }
        if fallbackLanHost.isEmpty || (!isConnected && fallbackLanHost != ip) || routeKind != .lanDirect {
            guard let pingURL = URL(string: "http://\(ip):\(port)/api/v1/ping") else { return }
            var req = URLRequest(url: pingURL)
            req.timeoutInterval = 1.2
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            if let (data, resp) = try? await fastSession.data(for: req),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (json["ok"] as? Bool) == true {
                print("[AntigravityClient] Bonjour 自动发现局域网 Mac: \(ip):\(port)")
                self.fallbackLanHost = ip
                UserDefaults.standard.set(ip, forKey: "agy.fallbackLanHost")
                if !self.isConnected || self.routeKind != .lanDirect {
                    await self.reprobeAndSwitchRouteIfNeeded(force: true)
                }
            }
        }
    }

    // MARK: - 本地通知与后台保活

    private func setupNotifications() {
        guard enableNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendLocalNotification(title: String, body: String, identifier: String) {
        guard enableNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func stopPollingAndSseTasks() {
        foregroundRecoveryTask?.cancel()
        foregroundRecoveryTask = nil
        networkSwitchTask?.cancel()
        networkSwitchTask = nil
        activeProbeTask?.cancel()
        activeProbeTask = nil
        pollTask?.cancel()
        pollTask = nil
        sseTask?.cancel()
        sseTask = nil
        sseConnectedCascadeId = ""
        sseConnectedBaseURL = nil
        isSSEActive = false
    }

    private func endCurrentBackgroundTask() {
        if bgTaskID != .invalid {
            let tid = bgTaskID
            bgTaskID = .invalid
            UIApplication.shared.endBackgroundTask(tid)
        }
        stopPollingAndSseTasks()
    }

    nonisolated private static func localInterfaceSnapshot() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "none" }
        defer { freeifaddrs(first) }

        var parts: [String] = []
        var cursor = first
        while true {
            let interface = cursor.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("utun") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: host)
                        parts.append("\(name):\(ip)")
                    }
                }
            }
            guard let next = interface.ifa_next else { break }
            cursor = next
        }
        return parts.sorted().joined(separator: "|")
    }

    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    public init() {
        setupNotifications()
        loadOfflineSnapshot()
        startNetworkPathMonitor()
        startBonjourBrowser()
        startPollingLoop()

        // 检测 App Store 自动化测试与营销截图启动参数
        let args = ProcessInfo.processInfo.arguments
        var initialScene: String? = nil
        if let idx = args.firstIndex(of: "-AGYMarketingScene"), idx + 1 < args.count {
            initialScene = args[idx + 1]
        }
        if args.contains("-AGYDemoMode") || initialScene != nil {
            enterDemoMode(scene: initialScene)
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillEnterForeground()
            }
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidBecomeActive()
            }
        }
    }

    private func startNetworkPathMonitor() {
        guard !isNetMonitorRunning else { return }
        isNetMonitorRunning = true
        netPathMonitor.pathUpdateHandler = { [weak self] path in
            let sig = Self.localInterfaceSnapshot() + "|\(path.status == .satisfied ? "up" : "down")"
            Task { @MainActor in
                self?.handleNetworkEnvironmentChanged(newSignature: sig, reason: "网络链路变更 (\(path.status == .satisfied ? "在线" : "离线"))")
            }
        }
        netPathMonitor.start(queue: netMonitorQueue)
    }

    private func handleNetworkEnvironmentChanged(newSignature: String, reason: String) {
        guard !isDemoMode else { return }
        if lastNetworkSignature.isEmpty {
            lastNetworkSignature = newSignature
            return
        }
        guard lastNetworkSignature != newSignature else { return }
        lastNetworkSignature = newSignature

        // 若前台恢复任务正在运行，交由前台恢复统一协调，避免互相取消请求
        if foregroundRecoveryTask != nil { return }

        TailnetManager.shared.wake(reason: "网络环境切换: \(reason)", resetLocalForwards: false)

        // 网络环境突变时 (Wi-Fi <-> 5G / VPN)，优先检查局域网是否可达，不主动中断正在正常工作的局域网连接
        networkSwitchTask?.cancel()
        networkSwitchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let checkpointsMs = [200, 900]
            for delayMs in checkpointsMs {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }
                if !self.isConnected || self.routeKind != .lanDirect {
                    await self.reprobeAndSwitchRouteIfNeeded(force: true)
                } else {
                    await self.probeLanUpgradeIfNeeded()
                }
            }
        }
    }

    private func reprobeAndSwitchRouteIfNeeded(force: Bool) async {
        let previousBase = cachedBaseURL
        guard let newBase = try? await resolveBestBaseURL(forceProbe: force) else {
            return
        }
        if previousBase != newBase || !isConnected {
            reconnectSSEIfActive()
            await fetchStatus()
        }
    }

    private func reconnectSSEIfActive() {
        guard !currentCascadeId.isEmpty, !isDemoMode else { return }
        let cid = currentCascadeId
        isSSEActive = false
        sseTask?.cancel()
        sseTask = nil
        sseConnectedCascadeId = ""
        sseConnectedBaseURL = nil
        ensureSSESubscription(cascadeId: cid)
    }

    private func handleDidEnterBackground() {
        if isGenerating {
            // 申请最多 28 秒后台宽限执行时间，确保收到 AI 回复完成或待审批本地通知
            bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "AGYGeneratingGrace") { [weak self] in
                Task { @MainActor in
                    self?.endCurrentBackgroundTask()
                }
            }
        } else {
            endCurrentBackgroundTask()
        }
    }

    private func handleWillEnterForeground() {
        triggerForegroundRecovery(reason: "willEnterForeground")
    }

    private func handleDidBecomeActive() {
        // 首次启动时 pollTask 已在 init 中启动；仅在从后台切回或轮询已停止/未连接时触发恢复
        if pollTask == nil || !isConnected || isReconnecting {
            triggerForegroundRecovery(reason: "didBecomeActive")
        }
    }

    private func triggerForegroundRecovery(reason: String) {
        guard !isDemoMode else { return }
        if let last = lastForegroundTriggerAt, Date().timeIntervalSince(last) < 0.8 {
            return
        }
        lastForegroundTriggerAt = Date()

        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        // 1. 先停止所有残留旧任务，彻底消除并发取消死锁
        stopPollingAndSseTasks()
        recordLanSuccess()
        etagByPath.removeAll()
        lastNetworkSignature = Self.localInterfaceSnapshot() + "|\(netPathMonitor.currentPath.status == .satisfied ? "up" : "down")"

        // 2. 重建干净的 URLSession，重启 Bonjour 与唤醒 Tailnet 转发
        rebuildFastSession(force: true)
        restartBonjourBrowser()
        TailnetManager.shared.wake(reason: "App 回到前台 (\(reason))", resetLocalForwards: true)

        // 3. 串行渐进式前台重连（兼容 iOS 从后台唤醒 Wi-Fi 套接字的 0~1.5s 恢复窗口）
        foregroundRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.foregroundRecoveryTask = nil }

            guard self.hasConfiguredHost else {
                self.startPollingLoop(skipInitialRefresh: false)
                return
            }

            let backoffDelaysMs = [0, 250, 600, 1200, 2200]
            for delayMs in backoffDelaysMs {
                if delayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                }
                guard !Task.isCancelled else { return }

                // 强制优先探测局域网（若局域网可达直接锁定局域网）
                _ = try? await self.resolveBestBaseURL(forceProbe: true)
                await self.fetchStatus()
                if self.isConnected {
                    break
                }
            }

            guard !Task.isCancelled else { return }
            if self.isConnected {
                await self.fetchModels()
                await self.fetchConversations()
                if !self.currentCascadeId.isEmpty {
                    await self.fetchConversationDetail(cascadeId: self.currentCascadeId)
                    await self.fetchDiffsAndArtifacts(cascadeId: self.currentCascadeId)
                    self.ensureSSESubscription(cascadeId: self.currentCascadeId)
                }
            }
            self.startPollingLoop(skipInitialRefresh: true)
        }
    }

    public func saveConnectionConfig() {
        let h1 = serverHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let h2 = fallbackLanHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["0.0.0.0", "0000", "demo", "test"].contains(h1) || ["0.0.0.0", "0000", "demo", "test"].contains(h2) {
            enterDemoMode()
            return
        }
        UserDefaults.standard.set(serverHost.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "agy.serverHost")
        UserDefaults.standard.set(fallbackLanHost.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "agy.fallbackLanHost")
        UserDefaults.standard.set(serverPort, forKey: "agy.serverPort")
        UserDefaults.standard.set(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "agy.accessToken")
        invalidateRouteCache()
        rebuildFastSession()
        reconnectSSEIfActive()
        Task { await reprobeAndSwitchRouteIfNeeded(force: true) }
    }

    public func invalidateRouteCache() {
        cachedBaseURL = nil
        lastRouteVerifiedAt = nil
        etagByPath.removeAll()
    }

    /// 扫码一键配对解析器
    @discardableResult
    public func applyPairingCode(_ rawCode: String) -> String {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "二维码内容为空" }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 0. 若直接扫描的是纯 Tailscale AuthKey (tskey-auth-...)
        if trimmed.lowercased().hasPrefix("tskey-") {
            TailnetManager.shared.restart(authKey: trimmed)
            invalidateRouteCache()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await refreshAll()
            }
            return "已将 AuthKey 注入内置 Tailscale 引擎，正在自动组网连接 Mac..."
        }

        // 1. 解析 URL 格式 (agyremote://pair?... 或 http://...)
        if let components = URLComponents(string: trimmed) {
            let items = components.queryItems ?? []
            func q(_ name: String) -> String? {
                items.first(where: { $0.name.lowercased() == name.lowercased() })?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let tsHost = q("ts") ?? q("tailscale")
            let lanHost = q("lan")
            let explicitHost = q("host") ?? components.host
            let portVal = Int(q("port") ?? "") ?? components.port ?? 8789
            let tokenVal = q("token")
            let authKeyVal = q("authkey") ?? q("tsauthkey")

            if let authKeyVal, !authKeyVal.isEmpty {
                TailnetManager.shared.restart(authKey: authKeyVal)
            }

            if let lanHost, !lanHost.isEmpty {
                fallbackLanHost = lanHost
            }

            if let tsHost, !tsHost.isEmpty {
                serverHost = tsHost
            } else if let lanHost, !lanHost.isEmpty {
                serverHost = lanHost
            } else if let explicitHost, !explicitHost.isEmpty, explicitHost != "pair" {
                serverHost = explicitHost
            }

            serverPort = portVal
            if let tokenVal, !tokenVal.isEmpty {
                accessToken = tokenVal
            }

            saveConnectionConfig()

            if TailnetManager.isTailnetHost(serverHost),
               !TailnetManager.shared.systemTailscaleActive,
               TailnetManager.shared.status?.isRunning != true,
               (authKeyVal ?? "").isEmpty {
                shouldPromptEmbeddedTailscaleLogin = true
            }

            Task { await refreshAll() }
            return "已配对 Mac (\(serverHost):\(serverPort))"
        }

        // 2. 纯 IP:Port 兜底
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let p = Int(parts[1]) {
            serverHost = String(parts[0])
            serverPort = p
            saveConnectionConfig()
            Task { await refreshAll() }
            return "已配对 Mac (\(serverHost):\(serverPort))"
        }

        serverHost = trimmed
        saveConnectionConfig()
        Task { await refreshAll() }
        return "已更新地址: \(serverHost)"
    }

    // MARK: - 多路并发智能选路 (Happy Eyeballs) + 0ms 路由缓存

    private enum CandidateType {
        case direct(url: URL, kind: RouteChannelKind, desc: String)
        case embeddedTailscale(host: String, port: Int, desc: String)

        var isLan: Bool {
            if case .direct(_, let kind, _) = self {
                return kind == .lanDirect
            }
            return false
        }
    }

    private enum ProbeOutcome {
        case success(CandidateProbeResult)
        case failure(isLan: Bool)
        case graceTimeout
    }

    private struct CandidateProbeResult {
        let baseURL: URL
        let kind: RouteChannelKind
        let description: String
        let rttMs: Int
    }

    private func recordLanSuccess() {
        lanFailureStartedAt = nil
        consecutiveLanFailures = 0
    }

    /// 局域网黏性保持策略：已在局域网连接时，除非局域网连续失败 >= 3 次且持续时间 >= 10 秒，否则绝不切换到 Tailscale
    private func shouldStayStickyOnLanAfterFailure() -> Bool {
        let now = Date()
        if lanFailureStartedAt == nil {
            lanFailureStartedAt = now
        }
        consecutiveLanFailures += 1
        let elapsed = now.timeIntervalSince(lanFailureStartedAt ?? now)
        return elapsed < lanStickinessGraceSeconds || consecutiveLanFailures < lanMinFailuresBeforeFallback
    }

    private func collectCandidates() -> [CandidateType] {
        let port = serverPort
        var lanHosts: [String] = []
        var tailscaleHosts: [String] = []
        let cleanServer = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLan = fallbackLanHost.trimmingCharacters(in: .whitespacesAndNewlines)

        for host in [cleanLan, cleanServer] where !host.isEmpty {
            if TailnetManager.isTailnetHost(host) {
                if !tailscaleHosts.contains(host) { tailscaleHosts.append(host) }
            } else {
                if !lanHosts.contains(host) { lanHosts.append(host) }
            }
        }

        var candidates: [CandidateType] = []

        // 1. 局域网候选始终排在最前
        for host in lanHosts {
            if let u = URL(string: "http://\(host):\(port)") {
                candidates.append(.direct(url: u, kind: .lanDirect, desc: "局域网极速 (\(host))"))
            }
        }

        // 2. Tailscale 候选作为后备
        for host in tailscaleHosts {
            if TailnetManager.shared.systemTailscaleActive {
                if let u = URL(string: "http://\(host):\(port)") {
                    candidates.append(.direct(url: u, kind: .systemTailscale, desc: "Tailscale 直连 (\(host))"))
                }
            } else {
                if TailnetManager.shared.isEnabled {
                    candidates.append(.embeddedTailscale(host: host, port: port, desc: "内置 Tailscale (\(host))"))
                }
                if let u = URL(string: "http://\(host):\(port)") {
                    candidates.append(.direct(url: u, kind: .systemTailscale, desc: "Tailscale 直连 (\(host))"))
                }
            }
        }

        return candidates
    }

    private func resolveBestBaseURL(forceProbe: Bool = false) async throws -> URL {
        // 1. 命中有效缓存时直接 0ms 返回（避免重复探测开销）
        if !forceProbe, let cached = cachedBaseURL {
            return cached
        }

        let cleanHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.hasPrefix("http://") || cleanHost.hasPrefix("https://"),
           let directURL = URL(string: cleanHost) {
            routeKind = .customTunnel
            connectionRouteDescription = "公网隧道 (\(directURL.host ?? cleanHost))"
            cachedBaseURL = directURL
            lastRouteVerifiedAt = Date()
            return directURL
        }

        // 2. 合并并发选路探测，避免多个并发请求同时发起重复探测
        if let existingProbe = activeProbeTask {
            if let url = await existingProbe.value {
                return url
            }
        }

        let probeTask = Task<URL?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            let candidates = self.collectCandidates()
            let lanCandidates = candidates.filter { $0.isLan }
            let otherCandidates = candidates.filter { !$0.isLan }

            // 阶段 A：局域网绝对优先 —— 只要配置了局域网地址，先单独探测局域网，局域网通畅时绝不触碰 Tailscale
            if !lanCandidates.isEmpty {
                if let lanWinner = await self.raceCandidates(lanCandidates) {
                    let previousBase = self.cachedBaseURL
                    self.recordLanSuccess()
                    self.cachedBaseURL = lanWinner.baseURL
                    self.lastRouteVerifiedAt = Date()
                    self.routeKind = .lanDirect
                    self.latencyMs = lanWinner.rttMs
                    self.connectionRouteDescription = "\(lanWinner.description) · \(lanWinner.rttMs)ms"
                    if previousBase != nil && previousBase != lanWinner.baseURL {
                        self.reconnectSSEIfActive()
                    }
                    return lanWinner.baseURL
                }

                // 若当前已处于局域网模式，且局域网仅短暂抖动（未满 10 秒持续故障），保持锁定在局域网，不切换到 Tailscale
                if self.routeKind == .lanDirect,
                   self.shouldStayStickyOnLanAfterFailure(),
                   case .direct(let lanURL, _, _) = lanCandidates[0] {
                    self.cachedBaseURL = lanURL
                    return lanURL
                }
            }

            // 阶段 B：仅当局域网不可用（或局域网持续故障超过 10 秒）时，才探测 Tailscale 后备通道
            if !otherCandidates.isEmpty, let tsWinner = await self.raceCandidates(otherCandidates) {
                let previousBase = self.cachedBaseURL
                self.cachedBaseURL = tsWinner.baseURL
                self.lastRouteVerifiedAt = Date()
                self.routeKind = tsWinner.kind
                self.latencyMs = tsWinner.rttMs
                self.connectionRouteDescription = "\(tsWinner.description) · \(tsWinner.rttMs)ms"
                if previousBase != nil && previousBase != tsWinner.baseURL {
                    self.reconnectSSEIfActive()
                }
                return tsWinner.baseURL
            }

            // 探测全部失败：若之前在局域网则优先保留局域网地址供后续重试
            self.cachedBaseURL = nil
            self.lastRouteVerifiedAt = nil

            let port = self.serverPort
            if let firstCandidate = candidates.first {
                switch firstCandidate {
                case .direct(let url, let kind, let desc):
                    self.routeKind = kind
                    self.connectionRouteDescription = "\(desc) (未联通)"
                    return url
                case .embeddedTailscale(let host, _, let desc):
                    self.routeKind = .embeddedTailnet
                    self.connectionRouteDescription = "\(desc) (未联通)"
                    if let u = URL(string: "http://\(host):\(port)") { return u }
                }
            }

            guard !cleanHost.isEmpty, let fallback = URL(string: "http://\(cleanHost):\(port)") else {
                self.connectionRouteDescription = "待扫码配对或配置 Mac 地址"
                return nil
            }
            return fallback
        }

        activeProbeTask = probeTask
        let resolved = await probeTask.value
        activeProbeTask = nil

        guard let finalURL = resolved else {
            throw URLError(.badURL)
        }
        return finalURL
    }

    private func raceCandidates(
        _ candidates: [CandidateType]
    ) async -> CandidateProbeResult? {
        guard !candidates.isEmpty else { return nil }
        let session = fastSession
        var pendingLanCount = candidates.filter { $0.isLan }.count

        return await withTaskGroup(of: ProbeOutcome.self) { group in
            for item in candidates {
                switch item {
                case .direct(let url, let kind, let desc):
                    group.addTask {
                        guard let pingURL = URL(string: "/api/v1/ping", relativeTo: url) else {
                            return .failure(isLan: kind == .lanDirect)
                        }
                        var req = URLRequest(url: pingURL)
                        req.timeoutInterval = 1.6
                        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        let start = DispatchTime.now().uptimeNanoseconds
                        do {
                            let (data, resp) = try await session.data(for: req)
                            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  (json["ok"] as? Bool) == true else {
                                return .failure(isLan: kind == .lanDirect)
                            }
                            let elapsedMs = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
                            return .success(CandidateProbeResult(
                                baseURL: url,
                                kind: kind,
                                description: desc,
                                rttMs: elapsedMs
                            ))
                        } catch {
                            return .failure(isLan: kind == .lanDirect)
                        }
                    }

                case .embeddedTailscale(let host, let port, let desc):
                    group.addTask {
                        let start = DispatchTime.now().uptimeNanoseconds
                        do {
                            guard let forwarded = try await TailnetManager.shared.resolveLiveRouteAwaitingEngine(
                                host: host,
                                port: port,
                                timeout: 1.8
                            ), let fURL = URL(string: "http://\(forwarded.host):\(forwarded.port)"),
                               let pingURL = URL(string: "/api/v1/ping", relativeTo: fURL) else {
                                return .failure(isLan: false)
                            }

                            var req = URLRequest(url: pingURL)
                            req.timeoutInterval = 1.4
                            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                            let (data, resp) = try await session.data(for: req)
                            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  (json["ok"] as? Bool) == true else {
                                return .failure(isLan: false)
                            }
                            let elapsedMs = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
                            return .success(CandidateProbeResult(
                                baseURL: fURL,
                                kind: .embeddedTailnet,
                                description: desc,
                                rttMs: elapsedMs
                            ))
                        } catch {
                            return .failure(isLan: false)
                        }
                    }
                }
            }

            var tailscaleWinner: CandidateProbeResult? = nil
            var isWaitingGracePeriod = false

            while let outcome = await group.next() {
                switch outcome {
                case .success(let res):
                    if res.kind == .lanDirect {
                        group.cancelAll()
                        return res
                    } else {
                        if tailscaleWinner == nil {
                            tailscaleWinner = res
                        }
                        if pendingLanCount == 0 {
                            group.cancelAll()
                            return tailscaleWinner
                        }
                        if !isWaitingGracePeriod {
                            isWaitingGracePeriod = true
                            group.addTask {
                                try? await Task.sleep(for: .milliseconds(800))
                                return .graceTimeout
                            }
                        }
                    }

                case .failure(let isLan):
                    if isLan {
                        pendingLanCount = max(0, pendingLanCount - 1)
                        if pendingLanCount == 0, let winner = tailscaleWinner {
                            group.cancelAll()
                            return winner
                        }
                    }

                case .graceTimeout:
                    if let winner = tailscaleWinner {
                        group.cancelAll()
                        return winner
                    }
                }
            }

            return tailscaleWinner
        }
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        retryOnFailure: Bool = true
    ) async throws -> T {
        let baseURL = try await resolveBestBaseURL(forceProbe: false)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = (method == "POST") ? 45 : 3.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !accessToken.isEmpty {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if method == "GET", let etag = etagByPath[path] {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let (data, resp) = try await fastSession.data(for: req)
            let rtt = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
            if routeKind == .lanDirect {
                recordLanSuccess()
            }
            if !isConnected || isReconnecting {
                isConnected = true
                isReconnecting = false
                lastError = nil
            }
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 304 {
                    latencyMs = rtt
                    lastRouteVerifiedAt = Date()
                    connectionRouteDescription = "\(routeKind.rawValue) · \(rtt)ms"
                    throw HTTPNotModifiedSignal.notModified
                }
                if (200...299).contains(httpResp.statusCode) {
                    if let etag = httpResp.value(forHTTPHeaderField: "ETag") {
                        etagByPath[path] = etag
                    }
                } else {
                    let errText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResp.statusCode)"
                    throw NSError(domain: "AntigravityClient", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: errText])
                }
            }
            latencyMs = rtt
            lastRouteVerifiedAt = Date()
            connectionRouteDescription = "\(routeKind.rawValue) · \(rtt)ms"
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if error is HTTPNotModifiedSignal {
                throw error
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            if retryOnFailure {
                // 若当前在局域网，且处于 10 秒局域网黏性保护期内，直接在原局域网通道上重试，不销毁会话池、不切 Tailscale
                if routeKind == .lanDirect && shouldStayStickyOnLanAfterFailure() {
                    try? await Task.sleep(for: .milliseconds(150))
                    let (data, resp) = try await fastSession.data(for: req)
                    let rtt = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
                    recordLanSuccess()
                    isConnected = true
                    isReconnecting = false
                    lastError = nil
                    if let httpResp = resp as? HTTPURLResponse {
                        if httpResp.statusCode == 304 {
                            throw HTTPNotModifiedSignal.notModified
                        }
                        if !(200...299).contains(httpResp.statusCode) {
                            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResp.statusCode)"
                            throw NSError(domain: "AntigravityClient", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: errText])
                        }
                    }
                    latencyMs = rtt
                    lastRouteVerifiedAt = Date()
                    connectionRouteDescription = "\(routeKind.rawValue) · \(rtt)ms"
                    return try JSONDecoder().decode(T.self, from: data)
                }

                // 局域网持续不可达超过 10 秒（或当前非局域网通道失效），重新选路并重试（绝不在请求中途调用 rebuildFastSession 以免误杀并发请求）
                let oldBase = cachedBaseURL
                invalidateRouteCache()
                TailnetManager.shared.wake(reason: "请求失败触发通道重选", resetLocalForwards: true)
                let newBase = try await resolveBestBaseURL(forceProbe: true)
                if oldBase != newBase {
                    reconnectSSEIfActive()
                }
                guard let retryURL = URL(string: path, relativeTo: newBase) else { throw error }
                req.url = retryURL
                let (data, resp) = try await fastSession.data(for: req)
                if let httpResp = resp as? HTTPURLResponse {
                    if httpResp.statusCode == 304 {
                        throw HTTPNotModifiedSignal.notModified
                    }
                    if !(200...299).contains(httpResp.statusCode) {
                        let errText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResp.statusCode)"
                        throw NSError(domain: "AntigravityClient", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: errText])
                    }
                }
                if routeKind == .lanDirect {
                    recordLanSuccess()
                }
                isConnected = true
                isReconnecting = false
                lastError = nil
                return try JSONDecoder().decode(T.self, from: data)
            }
            throw error
        }
    }

    // MARK: - 数据拉取与控制指令

    public var hasConfiguredHost: Bool {
        !serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !fallbackLanHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var shouldShowFirstTimeMacOnboarding: Bool {
        !isConnected && !isDemoMode && !hasEverConnectedMac && !hasConfiguredHost && conversations.isEmpty
    }

    private func markMacConnected() {
        if !hasEverConnectedMac {
            hasEverConnectedMac = true
            UserDefaults.standard.set(true, forKey: "agy.hasEverConnectedMac")
        }
    }

    public func refreshAll() async {
        if isDemoMode { return }
        guard hasConfiguredHost else {
            isConnected = false
            isReconnecting = false
            connectionRouteDescription = "待扫码配对或配置 Mac 地址"
            lastError = nil
            return
        }
        await fetchStatus()
        guard isConnected else { return }
        await fetchModels()
        await fetchConversations()
        if !currentCascadeId.isEmpty {
            await fetchConversationDetail(cascadeId: currentCascadeId)
            await fetchDiffsAndArtifacts(cascadeId: currentCascadeId)
            ensureSSESubscription(cascadeId: currentCascadeId)
        }
    }

    public func fetchStatus() async {
        if isDemoMode { return }
        guard hasConfiguredHost else {
            isConnected = false
            isReconnecting = false
            connectionRouteDescription = "待扫码配对或配置 Mac 地址"
            lastError = nil
            return
        }
        do {
            let st: DaemonStatusResponse = try await request(path: "/api/v1/status")
            daemonStatus = st
            isConnected = (st.online == true)
            if isConnected {
                markMacConnected()
            }
            isReconnecting = false
            lastError = nil

            // 双向自动同步保存 Mac 的 LAN IP 与 Tailscale IP:
            // 1. 同步 LAN IP 到 fallbackLanHost
            if let macLan = st.network?.lanIP?.trimmingCharacters(in: .whitespacesAndNewlines), !macLan.isEmpty {
                let lanUpdated = (fallbackLanHost != macLan)
                if lanUpdated {
                    fallbackLanHost = macLan
                    UserDefaults.standard.set(macLan, forKey: "agy.fallbackLanHost")
                }
                if routeKind != .lanDirect && (lanUpdated || lastLanUpgradeProbeAt == nil) {
                    lastLanUpgradeProbeAt = nil
                    Task { @MainActor [weak self] in
                        await self?.probeLanUpgradeIfNeeded()
                    }
                }
            }

            // 2. 同步 Tailscale IP 到 serverHost
            if let macTs = st.network?.systemTailscaleIP?.trimmingCharacters(in: .whitespacesAndNewlines), !macTs.isEmpty {
                let currentHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentHost.isEmpty {
                    serverHost = macTs
                    UserDefaults.standard.set(macTs, forKey: "agy.serverHost")
                } else if !TailnetManager.isTailnetHost(currentHost) {
                    if fallbackLanHost.isEmpty {
                        fallbackLanHost = currentHost
                        UserDefaults.standard.set(currentHost, forKey: "agy.fallbackLanHost")
                    }
                    serverHost = macTs
                    UserDefaults.standard.set(macTs, forKey: "agy.serverHost")
                }
            }
        } catch HTTPNotModifiedSignal.notModified {
            isConnected = true
            markMacConnected()
            isReconnecting = false
            lastError = nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            isReconnecting = true
            isConnected = false
            lastError = error.localizedDescription
        }
    }

    public func fetchModels() async {
        if isDemoMode { return }
        if models.count <= 2 {
            etagByPath.removeValue(forKey: "/api/v1/models")
        }
        do {
            let res: ModelsResponse = try await request(path: "/api/v1/models")
            if let list = res.models, !list.isEmpty {
                if models != list {
                    models = list
                    scheduleSaveOfflineSnapshot()
                }
                if selectedModelId.isEmpty {
                    selectedModelId = !activeConversationModelId.isEmpty ? activeConversationModelId : (list.first?.modelId ?? "")
                }
            }
        } catch HTTPNotModifiedSignal.notModified {
            // 304 未修改，直接保留现有完整模型列表
        } catch {
            // 忽略网络瞬时异常
        }
    }

    public func selectModelForCurrentConversation(_ modelId: String) {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userManualModelOverrideByCascadeId.removeValue(forKey: currentCascadeId)
            selectedModelId = activeConversationModelId
        } else {
            if !currentCascadeId.isEmpty {
                userManualModelOverrideByCascadeId[currentCascadeId] = trimmed
            }
            selectedModelId = trimmed
        }
    }

    public func selectPermissionModeForCurrentConversation(_ mode: AgentPermissionMode) {
        permissionMode = mode
        let cid = currentCascadeId
        if !cid.isEmpty {
            userManualPermissionOverrideByCascadeId[cid] = mode
            conversationActivePermissionCache[cid] = mode
            if !isDemoMode {
                Task { [weak self] in
                    struct EmptyOK: Codable { let ok: Bool? }
                    _ = try? await self?.request(
                        path: "/api/v1/conversations/\(cid)/permission",
                        method: "POST",
                        body: ["permissionMode": mode.rawValue]
                    ) as EmptyOK?
                }
            }
        }
    }

    public func fetchConversations() async {
        if isDemoMode { return }
        do {
            let res: ConversationsListResponse = try await request(path: "/api/v1/conversations")
            await applyConversationsList(projects: res.projects ?? [], conversations: res.conversations ?? [])
        } catch HTTPNotModifiedSignal.notModified {
            // 304 未修改，直接跳过
        } catch {
            // 网络异常处理
        }
    }

    private func applyConversationsList(projects newProjects: [ProjectGroup], conversations newConvos: [ConversationSummary]) async {
        let incomingIds = Set(newConvos.map(\.id))
        let isInitialLoad = knownConversationIds.isEmpty
        let newlyCreatedOnMac = incomingIds.subtracting(knownConversationIds)
        knownConversationIds.formUnion(incomingIds)

        if projects != newProjects { projects = newProjects }
        if conversations != newConvos { conversations = newConvos }

        // 仅在首次加载且当前未选中有效会话时，默认选中第一条会话
        if currentCascadeId.isEmpty || (isInitialLoad && !incomingIds.contains(currentCascadeId)) {
            if let first = newConvos.first {
                await selectConversation(first)
            }
            return
        }

        // 绝不在后台旧对话思考/回复时强制切回！
        // 仅当用户在电脑端全新创建了一个此前不存在的新对话、且开启了自动跟随、且当前手机端没有正在生成的对话时，才自动切换到该全新对话。
        if !isInitialLoad, autoFollowMacConversation, !isGenerating {
            if let brandNewConvo = newConvos.first(where: { newlyCreatedOnMac.contains($0.id) }) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                await selectConversation(brandNewConvo)
                return
            }
        }

        scheduleSaveOfflineSnapshot()
    }

    /// 在最近使用的对话列表中快速前后切换 (direction: -1 为上一个，+1 为下一个)
    public func switchToAdjacentConversation(direction: Int) async {
        let list = conversations
        guard list.count > 1 else { return }
        let currentIndex = list.firstIndex(where: { $0.id == currentCascadeId }) ?? 0
        let nextIndex = (currentIndex + direction + list.count) % list.count
        let target = list[nextIndex]
        await selectConversation(target)
    }

    public func selectConversation(_ convo: ConversationSummary) async {
        if isDemoMode {
            currentCascadeId = convo.id
            currentWorkspaceUri = convo.workspaceUri ?? ""
            messages = DemoModeData.makeDemoMessages(for: convo.id)
            if convo.id == "demo-convo-2" {
                pendingInteraction = DemoModeData.makeDemoPendingInteraction(cascadeId: convo.id)
            } else {
                pendingInteraction = nil
            }
            return
        }
        let changed = (currentCascadeId != convo.id)
        lastSyncedStepCount = -1

        let cachedActive = conversationActiveModelCache[convo.id] ?? ""
        activeConversationModelId = cachedActive
        selectedModelId = userManualModelOverrideByCascadeId[convo.id] ?? cachedActive
        if let cachedPerm = userManualPermissionOverrideByCascadeId[convo.id] ?? conversationActivePermissionCache[convo.id] {
            if permissionMode != cachedPerm {
                permissionMode = cachedPerm
            }
        }

        if changed {
            pendingOptimisticMessages.removeAll()
            queuedMessages.removeAll()
            isGenerating = convo.isRunning ?? false
            pendingInteraction = nil
            let cached = conversationMessagesCache[convo.id] ?? []
            messages = cached
            diffs = conversationDiffsCache[convo.id] ?? []
            artifacts = conversationArtifactsCache[convo.id] ?? []
            if cached.isEmpty {
                etagByPath.removeValue(forKey: "/api/v1/conversations/\(convo.id)")
            }
            contextUsage = conversationContextUsageCache[convo.id]
        }
        currentWorkspaceUri = convo.workspaceUri ?? ""
        currentCascadeId = convo.id
        UserDefaults.standard.set(currentCascadeId, forKey: "agy.currentCascadeId")
        UserDefaults.standard.set(currentWorkspaceUri, forKey: "agy.currentWorkspaceUri")
        ensureSSESubscription(cascadeId: convo.id)
        await fetchConversationDetail(cascadeId: convo.id)
        await fetchDiffsAndArtifacts(cascadeId: convo.id)
    }

    public func fetchConversationDetail(cascadeId: String) async {
        if isDemoMode { return }
        guard !cascadeId.isEmpty else { return }
        do {
            let detail: ConversationDetailResponse = try await request(path: "/api/v1/conversations/\(cascadeId)")
            await applyConversationDetail(detail, cascadeId: cascadeId)
        } catch HTTPNotModifiedSignal.notModified {
            // 304 未修改，0ms 无额外反序列化开销
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyConversationDetail(_ detail: ConversationDetailResponse, cascadeId: String) async {
        let serverMsgs = detail.messages ?? []
        conversationMessagesCache[cascadeId] = serverMsgs
        if let usage = detail.contextUsage {
            conversationContextUsageCache[cascadeId] = usage
        }
        if let actModel = detail.activeModel, !actModel.isEmpty {
            let prevModel = conversationActiveModelCache[cascadeId]
            conversationActiveModelCache[cascadeId] = actModel
            if let prevModel, prevModel != actModel {
                // 电脑端该对话切换了新模型，清除旧的手机端临时覆盖
                userManualModelOverrideByCascadeId.removeValue(forKey: cascadeId)
            }
        }
        if let rawPerm = detail.activePermissionMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let macPerm = AgentPermissionMode(rawValue: rawPerm) {
            let prevPerm = conversationActivePermissionCache[cascadeId]
            conversationActivePermissionCache[cascadeId] = macPerm
            if let prevPerm, prevPerm != macPerm {
                userManualPermissionOverrideByCascadeId.removeValue(forKey: cascadeId)
            }
        }
        guard cascadeId == currentCascadeId else { return }

        if contextUsage != detail.contextUsage {
            contextUsage = detail.contextUsage
        }

        let serverQueued = detail.queuedMessages ?? []
        if queuedMessages != serverQueued {
            queuedMessages = serverQueued
        }

        let recentSendWindow = lastMessageSentAt.map { Date().timeIntervalSince($0) < 12.0 } ?? false

        // 清理已经被服务端落盘或已进入排队队列的乐观消息，未落盘的继续保留在末尾，彻底消除闪烁
        if !pendingOptimisticMessages.isEmpty {
            let newServerUserTexts = Set(
                serverMsgs
                    .filter { $0.role == "user" && (($0.stepIndex ?? Int.max) >= optimisticBaselineStepIndex || $0.id.hasPrefix("pending-dispatch-")) }
                    .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
            let queuedTexts = Set(serverQueued.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
            pendingOptimisticMessages.removeAll { opt in
                guard let t = opt.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
                return newServerUserTexts.contains(t) || queuedTexts.contains(t)
            }
        }

        let merged = serverMsgs + pendingOptimisticMessages
        if messages != merged {
            messages = merged
        }

        let rawGen = detail.isGenerating ?? false
        let gen = (recentSendWindow && !pendingOptimisticMessages.isEmpty) ? true : rawGen
        if isGenerating != gen {
            isGenerating = gen
        }

        // 同步修正会话列表里对应会话的 isRunning 状态，防止已完成对话在侧边栏或多任务条中仍显示运行中
        if let idx = conversations.firstIndex(where: { $0.id == cascadeId }),
           conversations[idx].isRunning != gen {
            var updated = conversations
            updated[idx].isRunning = gen
            updated[idx].status = gen ? "CASCADE_RUN_STATUS_RUNNING" : "CASCADE_RUN_STATUS_IDLE"
            conversations = updated
        }

        // 若对话已结束生成且已超过发送保护窗口，才清理残余的乐观气泡
        if !gen && !recentSendWindow && !pendingOptimisticMessages.isEmpty && !serverMsgs.isEmpty {
            pendingOptimisticMessages.removeAll()
            if messages != serverMsgs {
                messages = serverMsgs
            }
        }

        if let actModel = detail.activeModel, !actModel.isEmpty {
            if activeConversationModelId != actModel {
                activeConversationModelId = actModel
            }
            let effectiveModel = userManualModelOverrideByCascadeId[cascadeId] ?? actModel
            if selectedModelId != effectiveModel {
                selectedModelId = effectiveModel
            }
        }
        if let rawPerm = detail.activePermissionMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let macPerm = AgentPermissionMode(rawValue: rawPerm) {
            let effectivePerm = userManualPermissionOverrideByCascadeId[cascadeId] ?? macPerm
            if permissionMode != effectivePerm {
                permissionMode = effectivePerm
            }
        }

        if pendingInteraction != detail.pendingInteraction {
            pendingInteraction = detail.pendingInteraction
        }

        let stepCount = detail.stepCount ?? serverMsgs.count
        if stepCount != lastSyncedStepCount {
            lastSyncedStepCount = stepCount
            await fetchDiffsAndArtifacts(cascadeId: cascadeId)
        }

        if let pending = detail.pendingInteraction, pending.stepIndex != lastPendingStepIndex {
            lastPendingStepIndex = pending.stepIndex
            if permissionMode == .turbo && pending.kind != "ask_question" && pending.kind != "artifact_approval" {
                Task { await respondToInteraction(pending, allow: true) }
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else if detail.pendingInteraction == nil {
            lastPendingStepIndex = nil
        }

        // 场景 A: 待审批远程本地提醒
        if let pending = detail.pendingInteraction, pending.stepIndex != lastNotifiedInteractionStepIndex {
            lastNotifiedInteractionStepIndex = pending.stepIndex
            if UIApplication.shared.applicationState != .active {
                sendLocalNotification(
                    title: "⚡ 需要您的远程审批",
                    body: pending.summary ?? pending.commandLine ?? "AI 正在等待您批准操作",
                    identifier: "pending-\(pending.stepIndex)"
                )
            }
        } else if detail.pendingInteraction == nil {
            lastNotifiedInteractionStepIndex = nil
        }

        // 场景 B: AI 完成回复提醒
        if wasGenerating && !gen {
            if UIApplication.shared.applicationState != .active {
                let lastAssistant = serverMsgs.last(where: { $0.role == "assistant" })?.text ?? "任务已完成"
                let snippet = String(lastAssistant.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                sendLocalNotification(
                    title: "✅ AI 已完成回复",
                    body: snippet.isEmpty ? "AI 已成功完成本次任务生成" : snippet,
                    identifier: "completed-\(Date().timeIntervalSince1970)"
                )
            }
            if UIApplication.shared.applicationState == .background, bgTaskID != .invalid {
                endCurrentBackgroundTask()
            }
        }
        wasGenerating = gen

        scheduleSaveOfflineSnapshot()
    }

    public func fetchDiffsAndArtifacts(cascadeId: String) async {
        if isDemoMode { return }
        guard !cascadeId.isEmpty else { return }
        guard let res: DiffsAndArtifactsResponse = try? await request(path: "/api/v1/conversations/\(cascadeId)/diffs") else { return }
        let newDiffs = res.diffs ?? []
        let newArtifacts = res.artifacts ?? []
        conversationDiffsCache[cascadeId] = newDiffs
        conversationArtifactsCache[cascadeId] = newArtifacts
        guard cascadeId == currentCascadeId else { return }
        if diffs != newDiffs { diffs = newDiffs }
        if artifacts != newArtifacts { artifacts = newArtifacts }
    }

    public func sendMessage(text: String, attachments: [PendingMediaAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if isDemoMode {
            let badgeLine = attachments.map { att in
                att.isVideo ? "🎬 [视频: \(att.fileName)]" : "🖼️ [图片: \(att.fileName)]"
            }.joined(separator: "  ")
            let displayUserText: String = {
                if attachments.isEmpty { return trimmed }
                return trimmed.isEmpty ? badgeLine : "\(badgeLine)\n\(trimmed)"
            }()
            let userMsg = ChatMessageItem(
                id: "demo-user-\(UUID().uuidString)",
                stepIndex: messages.count,
                role: "user",
                thinking: nil,
                text: displayUserText,
                toolName: nil,
                summary: nil,
                model: selectedModelId,
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            )
            messages.append(userMsg)
            isGenerating = true

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let self, self.isDemoMode else { return }
                let isZh = LocalizationManager.shared.resolvedLanguage.hasPrefix("zh")
                let lower = trimmed.lowercased()
                let isTest = lower.contains("test") || lower.contains("测试") || lower.contains("run") || lower.contains("命令") || lower.contains("approval")

                let thinkMsg = ChatMessageItem(
                    id: "demo-think-\(UUID().uuidString)",
                    stepIndex: self.messages.count,
                    role: "assistant",
                    thinking: isZh
                        ? "理解用户指令：已接收新输入，正在综合上下文规划任务并分析工程依赖关系..."
                        : "Understanding instruction: parsing prompt context and planning task actions...",
                    text: nil,
                    toolName: nil,
                    summary: nil,
                    model: self.selectedModelId,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
                self.messages.append(thinkMsg)

                let toolMsg = ChatMessageItem(
                    id: "demo-tool-\(UUID().uuidString)",
                    stepIndex: self.messages.count,
                    role: "tool",
                    thinking: nil,
                    text: nil,
                    toolName: isTest ? "run_command" : "read_file",
                    summary: isTest ? "xcodebuild test -scheme AGYRemote" : "read_file: Services/AntigravityClient.swift",
                    model: self.selectedModelId,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
                self.messages.append(toolMsg)

                let replyMsg = ChatMessageItem(
                    id: "demo-reply-\(UUID().uuidString)",
                    stepIndex: self.messages.count,
                    role: "assistant",
                    thinking: nil,
                    text: isZh
                        ? "已根据您的指令完成演示响应！在离线演示模式下，所有界面元素均支持真实点击、展开思考、切换模型与查看代码 Diff。"
                        : "Processed your instruction in Demo Mode! All UI interactions, thinking traces, model switching, and diff views are fully interactive.",
                    toolName: nil,
                    summary: nil,
                    model: self.selectedModelId,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
                self.messages.append(replyMsg)
                self.isGenerating = false

                if isTest {
                    self.pendingInteraction = DemoModeData.makeDemoPendingInteraction(cascadeId: self.currentCascadeId)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
            return
        }

        if currentCascadeId.isEmpty {
            await startNewConversation(prompt: trimmed, attachments: attachments)
            return
        }

        let targetCascadeId = currentCascadeId
        let shouldQueueOptimistically = queueMessagesWhenBusy && (isGenerating || !queuedMessages.isEmpty)

        let badgeLine = attachments.map { att in
            att.isVideo ? "🎬 [视频: \(att.fileName)]" : "🖼️ [图片: \(att.fileName)]"
        }.joined(separator: "  ")
        let displayUserText: String = {
            if attachments.isEmpty { return trimmed }
            return trimmed.isEmpty ? badgeLine : "\(badgeLine)\n\(trimmed)"
        }()

        if shouldQueueOptimistically {
            let optQueued = QueuedMessageItem(
                id: "opt-q-\(UUID().uuidString)",
                text: displayUserText,
                model: selectedModelId.isEmpty ? nil : selectedModelId
            )
            queuedMessages.append(optQueued)
        } else {
            lastMessageSentAt = Date()
            optimisticBaselineStepIndex = (messages.compactMap(\.stepIndex).max() ?? -1) + 1
            let optimistic = ChatMessageItem(
                id: "optimistic-\(UUID().uuidString)",
                stepIndex: nil,
                role: "user",
                thinking: nil,
                text: displayUserText,
                toolName: nil,
                summary: nil,
                model: nil,
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            )
            pendingOptimisticMessages.append(optimistic)
            messages.append(optimistic)
            isGenerating = true
        }

        var payload: [String: Any] = [
            "text": trimmed,
            "queueIfBusy": queueMessagesWhenBusy,
            "permissionMode": permissionMode.rawValue
        ]
        if !selectedModelId.isEmpty {
            payload["model"] = selectedModelId
        }
        if !attachments.isEmpty {
            payload["media"] = attachments.map { att in
                [
                    "mimeType": att.mimeType,
                    "fileName": att.fileName,
                    "inlineData": att.base64Data
                ]
            }
        }

        if let res: SendMessageResponse = try? await request(
            path: "/api/v1/conversations/\(targetCascadeId)/messages",
            method: "POST",
            body: payload
        ), currentCascadeId == targetCascadeId {
            if let qList = res.queuedMessages {
                queuedMessages = qList
            }
            if res.queued == true {
                pendingOptimisticMessages.removeAll { $0.text == displayUserText }
            }
        }

        if currentCascadeId == targetCascadeId {
            await fetchConversationDetail(cascadeId: targetCascadeId)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.fetchConversationDetail(cascadeId: targetCascadeId)
            }
        }
    }

    public func removeQueuedMessage(_ item: QueuedMessageItem) async {
        guard !currentCascadeId.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let targetCascadeId = currentCascadeId
        queuedMessages.removeAll { $0.id == item.id }

        struct QueueResp: Codable {
            let ok: Bool?
            let queuedMessages: [QueuedMessageItem]?
        }
        if let res: QueueResp = try? await request(
            path: "/api/v1/conversations/\(targetCascadeId)/queue/remove",
            method: "POST",
            body: ["queueId": item.id]
        ), currentCascadeId == targetCascadeId, let qList = res.queuedMessages {
            queuedMessages = qList
        }
    }

    public func flushQueuedMessage(_ item: QueuedMessageItem) async {
        guard !currentCascadeId.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let targetCascadeId = currentCascadeId
        queuedMessages.removeAll { $0.id == item.id }

        struct QueueResp: Codable {
            let ok: Bool?
            let queuedMessages: [QueuedMessageItem]?
        }
        if let res: QueueResp = try? await request(
            path: "/api/v1/conversations/\(targetCascadeId)/queue/flush",
            method: "POST",
            body: ["queueId": item.id]
        ), currentCascadeId == targetCascadeId, let qList = res.queuedMessages {
            queuedMessages = qList
        }
        if currentCascadeId == targetCascadeId {
            await fetchConversationDetail(cascadeId: targetCascadeId)
        }
    }

    public func createNewBlankConversation(title: String, workspaceUri: String? = nil) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetWs = workspaceUri ?? currentWorkspaceUri

        if isDemoMode {
            let newId = "demo-convo-\(UUID().uuidString.prefix(6))"
            let newConvo = ConversationSummary(
                id: newId,
                trajectoryId: "traj-\(newId)",
                title: cleanTitle.isEmpty ? "新演示对话" : cleanTitle,
                projectName: "AGY Remote iOS",
                workspaceUri: targetWs,
                workspacePath: "/Users/developer/AntigravityRemote",
                stepCount: 0,
                status: "CASCADE_RUN_STATUS_IDLE",
                isRunning: false,
                updatedAt: "刚刚"
            )
            conversations.insert(newConvo, at: 0)
            if !projects.isEmpty {
                projects[0].conversations.insert(newConvo, at: 0)
            }
            currentCascadeId = newId
            messages = []
            diffs = []
            artifacts = []
            return
        }

        struct StartResponse: Codable {
            let ok: Bool?
            let cascadeId: String?
            let title: String?
        }
        var payload: [String: Any] = [
            "title": cleanTitle,
            "permissionMode": permissionMode.rawValue
        ]
        if !targetWs.isEmpty {
            payload["workspaceUri"] = targetWs
        }
        if !selectedModelId.isEmpty {
            payload["model"] = selectedModelId
        }

        if let res: StartResponse = try? await request(path: "/api/v1/conversations", method: "POST", body: payload),
           let newId = res.cascadeId {
            knownConversationIds.insert(newId)
            currentCascadeId = newId
            pendingOptimisticMessages.removeAll()
            messages = []
            queuedMessages = []
            diffs = []
            artifacts = []
            pendingInteraction = nil
            isGenerating = false
            if !targetWs.isEmpty {
                currentWorkspaceUri = targetWs
                UserDefaults.standard.set(targetWs, forKey: "agy.currentWorkspaceUri")
            }
            UserDefaults.standard.set(newId, forKey: "agy.currentCascadeId")
            ensureSSESubscription(cascadeId: newId)
            await fetchConversations()
        }
    }

    public func startNewConversation(prompt: String, workspaceUri: String? = nil, attachments: [PendingMediaAttachment] = []) async {
        if isDemoMode {
            let newId = "demo-convo-\(UUID().uuidString.prefix(6))"
            let newConvo = ConversationSummary(
                id: newId,
                trajectoryId: "traj-\(newId)",
                title: prompt.isEmpty ? "新演示对话" : String(prompt.prefix(20)),
                projectName: "AGY Remote iOS",
                workspaceUri: currentWorkspaceUri,
                workspacePath: "/Users/developer/AntigravityRemote",
                stepCount: 1,
                status: "CASCADE_RUN_STATUS_IDLE",
                isRunning: false,
                updatedAt: "刚刚"
            )
            conversations.insert(newConvo, at: 0)
            if !projects.isEmpty {
                projects[0].conversations.insert(newConvo, at: 0)
            }
            await selectConversation(newConvo)
            return
        }

        struct StartResponse: Codable {
            let ok: Bool?
            let cascadeId: String?
        }
        let targetWs = workspaceUri ?? currentWorkspaceUri
        var payload: [String: Any] = [
            "text": prompt,
            "permissionMode": permissionMode.rawValue
        ]
        if !targetWs.isEmpty {
            payload["workspaceUri"] = targetWs
        }
        if !selectedModelId.isEmpty {
            payload["model"] = selectedModelId
        }
        if !attachments.isEmpty {
            payload["media"] = attachments.map { att in
                [
                    "mimeType": att.mimeType,
                    "fileName": att.fileName,
                    "inlineData": att.base64Data
                ]
            }
        }
        if let res: StartResponse = try? await request(path: "/api/v1/conversations", method: "POST", body: payload),
           let newId = res.cascadeId {
            knownConversationIds.insert(newId)
            currentCascadeId = newId
            if !targetWs.isEmpty {
                currentWorkspaceUri = targetWs
                UserDefaults.standard.set(targetWs, forKey: "agy.currentWorkspaceUri")
            }
            UserDefaults.standard.set(newId, forKey: "agy.currentCascadeId")
            ensureSSESubscription(cascadeId: newId)
            await fetchConversations()
            await fetchConversationDetail(cascadeId: newId)
        }
    }

    public func respondToInteraction(
        _ pending: PendingInteractionItem,
        allow: Bool,
        selectedOptionId: String? = nil
    ) async {
        if isDemoMode {
            pendingInteraction = nil
            let isZh = LocalizationManager.shared.resolvedLanguage.hasPrefix("zh")
            let resultMsg: ChatMessageItem
            if allow {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                resultMsg = ChatMessageItem(
                    id: "demo-approved-\(UUID().uuidString)",
                    stepIndex: messages.count,
                    role: "assistant",
                    thinking: nil,
                    text: isZh
                        ? "✅ **命令已批准并执行成功**：所有 24 项回归单元测试均通过 (耗时 2.3s)，核心流式引擎零闪烁！"
                        : "✅ **Command approved and executed**: All 24 unit tests passed (2.3s), zero-flicker streaming confirmed!",
                    toolName: "run_command",
                    summary: isZh ? "测试套件执行完毕：24 passed, 0 failed" : "Test suite passed: 24 passed, 0 failed",
                    model: selectedModelId,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                resultMsg = ChatMessageItem(
                    id: "demo-rejected-\(UUID().uuidString)",
                    stepIndex: messages.count,
                    role: "assistant",
                    thinking: nil,
                    text: isZh
                        ? "❌ 已收到拒绝指令，已终止该命令执行。您可以随时调整提示词或指定其他测试目标。"
                        : "❌ Command execution cancelled by reviewer. You may adjust prompts or test targets at any time.",
                    toolName: nil,
                    summary: nil,
                    model: selectedModelId,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
            }
            messages.append(resultMsg)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(allow ? .success : .error)
        var body: [String: Any] = [
            "trajectoryId": pending.trajectoryId ?? "",
            "stepIndex": pending.stepIndex,
            "kind": pending.kind,
            "allow": allow
        ]
        if let cmd = pending.commandLine {
            body["commandLine"] = cmd
        }
        if let uri = pending.artifactUri {
            body["artifactUri"] = uri
        }
        if pending.kind == "ask_question",
           let q = pending.questions?.first,
           let optId = selectedOptionId {
            body["questionResponses"] = [
                [
                    "question": q.question ?? "",
                    "selectedOptionIds": [optId]
                ]
            ]
        }

        // 乐观收起审批卡片，响应更跟手
        pendingInteraction = nil

        struct EmptyOK: Codable { let ok: Bool? }
        _ = try? await request(
            path: "/api/v1/conversations/\(pending.cascadeId)/interactions",
            method: "POST",
            body: body
        ) as EmptyOK

        await fetchConversationDetail(cascadeId: pending.cascadeId)
    }

    public func stopRunningAgent() async {
        if isDemoMode {
            isGenerating = false
            return
        }
        guard !currentCascadeId.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isGenerating = false
        struct EmptyOK: Codable { let ok: Bool? }
        _ = try? await request(
            path: "/api/v1/conversations/\(currentCascadeId)/cancel",
            method: "POST",
            body: [:]
        ) as EmptyOK
        await fetchConversationDetail(cascadeId: currentCascadeId)
    }

    public func renameConversation(cascadeId: String, newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cascadeId.isEmpty, !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 乐观更新本地会话列表与项目分组
        conversations = conversations.map { c in
            guard c.id == cascadeId else { return c }
            var updated = c
            updated.title = trimmed
            return updated
        }
        projects = projects.map { p in
            var updatedProj = p
            updatedProj.conversations = p.conversations.map { c in
                guard c.id == cascadeId else { return c }
                var updated = c
                updated.title = trimmed
                return updated
            }
            return updatedProj
        }

        if isDemoMode { return }

        struct EmptyOK: Codable { let ok: Bool? }
        _ = try? await request(
            path: "/api/v1/conversations/\(cascadeId)/rename",
            method: "POST",
            body: ["title": trimmed]
        ) as EmptyOK

        await fetchConversations()
    }

    public func archiveConversation(cascadeId: String) async {
        guard !cascadeId.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 乐观从本地会话列表移除
        conversations.removeAll { $0.id == cascadeId }
        projects = projects.compactMap { p in
            var updatedProj = p
            updatedProj.conversations.removeAll { $0.id == cascadeId }
            return updatedProj.conversations.isEmpty ? nil : updatedProj
        }
        conversationMessagesCache.removeValue(forKey: cascadeId)

        if currentCascadeId == cascadeId {
            if let next = conversations.first {
                await selectConversation(next)
            } else {
                currentCascadeId = ""
                messages = []
                diffs = []
                artifacts = []
                pendingInteraction = nil
            }
        }

        if isDemoMode { return }

        struct EmptyOK: Codable { let ok: Bool? }
        _ = try? await request(
            path: "/api/v1/conversations/\(cascadeId)/archive",
            method: "POST",
            body: ["archived": true]
        ) as EmptyOK

        await fetchConversations()
    }

    // MARK: - 原生 SSE 实时事件流 + 自适应后台轮询

    private func ensureSSESubscription(cascadeId: String) {
        if isDemoMode { return }
        guard !cascadeId.isEmpty else { return }
        if sseConnectedCascadeId == cascadeId, sseTask != nil, sseConnectedBaseURL != nil { return }
        sseConnectedCascadeId = cascadeId
        sseTask?.cancel()

        sseTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let base = try await self.resolveBestBaseURL(forceProbe: false)
                    self.sseConnectedBaseURL = base
                    guard let sseURL = URL(string: "/api/v1/events?cascadeId=\(cascadeId)", relativeTo: base) else {
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }
                    var req = URLRequest(url: sseURL)
                    req.timeoutInterval = 300
                    if !self.accessToken.isEmpty {
                        req.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
                    }

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        self.isSSEActive = false
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }

                    self.isSSEActive = true
                    var currentEvent = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("event:") {
                            currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            guard let data = jsonStr.data(using: .utf8) else { continue }
                            if currentEvent == "conversation_update" {
                                if let detail = try? JSONDecoder().decode(ConversationDetailResponse.self, from: data) {
                                    await self.applyConversationDetail(detail, cascadeId: cascadeId)
                                }
                            } else if currentEvent == "conversations_update" {
                                if let listRes = try? JSONDecoder().decode(ConversationsListResponse.self, from: data) {
                                    await self.applyConversationsList(
                                        projects: listRes.projects ?? [],
                                        conversations: listRes.conversations ?? []
                                    )
                                }
                            }
                        }
                    }
                } catch {
                    self.isSSEActive = false
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    // MARK: - 交互式演示模式 (Demo Mode)

    public func enterDemoMode(scene: String? = nil) {
        isDemoMode = true
        activeMarketingScene = scene
        isConnected = true
        isReconnecting = false
        latencyMs = 4
        connectionRouteDescription = (scene != nil) ? L("Tailscale · 4ms") : L("演示模式 · 离线交互")

        models = DemoModeData.makeDemoModels()
        selectedModelId = "gemini-3.1-pro"
        activeConversationModelId = "gemini-3.1-pro"

        let (projs, convos) = DemoModeData.makeDemoProjects()
        projects = projs
        conversations = convos

        let targetConvo: ConversationSummary
        if scene == "approval" {
            targetConvo = convos.first(where: { $0.id == "demo-convo-2" }) ?? convos[0]
        } else {
            targetConvo = convos[0]
        }

        currentCascadeId = targetConvo.id
        currentWorkspaceUri = targetConvo.workspaceUri ?? ""
        contextUsage = DemoModeData.makeDemoContextUsage()
        messages = DemoModeData.makeDemoMessages(for: targetConvo.id)
        diffs = DemoModeData.makeDemoDiffs()
        artifacts = DemoModeData.makeDemoArtifacts()

        if scene == "approval" || targetConvo.id == "demo-convo-2" {
            pendingInteraction = DemoModeData.makeDemoPendingInteraction(cascadeId: targetConvo.id)
        } else {
            pendingInteraction = nil
        }

        if scene == "chat" {
            expandedThinkingIds.insert("step-1")
        }
    }

    public func exitDemoMode() {
        isDemoMode = false
        activeMarketingScene = nil
        pendingInteraction = nil
        messages.removeAll()
        diffs.removeAll()
        artifacts.removeAll()
        currentCascadeId = ""
        etagByPath.removeAll()
        Task {
            await refreshAll()
        }
    }

    public func triggerDemoApproval() {
        guard isDemoMode else { return }
        pendingInteraction = DemoModeData.makeDemoPendingInteraction(cascadeId: currentCascadeId.isEmpty ? "demo-convo-2" : currentCascadeId)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func probeLanUpgradeIfNeeded() async {
        guard !isDemoMode, hasConfiguredHost else { return }

        // 每 2.4 秒进行一次轻量通道健康与优选探测
        if let last = lastLanUpgradeProbeAt, Date().timeIntervalSince(last) < 2.4 {
            return
        }
        lastLanUpgradeProbeAt = Date()

        // 确定局域网候选 IP (优先 fallbackLanHost，其次 serverHost 若非 Tailnet 地址)
        let lanCandidate: String?
        let cleanLan = fallbackLanHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanServer = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanLan.isEmpty && !TailnetManager.isTailnetHost(cleanLan) {
            lanCandidate = cleanLan
        } else if !cleanServer.isEmpty && !TailnetManager.isTailnetHost(cleanServer) {
            lanCandidate = cleanServer
        } else {
            lanCandidate = nil
        }

        // 情况 A：当前处于局域网直连，优先信任常规 API 通信心跳；仅当持续故障超过 10 秒且连续失败 >= 3 次时才回退至 Tailscale
        if routeKind == .lanDirect {
            if isConnected, let lastVerified = lastRouteVerifiedAt, Date().timeIntervalSince(lastVerified) < 3.5 {
                return
            }
            guard let activeBase = cachedBaseURL,
                  let pingURL = URL(string: "/api/v1/ping", relativeTo: activeBase) else {
                await reprobeAndSwitchRouteIfNeeded(force: true)
                return
            }
            var req = URLRequest(url: pingURL)
            req.timeoutInterval = 1.8
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                let (data, resp) = try await fastSession.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["ok"] as? Bool) == true {
                    let rtt = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
                    recordLanSuccess()
                    latencyMs = rtt
                    lastRouteVerifiedAt = Date()
                    isConnected = true
                    isReconnecting = false
                    lastError = nil
                    if let host = activeBase.host {
                        connectionRouteDescription = "局域网极速 (\(host)) · \(rtt)ms"
                    }
                    return
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return
                }
            }

            // 局域网黏性保持：未满 10 秒持续故障（或连续失败不足 3 次）时，继续留在局域网，不切换到 Tailscale
            if shouldStayStickyOnLanAfterFailure() {
                return
            }

            invalidateRouteCache()
            TailnetManager.shared.wake(reason: "局域网持续不可达超过 10s 自动回退 Tailscale", resetLocalForwards: true)
            await reprobeAndSwitchRouteIfNeeded(force: true)
            return
        }

        // 情况 B：当前处于非局域网直连（如 Tailscale 通道或重连探测态），尝试探测是否有局域网极速通道可用以自动切回局域网
        guard let targetHost = lanCandidate,
              let lanPingURL = URL(string: "http://\(targetHost):\(serverPort)/api/v1/ping") else {
            return
        }

        var req = URLRequest(url: lanPingURL)
        req.timeoutInterval = 1.4
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let (data, resp) = try await fastSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["ok"] as? Bool) == true else {
                return
            }
            let rtt = max(1, Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
            guard let newBase = URL(string: "http://\(targetHost):\(serverPort)") else { return }

            let previousBase = cachedBaseURL
            recordLanSuccess()
            cachedBaseURL = newBase
            lastRouteVerifiedAt = Date()
            routeKind = .lanDirect
            latencyMs = rtt
            isConnected = true
            markMacConnected()
            isReconnecting = false
            lastError = nil
            connectionRouteDescription = "局域网极速 (\(targetHost)) · \(rtt)ms"

            if previousBase != newBase {
                reconnectSSEIfActive()
                await fetchStatus()
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            // 局域网尚不可达，若当前处于未连接状态则唤醒 Tailnet 尝试恢复连接
            if !isConnected {
                TailnetManager.shared.wake(reason: "未连接状态唤醒 Tailnet", resetLocalForwards: true)
                await reprobeAndSwitchRouteIfNeeded(force: true)
            }
        }
    }

    private func startPollingLoop(skipInitialRefresh: Bool = false) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if !skipInitialRefresh {
                await self?.refreshAll()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, !Task.isCancelled else { return }
                if self.isDemoMode { continue }

                // 实时比对本机网卡快照，若 Wi-Fi / 蜂窝 / VPN IP 发生切换立即刷新选路
                let liveSig = Self.localInterfaceSnapshot() + "|\(self.netPathMonitor.currentPath.status == .satisfied ? "up" : "down")"
                if !self.lastNetworkSignature.isEmpty && liveSig != self.lastNetworkSignature {
                    self.handleNetworkEnvironmentChanged(newSignature: liveSig, reason: "轮询捕获网卡 IP 变更")
                }

                // 后台非阻塞并发探测局域网极速通道升级（不阻塞常规轮询）
                Task { @MainActor [weak self] in
                    await self?.probeLanUpgradeIfNeeded()
                }

                self.pollTickCount += 1

                // 若当前尚未连上，仅快速轮询 fetchStatus 探活，避免在断连时堆积多个无效请求导致重连卡死；一旦恢复连接立即拉取全量数据
                if !self.isConnected {
                    await self.fetchStatus()
                    if self.isConnected {
                        await self.fetchModels()
                        await self.fetchConversations()
                        if !self.currentCascadeId.isEmpty {
                            await self.fetchConversationDetail(cascadeId: self.currentCascadeId)
                            await self.fetchDiffsAndArtifacts(cascadeId: self.currentCascadeId)
                            self.ensureSSESubscription(cascadeId: self.currentCascadeId)
                        }
                    }
                    continue
                }

                if self.models.isEmpty || (self.pollTickCount % 10 == 0) {
                    await self.fetchModels()
                }
                let needsHighFrequency = self.isGenerating || !self.isSSEActive
                if needsHighFrequency || (self.pollTickCount % 5 == 0) {
                    await self.fetchStatus()
                    if self.isConnected {
                        await self.fetchConversations()
                        if !self.currentCascadeId.isEmpty {
                            await self.fetchConversationDetail(cascadeId: self.currentCascadeId)
                        }
                    }
                }
            }
        }
    }
}
