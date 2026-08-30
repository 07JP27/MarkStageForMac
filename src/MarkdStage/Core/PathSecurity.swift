import Foundation

enum PathSecurity {
    static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isFileURL(_ fileURL: URL, containedIn folderURL: URL) -> Bool {
        let folderPath = canonicalURL(folderURL).path
        let filePath = canonicalURL(fileURL).path
        if filePath == folderPath { return true }
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return filePath.hasPrefix(prefix)
    }

    static func resolveFile(in rootURL: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0"),
              !relativePath.split(separator: "/").contains("..")
        else {
            return nil
        }
        let candidate = canonicalURL(
            rootURL.appendingPathComponent(
                relativePath.removingPercentEncoding ?? relativePath,
                isDirectory: false
            )
        )
        var isDirectory: ObjCBool = false
        guard isFileURL(candidate, containedIn: rootURL),
              FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }
        return candidate
    }
}
