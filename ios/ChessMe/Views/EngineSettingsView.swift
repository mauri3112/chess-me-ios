import SwiftUI
import UIKit
import ChessMeCore

struct EngineSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCloudSetup = false
    @State private var catalog: CloudEngineCatalog?
    @State private var cloudError: String?
    private var memoryMB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) }
    private var maximumCache: Int { DeviceEngineConfiguration.maximumCacheMB(physicalMemory: memoryMB) }
    private var hardware: String {
        #if targetEnvironment(simulator)
        return "Simulator · \(ProcessInfo.processInfo.activeProcessorCount) cores"
        #else
        return "\(UIDevice.current.model) · \(ProcessInfo.processInfo.activeProcessorCount) cores"
        #endif
    }

    var body: some View {
        Form {
            Section("On device") {
                HStack(spacing: 8) {
                    ForEach(Preset.allCases, id: \.self) { choice in
                        let values = limits(for: choice)
                        let selected = model.engineConfiguration.depth == values.depth && model.engineConfiguration.secondsPerPosition == values.seconds && model.engineConfiguration.nodesPerCandidate == values.nodes
                        Button { preset(choice) } label: {
                            Text(choice.rawValue).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? .white : ChessMeStyle.green)
                                .background(selected ? ChessMeStyle.green : ChessMeStyle.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.borderless).accessibilityValue(selected ? "Selected" : "")
                    }
                }
                Text("\(model.engineConfiguration.engine.title) · up to \(model.engineConfiguration.secondsPerPosition)s per position")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                DisclosureGroup("Advanced") {
                    LabeledContent("Engine", value: model.engineConfiguration.engine.title).accessibilityIdentifier("engine.device")
                    Text(model.engineConfiguration.engine.detail).font(.caption).foregroundStyle(ChessMeStyle.muted)
                    Stepper("Maximum depth: \(model.engineConfiguration.depth)", value: $model.engineConfiguration.depth,
                            in: 1...model.engineConfiguration.engine.maximumDepth)
                        .accessibilityIdentifier("engine.depth")
                    Stepper("Time per position: \(model.engineConfiguration.secondsPerPosition)s",
                            value: $model.engineConfiguration.secondsPerPosition, in: 1...15)
                    Picker("Search cache", selection: $model.engineConfiguration.memoryMB) {
                        ForEach([1, 8, 16, 32, 64].filter { $0 <= maximumCache }, id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    if !model.engineConfiguration.engine.isNeural {
                        Picker("Nodes per candidate", selection: $model.engineConfiguration.nodesPerCandidate) {
                            ForEach([1_200, 4_000, 16_000, 50_000, 100_000], id: \.self) { Text($0.formatted()).tag($0) }
                        }
                    }
                    Picker("Suggested moves", selection: $model.engineConfiguration.topMoves) {
                        ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            }
            Section {
                DisclosureGroup("Device limits") {
                    LabeledContent("Hardware", value: hardware)
                    LabeledContent("Memory", value: "\(memoryMB / 1_024) GB")
                    LabeledContent("Maximum cache", value: "\(maximumCache) MB")
                    Text("Search stops at its depth, time or node limit. Game reviews save progress, can continue in the background, and wait if the device gets too hot.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    Label("Low Power Mode limits depth and time", systemImage: "battery.25").font(.caption)
                }
            }
            Section {
                NavigationLink("On-device analysis at night") { LocalAnalysisSettingsView() }
            }
            Section("Cloud") {
                Button("Set up cloud reviews & view queue") { showCloudSetup = true }
                Text(model.cloudNextStep).font(.caption).foregroundStyle(ChessMeStyle.muted)
                if let catalog {
                    Picker("Engine", selection: $model.cloudEngineConfiguration.engine_id) {
                        ForEach(catalog.engines.filter(\.available)) { engine in Text(engine.name).tag(engine.id) }
                    }.accessibilityIdentifier("engine.cloud")
                    DisclosureGroup("Cloud settings") {
                        if let engine = catalog.engines.first(where: { $0.id == model.cloudEngineConfiguration.engine_id }) {
                            LabeledContent("Network", value: engine.network)
                        }
                        if catalog.review_uses_node_budget == true, let nodes = catalog.review_nodes_per_search {
                            Text("\(nodes.formatted()) nodes per search. Review depth varies by position.").font(.caption)
                        } else {
                            Stepper("Maximum depth: \(model.cloudEngineConfiguration.depth)", value: $model.cloudEngineConfiguration.depth, in: 1...catalog.max_depth)
                        }
                        Picker("Hash memory", selection: $model.cloudEngineConfiguration.hash_mb) {
                            ForEach([8, 16, 32, 64, 128, 256].filter { $0 <= catalog.max_hash_mb }, id: \.self) { Text("\($0) MB").tag($0) }
                        }
                        Stepper("Threads: \(model.cloudEngineConfiguration.threads)", value: $model.cloudEngineConfiguration.threads, in: 1...catalog.max_threads)
                        Text("\(catalog.nodes_per_game.formatted()) nodes per game · \(catalog.timeout_seconds)s limit").font(.caption)
                    }
                    if !catalog.engines.contains(where: \.available) { Text("No engine available").font(.caption) }
                } else {
                    LabeledContent("Stockfish", value: model.cloud.isConfigured ? "Unavailable" : "Not enabled")
                        .accessibilityElement(children: .combine).accessibilityIdentifier("engine.cloud")
                    if let cloudError { Text(cloudError).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                }
            }
            Section {
                NavigationLink("About analysis") { AnalysisInfoView() }
                NavigationLink("Open Source Licenses") { OpenSourceLicensesView() }
            }
        }
        .disclosureGroupStyle(FullRowDisclosureStyle())
        .sheet(isPresented: $showCloudSetup) { CloudSetupView() }
        .navigationTitle("Analysis engines").navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.engineConfiguration.engine) { _, _ in preset(.balanced) }
        .task {
            model.engineConfiguration = model.effectiveEngineConfiguration
            guard model.cloud.isConfigured else { return }
            do {
                let result = try await model.cloud.engines()
                catalog = result
                model.cloudEngineConfiguration.depth = min(result.max_depth, max(1, model.cloudEngineConfiguration.depth))
                model.cloudEngineConfiguration.hash_mb = min(result.max_hash_mb, max(8, model.cloudEngineConfiguration.hash_mb))
                model.cloudEngineConfiguration.threads = min(result.max_threads, max(1, model.cloudEngineConfiguration.threads))
                if !result.engines.contains(where: { $0.id == model.cloudEngineConfiguration.engine_id && $0.available }), let first = result.engines.first(where: \.available) {
                    model.cloudEngineConfiguration.engine_id = first.id
                }
            } catch { cloudError = error.localizedDescription }
        }
    }

    private enum Preset: String, CaseIterable { case quick = "Quick", balanced = "Balanced", deep = "Deep" }
    private func limits(for preset: Preset) -> (depth: Int, nodes: Int, seconds: Int) {
        let neural = model.engineConfiguration.engine.isNeural
        switch preset {
        case .quick: return (neural ? 8 : 2, neural ? 50_000 : 1_200, neural ? 1 : 2)
        case .balanced: return (neural ? 21 : 3, neural ? 100_000 : 4_000, 3)
        case .deep: return (neural ? 24 : 5, neural ? 100_000 : 16_000, neural ? 10 : 6)
        }
    }
    private func preset(_ preset: Preset) {
        let values = limits(for: preset)
        model.engineConfiguration.depth = values.depth
        model.engineConfiguration.nodesPerCandidate = values.nodes
        model.engineConfiguration.secondsPerPosition = values.seconds
    }
}
