import Cocoa

enum CopyPathAction {

    static func execute(urls: [URL]) {
        let paths = urls.map { $0.path }
        let combined = paths.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(combined, forType: .string)
    }
}
