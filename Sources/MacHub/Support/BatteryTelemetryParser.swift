import Foundation

struct BatteryDetails: Equatable {
  var watts: Double?
  var voltage: Double?
  var amperage: Double?
  var temperature: Double?
  var cycleCount: Int?
  var health: String?
}

enum BatteryTelemetryParser {
  static func details(from output: String) -> BatteryDetails {
    let voltageMillivolts = integerValue(for: "AppleRawBatteryVoltage", in: output)
      ?? integerValue(for: "Voltage", in: output)
    let amperageMilliamps = signedIntegerValue(for: "InstantAmperage", in: output)
      ?? signedIntegerValue(for: "Amperage", in: output)
    let batteryPowerMilliwatts = signedIntegerValue(for: "BatteryPower", in: output)
    let cycleCount = integerValue(for: "CycleCount", in: output)
    let temperature = integerValue(for: "Temperature", in: output).map { Double($0) / 100 }
    let condition = stringValue(for: "BatteryHealth", in: output)
      ?? signedIntegerValue(for: "PermanentFailureStatus", in: output).map { $0 == 0 ? "Normal" : "Service recommended" }

    let voltage = voltageMillivolts.map { Double($0) / 1000 }
    let amperage = amperageMilliamps.map { Double($0) / 1000 }
    let watts: Double?
    if let batteryPowerMilliwatts {
      watts = Double(batteryPowerMilliwatts) / 1000
    } else if let voltage, let amperage {
      watts = voltage * amperage
    } else {
      watts = nil
    }

    return BatteryDetails(
      watts: watts,
      voltage: voltage,
      amperage: amperage,
      temperature: temperature,
      cycleCount: cycleCount,
      health: condition
    )
  }

  private static func integerValue(for key: String, in output: String) -> Int? {
    signedIntegerValue(for: key, in: output)
  }

  private static func signedIntegerValue(for key: String, in output: String) -> Int? {
    guard let raw = rawValue(for: key, in: output), !raw.isEmpty else { return nil }
    if raw.hasPrefix("-") {
      return Int(raw)
    }
    guard let unsigned = UInt64(raw) else { return Int(raw) }
    if unsigned > UInt64(Int64.max) {
      return Int(Int64(bitPattern: unsigned))
    }
    return Int(unsigned)
  }

  private static func stringValue(for key: String, in output: String) -> String? {
    guard
      let regex = try? NSRegularExpression(pattern: #""\#(NSRegularExpression.escapedPattern(for: key))"\s*=\s*"([^"]+)""#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)),
      let range = Range(match.range(at: 1), in: output)
    else {
      return nil
    }
    return String(output[range])
  }

  private static func rawValue(for key: String, in output: String) -> String? {
    guard
      let regex = try? NSRegularExpression(pattern: #""\#(NSRegularExpression.escapedPattern(for: key))"\s*=\s*(-?\d+)"#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)),
      let range = Range(match.range(at: 1), in: output)
    else {
      return nil
    }
    return String(output[range])
  }
}
