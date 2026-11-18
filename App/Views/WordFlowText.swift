import SwiftUI

/// 可点词的流式排版文本：每个英文单词可点击查词，标点附着在前一个词上
struct WordFlowText: View {
    let text: String
    let fontSize: CGFloat
    let isCurrent: Bool
    let selectedWord: String?
    var hideMode: TextHideMode = .normal
    let onWordTap: (String) -> Void

    struct Token: Identifiable {
        let id: Int
        let display: String
        let word: String?
    }

    var body: some View {
        WordFlowLayout(hSpacing: 5, vSpacing: 3) {
            ForEach(Self.tokenize(text)) { token in
                if let word = token.word {
                    WordTokenView(
                        display: token.display,
                        word: word,
                        fontSize: fontSize,
                        isCurrent: isCurrent,
                        isSelected: selectedWord == word,
                        hideMode: hideMode,
                        onTap: { onWordTap(word) }
                    )
                } else {
                    Text(token.display)
                        .font(.system(size: fontSize))
                        .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                }
            }
        }
    }

    /// 分词：英文单词（含内部 ' 和 -）+ 附着其后的标点；其余为普通文本
    static func tokenize(_ text: String) -> [Token] {
        let pattern = "[A-Za-z]+(?:['’\\-][A-Za-z]+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [Token(id: 0, display: text, word: nil)]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var tokens: [Token] = []
        var cursor = 0
        var id = 0

        for m in matches {
            // 词前间隙
            if m.range.location > cursor {
                let gap = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let trimmed = gap.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if tokens.isEmpty {
                        tokens.append(Token(id: id, display: gap, word: nil)); id += 1
                    } else {
                        // 附着到前一个词
                        let prev = tokens.removeLast()
                        tokens.append(Token(id: prev.id, display: prev.display + gap, word: prev.word))
                    }
                }
            }
            let word = ns.substring(with: m.range)
            tokens.append(Token(id: id, display: word, word: word.lowercased()))
            id += 1
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            if !tail.trimmingCharacters(in: .whitespaces).isEmpty {
                if let prev = tokens.last, prev.word != nil {
                    _ = tokens.removeLast()
                    tokens.append(Token(id: prev.id, display: prev.display + tail, word: prev.word))
                } else {
                    tokens.append(Token(id: id, display: tail, word: nil))
                }
            }
        }
        return tokens
    }
}

private struct WordTokenView: View {
    let display: String
    let word: String
    let fontSize: CGFloat
    let isCurrent: Bool
    let isSelected: Bool
    var hideMode: TextHideMode = .normal
    let onTap: () -> Void

    @State private var isHovered = false

    /// 悬停/选中时可临时窥视（peek）
    private var revealed: Bool {
        hideMode == .normal || isHovered || isSelected
    }

    private var shownText: String {
        switch hideMode {
        case .normal, .blur, .hidden:
            return display
        case .initials:
            if revealed { return display }
            guard let first = word.first else { return display }
            return String(first) + String(repeating: "·", count: min(word.count - 1, 8))
        }
    }

    var body: some View {
        Text(shownText)
            .font(.system(size: fontSize))
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(
                isSelected ? Color.accentColor
                : (isCurrent ? Color.primary : Color.secondary)
            )
            .blur(radius: hideMode == .blur && !revealed ? 4 : 0)
            .underline(isHovered || isSelected)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: revealed)
    }
}

/// 简单流式布局：横向排列，超宽换行
struct WordFlowLayout: Layout {
    var hSpacing: CGFloat = 5
    var vSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - hSpacing)
                x = 0
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - hSpacing)
        return CGSize(
            width: proposal.width ?? max(0, maxLineWidth),
            height: y + lineHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
