import Observation

@MainActor
@Observable
final class GunkListModel {
  private let store: Store

  private(set) var sources: [Source] = []
  private(set) var errorMessage: String?

  init(store: Store) {
    self.store = store
  }

  func refresh() {
    do {
      sources = try store.listSources()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(id: Int64) {
    do {
      try store.removeSource(id: id)
      sources = try store.listSources()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
