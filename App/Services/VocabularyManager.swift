import Foundation
import Observation
import VocabularyKit

/// 查词状态管理（右侧单词详情面板的数据源）
@MainActor
@Observable
final class VocabularyManager {
    private let repository: VocabularyRepository

    var selectedWord: String?
    var entry: WordEntry?
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var lookupTask: Task<Void, Never>?

    init(repository: VocabularyRepository? = nil) {
        self.repository = repository ?? DefaultVocabularyRepository(
            dictionary: FreeDictionaryService(),
            thesaurus: DatamuseService(),
            cache: DiskDictionaryCache()
        )
    }

    func lookup(_ word: String) {
        let cleaned = word.lowercased()
        guard !cleaned.isEmpty else { return }
        selectedWord = cleaned
        lookupTask?.cancel()
        isLoading = true
        errorMessage = nil
        lookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let entry = try await self.repository.lookup(word: cleaned)
                guard !Task.isCancelled, self.selectedWord == cleaned else { return }
                self.entry = entry
                self.isLoading = false
                StatsTracker.shared.recordLookup()
            } catch is CancellationError {
                // 被新查询取消，忽略
            } catch {
                guard !Task.isCancelled, self.selectedWord == cleaned else { return }
                self.entry = nil
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
