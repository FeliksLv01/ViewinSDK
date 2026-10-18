import SwiftUI

struct SwiftUIDemoCard: View {
  @State private var taps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("SwiftUI inside UIKit", systemImage: "square.stack.3d.up")
        .font(.headline)
      Text(taps == 0 ? "Inspect the logical tree, layout and gesture modifiers." : "SwiftUI taps: \(taps)")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding().frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
    .contentShape(Rectangle())
    .onTapGesture { taps += 1 }
    .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { _ in })
  }
}
