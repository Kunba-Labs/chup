import AppKit
import SwiftUI

@MainActor final class DictationReviewController {
  private let panel: NonactivatingPanel
  private weak var state: WorkspaceState?

  init(state: WorkspaceState) {
    self.state = state
    panel = NonactivatingPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.appearance = NSAppearance(named: .aqua)
    panel.keyboardRequested = true
    panel.contentView = NSHostingView(rootView: DictationReviewView(state: state))
  }

  func show() {
    guard let screen = NSScreen.main else { return }
    let size = NSSize(width: 430, height: 260)
    panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height), display: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() { panel.orderOut(nil) }
}

struct DictationReviewView: View {
  @ObservedObject var state: WorkspaceState

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("DICTATION REVIEW")
        .font(.system(size: 11, weight: .semibold))
        .tracking(1.4)
        .foregroundStyle(Palette.secondary)
      Text("Review before pasting")
        .font(.system(size: 20, weight: .semibold, design: .serif))
      ReviewTextEditor(state: state)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.12)) }
      HStack {
        Spacer()
        Button("Cancel") { state.cancelDictationReview() }
        Button("OK") { state.approveDictationReview() }.keyboardShortcut(.return)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(width: 430, height: 260)
    .background(Palette.workspace, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.border, lineWidth: 1) }
  }
}

extension WorkspaceState {
  func requestDictationReview() {
    guard dictationStatus == .listening || dictationStatus == .processing else { return }
    dictationReviewRequested = true
    if !dictationReviewActive {
      let seed = dictationLiveText.isEmpty
        ? (history.first(where: { !$0.text.isEmpty })?.text ?? "")
        : dictationLiveText
      dictationReviewText = seed
      dictationReviewSeed = seed
      dictationReviewActive = true
      dictationReviewController?.show()
    }
  }

  func presentDictationReview(entryID: String, text: String) {
    dictationReviewEntryID = entryID
    let seed = text.isEmpty ? (history.first(where: { !$0.text.isEmpty })?.text ?? "") : text
    dictationReviewText = seed
    dictationReviewSeed = seed
    dictationReviewSelection = NSRange(location: (seed as NSString).length, length: 0)
    dictationReviewApproved = false
    dictationReviewActive = true
    dictationReviewController?.show()
  }

  func approveDictationReview() {
    guard dictationReviewActive else { return }
    dictationReviewApproved = true
    dictationReviewActive = false
    dictationReviewController?.hide()
  }

  func cancelDictationReview() {
    dictationReviewApproved = false
    dictationReviewRequested = false
    dictationReviewActive = false
    dictationReviewSeed = ""
    dictationReviewController?.hide()
  }

  func appendDictationReview(_ text: String) {
    guard !text.isEmpty else { return }
    let source = dictationReviewText as NSString
    let location = min(dictationReviewSelection.location, source.length)
    let range = NSRange(location: location, length: min(dictationReviewSelection.length, source.length - location))
    dictationReviewText = source.replacingCharacters(in: range, with: text)
    dictationReviewSelection = NSRange(location: location + (text as NSString).length, length: 0)
  }
}

private struct ReviewTextEditor: NSViewRepresentable {
  @ObservedObject var state: WorkspaceState

  func makeCoordinator() -> Coordinator { Coordinator(state: state) }
  func makeNSView(context: Context) -> NSTextView {
    let view = NSTextView()
    view.delegate = context.coordinator
    view.font = .systemFont(ofSize: 16)
    view.isRichText = false
    view.drawsBackground = false
    context.coordinator.apply(state.dictationReviewText,
      selection: NSRange(location: (state.dictationReviewText as NSString).length, length: 0),
      to: view)
    return view
  }
  func updateNSView(_ view: NSTextView, context: Context) {
    // NSTextView sends textDidChange while its string is assigned. Without a
    // guard, the initial blank view can overwrite the freshly seeded state
    // during the same render pass that presents the panel.
    let selection = state.dictationReviewSelection
    if view.string != state.dictationReviewText || view.selectedRange != selection {
      context.coordinator.apply(state.dictationReviewText, selection: selection, to: view)
    }
  }
  final class Coordinator: NSObject, NSTextViewDelegate {
    let state: WorkspaceState
    private var applyingState = false
    init(state: WorkspaceState) { self.state = state }
    func apply(_ text: String, selection: NSRange, to view: NSTextView) {
      applyingState = true
      defer { applyingState = false }
      if view.string != text { view.string = text }
      let clamped = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
      view.setSelectedRange(clamped)
    }
    func textDidChange(_ notification: Notification) {
      guard !applyingState else { return }
      guard let view = notification.object as? NSTextView else { return }
      state.dictationReviewText = view.string
      state.dictationReviewSelection = view.selectedRange()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard !applyingState else { return }
      guard let view = notification.object as? NSTextView else { return }
      state.dictationReviewSelection = view.selectedRange()
    }
  }
}
