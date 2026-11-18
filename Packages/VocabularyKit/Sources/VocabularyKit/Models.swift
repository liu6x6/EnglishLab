import Foundation

/// 一个单词的完整信息（词典查询结果）
public struct WordEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "en:\(word)" }
    public let word: String
    public let phonetics: [Phonetic]
    public let definitions: [Definition]
    public let synonyms: [String]
    public let antonyms: [String]
    public let examples: [String]
    public let phrases: [String]
    public let source: String
    public let createdAt: Date

    public init(
        word: String,
        phonetics: [Phonetic] = [],
        definitions: [Definition] = [],
        synonyms: [String] = [],
        antonyms: [String] = [],
        examples: [String] = [],
        phrases: [String] = [],
        source: String = "",
        createdAt: Date = Date()
    ) {
        self.word = word
        self.phonetics = phonetics
        self.definitions = definitions
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.examples = examples
        self.phrases = phrases
        self.source = source
        self.createdAt = createdAt
    }
}

public struct Phonetic: Codable, Equatable, Sendable {
    public let text: String?
    public let audioURL: URL?
    public let accent: String?

    public init(text: String?, audioURL: URL? = nil, accent: String? = nil) {
        self.text = text
        self.audioURL = audioURL
        self.accent = accent
    }
}

public struct Definition: Codable, Equatable, Sendable {
    public let partOfSpeech: String
    public let meaning: String
    public let examples: [String]

    public init(partOfSpeech: String, meaning: String, examples: [String] = []) {
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.examples = examples
    }
}

/// 生词掌握状态
public enum LearningStatus: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case mastered

    public var displayName: String {
        switch self {
        case .new: return "未掌握"
        case .learning: return "复习中"
        case .mastered: return "已掌握"
        }
    }
}
