import Foundation

/// 词形还原：给出按优先级排序的候选原形列表（第一个永远是原词）
public protocol WordNormalizer: Sendable {
    func candidates(for word: String) -> [String]
}

public struct RuleBasedWordNormalizer: WordNormalizer {

    /// 常见不规则变形表
    static let irregulars: [String: String] = [
        "went": "go", "gone": "go", "goes": "go",
        "did": "do", "done": "do", "does": "do",
        "was": "be", "were": "be", "is": "be", "are": "be", "am": "be", "been": "be",
        "had": "have", "has": "have",
        "children": "child", "men": "man", "women": "woman",
        "feet": "foot", "teeth": "tooth", "mice": "mouse", "geese": "goose",
        "people": "person", "better": "good", "best": "good", "worse": "bad", "worst": "bad",
        "said": "say", "made": "make", "took": "take", "taken": "take",
        "came": "come", "saw": "see", "seen": "see", "knew": "know", "known": "know",
        "got": "get", "gotten": "get", "thought": "think", "brought": "bring",
        "bought": "buy", "caught": "catch", "taught": "teach", "felt": "feel",
        "kept": "keep", "left": "leave", "lost": "lose", "meant": "mean",
        "met": "meet", "paid": "pay", "ran": "run", "sold": "sell", "sent": "send",
        "spoke": "speak", "spoken": "speak", "told": "tell", "understood": "understand",
        "wore": "wear", "worn": "wear", "won": "win", "wrote": "write", "written": "write",
        "ate": "eat", "eaten": "eat", "began": "begin", "begun": "begin",
        "drank": "drink", "drunk": "drink", "drove": "drive", "driven": "drive",
        "fell": "fall", "fallen": "fall", "flew": "fly", "flown": "fly",
        "forgot": "forget", "forgotten": "forget", "gave": "give", "given": "give",
        "grew": "grow", "grown": "grow", "heard": "hear", "held": "hold",
        "led": "lead", "rode": "ride", "ridden": "ride", "rose": "rise",
        "sat": "sit", "sang": "sing", "sung": "sing", "slept": "sleep",
        "swam": "swim", "swum": "swim", "threw": "throw", "thrown": "throw",
        "woke": "wake", "woken": "wake", "found": "find", "built": "build",
        "spent": "spend", "lent": "lend", "bent": "bend", "dealt": "deal",
        "dreamt": "dream", "learnt": "learn", "lit": "light", "shot": "shoot",
        "stood": "stand", "stuck": "stick", "struck": "strike", "swept": "sweep",
        "wept": "weep", "wound": "wind", "hung": "hang", "dug": "dig",
        "fed": "feed", "fled": "flee", "fought": "fight", "laid": "lay",
        "lain": "lie", "lay": "lie", "sought": "seek", "shone": "shine",
        "slid": "slide", "spun": "spin", "split": "split", "spread": "spread",
        "stole": "steal", "stolen": "steal", "swore": "swear", "sworn": "swear",
        "tore": "tear", "torn": "tear", "withdrew": "withdraw", "withdrawn": "withdraw"
    ]

    public init() {}

    public func candidates(for word: String) -> [String] {
        let w = word.lowercased()
        var result: [String] = [w]

        func add(_ s: String) {
            if s.count >= 2, !result.contains(s) { result.append(s) }
        }

        if let irr = Self.irregulars[w] { add(irr) }

        // 复数 / 三单
        if w.hasSuffix("ies"), w.count > 4 {
            add(String(w.dropLast(3)) + "y")   // studies -> study
            add(String(w.dropLast(3)) + "ie")  // dies -> die
        }
        if w.hasSuffix("ves"), w.count > 4 {
            add(String(w.dropLast(3)) + "f")   // leaves -> leaf
            add(String(w.dropLast(3)) + "fe")  // knives -> knife
        }
        if w.hasSuffix("es"), w.count > 3 {
            let stem = String(w.dropLast(2))
            if stem.hasSuffix("s") || stem.hasSuffix("x") || stem.hasSuffix("z")
                || stem.hasSuffix("ch") || stem.hasSuffix("sh") {
                add(stem)                       // boxes -> box, watches -> watch
            }
            add(stem)                           // goes -> go
        }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is"), w.count > 3 {
            add(String(w.dropLast()))           // cats -> cat, makes -> make
        }

        // 过去式 / 过去分词
        if w.hasSuffix("ied"), w.count > 4 {
            add(String(w.dropLast(3)) + "y")   // tried -> try
            add(String(w.dropLast(3)) + "ie")  // died -> die
        }
        if w.hasSuffix("ed"), w.count > 3 {
            let stem = String(w.dropLast(2))
            add(stem)                           // walked -> walk
            add(stem + "e")                     // liked -> like
            if let last = stem.last, stem.count >= 3, Self.isConsonant(last),
               let prev = stem.dropLast().last, prev == last {
                add(String(stem.dropLast()))    // stopped -> stop
            }
        }

        // 进行时
        if w.hasSuffix("ing"), w.count > 4 {
            let stem = String(w.dropLast(3))
            add(stem)                           // going -> go
            add(stem + "e")                     // making -> make
            if let last = stem.last, stem.count >= 3, Self.isConsonant(last),
               let prev = stem.dropLast().last, prev == last {
                add(String(stem.dropLast()))    // running -> run
            }
        }

        // 比较级 / 最高级
        if w.hasSuffix("ier"), w.count > 4 { add(String(w.dropLast(3)) + "y") } // happier -> happy
        if w.hasSuffix("er"), w.count > 4 {
            let stem = String(w.dropLast(2))
            add(stem)
            add(stem + "e")                     // nicer -> nice
            if let last = stem.last, stem.count >= 3, Self.isConsonant(last),
               let prev = stem.dropLast().last, prev == last {
                add(String(stem.dropLast()))    // bigger -> big
            }
        }
        if w.hasSuffix("iest"), w.count > 5 { add(String(w.dropLast(4)) + "y") }
        if w.hasSuffix("est"), w.count > 5 {
            let stem = String(w.dropLast(3))
            add(stem)
            add(stem + "e")
            if let last = stem.last, stem.count >= 3, Self.isConsonant(last),
               let prev = stem.dropLast().last, prev == last {
                add(String(stem.dropLast()))
            }
        }

        return result
    }

    static func isConsonant(_ c: Character) -> Bool {
        c.isLetter && !"aeiou".contains(c)
    }
}
