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
    let offline: OfflineDictionary?

    public init(
        dictionary: DictionaryLookupService,
        thesaurus: ThesaurusService? = nil,
        cache: DictionaryCache,
        normalizer: WordNormalizer = RuleBasedWordNormalizer(),
        offline: OfflineDictionary? = nil
    ) {
        self.dictionary = dictionary
        self.thesaurus = thesaurus
        self.cache = cache
        self.normalizer = normalizer
        self.offline = offline
    }

    public func lookup(word raw: String) async throws -> WordEntry {
        let cleaned = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.first?.isLetter == true else {
            throw LookupError.invalidWord
        }
        // 词组：跳过词形还原，直接 缓存→在线→离线（ECDICT 含词组条目）
        if cleaned.contains(" ") {
            return try await lookupPhrase(cleaned)
        }
        let candidates = normalizer.candidates(for: cleaned)

        // 1. 缓存（含别名）
        for candidate in candidates {
            if let hit = await cache.entry(for: candidate) { return hit }
        }

        // 2. 在线查询（按候选顺序，找到即止），成功时合并离线中文释义
        var lastError: Error?
        for candidate in candidates {
            do {
                if var entry = try await dictionary.lookup(word: candidate) {
                    if let thesaurus {
                        let rel = await thesaurus.relations(for: candidate)
                        entry = entry.merging(synonyms: rel.synonyms, antonyms: rel.antonyms)
                    }
                    if let chinese = offline?.entry(for: candidate) {
                        entry = entry.mergingChinese(chinese)
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

        // 3. 离线兑底（断网/在线未收录）
        for candidate in candidates {
            if let entry = offline?.entry(for: candidate) {
                await cache.store(entry, for: candidate)
                if candidate != cleaned {
                    await cache.store(entry, for: cleaned)
                }
                return entry
            }
        }

        if let lastError { throw lastError }
        throw LookupError.notFound(cleaned)
    }

    private func lookupPhrase(_ phrase: String) async throws -> WordEntry {
        if let hit = await cache.entry(for: phrase) { return hit }
        var lastError: Error?
        do {
            if var entry = try await dictionary.lookup(word: phrase) {
                if let chinese = offline?.entry(for: phrase) {
                    entry = entry.mergingChinese(chinese)
                }
                await cache.store(entry, for: phrase)
                return entry
            }
        } catch {
            lastError = error
        }
        if let entry = offline?.entry(for: phrase) {
            await cache.store(entry, for: phrase)
            return entry
        }
        if let lastError { throw lastError }
        throw LookupError.notFound(phrase)
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

    /// 合并中文释义（放最前），音标缺失时补充
    public func mergingChinese(_ chinese: WordEntry) -> WordEntry {
        WordEntry(
            word: word,
            phonetics: phonetics.isEmpty ? chinese.phonetics : phonetics,
            definitions: chinese.definitions + definitions,
            synonyms: synonyms,
            antonyms: antonyms,
            examples: examples,
            phrases: phrases,
            source: source + " + ECDICT",
            createdAt: createdAt
        )
    }
}
