import Foundation

/// 解析后的一条字幕（时间单位：秒）
public struct ParsedSubtitleLine: Equatable, Sendable {
    public let index: Int
    public let start: Double
    public let end: Double
    public let text: String

    public init(index: Int, start: Double, end: Double, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SubtitleFormat: String, Sendable, CaseIterable {
    case srt, lrc, vtt, txt

    /// 按文件扩展名识别格式，未知扩展名按纯文本处理
    public static func detect(fileName: String) -> SubtitleFormat {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return SubtitleFormat(rawValue: ext) ?? .txt
    }
}

public enum SubtitleParser {

    public static func parse(_ content: String, format: SubtitleFormat) -> [ParsedSubtitleLine] {
        let normalized = normalize(content)
        let raw: [(Double, Double, String)]
        switch format {
        case .srt, .vtt: raw = parseCueFormat(normalized)
        case .lrc: raw = parseLRC(normalized)
        case .txt: raw = parsePlainText(normalized)
        }
        return raw.enumerated().map { i, t in
            ParsedSubtitleLine(index: i, start: t.0, end: t.1, text: t.2)
        }
    }

    // MARK: - Normalization

    static func normalize(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 "HH:MM:SS,mmm" / "MM:SS.mmm" / "MM:SS" 为秒
    static func parseTimestamp(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let v = Double(part) else { return nil }
            seconds = seconds * 60 + v
        }
        return seconds
    }

    // MARK: - SRT / VTT

    static func parseCueFormat(_ content: String) -> [(Double, Double, String)] {
        var result: [(Double, Double, String)] = []
        let blocks = content.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let arrowIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[arrowIdx]
            let sides = timeLine.components(separatedBy: "-->")
            guard sides.count == 2,
                  let start = parseTimestamp(sides[0]),
                  let end = parseTimestamp(sides[1].trimmingCharacters(in: .whitespaces)
                      .components(separatedBy: " ").first ?? "")
            else { continue }
            let textLines = lines[(arrowIdx + 1)...].map(stripTags)
            let text = textLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, end >= start else { continue }
            result.append((start, end, text))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    // MARK: - LRC

    static func parseLRC(_ content: String) -> [(Double, Double, String)] {
        // [mm:ss.xx] 或 [mm:ss.xxx] 或 [mm:ss]，一行可有多个时间标签
        let tagPattern = "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        var pairs: [(Double, String)] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineStr = String(line)
            let ns = lineStr as NSString
            let matches = regex.matches(in: lineStr, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            let text = stripTags(regex.stringByReplacingMatches(
                in: lineStr, range: NSRange(location: 0, length: ns.length), withTemplate: ""
            ))
            guard !text.isEmpty else { continue } // 跳过 [ti:] [ar:] 等元数据
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let fracStr = ns.substring(with: m.range(at: 3))
                    let divisor = pow(10.0, Double(fracStr.count))
                    fraction = (Double(fracStr) ?? 0) / divisor
                }
                pairs.append((minutes * 60 + seconds + fraction, text))
            }
        }

        pairs.sort { $0.0 < $1.0 }
        return pairs.enumerated().map { i, p in
            let end = i + 1 < pairs.count ? pairs[i + 1].0 : p.0 + 5
            return (p.0, max(end, p.0), p.1)
        }
    }

    // MARK: - Plain text

    static func parsePlainText(_ content: String) -> [(Double, Double, String)] {
        var result: [(Double, Double, String)] = []
        for paragraph in content.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // 按句末标点切句
            let sentences = splitByRegex(trimmed, pattern: "(?<=[.!?])\\s+")
            for s in sentences {
                let t = s.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { result.append((0, 0, t)) }
            }
        }
        return result
    }

    /// 用正则切分字符串（保留分隔符前后的内容）
    static func splitByRegex(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [text] }
        var result: [String] = []
        var cursor = 0
        for m in matches {
            result.append(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result.append(ns.substring(from: cursor))
        }
        return result
    }
}

private extension NSRegularExpression {
    func stringByReplacingMatches(in string: String, range: NSRange, withTemplate template: String) -> String {
        stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }
}
