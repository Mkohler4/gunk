import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
  static let gunkInserted = Notification.Name("gunkInserted")
}

@MainActor
final class DropZoneHandler {
  private let store: Store
  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter
  private let processSource: (Source) -> Void

  init(
    store: Store,
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default,
    processSource: @escaping (Source) -> Void = { _ in }
  ) {
    self.store = store
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
    self.processSource = processSource
  }

  func filterDirectoryURLs(_ urls: [URL]) -> [URL] {
    urls.filter(isDirectoryURL)
  }

  @discardableResult
  func handleDrop(urls: [URL]) throws -> Bool {
    let directories = filterDirectoryURLs(urls)

    for directory in directories {
      let url = directory.standardizedFileURL
      let source = try store.insertSource(
        name: url.lastPathComponent,
        path: url.path
      )

      notificationCenter.post(name: .gunkInserted, object: source)
      processSource(source)
    }

    return !directories.isEmpty
  }

  private func isDirectoryURL(_ url: URL) -> Bool {
    guard url.isFileURL else {
      return false
    }

    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

/// The Sources hero: a glass drop target with branded idle/targeted states
/// (ux §3.1, D15 — constant position, no layout shift). Visual-only rebuild
/// of the old `DropZoneView`; the drop handling is unchanged.
struct BrandDropZone: View {
  let handler: DropZoneHandler

  @State private var isTargeted = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "folder.badge.plus")
        .font(BrandTypography.title)
        .foregroundStyle(isTargeted ? BrandColors.accent : BrandColors.textSecondary)

      Text("Drag folders here")
        .font(BrandTypography.headline)
        .foregroundStyle(isTargeted ? BrandColors.textPrimary : BrandColors.textSecondary)

      if let errorMessage {
        Text(errorMessage)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.danger)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(BrandMetrics.Spacing.lg)
    .brandGlass(cornerRadius: BrandMetrics.Radius.large, elevated: false)
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
        .strokeBorder(
          isTargeted ? BrandColors.accent : BrandColors.separator,
          style: StrokeStyle(
            lineWidth: BrandMetrics.Spacing.xs / 2,
            dash: [BrandMetrics.Spacing.sm, BrandMetrics.Spacing.xs]
          )
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
        .fill(BrandColors.accent.opacity(
          isTargeted ? BrandMetrics.Control.tintedFillOpacity : 0
        ))
        .allowsHitTesting(false)
    }
    .scaleEffect(isTargeted ? 2 - BrandMetrics.Control.pressedScale : 1)
    .animation(BrandMotion.settle, value: isTargeted)
    .contentShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
    .onDrop(
      of: [UTType.fileURL.identifier],
      isTargeted: $isTargeted,
      perform: receiveDrop
    )
    .accessibilityLabel("Drag folders here")
  }

  private func receiveDrop(providers: [NSItemProvider]) -> Bool {
    let fileURLProviders = providers.filter {
      $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    for provider in fileURLProviders {
      provider.loadItem(
        forTypeIdentifier: UTType.fileURL.identifier,
        options: nil
      ) { item, error in
        guard error == nil, let url = Self.fileURL(from: item) else {
          return
        }

        DispatchQueue.main.async {
          do {
            let inserted = try handler.handleDrop(urls: [url])
            errorMessage = inserted ? nil : "Only folders can be added."
          } catch {
            errorMessage = error.localizedDescription
          }
        }
      }
    }

    return !fileURLProviders.isEmpty
  }

  private static func fileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
      return url
    }

    if let url = item as? NSURL {
      return url as URL
    }

    if let data = item as? Data {
      return URL(dataRepresentation: data, relativeTo: nil)
    }

    return nil
  }
}
