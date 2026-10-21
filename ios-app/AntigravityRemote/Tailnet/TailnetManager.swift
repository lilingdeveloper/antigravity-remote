//
//  TailnetManager.swift
//  AntigravityRemote
//
//  内置 TailnetKit.xcframework (Go/tsnet, gomobile 生成) 的生命周期与状态管理:
//  - 核心防冲突机制: 系统级 Tailscale (官方 App/VPN/Mac utun*) 在线时自动停用内嵌引擎 (避免同机双节点),
//    系统级离线后自动恢复 (登录态持久化在 stateDir, 无需重新登录)
//  - 路由: 当目标为 tailnet 地址 (100.64/10 或 *.ts.net) 且本机无系统级 Tailscale 时,
//    通过 Go 侧 127.0.0.1 本地转发器透明转发; 若系统级 Tailscale 已在线则直接走系统网卡直连。
//

import Foundation
import Combine
import Darwin
import Network
import UIKit
import TailnetKit

public struct TailnetStatus: Codable, Equatable {
    public struct Peer: Codable, Equatable, Identifiable {
        public let hostname: String
        public let dnsName: String
        public let ip: String
        public let online: Bool
        public let curAddr: String?
        public let relay: String?
        public var id: String { ip.isEmpty ? hostname : ip }
        public var isDirect: Bool { !(curAddr ?? "").isEmpty }
        public var displayName: String { hostname.isEmpty ? dnsName : hostname }
    }

    public let backendState: String
    public let authURL: String?
    public let selfIP: String
    public let hostname: String
    public let peers: [Peer]

    public var isRunning: Bool { backendState == "Running" }
    public var needsLogin: Bool { backendState == "NeedsLogin" || backendState == "NoState" }
}

public enum TailnetRouteError: LocalizedError {
    case engineNotRunning(String)

    public var errorDescription: String? {
        if case .engineNotRunning(let message) = self { return message }
        return nil
    }
}

@MainActor
public final class TailnetManager: ObservableObject {

    public static let shared = TailnetManager()

    @Published public private(set) var status: TailnetStatus?
    @Published public private(set) var lastError: String?
    /// 系统级 Tailscale (官方 App/VPN 或 Mac 系统 Tailscale) 在线: 内嵌引擎自动保持停用
    @Published public private(set) var systemTailscaleActive = false
    /// 系统级 Tailscale 当前 IP (如 100.x.y.z)
    @Published public private(set) var systemTailscaleIP: String?
    /// 用户总开关: 关闭时内嵌引擎彻底停止
    @Published public private(set) var isEnabled: Bool =
        UserDefaults.standard.object(forKey: TailnetManager.enabledDefaultsKey) as? Bool ?? true
    static let enabledDefaultsKey = "tailnet.embeddedEnabled"

    private let engine: TailnetkitEngine?
    public var isEngineUnavailable: Bool { engine == nil }
    private let bridge: NotifierBridge
    private var started = false
    /// 因系统级 Tailscale 上线而自动停用 (系统 Tailscale 离线后自动恢复)
    private var suppressedBySystem = false
    private var pendingAuthKey = ""
    private var systemWatcher: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var pathMonitorStarted = false
    private var lastPathSignature: String?
    private var networkRecoveryTask: Task<Void, Never>?
    private var lastRecoveryAt: Date?
    private var backgroundedAt: Date?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// 缓存已建立的本地转发端口 ("host:port" -> localPort)，避免每次选路都重复调用 Go engine.forward 或阻塞主线程
    private var cachedForwards: [String: Int] = [:]

    private init() {
        engine = TailnetkitNewEngine() ?? TailnetkitEngine()
        bridge = NotifierBridge()
        bridge.manager = self
    }

