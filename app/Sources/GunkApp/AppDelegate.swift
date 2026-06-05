import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var dockIconController: DockIconController?
  private var processingModel: ProcessingModel?
  private var menubarController: MenubarController?
  private var sourceProcessingRunner: SourceProcessingRunner?
  private var store: Store?
  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter
  private let sourceDetector: SourceDetector

  init(
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default,
    sourceDetector: SourceDetector = SourceDetector()
  ) {
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
    self.sourceDetector = sourceDetector
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)

    do {
      let store = try Store(path: Store.defaultURL)
      let dockIconController = DockIconController()
      let processingModel = ProcessingModel(
        dockIconController: dockIconController,
        gunkCount: { try store.listGunks().count }
      )
      processingModel.refreshIdleDockState()

      self.store = store
      self.dockIconController = dockIconController
      self.processingModel = processingModel
      let sourceProcessingRunner = SourceProcessingRunner(
        store: store,
        processingModel: processingModel
      )
      self.sourceProcessingRunner = sourceProcessingRunner
      menubarController = MenubarController(
        store: store,
        processingModel: processingModel,
        sourceProcessingRunner: sourceProcessingRunner
      )
    } catch {
      NSApp.presentError(error)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    let directories = urls
      .map(\.standardizedFileURL)
      .filter(isDirectoryURL)

    guard !directories.isEmpty else {
      return
    }

    do {
      let store = try activeStore()
      let processingModel = try activeProcessingModel(store: store)
      let sourceProcessingRunner = activeSourceProcessingRunner(
        store: store,
        processingModel: processingModel
      )

      for directory in directories {
        for sourceURL in try sourceDetector.detect(folder: directory) {
          let source = try store.insertSource(
            name: sourceURL.lastPathComponent,
            path: sourceURL.path
          )

          notificationCenter.post(name: .gunkInserted, object: source)
          Task {
            await sourceProcessingRunner.process(source: source)
          }
        }
      }
    } catch {
      NSApp.presentError(error)
    }
  }

  private func activeStore() throws -> Store {
    if let store {
      return store
    }

    let store = try Store(path: Store.defaultURL)
    self.store = store
    return store
  }

  private func activeProcessingModel(store: Store) throws -> ProcessingModel {
    if let processingModel {
      return processingModel
    }

    let dockIconController = dockIconController ?? DockIconController()
    self.dockIconController = dockIconController

    let processingModel = ProcessingModel(
      dockIconController: dockIconController,
      gunkCount: { try store.listGunks().count }
    )
    self.processingModel = processingModel
    return processingModel
  }

  private func activeSourceProcessingRunner(
    store: Store,
    processingModel: ProcessingModel
  ) -> SourceProcessingRunner {
    if let sourceProcessingRunner {
      return sourceProcessingRunner
    }

    let sourceProcessingRunner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel
    )
    self.sourceProcessingRunner = sourceProcessingRunner
    return sourceProcessingRunner
  }

  private func isDirectoryURL(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

}
