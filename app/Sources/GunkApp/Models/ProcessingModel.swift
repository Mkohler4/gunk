import Foundation
import Observation

enum SourceImportStatus: String, CaseIterable, Sendable {
  case queued
  case processing
  case complete
  case failed

  var label: String {
    switch self {
    case .queued:
      return "Queued"
    case .processing:
      return "Processing"
    case .complete:
      return "Complete"
    case .failed:
      return "Failed"
    }
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
  private(set) var sourceStatuses: [Int64: SourceImportStatus] = [:]
  private(set) var sourceErrors: [Int64: String] = [:]
  private(set) var modulesFound = 0
  private(set) var errorMessage: String?

  init(
    dockIconController: DockIconController,
    gunkCount: @escaping () throws -> Int
  ) {
    self.dockIconController = dockIconController
    self.gunkCount = gunkCount
  }

  func queue(sourceId: Int64) {
    sourceStatuses[sourceId] = .queued
    sourceErrors[sourceId] = nil
  }

  func begin(sourceId: Int64) {
    activeSourceIds.insert(sourceId)
    progressBySource[sourceId] = 0
    sourceStatuses[sourceId] = .processing
    sourceErrors[sourceId] = nil
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
    sourceStatuses[sourceId] = .processing

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
    sourceStatuses[sourceId] = .complete
    sourceErrors[sourceId] = nil

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
    sourceStatuses[sourceId] = .failed
    sourceErrors[sourceId] = error.localizedDescription

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

  func status(for source: Source) -> SourceImportStatus {
    sourceStatuses[source.id] ?? .complete
  }

  func progress(for source: Source) -> Double? {
    progressBySource[source.id]
  }

  func error(for source: Source) -> String? {
    sourceErrors[source.id]
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
