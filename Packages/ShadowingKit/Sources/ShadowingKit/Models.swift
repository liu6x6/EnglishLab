import Foundation

/// 词级匹配状态（见 ShadowingModule_Design.md §6.3）
public enum ScoredWordStatus: String, Codable, Sendable, CaseIterable {
    case correct       // 识别词与目标词一致 → 绿色
    case substitution  // 识别成别的词 → 红色
    case deletion      // 目标词未识别出（漏读）→ 红色+下划线
    case insertion     // 多读了词 → 灰色
}

public struct ScoredWord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// 在目标句中的位置（insertion 时为插入点前一个目标词的下一位置）
    public let index: Int
    public let targetWord: String
    public let recognizedWord: String?
    public let status: ScoredWordStatus
    /// 发音分数（本地识别为 nil；预留给 Azure 音素级评估）
    public let score: Double?

    public init(
        id: UUID = UUID(),
        index: Int,
        targetWord: String,
        recognizedWord: String?,
        status: ScoredWordStatus,
        score: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.targetWord = targetWord
        self.recognizedWord = recognizedWord
        self.status = status
        self.score = score
    }
}

/// 一次跟读的评估结果
public struct ShadowingResult: Codable, Equatable, Sendable {
    public let targetText: String
    public let recognizedText: String
    public let words: [ScoredWord]
    /// 总体正确率 0–100
    public let overallScore: Double
    public let correctCount: Int
    public let targetCount: Int

    public init(
        targetText: String,
        recognizedText: String,
        words: [ScoredWord],
        overallScore: Double,
        correctCount: Int,
        targetCount: Int
    ) {
        self.targetText = targetText
        self.recognizedText = recognizedText
        self.words = words
        self.overallScore = overallScore
        self.correctCount = correctCount
        self.targetCount = targetCount
    }

    /// 需要改进的词（读错/漏读）
    public var wordsToImprove: [ScoredWord] {
        words.filter { $0.status == .substitution || $0.status == .deletion }
    }
}
