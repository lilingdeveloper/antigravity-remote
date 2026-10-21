//
//  TailscaleService.swift
//  AntigravityRemote
//
//  智能本机系统级 Tailscale 探测:
//  - 扫描 utun* 接口是否在 100.64.0.0/10 (CGNAT 段)；
//  - 关键防误判: iOS 上的代理工具 (Shadowrocket / Surge / Stash / Clash / Loon) 也会占用 utun* 并分配 100.64.0.1 等地址!
//    因此除了过滤 100.64.0.x 代理网关外，还会探测 Tailscale 官方专属的 Quad100 本地节点服务 (100.100.100.100:80)，
//    只有真正在运行官方系统级 Tailscale 时才返回本机 Tailscale IP，绝不因为开了代理 VPN 而误关内置 Tailscale 引擎！
//

import Foundation
import Darwin

public enum TailscaleLocal {

    /// 本机系统级 Tailscale IPv4 (100.64.0.0/10); 未检测到真实系统级 Tailscale 时返回 nil
    public static func localIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var candidateIP: String?
        var cursor = first
        while true {
            let interface = cursor.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            if isUp, let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("utun") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if isTailscaleIPv4(ip) && !isLikelyProxyFakeTunnelIP(ip) {
                            candidateIP = ip
                            break
                        }
                    }
                }
            }
            guard let next = interface.ifa_next else { break }
            cursor = next
        }

        guard let ip = candidateIP else { return nil }
        // 验证 Tailscale 官方 Quad100 (100.100.100.100:80) 本地服务是否可达，排除第三方代理 Fake-IP / TUN 误判
        guard isQuad100Reachable(timeoutMs: 180) else { return nil }
        return ip
    }

    /// 排除代理软件 (Shadowrocket / Surge / Clash / Sing-box) 常用的 CGNAT TUN 网关地址
    private static func isLikelyProxyFakeTunnelIP(_ ip: String) -> Bool {
        if ip.hasPrefix("100.64.0.") || ip.hasPrefix("100.127.0.") {
            return true
        }
        return false
    }

    /// 检测 Tailscale 官方专有的 100.100.100.100:80 本地 Quad100 接口是否在线
    public static func isQuad100Reachable(timeoutMs: Int32 = 180) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(80).bigEndian)
        addr.sin_addr.s_addr = inet_addr("100.100.100.100")

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if res == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let polled = poll(&pfd, 1, timeoutMs)
        guard polled > 0 && (pfd.revents & Int16(POLLOUT)) != 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 {
            return soError == 0
        }
        return false
    }

    /// 100.64.0.0/10: 100.64.x.x – 100.127.x.x (Tailscale 使用的 CGNAT 地址段)
    public static func isTailscaleIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              let first = UInt8(parts[0]),
              let second = UInt8(parts[1]) else { return false }
        return first == 100 && (64...127).contains(second)
    }

    /// 检查本地 127.0.0.1:<port> 转发端口是否仍在监听 (非阻塞，最长等待 40ms)
    public static func isLocalPortListening(_ port: Int) -> Bool {
        guard port > 0 && port <= 65535 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if res == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let polled = poll(&pfd, 1, 40)
        guard polled > 0 && (pfd.revents & Int16(POLLOUT)) != 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 {
            return soError == 0
        }
        return false
    }
}
