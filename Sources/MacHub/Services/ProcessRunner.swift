import Foundation

enum ProcessRunnerError: Error, LocalizedError {
  case nonZeroExit(launchPath: String, arguments: [String], status: Int32, stderr: String)
  case timedOut(launchPath: String, arguments: [String], timeout: TimeInterval)

  var errorDescription: String? {
    switch self {
    case let .nonZeroExit(launchPath, arguments, status, stderr):
      let command = ([launchPath] + arguments).joined(separator: " ")
      return "\(command) exited with status \(status): \(stderr)"
    case let .timedOut(launchPath, arguments, timeout):
      let command = ([launchPath] + arguments).joined(separator: " ")
      return "\(command) timed out after \(timeout)s"
    }
  }
}

enum ProcessRunner {
  static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval? = 6) async throws -> String {
    try await Task.detached(priority: .utility) {
      let process = Process()
      let stdout = Pipe()
      let stderr = Pipe()
      process.executableURL = URL(fileURLWithPath: launchPath)
      process.arguments = arguments
      process.standardOutput = stdout
      process.standardError = stderr

      try process.run()

      var didTimeOut = false
      if let timeout {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if process.isRunning {
          didTimeOut = true
          process.terminate()
          try? await Task.sleep(nanoseconds: 100_000_000)
          if process.isRunning {
            process.interrupt()
          }
        }
      }

      process.waitUntilExit()

      let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
      let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: outputData, encoding: .utf8) ?? ""
      let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

      if didTimeOut, let timeout {
        throw ProcessRunnerError.timedOut(launchPath: launchPath, arguments: arguments, timeout: timeout)
      }
      guard process.terminationStatus == 0 else {
        throw ProcessRunnerError.nonZeroExit(
          launchPath: launchPath,
          arguments: arguments,
          status: process.terminationStatus,
          stderr: errorOutput
        )
      }
      return output
    }.value
  }
}
