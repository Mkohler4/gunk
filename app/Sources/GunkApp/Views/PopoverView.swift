import SwiftUI

struct PopoverView: View {
  let dropHandler: DropZoneHandler

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("gunk")
        .font(.headline)

      DropZoneView(handler: dropHandler)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(20)
  }
}
