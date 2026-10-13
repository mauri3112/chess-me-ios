import SwiftUI
import ChessMeCore

struct LocalAnalysisSettingsView: View {
    @EnvironmentObject private var model: AppModel
    private var hardware: LocalAnalysisHardware { DeviceAnalysisCoordinator.hardware }
    private var jobs: [LocalAnalysisJob] { (model.library.localAnalysisJobs ?? []).filter { $0.level != nil } }

    var body: some View {
        Form {
            Section {
                Toggle("Analyze while charging at night", isOn: $model.overnightSettings.enabled)
                    .disabled(!hardware.supportsOvernight)
                    .accessibilityIdentifier("localAnalysis.overnight")
            } header: { Text("Overnight analysis") } footer: {
                Text(hardware.supportsOvernight
                     ? "Reviews saved games in your selected period between 10 pm and 7 am, while charging. iOS chooses when background work can run. Completed decisions are saved and unfinished reviews resume later."
                     : LocalAnalysisLevel.balanced.requirement)
            }
            Section {
                ForEach(LocalAnalysisLevel.allCases) { level in
                    let estimate = model.nightEstimate(level)
                    Button {
                        model.overnightSettings.level = level
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hardware.bounded(model.overnightSettings.level) == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(hardware.supports(level) ? ChessMeStyle.green : ChessMeStyle.muted)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(level.title) · depth \(level.depth)").font(.body.weight(.semibold))
                                Text(estimate.summary)
                                    .font(.subheadline).foregroundStyle(ChessMeStyle.green)
                                    .accessibilityIdentifier("localAnalysis.capacity.\(level.rawValue)")
                                Text(estimate.usesMeasuredSpeed ? "Based on completed reviews on this device"
                                     : (model.isDemo || model.windowGames.isEmpty ? "Initial estimate for a 40-move game" : "Initial estimate for games like yours"))
                                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                            }
                            Spacer()
                            if !hardware.supports(level) { Image(systemName: "lock.fill").foregroundStyle(ChessMeStyle.muted) }
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hardware.supports(level))
                    .accessibilityIdentifier("localAnalysis.level.\(level.rawValue)")
                    .accessibilityAddTraits(hardware.bounded(model.overnightSettings.level) == level ? .isSelected : [])
                }
            } header: { Text("Depth target") } footer: {
                Text("Estimates use your recent game lengths and improve after complete reviews. iOS scheduling and temperature affect nightly capacity. Higher targets take longer and may not be reached within the search limit. This level also applies to reviews you start yourself.")
            }
            Section {
                LabeledContent("Engine", value: model.deepConfiguration(.balanced).engine.title)
                Text("Game analysis stays on this device and uses no cloud allowance.").font(.footnote)
                Text("Memory use adjusts automatically. Each review shows the depth actually reached.").font(.footnote)
                if #unavailable(iOS 26.0) {
                    Text("iOS 26 or later is needed to continue an immediate review after leaving the app. On this version, unfinished work is saved and can resume while charging.")
                        .font(.footnote).foregroundStyle(ChessMeStyle.muted)
                }
                Button("Analyze games in this period now") {
                    for game in model.windowGames { model.analyzeOnDevice(gameID: game.id) }
                }
                .disabled(!hardware.supportsOvernight || model.windowGames.isEmpty || model.isImporting || model.cloudIsRunning)
                .accessibilityIdentifier("localAnalysis.analyzeNow")
                if model.isAnalyzing { Button("Pause analysis") { model.pauseAnalysis() } }
            } header: { Text("On this device") }
            if !jobs.isEmpty {
                Section("Your reviews") {
                    ForEach(jobs.reversed()) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.library.games.first(where: { $0.id == job.gameID })?.label ?? "Saved game")
                                .font(.subheadline.weight(.semibold))
                            LocalAnalysisStatusView(job: job, currentDepth: job.state == .running ? model.deviceAnalysisDepth : 0)
                            if [.paused, .failed].contains(job.state) {
                                Button("Resume on device") { model.analyzeOnDevice(gameID: job.gameID) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if let notice = model.notice { Section { Text(notice).font(.footnote) } }
        }
        .scrollContentBackground(.hidden).background(ChessMeStyle.paper)
        .navigationTitle("On-device analysis").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("localAnalysis.settings")
    }
}

struct LocalAnalysisStatusView: View {
    let job: LocalAnalysisJob
    var currentDepth = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Bool { job.state == .running }
    private var symbol: String {
        switch job.state {
        case .running: return "cpu"
        case .queued: return job.nightOnly ? "moon.zzz" : "clock"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3).foregroundStyle(ChessMeStyle.green)
                    .symbolEffect(.pulse, isActive: running && !reduceMotion)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(job.configuration.engine.title) · on device").font(.caption.weight(.semibold))
                    Text(job.message ?? (job.nightOnly ? "Waiting for tonight and charging" : "Waiting to start"))
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                Spacer()
                if running { ProgressView().accessibilityLabel("Analyzing game") }
            }
            if job.state != .failed {
                ProgressView(value: job.progress).tint(ChessMeStyle.green)
            }
            if let checkpoint = job.checkpoint {
                Text("\(checkpoint.analyzedPlies)/\(checkpoint.totalPlies) decisions saved").font(.caption.monospacedDigit())
            }
            if running && currentDepth > 0 {
                Text("Current search depth \(currentDepth) · target \(job.configuration.depth)")
                    .font(.caption.monospacedDigit()).foregroundStyle(ChessMeStyle.muted)
            } else if let reached = job.reachedDepth {
                Text("Lowest assessed depth \(reached) · target \(job.configuration.depth)")
                    .font(.caption.monospacedDigit()).foregroundStyle(ChessMeStyle.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("localAnalysis.status.\(job.gameID)")
    }
}
