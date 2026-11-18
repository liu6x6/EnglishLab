import Foundation

/// 文本标准化 + Levenshtein 词级对齐 + 正确率评分
public enum TextAligner {

    /// 标准化：小写、去标点（含撇号：we're → were）、按空白分词
    public static func normalize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.compactMap { scalar -> Character? in
            // 撇号直接删除：we're → were, don't → dont
            if scalar == "'" || scalar == "\u{2019}" { return nil }
            if CharacterSet.letters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            // 数字保留（如 "2024"），其余标点替换为空格
            if CharacterSet.decimalDigits.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(cleaned)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 评估：目标文本 vs 识别文本
    public static func assess(targetText: String, recognizedText: String) -> ShadowingResult {
        let target = normalize(targetText)
        let recognized = normalize(recognizedText)
        let words = align(target: target, recognized: recognized)
        let correct = words.filter { $0.status == .correct }.count
        let score = target.isEmpty ? 0 : Double(correct) / Double(target.count) * 100
        return ShadowingResult(
            targetText: targetText,
            recognizedText: recognizedText,
            words: words,
            overallScore: (score * 10).rounded() / 10,
            correctCount: correct,
            targetCount: target.count
        )
    }

    /// Levenshtein DP + 回溯，产出按目标句顺序排列的词级状态序列。
    /// insertion（多读）插在对应目标词位置之后，targetWord 为空串。
    public static func align(target: [String], recognized: [String]) -> [ScoredWord] {
        let n = target.count
        let m = recognized.count

        // dp[i][j] = target 前 i 词与 recognized 前 j 词的最小编辑距离
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let subCost = target[i - 1] == recognized[j - 1] ? 0 : 1
                    dp[i][j] = min(
                        dp[i - 1][j - 1] + subCost,  // 匹配/替换
                        dp[i - 1][j] + 1,            // 漏读
                        dp[i][j - 1] + 1             // 多读
                    )
                }
            }
        }

        // 回溯
        var reversed: [ScoredWord] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let equal = target[i - 1] == recognized[j - 1]
                let subCost = equal ? 0 : 1
                if dp[i][j] == dp[i - 1][j - 1] + subCost {
                    reversed.append(ScoredWord(
                        index: i - 1,
                        targetWord: target[i - 1],
                        recognizedWord: recognized[j - 1],
                        status: equal ? .correct : .substitution
                    ))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                reversed.append(ScoredWord(
                    index: i - 1,
                    targetWord: target[i - 1],
                    recognizedWord: nil,
                    status: .deletion
                ))
                i -= 1
                continue
            }
            if j > 0, dp[i][j] == dp[i][j - 1] + 1 {
                reversed.append(ScoredWord(
                    index: i,
                    targetWord: "",
                    recognizedWord: recognized[j - 1],
                    status: .insertion
                ))
                j -= 1
                continue
            }
            // 理论上不会到达
            break
        }
        return reversed.reversed()
    }
}
