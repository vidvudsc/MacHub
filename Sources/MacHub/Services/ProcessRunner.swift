import Foundation

enum ProcessRunner {
  static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval? = 6) async throws -> String {
    try await Task.detached(priority: .utility) {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: launchPath)
      process.arguments = arguments
      process.standardOutput = pipe
      process.standardError = Pipe()

      try process.run()

      if let timeout {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if process.isRunning {
          process.terminate()
          try? await Task.sleep(nanoseconds: 100_000_000)
          if process.isRunning {
            process.interrupt()
          }
        }
      }

      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8) ?? ""
    }.value
  }
}
