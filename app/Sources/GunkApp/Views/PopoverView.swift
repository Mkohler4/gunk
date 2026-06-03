import SwiftUI

struct PopoverView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("gunk")
        .font(.headline)

      Text("Drop folders here (T-2.11)")
        .font(.body)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(20)
  }
}

#Preview {
  PopoverView()
}
