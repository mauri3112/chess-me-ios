import SwiftUI
import ChessMeCore

struct GameAnalysisSelectionView: View {
    let schedule: DeviceAnalysisSchedule
    let games: [ChessGame]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var speedFilter: GameSpeedFilter = .all
    private var available: [ChessGame] {
        let allowed = Set(model.windowGames.map(\.id))
        return games.filter { allowed.contains($0.id) && speedFilter.includes($0) }
    }
    private func alreadyCovered(_ game: ChessGame) -> Bool {
        model.completeDeviceReview(for: game.id, covering: model.deepConfiguration(model.overnightSettings.level)) != nil
    }
    private var selectable: Set<String> { Set(available.filter { !alreadyCovered($0) }.map(\.id)) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(schedule == .night ? "While charging tonight" : "Start on this device", systemImage: schedule.symbol)
                    Text("Depth \(model.overnightSettings.level.depth) · \(selected.count) selected")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    GameSpeedMenu(selection: $speedFilter, identifier: "analysis.speed")
                    Button(selected == selectable ? "Deselect all" : "Select all") {
                        selected = selected == selectable ? [] : selectable
                    }.disabled(selectable.isEmpty).accessibilityIdentifier("analysis.selectAll")
                }
                Section("Choose games") {
                    ForEach(available) { game in
                        let covered = alreadyCovered(game)
                        Button { if selected.contains(game.id) { selected.remove(game.id) } else { selected.insert(game.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(game.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(covered ? ChessMeStyle.muted : ChessMeStyle.green)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(game.reviewLabel).font(.subheadline.weight(.semibold))
                                    Text(covered ? "Review ready at this depth" : "\(game.timeControl.title) · \(game.playedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                Spacer()
                                GameAnalysisIndicator(game: game)
                            }.foregroundStyle(ChessMeStyle.ink)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.automatic).disabled(covered)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(game.reviewLabel)
                            .accessibilityValue(covered ? "Review ready at this depth" : selected.contains(game.id) ? "Selected" : "Not selected")
                            .accessibilityIdentifier("analysis.select.\(game.id)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selected.contains(game.id) ? .isSelected : [])
                    }
                    if available.isEmpty { Text("Choose a review period with games to add.").font(.subheadline) }
                }
                if let notice = model.notice {
                    Section { Text(notice).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(ChessMeStyle.paper)
            .navigationTitle(schedule.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("analysis.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.queueForAnalysis(gameIDs: selected, schedule: schedule) { dismiss() }
                    }.fontWeight(.semibold).disabled(selected.isEmpty || model.isImporting || model.cloudIsRunning)
                        .accessibilityIdentifier("analysis.save")
                }
            }
            .onChange(of: selectable) { _, allowed in selected.formIntersection(allowed) }
        }
    }
}
