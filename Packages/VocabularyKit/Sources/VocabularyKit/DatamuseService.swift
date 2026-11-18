import Foundation

/// 近反义词服务（失败时静默返回空，不阻塞主查词流程）
public protocol ThesaurusService: Sendable {
    func relations(for word: String) async -> (synonyms: [String], antonyms: [String])
}

/// datamuse.com 免费词汇关系 API
public struct DatamuseService: ThesaurusService {
    let session: URLSession
    let maxResults: Int

    public init(session: URLSession = .shared, maxResults: Int = 8) {
        self.session = session
        self.maxResults = maxResults
    }

    public func relations(for word: String) async -> (synonyms: [String], antonyms: [String]) {
        async let syn = fetch(relation: "rel_syn", word: word)
        async let ant = fetch(relation: "rel_ant", word: word)
        return await (syn, ant)
    }

    private func fetch(relation: String, word: String) async -> [String] {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.datamuse.com/words?\(relation)=\(encoded)&max=\(maxResults)")
        else { return [] }
        guard let (data, _) = try? await session.data(from: url),
              let items = try? JSONDecoder().decode([DatamuseWord].self, from: data)
        else { return [] }
        return items.map(\.word).filter { !$0.contains(" ") }
    }
}

struct DatamuseWord: Decodable {
    let word: String
    let score: Int?
}
