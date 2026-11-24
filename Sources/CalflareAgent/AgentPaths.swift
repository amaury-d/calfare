import Foundation

enum AgentPaths {
    static let appContents = Bundle.main.bundleURL.appendingPathComponent("Contents")
    static let overlayBinary = appContents.appendingPathComponent("MacOS/CalflareOverlay").path
    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Calflare")
    static let configURL = dataDirectory.appendingPathComponent("config.json")
    static let stateURL = dataDirectory.appendingPathComponent("alerted-events.txt")
    static let lockURL = dataDirectory.appendingPathComponent("calflare.lock")
}

func log(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}
