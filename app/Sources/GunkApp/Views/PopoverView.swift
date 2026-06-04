import SwiftUI

struct PopoverView: View {
  let dropHandler: DropZoneHandler
  let listModel: GunkListModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("gunk")
        .font(.headline)

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
    .padding(20)
    .onAppear {
      listModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      listModel.refresh()
    }
  }
}
