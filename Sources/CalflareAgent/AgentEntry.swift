import AppKit

@main
struct CalflareAgentEntry {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let oneShot: Set<String> = ["--test", "--list", "--list-calendars", "--once"]
        if arguments.contains(where: oneShot.contains) {
            AgentCLI.run(arguments)  // never returns
        }
        MenuBarController.runResident()
    }
}
