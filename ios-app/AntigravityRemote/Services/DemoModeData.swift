//
//  DemoModeData.swift
//  AntigravityRemote
//
//  Created for Interactive App Store Review Demo & Marketing Screenshots.
//

import Foundation

public enum DemoModeData {

    public static func makeDemoModels() -> [AIModelItem] {
        [
            AIModelItem(
                label: "Gemini 3.1 Pro (High)",
                modelId: "gemini-3.1-pro",
                isRecommended: true,
                supportsImages: true,
                tagTitle: "High",
                remainingFraction: 0.88,
                resetTime: "2h 45m",
                fiveHourRemainingFraction: 0.88,
                fiveHourResetTime: "2h 45m",
                fiveHourDescription: "5h Quota: 88% remaining",
                weeklyRemainingFraction: 0.94,
                weeklyResetTime: "3d 12h",
                weeklyDescription: "Weekly Quota: 94% remaining"
            ),
            AIModelItem(
                label: "Claude Opus 4.6 (Thinking)",
                modelId: "claude-opus-4.6",
                isRecommended: false,
                supportsImages: true,
                tagTitle: "Thinking",
                remainingFraction: 0.74,
                resetTime: "1h 15m",
                fiveHourRemainingFraction: 0.74,
                fiveHourResetTime: "1h 15m",
                fiveHourDescription: "5h Quota: 74% remaining",
                weeklyRemainingFraction: 0.82,
                weeklyResetTime: "2d 08h",
                weeklyDescription: "Weekly Quota: 82% remaining"
            ),
            AIModelItem(
                label: "Gemini 3.8 Flash",
                modelId: "gemini-3.8-flash",
                isRecommended: false,
                supportsImages: true,
                tagTitle: "Fast",
                remainingFraction: 0.96,
                resetTime: "4h 10m",
                fiveHourRemainingFraction: 0.96,
                fiveHourResetTime: "4h 10m",
                fiveHourDescription: "5h Quota: 96% remaining",
                weeklyRemainingFraction: 0.98,
                weeklyResetTime: "5d 16h",
                weeklyDescription: "Weekly Quota: 98% remaining"
            ),
            AIModelItem(
                label: "GPT-5.2 Codex",
                modelId: "gpt-5.2-codex",
                isRecommended: false,
                supportsImages: true,
                tagTitle: "Code",
                remainingFraction: 0.81,
                resetTime: "3h 20m",
                fiveHourRemainingFraction: 0.81,
                fiveHourResetTime: "3h 20m",
                fiveHourDescription: "5h Quota: 81% remaining",
                weeklyRemainingFraction: 0.89,
                weeklyResetTime: "4d 04h",
                weeklyDescription: "Weekly Quota: 89% remaining"
            )
        ]
    }

    public static func makeDemoProjects() -> ([ProjectGroup], [ConversationSummary]) {
        let isZh = LocalizationManager.shared.resolvedLanguage.hasPrefix("zh")

        let c1 = ConversationSummary(
            id: "demo-convo-1",
            trajectoryId: "traj-001",
            title: isZh ? "实时流式引擎与零延迟多路竞速优化" : "Real-time Streaming Engine & Latency Optimization",
            projectName: "AGY Remote iOS",
            workspaceUri: "file:///Users/developer/AntigravityRemote",
            workspacePath: "/Users/developer/AntigravityRemote",
            stepCount: 8,
            status: "CASCADE_RUN_STATUS_IDLE",
            isRunning: false,
            updatedAt: isZh ? "刚刚" : "Just now"
        )

        let c2 = ConversationSummary(
            id: "demo-convo-2",
            trajectoryId: "traj-002",
            title: isZh ? "单元测试与发布前安全检查" : "Unit Tests & Pre-release Security Checks",
            projectName: "AGY Remote iOS",
            workspaceUri: "file:///Users/developer/AntigravityRemote",
            workspacePath: "/Users/developer/AntigravityRemote",
            stepCount: 12,
            status: "CASCADE_RUN_STATUS_WAITING_USER",
            isRunning: false,
            updatedAt: isZh ? "10分钟前" : "10m ago"
        )

        let c3 = ConversationSummary(
            id: "demo-convo-3",
            trajectoryId: "traj-003",
            title: isZh ? "分布式限流器与 JWT 鉴权中间件重构" : "Distributed Rate Limiter & JWT Auth Middleware",
            projectName: "Cloud API Gateway",
            workspaceUri: "file:///Users/developer/cloud-api-gateway",
            workspacePath: "/Users/developer/cloud-api-gateway",
            stepCount: 6,
            status: "CASCADE_RUN_STATUS_IDLE",
            isRunning: false,
            updatedAt: isZh ? "1小时前" : "1h ago"
        )

        let c4 = ConversationSummary(
            id: "demo-convo-4",
            trajectoryId: "traj-004",
            title: isZh ? "多模态工具调用与上下文窗口压缩策略" : "Multimodal Tool Calling & Context Compression",
            projectName: "AI Agent Core",
            workspaceUri: "file:///Users/developer/ai-agent-core",
            workspacePath: "/Users/developer/ai-agent-core",
            stepCount: 15,
            status: "CASCADE_RUN_STATUS_IDLE",
            isRunning: false,
            updatedAt: isZh ? "昨天" : "Yesterday"
        )

        let p1 = ProjectGroup(
            name: "AGY Remote iOS",
            workspaceUri: "file:///Users/developer/AntigravityRemote",
            workspacePath: "/Users/developer/AntigravityRemote",
            conversations: [c1, c2]
        )

        let p2 = ProjectGroup(
            name: "Cloud API Gateway",
            workspaceUri: "file:///Users/developer/cloud-api-gateway",
            workspacePath: "/Users/developer/cloud-api-gateway",
            conversations: [c3]
        )

        let p3 = ProjectGroup(
            name: "AI Agent Core",
            workspaceUri: "file:///Users/developer/ai-agent-core",
            workspacePath: "/Users/developer/ai-agent-core",
            conversations: [c4]
        )

        return ([p1, p2, p3], [c1, c2, c3, c4])
    }

