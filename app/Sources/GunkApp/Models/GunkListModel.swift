import Observation

@MainActor
@Observable
final class GunkListModel {
  private let store: Store

  private(set) var gunks: [Gunk] = []
  private(set) var errorMessage: String?

  init(store: Store) {
    self.store = store
  }

  func refresh() {
    do {
      gunks = try store.listGunks()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(id: Int64) {
    do {
      try store.removeGunk(id: id)
      gunks = try store.listGunks()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
