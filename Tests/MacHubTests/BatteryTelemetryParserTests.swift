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
    XCTAssertEqual(details.watts ?? 0, -30.618, accuracy: 0.001)
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
}