    public static func makeDemoContextUsage() -> ContextUsageInfo {
        ContextUsageInfo(
            usedTokens: 142_800,
            maxTokens: 1_000_000,
            usageFraction: 0.1428,
            usagePercent: 14.3
        )
    }

    public static func makeDemoMessages(for cascadeId: String) -> [ChatMessageItem] {
        let isZh = LocalizationManager.shared.resolvedLanguage.hasPrefix("zh")

        if cascadeId == "demo-convo-2" {
            return [
                ChatMessageItem(
                    id: "c2-step-0",
                    stepIndex: 0,
                    role: "user",
                    thinking: nil,
                    text: isZh
                        ? "请运行 AntigravityRemote 的自动化单元测试套件，验证流式重连与审批卡片逻辑无崩溃并输出测试覆盖率。"
                        : "Please run the AntigravityRemote unit test suite to verify streaming reconnection and interaction card safety.",
                    toolName: nil,
                    summary: nil,
                    model: nil,
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                ),
                ChatMessageItem(
                    id: "c2-step-1",
                    stepIndex: 1,
                    role: "assistant",
                    thinking: isZh
                        ? "已定位单元测试方案，准备调用 xcodebuild 针对 iPhone 17 Pro 模拟器环境执行回归测试。由于涉及终端命令执行，生成审批卡片等待开发者授权。"
                        : "Preparing to execute regression tests via xcodebuild on iPhone 17 Pro simulator. Raising command approval card for developer authorization.",
                    text: nil,
                    toolName: nil,
                    summary: nil,
                    model: "gemini-3.1-pro",
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                ),
                ChatMessageItem(
                    id: "c2-step-2",
                    stepIndex: 2,
                    role: "assistant",
                    thinking: nil,
                    text: isZh
                        ? "我已准备好完整的回归测试命令，包含 UI 单元测试和流式解析器压力测试。请审批执行："
                        : "Ready to run the full regression test suite including UI tests and stream parser stress tests. Please approve execution:",
                    toolName: nil,
                    summary: nil,
                    model: "gemini-3.1-pro",
                    status: "CORTEX_STEP_STATUS_DONE",
                    isGenerating: false
                )
            ]
        }

        // 默认 demo-convo-1 展现极为精致的流式交互与代码高亮
        let userPrompt = isZh
            ? "请对当前 iOS 端的 SSE 流式传输引擎进行并发优化，消除在弱网与长对话下的渲染掉帧与残余乐观气泡，并执行编译测试验证。"
            : "Please optimize the iOS SSE streaming engine concurrency to eliminate UI frame drops and stale optimistic bubbles on weak network conditions, then verify with unit tests."

        let thinkingText = isZh
            ? """
            深入分析当前 SSE 流式机制：在弱网或网络断开重连时，URLSession 可能会积攒多条分块事件，导致主线程连续触发 SwiftUI Diff 引起微掉帧。同时乐观发送气泡如果清理策略未考虑边界步长，容易导致重复闪烁。

            优化方案：
            1. 在 StreamEngine 中引入 16ms 帧同步合并缓冲队列 (Throttle/Debounce)，把高频增量事件批量合并为单次 MainActor 发布。
            2. 引入精确的 optimisticBaselineStepIndex 与 UUID 排队匹配规则，确保已落盘气泡能被原子化移出。
            3. 调用 xcodebuild 针对 AGYRemote 运行单元测试验证。
            """
            : """
            Analyzing SSE streaming architecture: under weak networks or reconnections, URLSession can buffer chunk bursts, triggering rapid SwiftUI diffing on the main thread and leading to micro-stutters.

            Optimization strategy:
            1. Introduce a 16ms frame-aligned batching queue in StreamEngine to coalesce high-frequency SSE deltas into atomic MainActor dispatches.
            2. Maintain an exact optimisticBaselineStepIndex with server UUID matching to atomically resolve optimistic bubbles.
            3. Run xcodebuild test suite to ensure 100% regression safety.
            """

        let codeSnippet = """
        ```swift
        // 核心帧同步批量流式合并实现片段 (Frame-Aligned Batching)
        actor StreamBatchBuffer {
            private var pendingDeltas: [StreamEvent] = []
            private var flushScheduled = false

            func append(_ event: StreamEvent) {
                pendingDeltas.append(event)
                guard !flushScheduled else { return }
                flushScheduled = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 16_600_000) // 60fps 帧对齐
                    self.flushToUI()
                }
            }
        }
        ```
        """

        let assistantReply = isZh
            ? """
            已完成 SSE 流式引擎与多路竞速调度的深度重构与优化！主要变更点如下：

            ### ⚡️ 核心架构优化
            1. **16ms 帧同步批量合并 (Frame-Aligned Batching)**：
               将单字符流式推送改为配合显示刷新率的原子发布，彻底杜绝高频 SSE 事件对主线程 SwiftUI `LazyVStack` 的高负载抢占。
            2. **原子化乐观气泡生命周期管理**：
               通过 `baselineStepIndex` 与服务器端消息 ID 双向校验，彻底消除弱网下消息重发或重复展示的偶发闪烁。
            3. **多路竞速直连策略 (Happy Eyeballs)**：
               Tailscale 与本地局域网通道双发竞速，优先选用 RTT 低于 10ms 的极速路由。

            \(codeSnippet)

            所有自动化单元测试均已通过，构建耗时 2.8 秒，零警告！
            """
            : """
            Completed comprehensive architectural optimizations for the SSE streaming engine and latency routing! Key improvements:

            ### ⚡️ Core Architectural Improvements
            1. **16ms Frame-Aligned Batching**:
               Coalesces character-level stream events to match the display refresh rate, preventing heavy main-thread diffing on SwiftUI `LazyVStack`.
            2. **Atomic Optimistic Bubble Lifecycle**:
               Bi-directional reconciliation using `baselineStepIndex` and server IDs eliminates all stale duplicate bubble glitches under weak connections.
            3. **Happy Eyeballs Latency Racing**:
               Dual-path racing between Tailscale and LAN to guarantee sub-10ms response times.

            \(codeSnippet)

            All automated test suites passed successfully with zero warnings!
            """

        return [
            ChatMessageItem(
                id: "step-0",
                stepIndex: 0,
                role: "user",
                thinking: nil,
                text: userPrompt,
                toolName: nil,
                summary: nil,
                model: nil,
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            ),
            ChatMessageItem(
                id: "step-1",
                stepIndex: 1,
                role: "assistant",
                thinking: thinkingText,
                text: nil,
                toolName: nil,
                summary: nil,
                model: "gemini-3.1-pro",
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            ),
            ChatMessageItem(
                id: "step-2",
                stepIndex: 2,
                role: "tool",
                thinking: nil,
                text: nil,
                toolName: "read_file",
                summary: isZh ? "读取 Services/StreamEngine.swift 核心实现" : "Read Services/StreamEngine.swift implementation",
                model: "gemini-3.1-pro",
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            ),
            ChatMessageItem(
                id: "step-3",
                stepIndex: 3,
                role: "tool",
                thinking: nil,
                text: nil,
                toolName: "edit_file",
                summary: isZh ? "修改文件 Services/StreamEngine.swift" : "Edited Services/StreamEngine.swift",
                model: "gemini-3.1-pro",
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            ),
            ChatMessageItem(
                id: "step-4",
                stepIndex: 4,
                role: "tool",
                thinking: nil,
                text: nil,
                toolName: "run_command",
                summary: "xcodebuild test -scheme AGYRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro'",
                model: "gemini-3.1-pro",
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            ),
            ChatMessageItem(
                id: "step-5",
                stepIndex: 5,
                role: "assistant",
                thinking: nil,
                text: assistantReply,
                toolName: nil,
                summary: nil,
                model: "gemini-3.1-pro",
                status: "CORTEX_STEP_STATUS_DONE",
                isGenerating: false
            )
        ]
    }

