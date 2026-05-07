import Foundation

enum FullDiskAccessService {
  static func hasFullDiskAccess() -> Bool {
    let tccDatabase = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")

    do {
      let handle = try FileHandle(forReadingFrom: tccDatabase)
      try? handle.close()
      return true
    } catch {
      return false
    }
  }
}
