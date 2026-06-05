import Foundation
import Observation

struct BrowseItem: Equatable, Identifiable, Sendable {
  let gunk: Gunk
  let source: Source
  let tags: [String]

  var id: Int64 {
    gunk.id
  }
}

struct BrowseSection: Equatable, Identifiable, Sendable {
  let tag: String
  let items: [BrowseItem]

  var id: String {
    tag
  }
}

@MainActor
@Observable
final class BrowseModel {
  typealias ExtractGunk = @MainActor (Gunk) throws -> Void
  typealias ReclassifySource = @MainActor (Int64) throws -> Void

  static let untaggedSection = "untagged"

  private let store: Store
  private let confidenceThreshold: Double
  private let extractGunk: ExtractGunk
  private let reclassifySource: ReclassifySource

  private(set) var sections: [BrowseSection] = []
  private(set) var approvalQueue: [BrowseItem] = []
  private(set) var errorMessage: String?

  init(
    store: Store,
    confidenceThreshold: Double = Extractor.defaultConfidenceThreshold,
    extractGunk: ExtractGunk? = nil,
    reclassifySource: @escaping ReclassifySource = { _ in }
  ) {
    self.store = store
    self.confidenceThreshold = confidenceThreshold
    self.extractGunk = extractGunk ?? { gunk in
      _ = try Extractor(
        store: store,
        confidenceThreshold: 0
      ).extract(gunk: gunk)
    }
    self.reclassifySource = reclassifySource
  }

  func refresh() {
    do {
      let items = try loadItems()
      approvalQueue = items
        .filter(isPendingApproval)
        .sorted(by: itemSort)
      sections = groupedSections(
        from: items.filter { !isPendingApproval($0) }
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func approve(gunkId: Int64) {
    do {
      try store.approveGunk(id: gunkId)

      if let approved = try store.gunk(id: gunkId) {
        try extractGunk(approved)
      }

      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(gunkId: Int64) {
    do {
      try store.removeGunk(id: gunkId)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func reject(gunkId: Int64) {
    delete(gunkId: gunkId)
  }

  func reclassify(sourceId: Int64) {
    do {
      try reclassifySource(sourceId)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func loadItems() throws -> [BrowseItem] {
    let sourcesById = Dictionary(uniqueKeysWithValues: try store.listSources().map { ($0.id, $0) })

    return try store.listGunks().compactMap { gunk in
      var source = sourcesById[gunk.sourceId]

      if source == nil {
        source = try store.source(id: gunk.sourceId)
      }

      guard let source else {
        return nil
      }

      return BrowseItem(
        gunk: gunk,
        source: source,
        tags: try store.listGunkTags(gunkId: gunk.id).map(\.tag)
      )
    }
  }

  private func groupedSections(from items: [BrowseItem]) -> [BrowseSection] {
    var buckets: [String: [BrowseItem]] = [:]

    for item in items {
      let tags = item.tags.isEmpty ? [Self.untaggedSection] : item.tags

      for tag in tags {
        buckets[tag, default: []].append(item)
      }
    }

    return buckets
      .map { tag, items in
        BrowseSection(tag: tag, items: items.sorted(by: itemSort))
      }
      .sorted { lhs, rhs in
        lhs.tag.localizedStandardCompare(rhs.tag) == .orderedAscending
      }
  }

  private func isPendingApproval(_ item: BrowseItem) -> Bool {
    (item.gunk.confidence ?? 0) < confidenceThreshold
      && item.gunk.approvedAt == nil
      && item.gunk.extractedAt == nil
  }

  private func itemSort(_ lhs: BrowseItem, _ rhs: BrowseItem) -> Bool {
    let lhsConfidence = lhs.gunk.confidence ?? 0
    let rhsConfidence = rhs.gunk.confidence ?? 0

    if lhsConfidence != rhsConfidence {
      return lhsConfidence > rhsConfidence
    }

    return lhs.gunk.name.localizedStandardCompare(rhs.gunk.name) == .orderedAscending
  }
}
