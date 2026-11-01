import SwiftUI
import AppKit
import PassagesCore

struct SettingsView: View {
    @EnvironmentObject var model: LibraryViewModel

    var body: some View {
        TabView {
            ExportSettingsTab()
                .environmentObject(model)
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

            NotionSettingsTab()
                .environmentObject(model)
                .tabItem {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                }
        }
        .frame(width: 480)
    }
}

struct ExportSettingsTab: View {
    @EnvironmentObject var model: LibraryViewModel

    var body: some View {
        Form {
            Section {
                Picker("Default format", selection: $model.format) {
                    ForEach(HighlightExporter.Format.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            } header: {
                Text("Format")
            } footer: {
                Text("Used for exports saved to your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Include notes", isOn: $model.includeNotes)
                Toggle("Group by chapter", isOn: $model.groupByChapter)
                Toggle("Include metadata (color | date)", isOn: $model.includeMetadata)
            } header: {
                Text("Content")
            } footer: {
                Text("Notes are included in file and Notion exports. Chapter grouping and metadata apply to files only. Chapters appear where Apple Books provides them; metadata adds the highlight color and creation date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
    }
}

private typealias SettingsState<Value> = SwiftUI.State<Value>

struct NotionSettingsTab: View {
    @EnvironmentObject var model: LibraryViewModel
    @SettingsState private var apiKey = ""
    @SettingsState private var revealKey = false
    @SettingsState private var isSaving = false
    @SettingsState private var operationTask: Task<Void, Never>?
    @SettingsState private var toastTask: Task<Void, Never>?
    @SettingsState private var toastMessage: String?
    @SettingsState private var toastFailed = false

    var body: some View {
        Form {
            Section("Notion") {
                Text("Add highlights to a Notion page using your own integration token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Group {
                        if revealKey {
                            TextField("Integration token", text: $apiKey)
                        } else {
                            SecureField("Integration token", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSaving)
                    Button { revealKey.toggle() } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .help(revealKey ? "Hide token" : "View token")
                    .accessibilityLabel(revealKey ? "Hide token" : "View token")
                }
                HStack {
                    Button {
                        let value = apiKey
                        isSaving = true
                        operationTask = Task {
                            defer { isSaving = false }
                            do {
                                try await model.saveNotionToken(value)
                                revealKey = false
                                showToast("Token verified and saved in Keychain.")
                            } catch is CancellationError {
                                return
                            } catch let error as NotionClient.NotionError {
                                showToast("Token not saved. \(error.description)", failed: true)
                            } catch {
                                showToast("Token not saved. \(error.localizedDescription)", failed: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().controlSize(.mini) }
                            Text(isSaving ? "Verifying…" : "Save token")
                        }
                    }
                    .disabled(isSaving || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Verify the token with Notion before saving it securely in Keychain.")
                    Spacer()
                    Button(role: .destructive) {
                        isSaving = true
                        operationTask = Task {
                            defer { isSaving = false }
                            let removed = await model.deleteNotionToken()
                            apiKey = ""
                            revealKey = false
                            showToast(removed ? "Token deleted." : "Couldn’t delete the saved token from Keychain.", failed: !removed)
                        }
                    } label: {
                        Label("Delete token", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete the saved Notion token from Keychain.")
                    .disabled(isSaving || (!model.hasNotionKey && !model.tokenStorageNeedsAttention))
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Label(toastMessage, systemImage: toastFailed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(toastFailed ? Color.red : Color.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .onAppear {
            revealKey = false
            apiKey = model.notionToken
            if model.tokenStorageNeedsAttention {
                showToast("Saved token unavailable. Paste and save it again.", failed: true)
            }
        }
        .onDisappear {
            operationTask?.cancel()
            toastTask?.cancel()
            revealKey = false
            apiKey = ""
        }
    }

    @MainActor
    private func showToast(_ message: String, failed: Bool = false) {
        toastTask?.cancel()
        toastFailed = failed
        toastMessage = message
        toastTask = Task {
            do { try await Task.sleep(for: .seconds(failed ? 8 : 4)) }
            catch { return }
            toastMessage = nil
        }
    }
}
