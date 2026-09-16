import SwiftUI

/// A visible processing state in the compact rail as well as the workspace sidebar.
struct ProcessingCircle: View {
  var size: CGFloat = 16
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spinning = false
  var body: some View {
    ZStack {
      Circle().stroke(.primary.opacity(0.18), lineWidth: 2)
      Circle().trim(from: 0, to: 0.72)
        .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
        .animation(reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false), value: spinning)
    }.frame(width: size, height: size)
      .onAppear { spinning = true }
      .accessibilityLabel("Processing dictation")
      .accessibilityValue("In progress")
  }
}
