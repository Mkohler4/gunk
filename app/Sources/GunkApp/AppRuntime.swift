import AppKit
import Combine
import Foundation

extension Notification.Name {
  /// Posted when folders arrive through the Dock icon
  /// (`application(_:open:)` → `handleOpenURLs`) so the shell can navigate
  /// to Sources (ux §4.4, D1). The window raise stays in `AppDelegate`.
  static let sourcesArrivedViaOpen = Notification.Name("gunkSourcesArrivedViaOpen")
}

@MainActor
final class AppRuntime: ObservableObject {
  static let shared = AppRuntime()

  @Published private(set) var services: AppServices?
  @Published private(set) var launchError: String?

  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter
  private let sourceDetector: SourceDetector

  private init(
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default,
    sourceDetector: SourceDetector = SourceDetector()
  ) {
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
    self.sourceDetector = sourceDetector
    bootstrap()
  }

  func handleOpenURLs(_ urls: [URL]) {
    guard let services else {
      return
    }

    let directories = urls
      .map(\.standardizedFileURL)
      .filter(isDirectoryURL)

    guard !directories.isEmpty else {
      return
    }

    notificationCenter.post(name: .sourcesArrivedViaOpen, object: nil)

    do {
      for directory in directories {
        for sourceURL in try sourceDetector.detect(folder: directory) {
          let source = try services.store.insertSource(
            name: sourceURL.lastPathComponent,
            path: sourceURL.path
          )

          notificationCenter.post(name: .gunkInserted, object: source)
          process(source: source)
        }
      }
    } catch {
      NSApp.presentError(error)
    }
  }

  func process(source: Source) {
    guard let services else {
      return
    }

    Task {
      await services.sourceProcessingRunner.process(source: source)
    }
  }

  private func bootstrap() {
    do {
      let store = try Store(path: Store.defaultURL)
      let dockIconController = DockIconController()
      let processingModel = ProcessingModel(
        dockIconController: dockIconController,
        gunkCount: { try store.listGunks().count }
      )
      let sourceProcessingRunner = SourceProcessingRunner(
        store: store,
        processingModel: processingModel
      )
      let browseModel = BrowseModel(
        store: store,
        reclassifySource: { sourceId in
          guard let source = try store.source(id: sourceId) else {
            return
          }

          Task {
            await sourceProcessingRunner.process(source: source)
          }
        }
      )
      let sourceListModel = GunkListModel(store: store)
      let dropZoneHandler = DropZoneHandler(store: store) { [weak self] source in
        self?.process(source: source)
      }

      processingModel.refreshIdleDockState()

      services = AppServices(
        store: store,
        dockIconController: dockIconController,
        processingModel: processingModel,
        sourceProcessingRunner: sourceProcessingRunner,
        browseModel: browseModel,
        sourceListModel: sourceListModel,
        dropZoneHandler: dropZoneHandler
      )
      launchError = nil
    } catch {
      services = nil
      launchError = error.localizedDescription
      NSApp.presentError(error)
    }
  }

  private func isDirectoryURL(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

@MainActor
struct AppServices {
  let store: Store
  let dockIconController: DockIconController
  let processingModel: ProcessingModel
  let sourceProcessingRunner: SourceProcessingRunner
  let browseModel: BrowseModel
  let sourceListModel: GunkListModel
  let dropZoneHandler: DropZoneHandler
}
