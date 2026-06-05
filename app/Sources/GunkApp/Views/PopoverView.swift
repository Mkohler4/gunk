import SwiftUI

@MainActor
struct PopoverView: View {
  let browseModel: BrowseModel
  let store: Store
  let processingModel: ProcessingModel
  let sourceProcessingRunner: SourceProcessingRunner

  var body: some View {
    TabView {
      browseTab
        .tabItem {
          Text("Browse")
        }

      RunsView()
        .tabItem {
          Text("Runs")
        }

      SettingsView()
        .tabItem {
          Text("Settings")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(20)
  }

  private var browseTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let errorMessage = browseModel.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      if processingModel.isProcessing {
        ProgressView("Processing")
      }

      if let errorMessage = processingModel.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      DropZoneView(
        handler: DropZoneHandler(store: store) { source in
          Task {
            await sourceProcessingRunner.process(source: source)
          }
        }
      )
        .frame(height: 120)

      BrowseView(model: browseModel)
        .frame(minHeight: 180)

      Divider()

      ApprovalQueueView(model: browseModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      browseModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      browseModel.refresh()
    }
  }
}
