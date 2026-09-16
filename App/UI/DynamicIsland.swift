import AppKit
import DynamicNotchKit
import SwiftUI

/// Native DynamicNotchKit-backed transcription surface. The package owns the
/// notch safe-area measurement, panel geometry, masking and transitions; Chup!
/// only supplies its live state and content.
@MainActor final class DynamicIslandController {
  private weak var state: WorkspaceState?
  private let notch: DynamicNotch<DynamicIslandContent, EmptyView, EmptyView>
  private var transitionTask: Task<Void, Never>?
  private var isPresented = false

  init(state: WorkspaceState) {
    self.state = state
    notch = DynamicNotch(style: .auto) {
      DynamicIslandContent(state: state)
    }
  }

  func refresh() {
    guard let state else { return }
    transitionTask?.cancel()
    if state.dynamicIslandEnabled,
       state.dictationStatus == .listening || state.dictationStatus == .processing {
      guard !isPresented else { return }
      isPresented = true
      transitionTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await notch.expand(on: NSScreen.main ?? NSScreen.screens[0])
      }
    } else {
      guard isPresented else { return }
      isPresented = false
      transitionTask = Task { @MainActor [weak self] in
        await self?.notch.hide()
      }
    }
  }
}

/// Content occupies only the visible band below the physical notch. The
/// package supplies the notch-height inset and black masked surface around it.
struct DynamicIslandContent: View {
  @ObservedObject var state: WorkspaceState
  @State private var isHovering = false

  private var transcribing: Bool {
    state.dictationStatus == .listening || state.dictationStatus == .processing
  }

  private var text: String {
    state.dictationLiveText.isEmpty
      ? (state.dictationStatus == .processing ? "" : "Listening…")
      : state.dictationLiveText
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      MarqueeText(text: text, animate: state.dictationStatus == .listening)
        .frame(maxWidth: .infinity, alignment: .leading)
      if transcribing && isHovering {
        Button { state.requestDictationReview() } label: {
          Image(systemName: "pencil")
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Review before pasting")
        .transition(.scale.combined(with: .opacity))
      } else if state.dictationStatus == .processing {
        ProgressView().controlSize(.small).tint(.white)
      } else {
        Image(systemName: "waveform").foregroundStyle(.white.opacity(0.62))
      }
    }
    .padding(.horizontal, 18)
    .frame(width: 300, height: 58, alignment: .center)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Dynamic Island · " + text)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.16)) { isHovering = hovering }
    }
    .animation(.smooth(duration: 0.28), value: state.dictationStatus)
  }
}

/// A compact, non-interactive marquee for live dictation. It only animates
/// when the sentence is wider than the island's available text lane.
private struct MarqueeText: View {
  let text: String
  let animate: Bool
  @State private var contentWidth: CGFloat = 0
  @State private var offset: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let overflow = max(0, contentWidth - proxy.size.width)
      Text(text)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .background {
          GeometryReader { textProxy in
            Color.clear.preference(key: MarqueeWidthKey.self, value: textProxy.size.width)
          }
        }
        .offset(x: overflow > 1 ? -min(offset, overflow) : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onPreferenceChange(MarqueeWidthKey.self) { width in
          contentWidth = width
          followTail(overflow: max(0, width - proxy.size.width))
        }
        .onAppear { followTail(overflow: overflow, animated: false) }
    }
    .clipped()
    .frame(height: 24, alignment: .center)
    .onChange(of: text) { _, _ in
      offset = 0
      if animate { followTail(overflow: max(0, contentWidth), animated: false) }
    }
    .onChange(of: animate) { _, enabled in
      if enabled { followTail(overflow: max(0, contentWidth), animated: false) }
      else { offset = 0 }
    }
  }

  private func followTail(overflow: CGFloat, animated: Bool = true) {
    guard animate, overflow > 1 else {
      offset = 0
      return
    }
    if animated {
      withAnimation(.easeOut(duration: 0.22)) { offset = overflow }
    } else {
      offset = overflow
    }
  }
}

private struct MarqueeWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
