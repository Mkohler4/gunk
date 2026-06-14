import Foundation

/// Resolves which provider · model extracted a module from `RunTrace` data —
/// gunk-id first, then the module's source's most recent trace. This is the
/// single source of the trace-derived resolution; both `BrowseModel` (the
/// view-time fallback) and `ProvenanceBackfill` (the one-time store write)
/// read it, so the durable value and the fallback can never use different
/// rules. Traces are expected newest-run-first (`RunTraceStore.recentTraces`),
/// so first-wins below means "most recent run".
struct RunTraceProvenanceIndex: Sendable {
  private var byGunkId: [Int64: BrowseProvenance] = [:]
  private var bySourceId: [Int64: BrowseProvenance] = [:]

  init(traces: [RunTrace]) {
    for trace in traces {
      let provenance = BrowseProvenance(provider: trace.provider, model: trace.model)

      if let sourceId = trace.sourceId, bySourceId[sourceId] == nil {
        bySourceId[sourceId] = provenance
      }

      for gunkId in trace.summary.gunkIds where byGunkId[gunkId] == nil {
        byGunkId[gunkId] = provenance
      }
    }
  }

  func provenance(gunkId: Int64, sourceId: Int64?) -> BrowseProvenance? {
    if let provenance = byGunkId[gunkId] {
      return provenance
    }

    if let sourceId, let provenance = bySourceId[sourceId] {
      return provenance
    }

    return nil
  }
}

/// One-time durable attribution backfill (T-9.2): for every stored module that
/// predates the `provider`/`model` columns, resolve its provenance from the
/// same `RunTrace` data `BrowseModel` shows and persist it — so today's library
/// isn't blank-attribution after the v5 upgrade. Modules with no resolvable
/// trace stay `NULL` (they render the neutral mark). Runs lazily on open rather
/// than blocking launch; idempotent — only ever fills `NULL`s.
enum ProvenanceBackfill {
  @discardableResult
  static func run(store: Store, traces: [RunTrace]) throws -> Int {
    let index = RunTraceProvenanceIndex(traces: traces)
    var backfilled = 0

    for gunk in try store.listGunks() where gunk.provider == nil {
      guard let provenance = index.provenance(gunkId: gunk.id, sourceId: gunk.sourceId) else {
        continue
      }

      try store.setGunkProvenance(
        gunkId: gunk.id,
        provider: provenance.provider,
        model: provenance.model
      )
      backfilled += 1
    }

    return backfilled
  }
}
