import Foundation

/// 查词业务入口：缓存 → 词形还原候选 → 在线词典 → 近反义词增强 → 写缓存
public protocol VocabularyRepository: Sendable {
    func lookup(word: String) async throws -> WordEntry
}

public struct DefaultVocabularyRepository: VocabularyRepository {
    let dictionary: DictionaryLookupService
    let thesaurus: ThesaurusService?
    let cache: DictionaryCache
    let normalizer: WordNormalizer

    public init(
        dictionary: DictionaryLookupService,
        thesaurus: ThesaurusService? = nil,
        cache: DictionaryCache,
        normalizer: WordNormalizer = RuleBasedWordNormalizer()
    ) {
        self.dictionary = dictionary
        self.thesaurus = thesaurus
        self.cache = cache
        self.normalizer = normalizer
    }

    public func lookup(word raw: String) async throws -> WordEntry {
        let cleaned = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.first?.isLetter == true else {
            throw LookupError.invalidWord
        }
        let candidates = normalizer.candidates(for: cleaned)

        // 1. 缓存（含别名）
        for candidate in candidates {
            if let hit = await cache.entry(for: candidate) { return hit }
        }

        // 2. 在线查询（按候选顺序，找到即止）
        var lastError: Error?
        for candidate in candidates {
            do {
                if var entry = try await dictionary.lookup(word: candidate) {
                    if let thesaurus {
                        let rel = await thesaurus.relations(for: candidate)
                        entry = entry.merging(synonyms: rel.synonyms, antonyms: rel.antonyms)
                    }
                    await cache.store(entry, for: candidate)
                    if candidate != cleaned {
                        await cache.store(entry, for: cleaned)
                    }
                    return entry
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw LookupError.notFound(cleaned)
    }
}

extension WordEntry {
    /// 合并近反义词（去重）
    public func merging(synonyms extraSyn: [String], antonyms extraAnt: [String]) -> WordEntry {
        WordEntry(
            word: word,
            phonetics: phonetics,
            definitions: definitions,
            synonyms: Array(Set(synonyms + extraSyn)).sorted(),
            antonyms: Array(Set(antonyms + extraAnt)).sorted(),
            examples: examples,
            phrases: phrases,
            source: source,
            createdAt: createdAt
        )
    }
}
