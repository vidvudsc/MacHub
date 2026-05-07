import Foundation
import IOKit

// Read-only AppleSMC access adapted from the MIT-licensed SMCKit/BatFi SMC
// struct contract. MacHub only reads telemetry keys; it never writes SMC state.
struct SMCPowerDistribution: Equatable {
  var batteryPower: Double
  var externalPower: Double
  var systemPower: Double
}

final class AppleSMCPowerReader {
  private var connection: io_connect_t = 0

  deinit {
    close()
  }

  func powerDistribution() throws -> SMCPowerDistribution {
    try openIfNeeded()
    let batteryPower = try readFloat(key: "SBAP")
    let externalPower = try readFloat(key: "PDTR")
    let systemPower = (try? readFloat(key: "PSTR")) ?? batteryPower + externalPower
    return SMCPowerDistribution(
      batteryPower: normalizedPower(batteryPower),
      externalPower: max(normalizedPower(externalPower), 0),
      systemPower: normalizedPower(systemPower)
    )
  }

  private func openIfNeeded() throws {
    guard connection == 0 else { return }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != IO_OBJECT_NULL else {
      throw AppleSMCError.driverNotFound
    }
    defer { IOObjectRelease(service) }

    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard result == kIOReturnSuccess else {
      connection = 0
      throw AppleSMCError.openFailed(result)
    }
  }

  private func close() {
    if connection != 0 {
      IOServiceClose(connection)
      connection = 0
    }
  }

  private func readFloat(key: String) throws -> Double {
    let bytes = try readBytes(key: key, size: 4)
    var valueBytes = (bytes.0, bytes.1, bytes.2, bytes.3)
    let value = withUnsafeBytes(of: &valueBytes) {
      $0.load(as: Float.self)
    }
    return Double(value)
  }

  private func readBytes(key: String, size: UInt32) throws -> SMCBytes {
    var input = SMCParamStruct()
    input.key = fourCharCode(key)
    input.keyInfo.dataSize = size
    input.data8 = SMCParamStruct.Selector.readKey.rawValue

    return try callDriver(&input).bytes
  }

  private func callDriver(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
    assert(MemoryLayout<SMCParamStruct>.stride == 80)

    var output = SMCParamStruct()
    var outputSize = MemoryLayout<SMCParamStruct>.stride
    let result = IOConnectCallStructMethod(
      connection,
      UInt32(SMCParamStruct.Selector.handleYPCEvent.rawValue),
      &input,
      MemoryLayout<SMCParamStruct>.stride,
      &output,
      &outputSize
    )

    guard result == kIOReturnSuccess, output.result == SMCParamStruct.Result.success.rawValue else {
      if result == kIOReturnNotPrivileged {
        throw AppleSMCError.notPrivileged
      }
      if output.result == SMCParamStruct.Result.keyNotFound.rawValue {
        throw AppleSMCError.keyNotFound(key: input.keyString)
      }
      close()
      throw AppleSMCError.callFailed(kernReturn: result, smcResult: output.result)
    }
    return output
  }

  private func fourCharCode(_ string: String) -> UInt32 {
    string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private func normalizedPower(_ value: Double) -> Double {
    abs(value) < 0.01 ? 0 : value
  }
}

private enum AppleSMCError: Error {
  case driverNotFound
  case openFailed(kern_return_t)
  case keyNotFound(key: String)
  case notPrivileged
  case callFailed(kernReturn: kern_return_t, smcResult: UInt8)
}

private typealias SMCBytes = (
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
  enum Selector: UInt8 {
    case handleYPCEvent = 2
    case readKey = 5
  }

  enum Result: UInt8 {
    case success = 0
    case keyNotFound = 132
  }

  struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
  }

  struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
  }

  var key: UInt32 = 0
  var vers = SMCVersion()
  var pLimitData = SMCPLimitData()
  var keyInfo = SMCKeyInfoData()
  var padding: UInt16 = 0
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
  )

  var keyString: String {
    String(describing: UnicodeScalar((key >> 24) & 0xFF) ?? "?") +
      String(describing: UnicodeScalar((key >> 16) & 0xFF) ?? "?") +
      String(describing: UnicodeScalar((key >> 8) & 0xFF) ?? "?") +
      String(describing: UnicodeScalar(key & 0xFF) ?? "?")
  }
}
