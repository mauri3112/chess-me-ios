import SwiftUI
import UniformTypeIdentifiers

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var authentication: LichessAuthentication
    @Environment(\.dismiss) private var dismiss
    @State private var consent = false
    @State private var error: String?
    @State private var showPGN = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(authentication.account == nil ? "Bring in your games" : "Your Lichess games")
                        .font(ChessMeStyle.title(30))
                    Text("Finished games become reviews and practice on this iPhone.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    PaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(authentication.account?.username ?? "Lichess", systemImage: authentication.account == nil ? "link" : "checkmark.circle")
                                .font(.headline)
                            if authentication.account == nil {
                                Text("Sign in securely on Lichess. We never ask for your password.")
                                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                            } else {
                                ReviewPeriodMenu()
                            }
                            Toggle("Allow importing my completed games", isOn: $consent)
                                .font(.subheadline).tint(ChessMeStyle.green).accessibilityIdentifier("connection.consent")
                            if authentication.account != nil {
                                PrimaryButton(title: model.isImporting ? "Importing…" : "Import my games", symbol: "arrow.down") {
                                    Task { if await model.importGames() { dismiss(); model.analyzePending() } }
                                }.disabled(!consent || model.isBusy).accessibilityIdentifier("connection.import")
                            } else {
                                PrimaryButton(title: authentication.isConnecting ? "Connecting…" : "Connect Lichess", symbol: "link") {
                                    Task {
                                        do { try await authentication.connect() }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }.disabled(!consent || authentication.isConnecting || model.isBusy)
                                    .accessibilityIdentifier("connection.connect")
                            }
                        }
                    }
                    if let error = error ?? authentication.lastError ?? model.notice {
                        Text(error).font(.footnote).foregroundStyle(ChessMeStyle.muted)
                    }
                    DisclosureGroup("Other ways to import") {
                        VStack(alignment: .leading, spacing: 16) {
                            NavigationLink { PublicProfileImportView(onImported: { dismiss() }) } label: { Label("Public Lichess username", systemImage: "person") }
                                .accessibilityIdentifier("connection.publicProfile")
                            Button { showPGN = true } label: { Label("PGN file or text", systemImage: "doc.text") }
                                .accessibilityIdentifier("connection.pgn")
                        }.font(.subheadline.weight(.medium)).padding(.top, 12)
                    }
                    Text("Disconnect or delete your games in Settings.").font(.caption).foregroundStyle(ChessMeStyle.muted)
                }.padding(24)
            }.background(ChessMeStyle.paper).accessibilityIdentifier("connection.scroll")
                .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showPGN) { PGNImportView() }
        }.disclosureGroupStyle(FullRowDisclosureStyle())
    }
}

private struct PublicProfileImportView: View {
    let onImported: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var username = ""
    @State private var consent = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Import public games").font(ChessMeStyle.title(28))
                Text("Review a public Lichess profile on this iPhone. Cloud reviews need a verified Lichess connection.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                TextField("Lichess username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("connection.username")
                ReviewPeriodMenu()
                Toggle("Allow importing these public games", isOn: $consent).font(.subheadline).tint(ChessMeStyle.green)
                PrimaryButton(title: model.isImporting ? "Importing…" : "Import public games", symbol: "arrow.down") {
                    Task { if await model.importGames(username: username.trimmingCharacters(in: .whitespacesAndNewlines)) { model.analyzePending(); onImported() } }
                }.disabled(!consent || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
            }.padding(24)
        }.background(ChessMeStyle.paper).navigationTitle("Public profile").navigationBarTitleDisplayMode(.inline)
    }
}

struct PGNImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var player = ""
    @State private var error: String?
    @State private var chooseFile = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bring a game with you.").font(ChessMeStyle.title(30))
                    Text("Import one finished standard game with White, Black, Date and a final result. It must fit your selected review period.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    TextField("Your player name in the PGN", text: $player).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding().background(.white, in: RoundedRectangle(cornerRadius: 12))
                    TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 250)
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Button("Choose a PGN file") { chooseFile = true }
                    if let error { Text(error).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
                    PrimaryButton(title: "Import game", symbol: "arrow.down") {
                        do {
                            guard text.utf8.count <= 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
                            try model.importPGN(text, username: player)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(text.isEmpty || player.isEmpty || model.isBusy)
                }.padding(24)
            }.background(ChessMeStyle.paper)
                .navigationTitle("PGN import").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        text = try String(contentsOf: url, encoding: .utf8)
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
}
