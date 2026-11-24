import Foundation

enum OverlayLauncher {
    // The resident app outlives every overlay it starts. A Process must stay referenced until
    // its termination handler runs, otherwise finished overlays linger as zombies.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: Set<Process> = []

    static func launch(title: String, details: String, url: String, start: String) throws {
        try spawn(["--title", title, "--details", details, "--url", url, "--start", start])
    }

    static func launchPreview() throws {
        try spawn(["--preview"])
    }

    private static func spawn(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AgentPaths.overlayBinary)
        process.arguments = arguments
        process.terminationHandler = { finished in
            lock.lock()
            running.remove(finished)
            lock.unlock()
        }
        lock.lock()
        running.insert(process)
        lock.unlock()
        do {
            try process.run()
        } catch {
            lock.lock()
            running.remove(process)
            lock.unlock()
            throw error
        }
    }
}
