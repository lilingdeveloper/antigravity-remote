//
//  AntigravityModels.swift
//  AntigravityRemote
//

import Foundation

public struct DaemonStatusResponse: Codable {
    public struct LanguageServerInfo: Codable {
        public let pid: Int?
        public let httpPort: Int?
        public let httpsPort: Int?
        public let cdpPort: Int?
        public let ideVersion: String?
    }

    public struct NetworkInfo: Codable {
        public let hostname: String?
        public let port: Int?
        public let lanIP: String?
        public let lanUrl: String?
        public let systemTailscaleActive: Bool?
        public let systemTailscaleInterface: String?
        public let systemTailscaleIP: String?
        public let magicDNSName: String?
        public let tailscaleUrl: String?
        public let embeddedTailscaleEnabled: Bool?
        public let embeddedTailscaleSuppressedBySystem: Bool?
        public let embeddedStatusHint: String?
        public let cloudflareTunnelUrl: String?
    }

    public let ok: Bool?
    public let online: Bool?
    public let languageServer: LanguageServerInfo?
    public let network: NetworkInfo?
}

public struct AIModelItem: Codable, Identifiable, Equatable {
    public let label: String
    public let modelId: String
    public let isRecommended: Bool?
    public let supportsImages: Bool?
    public let tagTitle: String?
    public let remainingFraction: Double?
    public let resetTime: String?
    public let fiveHourRemainingFraction: Double?
    public let fiveHourResetTime: String?
    public let fiveHourDescription: String?
    public let weeklyRemainingFraction: Double?
    public let weeklyResetTime: String?
    public let weeklyDescription: String?

    public var id: String { modelId.isEmpty ? label : modelId }
}

public struct ModelsResponse: Codable {
    public let ok: Bool?
    public let models: [AIModelItem]?
}

public struct ConversationSummary: Codable, Identifiable, Equatable {
    public let id: String
    public let trajectoryId: String?
    public var title: String
    public let projectName: String
    public let workspaceUri: String?
    public let workspacePath: String?
    public let stepCount: Int?
    public var status: String?
    public var isRunning: Bool?
    public let updatedAt: String?
}

public struct ProjectGroup: Codable, Identifiable, Equatable {
    public let name: String
    public let workspaceUri: String?
    public let workspacePath: String?
    public var conversations: [ConversationSummary]

    public var id: String { name }
}

public struct ConversationsListResponse: Codable {
    public let ok: Bool?
    public let projects: [ProjectGroup]?
    public let conversations: [ConversationSummary]?
}

public struct QuestionOptionItem: Codable, Identifiable, Equatable {
    public let id: String?
    public let text: String?

    public var optionId: String { id ?? text ?? UUID().uuidString }
}

public struct AskQuestionEntryItem: Codable, Identifiable, Equatable {
    public let question: String?
    public let isMultiSelect: Bool?
    public let options: [QuestionOptionItem]?

    public var id: String { question ?? UUID().uuidString }
}

public struct PendingInteractionItem: Codable, Equatable {
    public let kind: String
    public let cascadeId: String
    public let trajectoryId: String?
    public let stepIndex: Int
    public let title: String?
    public let summary: String?
    public let commandLine: String?
    public let pathUri: String?
    public let reason: String?
    public let artifactPath: String?
    public let artifactUri: String?
    public let content: String?
    public let questions: [AskQuestionEntryItem]?
}

public struct ChatMessageItem: Codable, Identifiable, Equatable {
    public let id: String
    public let stepIndex: Int?
    public let role: String
    public let thinking: String?
    public let text: String?
    public let toolName: String?
    public let summary: String?
    public let model: String?
    public let status: String?
    public let isGenerating: Bool?
}

public struct QueuedMessageItem: Codable, Identifiable, Equatable {
    public let id: String
    public let text: String
    public let model: String?
    public let createdAt: String?

    public init(id: String, text: String, model: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.text = text
        self.model = model
        self.createdAt = createdAt
    }
}

public struct SendMessageResponse: Codable {
    public let ok: Bool?
    public let cascadeId: String?
    public let queued: Bool?
    public let queuedMessages: [QueuedMessageItem]?
}

public struct ContextUsageInfo: Codable, Equatable {
    public let usedTokens: Int?
    public let maxTokens: Int?
    public let usageFraction: Double?
    public let usagePercent: Double?

    public init(usedTokens: Int? = nil, maxTokens: Int? = nil, usageFraction: Double? = nil, usagePercent: Double? = nil) {
        self.usedTokens = usedTokens
        self.maxTokens = maxTokens
        self.usageFraction = usageFraction
        self.usagePercent = usagePercent
    }
}

public struct ConversationDetailResponse: Codable {
    public let ok: Bool?
    public let cascadeId: String?
    public let trajectoryId: String?
    public let status: String?
    public let isGenerating: Bool?
    public let stepCount: Int?
    public let activeModel: String?
    public let pendingInteraction: PendingInteractionItem?
    public let queuedMessages: [QueuedMessageItem]?
    public let messages: [ChatMessageItem]?
    public let contextUsage: ContextUsageInfo?
}

public struct FileDiffItem: Codable, Identifiable, Equatable {
    public let uri: String?
    public let filePath: String
    public let fileName: String
    public let originalContent: String?
    public let modifiedContent: String?

    public var id: String { filePath }
}

public struct ArtifactItem: Codable, Identifiable, Equatable {
    public let name: String
    public let uri: String?
    public let filePath: String?
    public let lastEdited: String?
    public let content: String?

    public var id: String { filePath ?? name }
}

public struct DiffsAndArtifactsResponse: Codable {
    public let ok: Bool?
    public let diffs: [FileDiffItem]?
    public let artifacts: [ArtifactItem]?
}
