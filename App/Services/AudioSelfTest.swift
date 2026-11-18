import Foundation

/// 自检钩子：--selftest-audio <url>（验证发音下载缓存：首次下载、二次命中）
enum AudioSelfTest {
    static func run(urlString: String) async {
        guard let url = URL(string: urlString) else {
            print("SELFTEST AUDIO FAILED: 无效 URL")
            exit(1)
        }
        let t0 = Date()
        guard let first = await AudioCache.shared.localURL(for: url) else {
            print("SELFTEST AUDIO FAILED: 首次下载失败")
            exit(1)
        }
        let downloadTime = Date().timeIntervalSince(t0)
        guard FileManager.default.fileExists(atPath: first.path) else {
            print("SELFTEST AUDIO FAILED: 缓存文件不存在")
            exit(1)
        }
        let t1 = Date()
        guard let second = await AudioCache.shared.localURL(for: url) else {
            print("SELFTEST AUDIO FAILED: 二次读取失败")
            exit(1)
        }
        let cacheTime = Date().timeIntervalSince(t1)
        precondition(first == second, "两次应返回同一缓存文件")
        precondition(cacheTime < 0.1, "缓存命中应 <0.1s，实际 \(cacheTime)")
        let size = (try? FileManager.default.attributesOfItem(atPath: first.path)[.size] as? Int) ?? 0
        print(String(format: "SELFTEST AUDIO OK: download %.2fs → cache %.4fs, %d bytes",
                     downloadTime, cacheTime, size ?? 0))
        exit(0)
    }
}
