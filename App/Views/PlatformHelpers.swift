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
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 原生文档选择器（比 SwiftUI fileImporter 可靠；asCopy 免去安全作用域处理）
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let multiple: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
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