    private static var stateDirURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("tailnet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 生命周期与系统级 Tailscale 自动避让 (全异步化，彻底杜绝主线程卡顿)

    public func start(authKey: String = "") {
        guard !started else { return }
        guard isEnabled else { return }
        guard let engine else {
            lastError = "内嵌 Tailscale 引擎不可用"
            return
        }

        started = true
        let bridgeRef = bridge
        let statePath = Self.stateDirURL.path

        Task.detached(priority: .userInitiated) { [weak self, engine, bridgeRef] in
            let sysIP = TailscaleLocal.localIP()
            if let sysIP {
                await MainActor.run {
                    guard let self else { return }
                    self.started = false
                    self.pendingAuthKey = authKey
                    self.suppressedBySystem = true
                    self.systemTailscaleActive = true
                    self.systemTailscaleIP = sysIP
                }
            } else {
                engine.setNotifier(bridgeRef)
                var startErr: String?
                do {
                    try engine.start(statePath, hostname: "antigravity-ios", authKey: authKey)
                } catch {
                    startErr = error.localizedDescription
                }
                await MainActor.run {
                    guard let self else { return }
                    self.suppressedBySystem = false
                    self.systemTailscaleActive = false
                    self.systemTailscaleIP = nil
                    if let startErr {
                        self.lastError = startErr
                    }
                }
            }
        }

        startSystemWatcher()
        startNetworkWatcher()
        startLifecycleObservers()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            lastRecoveryAt = nil
            start()
        } else {
            networkRecoveryTask?.cancel()
            let wasStarted = started
            let eng = engine
            started = false
            status = nil
            lastError = nil
            suppressedBySystem = false
            pendingAuthKey = ""
            cachedForwards.removeAll()
            if wasStarted, let eng {
                Task.detached(priority: .utility) {
                    eng.resetForwards()
                    eng.stop()
                }
            }
        }
    }

    public func forceStartEmbeddedEngine(authKey: String = "") {
        guard let engine else {
            lastError = "内嵌 Tailscale 引擎不可用"
            return
        }
        if !isEnabled {
            isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
        }
        suppressedBySystem = false
        systemTailscaleActive = false
        if !started {
            started = true
            let bridgeRef = bridge
            let statePath = Self.stateDirURL.path
            Task.detached(priority: .userInitiated) { [weak self, engine, bridgeRef] in
                engine.setNotifier(bridgeRef)
                do {
                    try engine.start(statePath, hostname: "antigravity-ios", authKey: authKey)
                } catch {
                    let msg = error.localizedDescription
                    await MainActor.run { self?.lastError = msg }
                }
            }
        }
    }

    public func loginURL() async throws -> String {
        guard let engine else { throw TailnetRouteError.engineNotRunning("内嵌引擎不可用") }
        if !started {
            forceStartEmbeddedEngine()
        }
        return try await Task.detached { [engine] in
            var err: NSError?
            let url = engine.loginURL(&err)
            if let err { throw err }
            return url
        }.value
    }

    public func logout() async throws {
        let eng = engine
        try? await Task.detached {
            try eng?.logout()
            eng?.stop()
        }.value
        started = false
        status = nil
        cachedForwards.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.stateDirURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        start()
    }