    public static func makeDemoPendingInteraction(cascadeId: String) -> PendingInteractionItem {
        let isZh = LocalizationManager.shared.resolvedLanguage.hasPrefix("zh")

        return PendingInteractionItem(
            kind: "command_approval",
            cascadeId: cascadeId,
            trajectoryId: "traj-002",
            stepIndex: 6,
            title: isZh ? "终端命令待审批" : "Shell Command Pending Approval",
            summary: isZh ? "运行完整单元回归测试套件" : "Run full unit regression test suite",
            commandLine: "xcodebuild test -scheme AntigravityRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro'",
            pathUri: nil,
            reason: isZh
                ? "运行完整回归测试套件以验证流式引擎零闪烁合并逻辑与边界安全性"
                : "Run regression test suite to verify zero-flicker streaming engine and boundary safety",
            artifactPath: nil,
            artifactUri: nil,
            content: nil,
            questions: nil
        )
    }

    public static func makeDemoDiffs() -> [FileDiffItem] {
        [
            FileDiffItem(
                uri: "file:///Users/developer/AntigravityRemote/Services/StreamEngine.swift",
                filePath: "Services/StreamEngine.swift",
                fileName: "StreamEngine.swift",
                originalContent: """
                func handleSSEEvent(_ event: String) {
                    self.delegate?.didReceiveChunk(event)
                }
                """,
                modifiedContent: """
                func handleSSEEvent(_ event: String) {
                    streamBuffer.append(event)
                    if streamBuffer.count >= batchThreshold {
                        flushBufferImmediately()
                    }
                }
                """
            ),
            FileDiffItem(
                uri: "file:///Users/developer/AntigravityRemote/Tailnet/TailnetRouter.swift",
                filePath: "Tailnet/TailnetRouter.swift",
                fileName: "TailnetRouter.swift",
                originalContent: """
                func probeRoute() async -> Route {
                    return .lanDirect
                }
                """,
                modifiedContent: """
                func probeRoute() async -> Route {
                    async let ts = probeTailscaleRTT()
                    async let lan = probeLanRTT()
                    return await (lan.rtt < ts.rtt) ? lan : ts
                }
                """
            ),
            FileDiffItem(
                uri: "file:///Users/developer/AntigravityRemote/Views/ChatTimelineView.swift",
                filePath: "Views/ChatTimelineView.swift",
                fileName: "ChatTimelineView.swift",
                originalContent: """
                ScrollView {
                    LazyVStack {
                        ForEach(messages) { msg in
                            MessageRow(msg)
                        }
                    }
                }
                """,
                modifiedContent: """
                ScrollView {
                    LazyVStack {
                        ForEach(messages) { msg in
                            MessageRow(msg)
                                .id(msg.id)
                        }
                    }
                }
                .id(currentCascadeId)
                """
            )
        ]
    }

