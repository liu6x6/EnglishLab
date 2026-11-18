import Foundation

public enum LookupError: Error, LocalizedError, Equatable {
    case invalidWord
    case notFound(String)
    case serverError(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidWord: return "无效的单词"
        case .notFound(let w): return "未找到「\(w)」的释义"
        case .serverError(let code): return "词典服务错误（\(code)），请稍后重试"
        }
    }
}

/// 查词服务：未找到返回 nil，网络/服务器错误抛出
public protocol DictionaryLookupService: Sendable {
    func lookup(word: String) async throws -> WordEntry?
}

/// dictionaryapi.dev（基于 Wiktionary，CC BY-SA，需在 About 页注明出处）
public struct FreeDictionaryService: DictionaryLookupService {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lookup(word: String) async throws -> WordEntry? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)")
        else { throw LookupError.invalidWord }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else {
                throw LookupError.serverError(http.statusCode)
            }
        }
        let tokens = try JSONDecoder().decode([FDToken].self, from: data)
        return Self.merge(tokens, word: word)
    }

    /// 把 API 返回的多个词条合并成一个 WordEntry
    static func merge(_ tokens: [FDToken], word: String) -> WordEntry? {
        guard !tokens.isEmpty else { return nil }
        var phonetics: [Phonetic] = []
        var definitions: [Definition] = []
        var synonyms: [String] = []
        var antonyms: [String] = []
        var examples: [String] = []

        for token in tokens {
            if let p = token.phonetic, !p.isEmpty, !phonetics.contains(where: { $0.text == p }) {
                phonetics.append(Phonetic(text: p))
            }
            for ph in token.phonetics ?? [] {
                let text = (ph.text?.isEmpty == false) ? ph.text : nil
                var audio: URL?
                if let a = ph.audio, !a.isEmpty {
                    let fixed = a.hasPrefix("//") ? "https:" + a : a
                    audio = URL(string: fixed)
                }
                guard text != nil || audio != nil else { continue }
                if let existing = phonetics.firstIndex(where: { $0.text == text && text != nil }) {
                    if phonetics[existing].audioURL == nil, audio != nil {
                        phonetics[existing] = Phonetic(text: text, audioURL: audio)
                    }
                } else {
                    phonetics.append(Phonetic(text: text, audioURL: audio))
                }
            }
            for meaning in token.meanings ?? [] {
                let pos = meaning.partOfSpeech ?? ""
                for def in meaning.definitions ?? [] {
                    guard let m = def.definition, !m.isEmpty else { continue }
                    let ex = def.example.map { [$0] } ?? []
                    definitions.append(Definition(partOfSpeech: pos, meaning: m, examples: ex))
                    examples.append(contentsOf: ex)
                    synonyms.append(contentsOf: def.synonyms ?? [])
                    antonyms.append(contentsOf: def.antonyms ?? [])
                }
                synonyms.append(contentsOf: meaning.synonyms ?? [])
                antonyms.append(contentsOf: meaning.antonyms ?? [])
            }
        }
        guard !definitions.isEmpty || !phonetics.isEmpty else { return nil }
        return WordEntry(
            word: word,
            phonetics: phonetics,
            definitions: definitions,
            synonyms: Array(Set(synonyms)).sorted(),
            antonyms: Array(Set(antonyms)).sorted(),
            examples: Array(Set(examples)),
            source: "dictionaryapi.dev (Wiktionary, CC BY-SA)"
        )
    }
}

// MARK: - API DTOs

struct FDToken: Decodable {
    let word: String?
    let phonetic: String?
    let phonetics: [FDPhonetic]?
    let meanings: [FDMeaning]?
}

struct FDPhonetic: Decodable {
    let text: String?
    let audio: String?
}

struct FDMeaning: Decodable {
    let partOfSpeech: String?
    let definitions: [FDDefinition]?
    let synonyms: [String]?
    let antonyms: [String]?
}

struct FDDefinition: Decodable {
    let definition: String?
    let example: String?
    let synonyms: [String]?
    let antonyms: [String]?
}
