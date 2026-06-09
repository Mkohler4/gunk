import SwiftUI

@MainActor
struct AppLaunchView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    Group {
      if let services = runtime.services {
        AppShellView(services: services)
      } else {
        launchFailureView
      }
    }
    .frame(minWidth: 760, minHeight: 520)
  }

  private var launchFailureView: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 34))
        .foregroundStyle(.orange)

      Text("gunk could not open")
        .font(.title3.bold())

      Text(runtime.launchError ?? "Unknown launch error.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
struct AppShellView: View {
  let services: AppServices

  @State private var selection: AppSection? = .sources

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("gunk")
      .frame(minWidth: 180)
    } detail: {
      detailView(for: selection ?? .sources)
        .navigationTitle((selection ?? .sources).title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
  }

  @ViewBuilder
  private func detailView(for section: AppSection) -> some View {
    switch section {
    case .sources:
      SourcesSectionView(
        processingModel: services.processingModel,
        sourceListModel: services.sourceListModel,
        dropZoneHandler: services.dropZoneHandler
      )
    case .modules:
      ModulesSectionView(model: services.browseModel)
    case .runs:
      RunsView()
    case .settings:
      SettingsView(storePath: services.store.databasePath)
    case .approval:
      ApprovalSectionView(model: services.browseModel)
    }
  }
}

private enum AppSection: String, CaseIterable, Identifiable {
  case sources
  case modules
  case runs
  case settings
  case approval

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .sources:
      return "Sources"
    case .modules:
      return "Modules"
    case .runs:
      return "Runs"
    case .settings:
      return "Settings"
    case .approval:
      return "Approval"
    }
  }

  var systemImage: String {
    switch self {
    case .sources:
      return "tray.and.arrow.down"
    case .modules:
      return "square.grid.2x2"
    case .runs:
      return "clock.arrow.circlepath"
    case .settings:
      return "gearshape"
    case .approval:
      return "checkmark.seal"
    }
  }
}

@MainActor
private struct SourcesSectionView: View {
  let processingModel: ProcessingModel
  let sourceListModel: GunkListModel
  let dropZoneHandler: DropZoneHandler

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      statusView

      DropZoneView(handler: dropZoneHandler)
        .frame(height: 170)

      GunkListView(model: sourceListModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      sourceListModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      sourceListModel.refresh()
    }
  }

  @ViewBuilder
  private var statusView: some View {
    if processingModel.isProcessing {
      ProgressView("Processing")
    }

    if let errorMessage = processingModel.errorMessage {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }

    if let errorMessage = sourceListModel.errorMessage {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
  }
}

@MainActor
private struct ModulesSectionView: View {
  let model: BrowseModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let errorMessage = model.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }

      BrowseView(model: model)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

@MainActor
private struct ApprovalSectionView: View {
  let model: BrowseModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let errorMessage = model.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }

        ApprovalQueueView(model: model)
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
    }
  }
}
