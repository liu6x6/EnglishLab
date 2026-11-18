import Foundation

/// 文本隐藏模式（听力训练）
enum TextHideMode: String, CaseIterable, Identifiable {
    case normal    // 正常显示
    case initials  // 首字母提示
    case blur      // 模糊隐藏
    case hidden    // 完全隐藏（盲听）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "正常显示"
        case .initials: return "首字母提示"
        case .blur: return "模糊隐藏"
        case .hidden: return "完全隐藏"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "eye"
        case .initials: return "textformat.abc"
        case .blur: return "eye.slash"
        case .hidden: return "eye.slash.fill"
        }
    }
}
