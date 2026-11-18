import Foundation
import SwiftData

enum MediaType: String, Codable {
    case video
    case audio
}

@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var title: String
    /// 相对于 Media 目录的文件名（导入时拷贝进沙盒）
    var fileName: String
    var subtitleFileName: String?
    var duration: Double
    var currentTime: Double
    var addedAt: Date
    var lastPlayedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SubtitleLine.mediaItem)
    var lines: [SubtitleLine]

    @Relationship(inverse: \Playlist.items)
    var playlists: [Playlist]

    var type: MediaType {
        get { MediaType(rawValue: typeRaw) ?? .audio }
        set { typeRaw = newValue.rawValue }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
    }

    init(
        id: UUID = UUID(),
        type: MediaType,
        title: String,
        fileName: String,
        subtitleFileName: String? = nil,
        duration: Double = 0,
        currentTime: Double = 0,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.title = title
        self.fileName = fileName
        self.subtitleFileName = subtitleFileName
        self.duration = duration
        self.currentTime = currentTime
        self.addedAt = addedAt
        self.lines = []
        self.playlists = []
    }
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date

    var items: [MediaItem]

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.items = []
    }
}

@Model
final class SubtitleLine {
    @Attribute(.unique) var id: UUID
    var index: Int
    var startTime: Double
    var endTime: Double
    var text: String

    var mediaItem: MediaItem?

    init(id: UUID = UUID(), index: Int, startTime: Double, endTime: Double, text: String) {
        self.id = id
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

/// 一次跟读会话（录音文件存 RecordingStore，评分结果 JSON 缓存）
@Model
final class ShadowingSession {
    @Attribute(.unique) var id: UUID
    var mediaItemID: UUID
    var subtitleLineID: UUID
    var mediaTitle: String
    var targetText: String
    var recognizedText: String
    var recordedAt: Date
    var audioFileName: String
    var overallScore: Double
    /// ShadowingResult JSON（词级着色回放用）
    var resultData: Data?

    init(
        id: UUID = UUID(),
        mediaItemID: UUID,
        subtitleLineID: UUID,
        mediaTitle: String,
        targetText: String,
        recognizedText: String,
        recordedAt: Date = Date(),
        audioFileName: String,
        overallScore: Double,
        resultData: Data? = nil
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.subtitleLineID = subtitleLineID
        self.mediaTitle = mediaTitle
        self.targetText = targetText
        self.recognizedText = recognizedText
        self.recordedAt = recordedAt
        self.audioFileName = audioFileName
        self.overallScore = overallScore
        self.resultData = resultData
    }
}

@Model
final class WordRecord {
    /// 单词原形（唯一）
    @Attribute(.unique) var word: String
    /// 缓存的 WordEntry JSON
    var entryData: Data
    var statusRaw: String
    var addedAt: Date
    var reviewCount: Int
    /// 来源素材标题（可空）
    var sourceTitle: String?
    /// 艾宾浩斯复习：连续记住阶段（默认值保证轻量迁移）
    var stage: Int = 0
    /// 下次复习到期时间（nil = 未排期，旧数据视为立即到期）
    var dueDate: Date? = nil
    var lastReviewedAt: Date? = nil

    var status: String {
        get { statusRaw }
        set { statusRaw = newValue }
    }

    init(word: String, entryData: Data, status: String = "new", addedAt: Date = Date(), reviewCount: Int = 0, sourceTitle: String? = nil) {
        self.word = word
        self.entryData = entryData
        self.statusRaw = status
        self.addedAt = addedAt
        self.reviewCount = reviewCount
        self.sourceTitle = sourceTitle
        self.stage = 0
        self.dueDate = addedAt   // 新词当天即可复习
        self.lastReviewedAt = nil
    }
}
