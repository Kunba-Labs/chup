import ChupCore
import SwiftUI

struct StorageSettingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var draft = RetentionPolicy()
  @State private var confirmRetention = false
  @State private var deletion: Meeting?
  private let periods = [0, 7, 30, 90, 365]
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      WorkspaceCard("On this Mac", icon: "lock.shield") {
        Label(
          state.store?.encrypted == true ? "Encrypted on this Mac" : "Workspace unavailable",
          systemImage: "lock.shield"
        ).font(.callout.weight(.medium)).foregroundStyle(Palette.olive)
        DetailDisclosure(
          title: "Encryption & backups",
          text:
            "Notes, transcripts and search indexes use SQLCipher encryption. Audio and voice references have their own encryption; keys stay in Keychain. Older backups and macOS snapshots may contain previously unencrypted data."
        )
      }
      WorkspaceCard(
        "Keep what matters", subtitle: "Choose how long your recordings and notes stay.",
        icon: "calendar"
      ) {
        period("Meetings, notes and related audio", value: $draft.meetingDays)
        period("Dictation history and audio", value: $draft.dictationDays)
        period("Private question audio", value: $draft.questionDays)
        Text(
          "Age is measured from creation. Cleanup runs hourly while Chup! is open and idle. Private-question retention removes audio; saved assistant exchanges remain with their meeting."
        ).font(.caption).foregroundStyle(Palette.secondary)
        HStack {
          Button("Save retention schedule") { confirmRetention = true }.disabled(
            !state.privacyWorkAllowed)
          Button("Run cleanup now") { state.runRetention() }.disabled(!state.privacyWorkAllowed)
        }
      }
      WorkspaceCard("Export & recovery", icon: "externaldrive") {
        Button("Encrypted backup or restore…") { state.backupSheet = true }.disabled(
          !state.privacyWorkAllowed)
        Button("Export selected meeting as aligned WAV tracks…") { state.exportMeetingAudio() }
          .disabled(state.selectedMeetingID == nil || !state.privacyWorkAllowed)
        if let progress = state.audioExportProgress {
          ProgressView("Exporting audio", value: progress)
          Button("Cancel audio export") { state.audioExportTask?.cancel() }
        }
        Button("Check database integrity") { state.inspectStorage() }.disabled(state.storageBusy)
        if state.selectedMeetingID != nil {
          Button("Export selected meeting as readable JSON…") { state.exportMeeting() }.disabled(
            !state.privacyWorkAllowed)
          Button("Export with private thoughts and assistant history…") {
            state.exportMeeting(includePrivate: true)
          }.disabled(!state.privacyWorkAllowed)
        }
        Text(
          "Readable exports are not encrypted. Deletion here cannot remove copies you exported, provider records, system snapshots or external backups."
        ).font(.caption).foregroundStyle(Palette.secondary)
      }
      WorkspaceCard(
        "Delete a meeting", subtitle: "Permanently remove its local audio and content.",
        icon: "trash"
      ) {
        if state.meetings.isEmpty {
          Text("No meetings to delete.").foregroundStyle(Palette.secondary)
        }
        ForEach(state.meetings) { meeting in
          HStack {
            Text(meeting.title).lineLimit(1)
            Spacer()
            Button("Delete…", role: .destructive) { deletion = meeting }.disabled(
              !state.privacyWorkAllowed)
          }
        }
      }
      if state.storageBusy { ProgressView("Working on your storage…") }
      if let message = state.storageMessage {
        InlineStatus(text: message).textSelection(.enabled)
      }
    }.onAppear { draft = state.retention }
      .confirmationDialog(
        "Apply this retention schedule?", isPresented: $confirmRetention, titleVisibility: .visible
      ) {
        Button("Apply schedule", role: .destructive) {
          state.retention = draft
          state.saveRetention()
        }
      } message: {
        Text(
          "\(eligible) existing records currently qualify for deletion. Cleanup removes their local content and audio when Chup! is idle. Keep a recovery backup if needed."
        )
      }
      .confirmationDialog(
        "Delete this meeting and all its local content?",
        isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
        titleVisibility: .visible
      ) {
        Button("Delete meeting", role: .destructive) {
          if let meeting = deletion { state.deleteMeeting(meeting) }
          deletion = nil
        }
      } message: {
        Text(
          "\(deletion?.title ?? "") — recordings, transcripts, notes, private thoughts, actions, assistant history and enrolled references from this meeting. This cannot be undone."
        )
      }
  }
  private var eligible: Int {
    state.meetings.filter { draft.expired($0.created, days: draft.meetingDays) }.count
      + state.history.filter { draft.expired($0.created, days: draft.dictationDays) }.count
      + ((try? state.db().list(VoiceQuestionRecord.self, kind: "voiceQuestion")) ?? []).filter {
        draft.expired($0.created, days: draft.questionDays)
      }.count
  }
  private func period(_ title: String, value: Binding<Int>) -> some View {
    Picker(title, selection: value) {
      ForEach(periods, id: \.self) { days in
        Text(days == 0 ? "Until I delete" : "\(days) days").tag(days)
      }
    }
  }
}
struct BackupSettingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""
  @State private var confirmation = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Keep a way back.").font(.system(size: 30, design: .serif))
      Text(
        "Recovery archives include encrypted recordings, notes, search data and wrapped encryption keys. Your backend token is excluded. Use a password of at least 12 characters and keep it separately."
      ).foregroundStyle(Palette.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          WorkspaceCard("Create a recovery backup", icon: "lock.doc") {
            SecureField("Backup password", text: $password)
            SecureField("Repeat password for a new backup", text: $confirmation)
            Button("Create encrypted backup…") { state.createBackup(password: password) }.disabled(
              !state.privacyWorkAllowed || password.count < 12 || confirmation != password)
          }
          WorkspaceCard("Return to an existing backup", icon: "arrow.counterclockwise") {
            Button("Verify an existing backup…") {
              state.restoreBackup(password: password, activate: false)
            }.disabled(!state.privacyWorkAllowed || password.count < 12)
            Button("Restore as a separate workspace…") {
              state.restoreBackup(password: password, activate: true)
            }.disabled(!state.privacyWorkAllowed || password.count < 12)
            Text(
              "Restore never overwrites your current workspace. After verification, quit and reopen Chup! to switch to the restored copy."
            ).font(.caption).foregroundStyle(Palette.secondary)
          }
          if state.storageBusy { ProgressView() }
          if let message = state.storageMessage {
            Text(message).font(.callout).textSelection(.enabled)
          }
        }
      }
      Divider()
      HStack {
        Spacer()
        Button("Done") {
          password = ""
          confirmation = ""
          dismiss()
        }.disabled(state.storageBusy)
      }
    }.padding(28).frame(width: 590, height: 650).background(Palette.workspace).tint(Palette.olive)
      .textFieldStyle(.roundedBorder)
  }
}
struct RequestRecoveryView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var chargedRetry: DurableRequest?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      WorkspaceCard("Interrupted work", icon: "arrow.counterclockwise") {
        Text(
          "Resume uses the same request ID and saved provider steps. If the provider may have charged for a lost response, Chup! asks before making a new request. No microphone or note write starts automatically."
        ).font(.callout).foregroundStyle(Palette.secondary)
      }
      if state.durableRequests.isEmpty {
        WorkspaceCard {
          QuietEmpty(
            icon: "checkmark.circle", title: "All caught up",
            subtitle: "Interrupted requests will appear here when there is work to recover.")
        }
      }
      ForEach(state.durableRequests.prefix(30)) { job in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(job.route.capitalized).font(.headline)
            Spacer()
            Text(job.status).font(.caption)
          }
          if let error = job.error { Text(error).font(.caption).foregroundStyle(Palette.secondary) }
          HStack {
            Button(job.status == "completed" ? "Use saved response" : "Resume") {
              state.resumeRequest(job)
            }.disabled(
              !state.privacyWorkAllowed || (!state.cloudEnabled && job.status != "completed"))
            if job.response != nil { Button("Copy response") { state.copyRequestResult(job) } }
            if job.status == "interrupted" || job.status == "cancelled" {
              Button("Start a new attempt…") { chargedRetry = job }.disabled(
                !state.privacyWorkAllowed)
            }
          }
        }.padding(20).workspaceSurface()
      }
    }.confirmationDialog(
      "A new attempt may incur another provider charge.",
      isPresented: Binding(get: { chargedRetry != nil }, set: { if !$0 { chargedRetry = nil } }),
      titleVisibility: .visible
    ) {
      Button("Start new request") {
        if let job = chargedRetry { state.resumeRequest(job, newAttempt: true) }
        chargedRetry = nil
      }
    } message: {
      Text(
        "The earlier provider response may be missing even if it was processed. Its usage stays marked unconfirmed."
      )
    }
  }
}
struct UsageSettingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var feedback: String?
  @State private var model = "gpt-live-1"
  @State private var input = ""
  @State private var cached = ""
  @State private var output = ""
  @State private var minute = ""
  @State private var rate = UsageRates()
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      WorkspaceCard(
        "Your estimates", subtitle: "Enter your provider’s USD rates.", icon: "dollarsign.circle"
      ) {
        Text(
          "Provider-reported units are separate from local session duration. Missing final usage stays unconfirmed. Estimates use the USD rates you enter and are not an invoice."
        ).font(.callout).foregroundStyle(Palette.secondary)
        Picker("Model", selection: $model) {
          ForEach(
            Array(
              Set(
                state.providerUsage.map(\.model) + [
                  "gpt-live-1", "gpt-live-transcribe", "gpt-4o-transcribe-diarize",
                  "gpt-transcribe",
                  "gpt-5.6-luna",
                ])
            ).sorted(), id: \.self
          ) { Text($0).tag($0) }
        }.onChange(of: model) { _, _ in loadRate() }
        HStack {
          TextField("Input / million", text: $input)
          TextField("Cached / million", text: $cached)
        }
        HStack {
          TextField("Output / million", text: $output)
          TextField("Audio / minute", text: $minute)
        }
        Button("Save rates for this model") {
          let values = [input, cached, output, minute]
          guard
            values.allSatisfy({ $0.isEmpty || (Double($0).map { $0.isFinite && $0 >= 0 } ?? false) }
            )
          else {
            feedback = "Enter nonnegative numeric rates, or leave them blank."
            return
          }
          rate = UsageRates(
            inputPerMillion: Double(input), cachedPerMillion: Double(cached),
            outputPerMillion: Double(output), perMinute: Double(minute))
          do {
            try state.db().put(rate, kind: "usageRates", id: model, parent: model)
            feedback = "Rates saved for this model."
          } catch {
            feedback = error.localizedDescription
          }
        }
        if let feedback { InlineStatus(text: feedback) }
      }
      WorkspaceCard("Provider activity", icon: "clock") {
        ForEach(state.providerUsage.filter { $0.model == model }.prefix(30)) { item in
          VStack(alignment: .leading, spacing: 5) {
            Text(item.category).font(.headline)
            Text(item.confirmed ? "Provider usage received" : "Final usage unconfirmed").font(
              .caption
            ).foregroundStyle(Palette.secondary)
            if let seconds = item.seconds {
              Text("\(seconds, specifier: "%.1f") seconds").font(.caption)
            }
            if let input = item.inputTokens {
              Text(
                "\(input.formatted(.number.precision(.fractionLength(0)))) input · \((item.outputTokens ?? 0).formatted(.number.precision(.fractionLength(0)))) output tokens"
              ).font(
                .caption)
            }
            if let cost = rate.estimate(item) {
              Text("Estimated $\(cost, specifier: "%.4f")").font(.caption)
            }
          }
        }
        if !state.providerUsage.contains(where: { $0.model == model }) {
          Text("No usage recorded for this model yet.").foregroundStyle(
            Palette.secondary)
        }
      }
    }.onAppear(perform: loadRate)
  }
  private func loadRate() {
    rate =
      (try? state.db().list(UsageRates.self, kind: "usageRates", parent: model).first)
      ?? UsageRates()
    input = rate.inputPerMillion.map { String($0) } ?? ""
    cached = rate.cachedPerMillion.map { String($0) } ?? ""
    output = rate.outputPerMillion.map { String($0) } ?? ""
    minute = rate.perMinute.map { String($0) } ?? ""
  }
}