    public func restart(authKey: String) {
        let eng = engine
        started = false
        status = nil
        cachedForwards.removeAll()
        let bridgeRef = bridge
        let statePath = Self.stateDirURL.path
        started = true
        Task.detached(priority: .userInitiated) { [weak self, eng, bridgeRef] in
            eng?.stop()
            eng?.setNotifier(bridgeRef)
            do {
                try eng?.start(statePath, hostname: "antigravity-ios", authKey: authKey)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.lastError = msg }
            }
        }
    }

    public func recordError(_ message: String) {
        lastError = message
    }

    // MARK: - 系统级 Tailscale 实时监视 (utun* 100.64.0.0/10)

    private func startSystemWatcher() {
        guard systemWatcher == nil else { return }
        systemWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                let sysIP = await Task.detached { TailscaleLocal.localIP() }.value
                guard let self, !Task.isCancelled else { return }
                self.handleSystemTailscale(sysIP: sysIP)
            }
        }
    }

    private func handleSystemTailscale(sysIP: String?) {
        let active = (sysIP != nil)
        systemTailscaleIP = sysIP
        guard active != systemTailscaleActive else { return }
        systemTailscaleActive = active
        if active {
            if started {
                let eng = engine
                started = false
                status = nil
                suppressedBySystem = true
                cachedForwards.removeAll()
                Task.detached(priority: .utility) {
                    eng?.stop()
                }
            }
        } else if suppressedBySystem, isEnabled {
            suppressedBySystem = false
            let key = pendingAuthKey
            pendingAuthKey = ""
            start(authKey: key)
        }
    }

    // MARK: - 网络接口变化与前后台自愈 (全后台线程执行，零主线程阻塞)

    private func startNetworkWatcher() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.pathSignature(path)
            let sysIP = TailscaleLocal.localIP()
            Task { @MainActor in
                self?.handleSystemTailscale(sysIP: sysIP)
                self?.handlePathChange(signature: signature)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.antigravity.tailnet.netpath"))
    }

    nonisolated private static func pathSignature(_ path: NWPath) -> String {
        let ifaces = path.availableInterfaces.map { $0.name }.sorted().joined(separator: ",")
        return "\(path.status == .satisfied ? "up" : "down")|\(ifaces)"
    }

    private func handlePathChange(signature: String) {
        defer { lastPathSignature = signature }
        guard let previous = lastPathSignature, previous != signature else { return }
        guard started, !suppressedBySystem else { return }
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            // 网络路径变化时重置旧接口上的残留转发端口并唤醒引擎
            self.wake(reason: "网络切换 \(previous) → \(signature)", resetLocalForwards: true)
        }
    }

    public func recoverEngine(reason: String) {
        guard isEnabled, started, !suppressedBySystem else { return }
        if let last = lastRecoveryAt, Date().timeIntervalSince(last) < 20 { return }
        lastRecoveryAt = Date()
        cachedForwards.removeAll()
        let eng = engine
        Task.detached(priority: .utility) {
            eng?.resetForwards()
            eng?.wake(reason)
        }
    }

    private func startLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundedAt = Date() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let away = self.backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.backgroundedAt = nil
                if away >= 5 {
                    self.wake(reason: "回前台 (\(Int(away))s)", resetLocalForwards: false)
                }
            }
        })
    }

    public func wake(reason: String, resetLocalForwards: Bool = false) {
        guard started, !suppressedBySystem, let engine else { return }
        if resetLocalForwards {
            cachedForwards.removeAll()
        }
        Task.detached(priority: .utility) { [engine] in
            if resetLocalForwards {
                engine.resetForwards()
            }
            engine.wake(reason)
        }
    }

    public func resetForwards() {
        cachedForwards.removeAll()
        guard let engine else { return }
        Task.detached(priority: .utility) { [engine] in
            engine.resetForwards()
        }
    }

    // MARK: - 路由解析 (自动判断走系统级 Tailscale 直连 vs 内嵌 tsnet 本地转发，全程后台执行)

    public static func isTailnetHost(_ host: String) -> Bool {
        if TailscaleLocal.isTailscaleIPv4(host) { return true }
        let h = host.lowercased()
        return h.hasSuffix(".ts.net") || h.hasSuffix(".ts.net.")
    }

    /// 若目标属于 Tailscale 地址且本机未开系统级 Tailscale，则通过内嵌引擎建立 127.0.0.1:<localPort> 转发；
    /// 若本机已开启系统级 Tailscale（或目标为普通局域网/公网地址），则返回 nil 直接连接。
    public func resolveLiveRouteAwaitingEngine(
        host: String,
        port: Int,
        timeout: TimeInterval = 2.0
    ) async throws -> (host: String, port: Int)? {
        guard Self.isTailnetHost(host) else { return nil }
        if systemTailscaleActive { return nil }

        guard isEnabled else {
            throw TailnetRouteError.engineNotRunning("系统未开启 Tailscale 且应用内嵌 Tailscale 已被关闭")
        }
        if !started { start() }

        let deadline = Date().addingTimeInterval(timeout)
        while !Task.isCancelled, Date() < deadline {
            if status?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard status?.isRunning == true, let engine else {
            throw TailnetRouteError.engineNotRunning("内嵌 Tailscale 尚未登录或未就绪")
        }

        let key = "\(host):\(port)"
        let existingPort = cachedForwards[key]

        let resolvedLocalPort: Int = try await Task.detached(priority: .userInitiated) { [engine] in
            if let existingPort, TailscaleLocal.isLocalPortListening(existingPort) {
                return existingPort
            }
            var localPort: Int32 = 0
            try engine.forward(host, targetPort: Int32(port), ret0_: &localPort)
            if !TailscaleLocal.isLocalPortListening(Int(localPort)) {
                engine.resetForwards()
                try engine.forward(host, targetPort: Int32(port), ret0_: &localPort)
            }
            return Int(localPort)
        }.value

        cachedForwards[key] = resolvedLocalPort
        return ("127.0.0.1", resolvedLocalPort)
    }

    fileprivate func apply(_ newStatus: TailnetStatus?) {
        guard started else { return }
        status = newStatus
    }
}

private final class NotifierBridge: NSObject, TailnetkitNotifierProtocol, @unchecked Sendable {
    weak var manager: TailnetManager?

    func onStatus(_ statusJSON: String?) {
        guard let json = statusJSON, let data = json.data(using: .utf8) else { return }
        let decoded = try? JSONDecoder().decode(TailnetStatus.self, from: data)
        Task { @MainActor [weak self] in
            self?.manager?.apply(decoded)
        }
    }
}
