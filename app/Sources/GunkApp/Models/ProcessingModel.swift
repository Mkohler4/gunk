import Foundation
import Observation

@MainActor
@Observable
final class ProcessingModel {
  private let dockIconController: DockIconController
  private let gunkCount: () throws -> Int
  private var activeSourceIds = Set<Int64>()

  private(set) var isProcessing = false
  private(set) var progressBySource: [Int64: Double] = [:]
  private(set) var modulesFound = 0
  private(set) var errorMessage: String?
  /// Ordered names of the sources **waiting** to process behind the active run
  /// (library-v2 §2; T-9.4). Processing is strictly one-at-a-time: this never
  /// includes the running source — it is the queue depth the run panel reads
  /// for its "N waiting" / "next: <source>" copy. Owned by
  /// `SourceProcessingRunner`, which drives the serial queue.
  private(set) var waitingSourceNames: [String] = []
  /// Source-level failures, kept per row so the Sources list can disclose
  /// the error on the affected row (ux §3.1, D5). Cleared when that source
  /// begins a new run; `errorMessage` stays the run-level signal (D4).
  private(set) var errorsBySource: [Int64: String] = [:]

  init(
    dockIconController: DockIconController,
    gunkCount: @escaping () throws -> Int
  ) {
    self.dockIconController = dockIconController
    self.gunkCount = gunkCount
  }

  /// Number of sources queued behind the active run (library-v2 §2).
  var waitingCount: Int {
    waitingSourceNames.count
  }

  /// The next source that will process when the active run finishes, if any.
  var nextWaitingName: String? {
    waitingSourceNames.first
  }

  /// The serial queue (`SourceProcessingRunner`) publishes its waiting depth
  /// here so the one global run panel can show it without owning the queue.
  /// Independent of the `isProcessing` / `progressBySource` contract the
  /// run-end toast's store-diff summary (T-8.7) relies on.
  func setWaitingSourceNames(_ names: [String]) {
    waitingSourceNames = names
  }

  func begin(sourceId: Int64) {
    activeSourceIds.insert(sourceId)
    progressBySource[sourceId] = 0
    isProcessing = true
    errorMessage = nil
    errorsBySource.removeValue(forKey: sourceId)
    // Atomic state+badge apply (B2): a fresh run badges `modulesFound` (0) on
    // the processing icon in one pass, so the previous idle count never flashes.
    dockIconController.transition(to: .processing, badgeCount: modulesFound)
  }

  func update(sourceId: Int64, progress: Double, modulesFound: Int? = nil) {
    guard activeSourceIds.contains(sourceId) else {
      return
    }

    progressBySource[sourceId] = progress.clamped(to: 0...1)

    if let modulesFound {
      self.modulesFound = max(0, modulesFound)
    }

    dockIconController.transition(to: .processing, badgeCount: self.modulesFound)
  }

  func moduleFound(sourceId: Int64) {
    guard activeSourceIds.contains(sourceId) else {
      return
    }

    modulesFound += 1
    dockIconController.transition(to: .processing, badgeCount: modulesFound)
  }

  func complete(sourceId: Int64) {
    activeSourceIds.remove(sourceId)
    progressBySource.removeValue(forKey: sourceId)

    guard activeSourceIds.isEmpty else {
      dockIconController.transition(to: .processing, badgeCount: modulesFound)
      return
    }

    isProcessing = false
    modulesFound = 0
    refreshIdleDockState()
  }

  func fail(sourceId: Int64, error: Error) {
    activeSourceIds.remove(sourceId)
    progressBySource.removeValue(forKey: sourceId)
    errorMessage = error.localizedDescription
    errorsBySource[sourceId] = error.localizedDescription

    guard activeSourceIds.isEmpty else {
      dockIconController.transition(to: .processing, badgeCount: modulesFound)
      return
    }

    isProcessing = false
    modulesFound = 0

    do {
      dockIconController.reflectGunkCount(try gunkCount())
    } catch {
      dockIconController.setState(.empty)
      dockIconController.badge(count: 0)
    }
  }

  func refreshIdleDockState() {
    do {
      dockIconController.reflectGunkCount(try gunkCount())
      errorMessage = nil
    } catch {
      dockIconController.setState(.empty)
      dockIconController.badge(count: 0)
      errorMessage = error.localizedDescription
    }
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