    public static func makeDemoArtifacts() -> [ArtifactItem] {
        [
            ArtifactItem(
                name: "implementation_plan.md",
                uri: "file:///Users/developer/AntigravityRemote/docs/implementation_plan.md",
                filePath: "docs/implementation_plan.md",
                lastEdited: "10m ago",
                content: """
                # SSE 流式引擎与零延迟竞速架构实施计划

                ## 目标与背景
                针对弱网长会话环境下的主线程掉帧与乐观消息残留问题，重构移动端网络通信层与渲染管道。

                ## 架构设计
                - **帧对齐缓冲**：采用 16.6ms 防抖合并高频 SSE 字符增量。
                - **Happy Eyeballs 竞速**：局域网与 Tailscale 智能选路，实时监测 RTT。
                - **生命周期校验**：严格的 StepIndex 单向递增校验。

                ## 验证方案
                - [x] 单元测试覆盖率 > 90%
                - [x] 真机弱网模拟 200ms 延迟无掉帧
                - [x] 模拟器回归测试全量通过
                """
            ),
            ArtifactItem(
                name: "walkthrough.md",
                uri: "file:///Users/developer/AntigravityRemote/docs/walkthrough.md",
                filePath: "docs/walkthrough.md",
                lastEdited: "5m ago",
                content: """
                # 架构优化验证与效果评估

                ## 1. 性能对比
                - **主线程占用率**：从 38% 降低至 7%
                - **滚动帧率**：稳定维持在 60 FPS
                - **重连恢复耗时**：从 1.4s 降低至 180ms

                ## 2. 交互体验
                - 命令审批弹窗响应延迟 < 50ms
                - 思考过程展开/折叠丝滑流畅，支持多级缩进语法高亮
                """
            )
        ]
    }
}
