import SwiftUI
import i2MessageCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AppSettings()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("Local privacy, permissions, appearance, and search indexing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)

            I2Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appearanceSection
                    permissionsSection
                    searchSection
                    privacySection
                    diagnosticsSection
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
            }

            I2Divider()

            HStack {
                Text("Settings are stored locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    draft = AppSettings()
                }
                Button("Save") {
                    Task { await model.updateSettings(draft) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(16)
        }
        .background(I2Palette.appBackground)
        .onAppear {
            draft = model.settings
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            I2SectionLabel(title: "Appearance")
                .padding(.horizontal, -14)

            Picker("Theme", selection: $draft.theme) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }
            .pickerStyle(.segmented)

            Picker("Transcript Density", selection: $draft.transcriptDensity) {
                Text("Comfortable").tag(TranscriptDensity.comfortable)
                Text("Compact").tag(TranscriptDensity.compact)
            }
            .pickerStyle(.segmented)

            Stepper("Messages per page: \(draft.pageSize)", value: $draft.pageSize, in: 20...120, step: 10)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            I2SectionLabel(title: "Permissions")
                .padding(.horizontal, -14)

            ForEach(AppPermission.allCases, id: \.self) { permission in
                let status = model.permissionSnapshot.status(for: permission)
                HStack(alignment: .top, spacing: 10) {
                    PermissionStateIcon(state: status?.state ?? .notDetermined)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.displayName)
                            .font(.callout.weight(.medium))
                        Text(status?.reason ?? reason(for: permission))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(status?.state == .granted ? "Refresh" : "Request") {
                        Task { await model.requestPermission(permission) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            I2SectionLabel(title: "Search Indexes")
                .padding(.horizontal, -14)

            Toggle("Enable exact search index", isOn: $draft.search.exactIndexEnabled)
            Toggle("Enable semantic search index", isOn: $draft.search.semanticIndexEnabled)
            Toggle("Index attachment filenames", isOn: $draft.search.indexAttachments)

            HStack {
                Text("Semantic model")
                Spacer()
                TextField("Model", text: Binding(
                    get: { draft.search.semanticModelIdentifier ?? "" },
                    set: { draft.search.semanticModelIdentifier = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }

            IndexingStatusView(progress: model.indexingProgress)

            Button {
                Task { await model.rebuildIndexes() }
            } label: {
                Label("Rebuild Indexes", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            I2SectionLabel(title: "Privacy")
                .padding(.horizontal, -14)

            Toggle("Redact private data from logs", isOn: $draft.privacy.redactLogs)
            Toggle("Allow external embedding providers", isOn: $draft.privacy.allowExternalEmbeddingProviders)

            Text("External embedding providers are off by default. Semantic search is designed for local indexing unless the user explicitly changes this future capability.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            I2SectionLabel(title: "Diagnostics")
                .padding(.horizontal, -14)

            HStack(spacing: 8) {
                Button {
                    model.toggleOfflineMode()
                } label: {
                    Label(model.isOffline ? "Disable Offline" : "Preview Offline", systemImage: "wifi.slash")
                }
                .buttonStyle(.bordered)

                Button {
                    model.showMockError()
                } label: {
                    Label("Show Error Banner", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func reason(for permission: AppPermission) -> String {
        switch permission {
        case .fullDiskAccess:
            return "Needed for read-only access to Messages history."
        case .contacts:
            return "Needed to resolve names and avatars."
        case .appleEventsMessages:
            return "Needed for supported Messages automation."
        case .notifications:
            return "Needed for local message notifications."
        }
    }
}
