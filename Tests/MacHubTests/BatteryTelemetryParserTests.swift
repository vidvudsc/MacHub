import XCTest
@testable import MacHub

final class BatteryTelemetryParserTests: XCTestCase {
  func testParsesUnsignedWrappedDischargeTelemetry() {
    let output = """
    "AppleRawBatteryVoltage" = 11011
    "Amperage" = 18446744073709549009
    "PowerTelemetryData" = {"BatteryPower"=18446744073709520998}
    "CycleCount" = 542
    "Temperature" = 3060
    "PermanentFailureStatus" = 0
    """

    let details = BatteryTelemetryParser.details(from: output)

    XCTAssertEqual(details.voltage ?? 0, 11.011, accuracy: 0.001)
    XCTAssertEqual(details.amperage ?? 0, -2.607, accuracy: 0.001)
    XCTAssertEqual(details.watts ?? 0, -28.7, accuracy: 0.01)
    XCTAssertEqual(details.temperature ?? 0, 30.6, accuracy: 0.001)
    XCTAssertEqual(details.cycleCount, 542)
    XCTAssertEqual(details.health, "Normal")
  }

  func testFallsBackToVoltageTimesAmperageWhenBatteryPowerIsMissing() {
    let output = """
    "Voltage" = 12000
    "InstantAmperage" = -1500
    "BatteryHealth" = "Good"
    """

    let details = BatteryTelemetryParser.details(from: output)

    XCTAssertEqual(details.voltage ?? 0, 12.0, accuracy: 0.001)
    XCTAssertEqual(details.amperage ?? 0, -1.5, accuracy: 0.001)
    XCTAssertEqual(details.watts ?? 0, -18.0, accuracy: 0.001)
    XCTAssertEqual(details.health, "Good")
  }

  func testParsesStructuredRegistryProperties() {
    let properties: [String: Any] = [
      "Voltage": 11_049,
      "Amperage": -4_430,
      "PowerTelemetryData": [
        "BatteryPower": 16_980
      ],
      "CycleCount": 542,
      "Temperature": 3_060,
      "PermanentFailureStatus": 0
    ]

    let details = BatteryTelemetryParser.details(from: properties)

    XCTAssertEqual(details.voltage ?? 0, 11.049, accuracy: 0.001)
    XCTAssertEqual(details.amperage ?? 0, -4.43, accuracy: 0.001)
    XCTAssertEqual(details.watts ?? 0, -48.947, accuracy: 0.001)
    XCTAssertEqual(details.temperature ?? 0, 30.6, accuracy: 0.001)
    XCTAssertEqual(details.cycleCount, 542)
    XCTAssertEqual(details.health, "Normal")
  }
}
