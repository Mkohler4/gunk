import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
  static let gunkInserted = Notification.Name("gunkInserted")
}

final class DropZoneHandler {
  private let store: Store
  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter

  init(
    store: Store,
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default
  ) {
    self.store = store
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
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

struct DropZoneView: View {
  let handler: DropZoneHandler

  @State private var isTargeted = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "folder.badge.plus")
        .font(.system(size: 28))
        .foregroundStyle(isTargeted ? .green : .secondary)

      Text("Drag folders here")
        .font(.headline)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
    .background(isTargeted ? Color.green.opacity(0.12) : Color.clear)
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          isTargeted ? Color.green : Color.secondary.opacity(0.6),
          style: StrokeStyle(lineWidth: 2, dash: [7, 5])
        )
    }
    .contentShape(Rectangle())
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
