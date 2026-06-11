import AppKit
import SwiftUI

/// The app icon: the Ooze (`BrandMark`) centered on a dark glass tile —
/// nothing else. The mark is not re-drawn here; `BrandMark` stays the single
/// source. The tile uses the `BrandColors.Mark.darkTile*` art tokens with the
/// `BrandMetrics.Glass` sheen/stroke treatment.
///
/// The Dock runtime states reuse the same tile (no trash-can metaphor):
/// - `.empty` — muted mark.
/// - `.full` — the mark at full strength (the count badge carries the number).
/// - `.processing` — a soft accent glow behind the mark.
struct AppIconTile: View {
  enum TileState {
    case empty
    case full
    case processing
  }

  /// Canvas edge in pixels. macOS icon grid: a 824/1024 squircle centered on
  /// the canvas with ~185/1024 continuous corner radius.
  var size: CGFloat = 1024
  var state: TileState = .full

  private var tileEdge: CGFloat { size * 824 / 1024 }
  private var cornerRadius: CGFloat { size * 185 / 1024 }

  var body: some View {
    ZStack {
      tile

      if state == .processing {
        Circle()
          .fill(BrandColors.accent)
          .frame(width: size * 0.6, height: size * 0.6)
          .blur(radius: size * 0.07)
          .opacity(0.5)
      }

      BrandMark(size: size * 0.8)
        // The mark's visual mass sits high on its 100pt canvas; nudge down
        // so it reads centered on the tile.
        .offset(y: size * 0.02)
        .opacity(state == .empty ? 0.55 : 1)
    }
    .frame(width: size, height: size)
  }

  private var tile: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return shape
      .fill(
        LinearGradient(
          colors: [BrandColors.Mark.darkTileTop, BrandColors.Mark.darkTileBottom],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      // Glass treatment: top sheen + inner hairline, from the Glass tokens.
      .overlay(
        shape.fill(
          LinearGradient(
            colors: [
              .white.opacity(BrandMetrics.Glass.sheenOpacity),
              .clear,
            ],
            startPoint: .top,
            endPoint: .center
          )
        )
      )
      .overlay(
        shape.strokeBorder(
          .white.opacity(BrandMetrics.Glass.strokeOpacity * 2),
          lineWidth: max(1, size / 256)
        )
      )
      .frame(width: tileEdge, height: tileEdge)
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
      try write(
        AppIconTile(size: variant.pixels),
        to: directory.appendingPathComponent("\(variant.filename).png"),
        name: variant.filename
      )
    }
  }

  static func write(
    _ content: AppIconTile,
    to url: URL,
    name: String
  ) throws {
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1

    guard let cgImage = renderer.cgImage else {
      throw AppIconExportError.renderFailed(name)
    }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw AppIconExportError.encodeFailed(name)
    }

    try png.write(to: url)
  }
}

/// Dev-only export of the Dock-state PNGs, mirroring `AppIconExporter`. When
/// the app is launched with `GUNK_RENDER_DOCKBIN=<directory>` it writes the
/// three state assets and exits (see `make icon`). The `DockBin*` asset and
/// file names are kept so `DockIconController` is untouched.
@MainActor
enum DockBinExporter {
  static let environmentFlag = "GUNK_RENDER_DOCKBIN"

  static let variants: [(filename: String, state: AppIconTile.TileState)] = [
    ("dock-bin-empty", .empty),
    ("dock-bin-full", .full),
    ("dock-bin-processing", .processing),
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
      print("DockBin: wrote \(variants.count) PNGs to \(directory.path)")
    } catch {
      FileHandle.standardError.write(Data("DockBin export failed: \(error)\n".utf8))
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
      try AppIconExporter.write(
        AppIconTile(size: 1024, state: variant.state),
        to: directory.appendingPathComponent("\(variant.filename).png"),
        name: variant.filename
      )
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

#Preview("App icon — sizes") {
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

#Preview("Dock states") {
  HStack(spacing: BrandMetrics.Spacing.xl) {
    VStack(spacing: BrandMetrics.Spacing.sm) {
      AppIconTile(size: 128, state: .empty)
      Text("empty").font(BrandTypography.caption)
    }
    VStack(spacing: BrandMetrics.Spacing.sm) {
      AppIconTile(size: 128, state: .full)
      Text("full").font(BrandTypography.caption)
    }
    VStack(spacing: BrandMetrics.Spacing.sm) {
      AppIconTile(size: 128, state: .processing)
      Text("processing").font(BrandTypography.caption)
    }
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}
