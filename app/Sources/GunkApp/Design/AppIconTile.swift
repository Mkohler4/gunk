import AppKit
import SwiftUI

/// The app icon: the static, export-sized form of `BrandMark` on the brand
/// icon tile (T-7.5). The mark is not re-drawn here — `BrandMark` stays the
/// single source; this view only composes it onto the macOS icon-grid tile
/// using the `BrandColors.Mark.tile*` art tokens.
struct AppIconTile: View {
  /// Canvas edge in pixels. macOS icon grid: a 824/1024 squircle centered on
  /// the canvas with ~185/1024 continuous corner radius.
  var size: CGFloat = 1024

  private var tileEdge: CGFloat { size * 824 / 1024 }
  private var cornerRadius: CGFloat { size * 185 / 1024 }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
          LinearGradient(
            colors: [BrandColors.Mark.tileTop, BrandColors.Mark.tileBottom],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: tileEdge, height: tileEdge)

      BrandMark(size: size * 0.62)
        // The mark's visual mass sits high on its 100pt canvas (body spans
        // y 8–85); nudge down so it reads centered on the tile.
        .offset(y: size * 0.015)
    }
    .frame(width: size, height: size)
  }
}

/// Dev-only export path for the icon artifacts. When the app is launched with
/// `GUNK_RENDER_APPICON=<directory>` it renders every `iconutil`-named PNG
/// into that directory and exits instead of running the UI (see `make icon`).
/// Mirrors the `GUNK_DESIGN_GALLERY` gating pattern — never part of normal
/// launches.
@MainActor
enum AppIconExporter {
  static let environmentFlag = "GUNK_RENDER_APPICON"

  /// All sizes required by `iconutil` and the `AppIcon.appiconset`.
  static let variants: [(filename: String, pixels: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
  ]

  /// Returns true when the export ran (the caller must not start the app).
  static func runIfRequested() -> Bool {
    guard
      let path = ProcessInfo.processInfo.environment[environmentFlag],
      !path.isEmpty
    else {
      return false
    }

    do {
      let directory = URL(fileURLWithPath: path, isDirectory: true)
      try export(to: directory)
      print("AppIcon: wrote \(variants.count) PNGs to \(directory.path)")
    } catch {
      FileHandle.standardError.write(Data("AppIcon export failed: \(error)\n".utf8))
      exit(1)
    }

    return true
  }

  static func export(to directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    for variant in variants {
      let renderer = ImageRenderer(content: AppIconTile(size: variant.pixels))
      renderer.scale = 1

      guard let cgImage = renderer.cgImage else {
        throw AppIconExportError.renderFailed(variant.filename)
      }

      let bitmap = NSBitmapImageRep(cgImage: cgImage)
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw AppIconExportError.encodeFailed(variant.filename)
      }

      let url = directory.appendingPathComponent("\(variant.filename).png")
      try png.write(to: url)
    }
  }
}

enum AppIconExportError: Error, CustomStringConvertible {
  case renderFailed(String)
  case encodeFailed(String)

  var description: String {
    switch self {
    case .renderFailed(let name):
      return "could not render \(name)"
    case .encodeFailed(let name):
      return "could not encode \(name) as PNG"
    }
  }
}

#Preview("App icon tile") {
  HStack(alignment: .bottom, spacing: BrandMetrics.Spacing.xl) {
    AppIconTile(size: 256)
    AppIconTile(size: 128)
    AppIconTile(size: 64)
    AppIconTile(size: 32)
    AppIconTile(size: 16)
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}
