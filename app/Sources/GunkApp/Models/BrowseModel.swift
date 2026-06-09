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

enum BrowseGroup: String, CaseIterable, Identifiable, Sendable {
  case tag
  case source
  case language
  case approval

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .tag:
      return "Tag"
    case .source:
      return "Source"
    case .language:
      return "Language"
    case .approval:
      return "Approval"
    }
  }
}

enum BrowseApprovalFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case autoAccepted
  case approved
  case needsApproval

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .all:
      return "All"
    case .autoAccepted:
      return "Auto accepted"
    case .approved:
      return "Approved"
    case .needsApproval:
      return "Needs approval"
    }
  }
}

struct BrowseFilters: Equatable, Sendable {
  var group: BrowseGroup = .tag
  var sourceId: Int64?
  var tag: String?
  var language: String?
  var approval: BrowseApprovalFilter = .all
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
  private(set) var availableSources: [Source] = []
  private(set) var availableTags: [String] = []
  private(set) var availableLanguages: [String] = []
  private(set) var errorMessage: String?
  var filters = BrowseFilters() {
    didSet {
      applyFilters()
    }
  }

  private var items: [BrowseItem] = []

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
      self.items = items
      approvalQueue = items
        .filter(isPendingApproval)
        .sorted(by: itemSort)
      availableSources = availableSources(from: items)
      availableTags = availableTags(from: items)
      availableLanguages = availableLanguages(from: items)
      sanitizeFilters()
      applyFilters()
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
      let groupNames: [String]
      switch filters.group {
      case .tag:
        groupNames = item.tags.isEmpty ? [Self.untaggedSection] : item.tags
      case .source:
        groupNames = [item.source.name]
      case .language:
        groupNames = [languageLabel(for: item)]
      case .approval:
        groupNames = [approvalLabel(for: item)]
      }

      for groupName in groupNames {
        buckets[groupName, default: []].append(item)
      }
    }

    return buckets
      .map { groupName, items in
        BrowseSection(tag: groupName, items: items.sorted(by: itemSort))
      }
      .sorted { lhs, rhs in
        lhs.tag.localizedStandardCompare(rhs.tag) == .orderedAscending
      }
  }

  private func applyFilters() {
    sections = groupedSections(from: filteredItems())
  }

  private func filteredItems() -> [BrowseItem] {
    items.filter { item in
      if let sourceId = filters.sourceId, item.source.id != sourceId {
        return false
      }

      if let tag = filters.tag, !item.tags.contains(tag) {
        return false
      }

      if let language = filters.language, item.gunk.language != language {
        return false
      }

      switch filters.approval {
      case .all:
        return true
      case .autoAccepted:
        return approvalFilter(for: item) == .autoAccepted
      case .approved:
        return approvalFilter(for: item) == .approved
      case .needsApproval:
        return approvalFilter(for: item) == .needsApproval
      }
    }
  }

  private func sanitizeFilters() {
    if let sourceId = filters.sourceId,
       !availableSources.contains(where: { $0.id == sourceId }) {
      filters.sourceId = nil
    }

    if let tag = filters.tag,
       !availableTags.contains(tag) {
      filters.tag = nil
    }

    if let language = filters.language,
       !availableLanguages.contains(language) {
      filters.language = nil
    }
  }

  private func availableSources(from items: [BrowseItem]) -> [Source] {
    Dictionary(grouping: items.map(\.source), by: \.id)
      .compactMap { _, sources in sources.first }
      .sorted { lhs, rhs in
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  private func availableTags(from items: [BrowseItem]) -> [String] {
    Array(Set(items.flatMap(\.tags)))
      .sorted { lhs, rhs in
        lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
  }

  private func availableLanguages(from items: [BrowseItem]) -> [String] {
    Array(Set(items.compactMap(\.gunk.language)))
      .sorted { lhs, rhs in
        lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
  }

  private func isPendingApproval(_ item: BrowseItem) -> Bool {
    (item.gunk.confidence ?? 0) < confidenceThreshold
      && item.gunk.approvedAt == nil
      && item.gunk.extractedAt == nil
  }

  func approvalFilter(for item: BrowseItem) -> BrowseApprovalFilter {
    if isPendingApproval(item) {
      return .needsApproval
    }

    if item.gunk.approvedAt != nil {
      return .approved
    }

    return .autoAccepted
  }

  func approvalLabel(for item: BrowseItem) -> String {
    approvalFilter(for: item).label
  }

  func extractionLabel(for item: BrowseItem) -> String {
    item.gunk.extractedAt == nil ? "Not extracted" : "Extracted"
  }

  func languageLabel(for item: BrowseItem) -> String {
    item.gunk.language ?? "Unknown language"
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
