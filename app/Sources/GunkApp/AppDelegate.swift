import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var dockIconController: DockIconController?
  private var menubarController: MenubarController?
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
      dockIconController.reflectGunkCount(try store.listGunks().count)

      self.store = store
      self.dockIconController = dockIconController
      menubarController = MenubarController(store: store)
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
      dockIconController?.setState(.processing)
      defer { refreshDockIcon(store: store) }

      for directory in directories {
        for sourceURL in try sourceDetector.detect(folder: directory) {
          let source = try store.insertSource(
            name: sourceURL.lastPathComponent,
            path: sourceURL.path
          )

          notificationCenter.post(name: .gunkInserted, object: source)
          enqueueDecomposition(for: source)
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

  private func refreshDockIcon(store: Store) {
    do {
      dockIconController?.reflectGunkCount(try store.listGunks().count)
    } catch {
      dockIconController?.setState(.empty)
      NSApp.presentError(error)
    }
  }

  private func isDirectoryURL(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func enqueueDecomposition(for source: Source) {
    // T-3.9 wires the real decomposition engine here.
    _ = source
  }
}
