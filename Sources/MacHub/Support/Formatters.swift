import Foundation

enum Formatters {
  static let bytes: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
  }()

  static let memoryBytes: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    formatter.countStyle = .memory
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
  }()

  static let percent: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  static func bytes(_ value: UInt64) -> String {
    bytes.string(fromByteCount: Int64(value))
  }

  static func memory(_ value: UInt64) -> String {
    memoryBytes.string(fromByteCount: Int64(value))
  }

  static func percent(_ value: Double) -> String {
    percent.string(from: NSNumber(value: value)) ?? "0%"
  }

  static func watts(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return String(format: "%+.1f W", value)
  }

  static func volts(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return String(format: "%.2f V", value)
  }

  static func amps(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return String(format: "%+.2f A", value)
  }

  static func celsius(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return String(format: "%.1f C", value)
  }

  static func duration(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds / 3600)
    let days = hours / 24
    if days > 0 { return "\(days)d \(hours % 24)h" }
    return "\(hours)h \(Int(seconds / 60) % 60)m"
  }

  static func minutes(_ minutes: Int?) -> String {
    guard let minutes else { return "Calculating" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes)m"
  }
}
