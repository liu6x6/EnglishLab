import Foundation
import VocabularyKit

/// 自检钩子：--selftest-dict（验证内嵌离线词典可打开可查询）
enum DictSelfTest {
    @MainActor
    static func run() {
        guard let dict = ECDICTDictionary() else {
            print("SELFTEST DICT FAILED: 无法打开内嵌词典资源")
            exit(1)
        }
        // 用库内实际存在的词验证（mini/全量均适用）
        let probes = ["'hood", "hello", "perseverance", "run", "english"]
        var hits = 0
        for word in probes {
            if let entry = dict.entry(for: word) {
                hits += 1
                if hits == 1 {
                    let first = entry.definitions.first?.meaning ?? ""
                    print("  sample: \(word) → \(first.prefix(40))")
                }
            }
        }
        guard hits > 0 else {
            print("SELFTEST DICT FAILED: 探测词全部未命中")
            exit(1)
        }
        print("SELFTEST DICT OK: \(hits)/\(probes.count) probes hit")
    }
}
