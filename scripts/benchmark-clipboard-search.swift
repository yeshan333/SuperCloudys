// 从仓库根目录编译并运行（Release 优化，不读写真实剪贴板或历史）：
// swiftc -O SuperCloudys/Clipboard/ClipboardEntry.swift SuperCloudys/Clipboard/ClipboardSearch.swift scripts/benchmark-clipboard-search.swift -o /tmp/clipboard-search-bench
// /tmp/clipboard-search-bench
import Foundation

@main
struct ClipboardSearchBenchmark {
    static func main() {
        for bytes in [1024, 65536] {
            let payload = String(repeating: "clipboard payload abcdefghijklmnopqrstuvwxyz 0123456789 ",
                                 count: bytes / 55 + 1)
            let entries = (0..<3000).map { i in
                ClipboardEntry(
                    id: UUID(), contentType: .text, plainText: "\(i) " + payload,
                    title: "Entry \(i)", subtitle: nil, createdAt: Date(),
                    sourceAppBundleID: "test", sourceAppName: "Bench", isPinned: false,
                    lastUsedAt: nil, fingerprint: "entry-\(i)", imagePath: nil,
                    thumbnailPath: nil, filePaths: nil, colorHex: nil
                )
            }
            for query in ["NO_MATCH_ZZZZZ", "0123456789"] {
                // 旧实现与新实现扫描同一份数据，校验结果和顺序一致。
                var expected: [ClipboardEntry] = []
                let baseline = elapsed {
                    expected = entries.filter {
                        $0.title.range(of: query, options: .caseInsensitive) != nil
                            || ($0.plainText?.range(of: query, options: .caseInsensitive) != nil)
                            || ($0.sourceAppName?.range(of: query, options: .caseInsensitive) != nil)
                    }
                }
                var samples: [Double] = []
                for _ in 0..<5 {
                    var actual: [ClipboardEntry]?
                    samples.append(elapsed { actual = ClipboardSearch.filter(entries, query: query) })
                    precondition(actual?.map(\.id) == expected.map(\.id))
                }
                let median = samples.sorted()[samples.count / 2]
                print(String(format: "3000 x ~%d bytes, %@: old=%.2f ms, new median=%.2f ms, speedup=%.1fx",
                             bytes, query, baseline, median, baseline / median))
                fflush(stdout)
            }
        }
    }

    private static func elapsed(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        autoreleasepool(invoking: body)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
