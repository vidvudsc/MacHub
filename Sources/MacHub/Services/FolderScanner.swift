import Foundation

struct FolderScanner {
  private let fileManager = FileManager.default

  func scanHomeFolders(onFolderScanned: @escaping (FolderUsage) async -> Void = { _ in }) async -> [FolderUsage] {
    let home = fileManager.homeDirectoryForCurrentUser
    let candidates = [
      "/Applications",
      "Downloads",
      "Desktop",
      "Documents",
      "Movies",
      "Pictures",
      "Music",
      "Library/Caches",
      "Library/Developer",
      "Library/Application Support"
    ]

    var results: [FolderUsage] = []
    for path in candidates {
      let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
      guard fileManager.fileExists(atPath: url.path) else { continue }
      let bytes = await sizeOf(url)
      let children = await largestChildren(in: url, limit: 12)
      let usage = FolderUsage(
        name: displayName(for: url, fallback: path),
        url: url,
        bytes: bytes,
        isDirectory: true,
        itemCount: children.count,
        children: children
      )
      results.append(usage)
      await onFolderScanned(usage)
    }
    return results.sorted { $0.bytes > $1.bytes }
  }

  func scanCleanupTargets() async -> [CleanupTarget] {
    let home = fileManager.homeDirectoryForCurrentUser
    let targets: [(String, String, URL, Bool, String)] = [
      ("User Caches", "App cache files that can usually be regenerated.", home.appendingPathComponent("Library/Caches"), true, "shippingbox"),
      ("Logs", "Diagnostic logs. Useful for debugging, disposable for most users.", home.appendingPathComponent("Library/Logs"), true, "doc.text.magnifyingglass"),
      ("Xcode DerivedData", "Build products and indexes from Xcode projects.", home.appendingPathComponent("Library/Developer/Xcode/DerivedData"), true, "hammer"),
      ("Xcode Archives", "Old app archives. Review before removing.", home.appendingPathComponent("Library/Developer/Xcode/Archives"), false, "archivebox"),
      ("SwiftPM Build Cache", "Swift package build artifacts in this project.", URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build"), true, "swift"),
      ("Downloads", "Files you downloaded. Review manually before cleaning.", home.appendingPathComponent("Downloads"), false, "arrow.down.circle"),
      ("Trash", "Files already moved to Trash.", home.appendingPathComponent(".Trash"), true, "trash")
    ]

    var results: [CleanupTarget] = []
    for target in targets {
      guard fileManager.fileExists(atPath: target.2.path) else { continue }
      results.append(CleanupTarget(
        title: target.0,
        detail: target.1,
        url: target.2,
        bytes: await sizeOf(target.2),
        isSafeToTrash: target.3,
        systemImage: target.4
      ))
    }
    return results.sorted { $0.bytes > $1.bytes }
  }

  func scanFolder(_ url: URL, limit: Int = 72) async -> FolderUsage {
    async let bytes = sizeOf(url)
    async let children = largestChildren(in: url, limit: limit)
    let resolvedBytes = await bytes
    let resolvedChildren = await children
    return FolderUsage(
      name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
      url: url,
      bytes: resolvedBytes,
      isDirectory: isDirectory(url),
      itemCount: resolvedChildren.count,
      children: resolvedChildren
    )
  }

  func largestChildren(in url: URL, limit: Int = 12) async -> [FolderUsage] {
    guard let urls = try? fileManager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
      options: []
    ) else {
      return []
    }

    var usages: [FolderUsage] = []
    for batch in Array(urls.prefix(limit)).chunked(into: 40) {
      let sizes = await sizesOf(batch)
      for child in batch {
        usages.append(FolderUsage(
          name: child.lastPathComponent,
          url: child,
          bytes: sizes[child.path] ?? 0,
          isDirectory: isDirectory(child)
        ))
      }
    }
    return Array(usages.sorted { $0.bytes > $1.bytes }.prefix(limit))
  }

  private func sizeOf(_ url: URL) async -> UInt64 {
    do {
      let output = try await ProcessRunner.run("/usr/bin/du", ["-sk", url.path], timeout: nil)
      guard let kb = UInt64(output.split(whereSeparator: \.isWhitespace).first ?? "") else {
        return fileSizeFallback(url)
      }
      return kb * 1024
    } catch {
      return fileSizeFallback(url)
    }
  }

  private func sizesOf(_ urls: ArraySlice<URL>) async -> [String: UInt64] {
    let paths = urls.map(\.path)
    guard !paths.isEmpty else { return [:] }

    do {
      let output = try await ProcessRunner.run("/usr/bin/du", ["-sk"] + paths, timeout: nil)
      var sizes: [String: UInt64] = [:]
      for line in output.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kb = UInt64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
        sizes[parts[1]] = kb * 1024
      }
      return sizes
    } catch {
      return Dictionary(uniqueKeysWithValues: urls.map { ($0.path, fileSizeFallback($0)) })
    }
  }

  private func fileSizeFallback(_ url: URL) -> UInt64 {
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
    return UInt64(values.fileSize ?? 0)
  }

  private func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
  }

  private func displayName(for url: URL, fallback: String) -> String {
    if fallback == "/Applications" {
      return "Applications"
    }
    if fallback.contains("/") {
      return fallback.replacingOccurrences(of: "Library/", with: "")
    }
    return url.lastPathComponent
  }
}

private extension Array {
  func chunked(into size: Int) -> [ArraySlice<Element>] {
    stride(from: 0, to: count, by: size).map {
      self[$0..<Swift.min($0 + size, count)]
    }
  }
}
