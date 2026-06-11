import Observation

@MainActor
@Observable
final class GunkListModel {
  private let store: Store

  private(set) var sources: [Source] = []
  /// Modules produced per source, for the rows' "N modules" outcome slot
  /// (ux §3.1, D3).
  private(set) var moduleCountBySource: [Int64: Int] = [:]
  private(set) var errorMessage: String?

  init(store: Store) {
    self.store = store
  }

  func refresh() {
    do {
      try reload()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(id: Int64) {
    do {
      try store.removeSource(id: id)
      try reload()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func reload() throws {
    sources = try store.listSources()
    moduleCountBySource = Dictionary(grouping: try store.listGunks(), by: \.sourceId)
      .mapValues(\.count)
  }
}
