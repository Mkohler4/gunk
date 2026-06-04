import Foundation

struct DetectedLicense: Equatable, Sendable {
  let detected: String
  let warning: String?
}

final class LicenseDetector {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func detect(sourceRoot: URL) throws -> DetectedLicense {
    guard let licenseURL = try topLevelLicenseFile(in: sourceRoot) else {
      return DetectedLicense(detected: "unknown", warning: nil)
    }

    let contents = try String(contentsOf: licenseURL, encoding: .utf8)
    let detected = spdxIdentifier(for: contents)
    let warning = isRestrictive(detected)
      ? "Restrictive source license detected: \(detected). Reuse may require extra review."
      : nil

    return DetectedLicense(detected: detected, warning: warning)
  }

  private func topLevelLicenseFile(in sourceRoot: URL) throws -> URL? {
    let children = try fileManager.contentsOfDirectory(
      at: sourceRoot,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )

    return children.first { url in
      let name = url.lastPathComponent.lowercased()
      return name == "license"
        || name.hasPrefix("license.")
        || name == "copying"
        || name.hasPrefix("copying.")
    }
  }

  private func spdxIdentifier(for contents: String) -> String {
    let uppercased = contents.uppercased()

    if uppercased.contains("GNU AFFERO GENERAL PUBLIC LICENSE") {
      return versionedGPL(prefix: "AGPL", contents: uppercased)
    }
    if uppercased.contains("GNU LESSER GENERAL PUBLIC LICENSE") {
      return versionedGPL(prefix: "LGPL", contents: uppercased)
    }
    if uppercased.contains("GNU GENERAL PUBLIC LICENSE") {
      return versionedGPL(prefix: "GPL", contents: uppercased)
    }
    if uppercased.contains("APACHE LICENSE") {
      return "Apache-2.0"
    }
    if uppercased.contains("MIT LICENSE") || uppercased.contains("PERMISSION IS HEREBY GRANTED") {
      return "MIT"
    }
    if uppercased.contains("BSD 3-CLAUSE") {
      return "BSD-3-Clause"
    }
    if uppercased.contains("BSD 2-CLAUSE") {
      return "BSD-2-Clause"
    }
    if uppercased.contains("ISC LICENSE") {
      return "ISC"
    }
    if uppercased.contains("MOZILLA PUBLIC LICENSE") {
      return "MPL-2.0"
    }

    return "unknown"
  }

  private func versionedGPL(prefix: String, contents: String) -> String {
    if contents.contains("VERSION 3") {
      return "\(prefix)-3.0-or-later"
    }
    if contents.contains("VERSION 2") {
      return "\(prefix)-2.0-or-later"
    }

    return prefix
  }

  private func isRestrictive(_ identifier: String) -> Bool {
    identifier.hasPrefix("GPL")
      || identifier.hasPrefix("AGPL")
      || identifier.hasPrefix("LGPL")
  }
}
