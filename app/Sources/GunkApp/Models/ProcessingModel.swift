import Foundation
import Observation

struct CostMeterTotals: Equatable, Sendable {
  let inputTokens: Int64
  let outputTokens: Int64
  let costUsd: Double

  var totalTokens: Int64 {
    inputTokens + outputTokens
  }
}

struct CostMeterSnapshot: Equatable, Sendable {
  let today: CostMeterTotals
  let allTime: CostMeterTotals

  static let empty = CostMeterSnapshot(
    today: CostMeterTotals(inputTokens: 0, outputTokens: 0, costUsd: 0),
    allTime: CostMeterTotals(inputTokens: 0, outputTokens: 0, costUsd: 0)
  )
}

enum CostMeterAggregator {
  static func snapshot(
    runs: [LLMRun],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> CostMeterSnapshot {
    let todayStart = calendar.startOfDay(for: now)
    let todayStartMilliseconds = Int64(todayStart.timeIntervalSince1970 * 1_000)

    return CostMeterSnapshot(
      today: totals(for: runs.filter { $0.startedAt >= todayStartMilliseconds }),
      allTime: totals(for: runs)
    )
  }

  private static func totals(for runs: [LLMRun]) -> CostMeterTotals {
    CostMeterTotals(
      inputTokens: runs.reduce(0) { $0 + ($1.inputTokens ?? 0) },
      outputTokens: runs.reduce(0) { $0 + ($1.outputTokens ?? 0) },
      costUsd: runs.reduce(0) { $0 + ($1.costUsd ?? 0) }
    )
  }
}

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

  init(
    dockIconController: DockIconController,
    gunkCount: @escaping () throws -> Int
  ) {
    self.dockIconController = dockIconController
    self.gunkCount = gunkCount
  }

  func begin(sourceId: Int64) {
    activeSourceIds.insert(sourceId)
    progressBySource[sourceId] = 0
    isProcessing = true
    errorMessage = nil
    dockIconController.setState(.processing)
    dockIconController.badge(count: modulesFound)
  }

  func update(sourceId: Int64, progress: Double, modulesFound: Int? = nil) {
    guard activeSourceIds.contains(sourceId) else {
      return
    }

    progressBySource[sourceId] = progress.clamped(to: 0...1)

    if let modulesFound {
      self.modulesFound = max(0, modulesFound)
    }

    dockIconController.setState(.processing)
    dockIconController.badge(count: self.modulesFound)
  }

  func moduleFound(sourceId: Int64) {
    guard activeSourceIds.contains(sourceId) else {
      return
    }

    modulesFound += 1
    dockIconController.setState(.processing)
    dockIconController.badge(count: modulesFound)
  }

  func complete(sourceId: Int64) {
    activeSourceIds.remove(sourceId)
    progressBySource.removeValue(forKey: sourceId)

    guard activeSourceIds.isEmpty else {
      dockIconController.setState(.processing)
      dockIconController.badge(count: modulesFound)
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

    guard activeSourceIds.isEmpty else {
      dockIconController.setState(.processing)
      dockIconController.badge(count: modulesFound)
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
