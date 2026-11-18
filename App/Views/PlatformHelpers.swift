import SwiftUI

// MARK: - 跨平台 View 修饰

extension View {
    /// 三栏列宽（仅 macOS 生效）
    @ViewBuilder
    func columnWidth(min: CGFloat, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        #if os(macOS)
        if let max {
            self.navigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
        } else {
            self.navigationSplitViewColumnWidth(min: min, ideal: ideal)
        }
        #else
        self
        #endif
    }

    /// 无边框菜单样式（macOS borderlessButton，iOS 默认）
    @ViewBuilder
    func adaptiveMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }

    /// sheet 尺寸：macOS 固定，iOS 全屏自适应
    @ViewBuilder
    func sheetFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    /// 最小 sheet 尺寸（macOS 固定最小值，iOS 自适应）
    @ViewBuilder
    func sheetMinFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

// MARK: - iOS 分享面板（导出用）

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - 跨平台剪贴板

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif
