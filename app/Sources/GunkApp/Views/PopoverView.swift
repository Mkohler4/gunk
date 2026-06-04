import SwiftUI

@MainActor
struct PopoverView: View {
  let browseModel: BrowseModel
  let store: Store

  var body: some View {
    TabView {
      browseTab
        .tabItem {
          Text("Browse")
        }

      SettingsView(store: store)
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

      BrowseView(model: browseModel)
        .frame(minHeight: 260)

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
