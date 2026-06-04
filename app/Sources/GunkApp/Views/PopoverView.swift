import SwiftUI

@MainActor
struct PopoverView: View {
  let dropHandler: DropZoneHandler
  let listModel: GunkListModel

  var body: some View {
    TabView {
      sourcesTab
        .tabItem {
          Text("Sources")
        }

      SettingsView()
        .tabItem {
          Text("Settings")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(20)
  }

  private var sourcesTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      DropZoneView(handler: dropHandler)
        .frame(height: 130)

      if let errorMessage = listModel.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      GunkListView(model: listModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      listModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      listModel.refresh()
    }
  }
}
