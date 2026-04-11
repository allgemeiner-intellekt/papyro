import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IntegrationsSettingsTab()
                .tabItem {
                    Label("Symlinks", systemImage: "link")
                }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    @State private var translationServerURL: String = ""
    @State private var saveError: String?
    @State private var savedConfirmation: Bool = false

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Library Path") {
                    Text(appState.libraryConfig?.libraryPath ?? "Not set")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section {
                TextField(
                    "Server URL",
                    text: $translationServerURL,
                    prompt: Text("https://translate.example.com")
                )
                .autocorrectionDisabled()
                .onSubmit { save() }

                HStack {
                    Text("Zotero translation-server endpoint. Leave blank to disable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if savedConfirmation {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Button("Save") { save() }
                        .disabled(!isDirty)
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Translation Server")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            translationServerURL = appState.libraryConfig?.translationServerURL ?? ""
        }
    }

    private var isDirty: Bool {
        let current = appState.libraryConfig?.translationServerURL ?? ""
        return translationServerURL.trimmingCharacters(in: .whitespaces) != current
    }

    private func save() {
        saveError = nil
        let trimmed = translationServerURL.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty {
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else {
                saveError = "Enter a valid http:// or https:// URL."
                return
            }
        }

        guard var config = appState.libraryConfig else {
            saveError = "No library loaded."
            return
        }
        config.translationServerURL = trimmed.isEmpty ? nil : trimmed

        do {
            let configURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent("config.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            appState.libraryConfig = config
            translationServerURL = trimmed
            withAnimation { savedConfirmation = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { withAnimation { savedConfirmation = false } }
            }
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Integrations Tab

private struct IntegrationsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var managedSymlinks: [ManagedSymlink] = []
    @State private var symlinkHealthMap: [UUID: SymlinkHealth] = [:]
    @State private var showingSourcePicker = false
    @State private var showingUnlinkConfirmation = false
    @State private var symlinkToUnlink: ManagedSymlink?

    private let symlinkService = ManagedSymlinkService()

    private var libraryRoot: URL? {
        guard let path = appState.libraryConfig?.libraryPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked Folders")
                        .font(.headline)
                    Text("Symlinks from your library to external locations like Obsidian vaults")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    do {
                        try coordinator.projectService.rebuildSymlinks(papers: coordinator.papers)
                    } catch {
                        appState.userError = UserFacingError(
                            title: "Couldn't rebuild symlinks",
                            message: error.localizedDescription
                        )
                    }
                } label: {
                    Label("Rebuild", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .help("Rebuild project symlinks from current papers")

                Button("Link Folder…") {
                    showingSourcePicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            // Symlink list
            if managedSymlinks.isEmpty {
                ContentUnavailableView(
                    "No Linked Folders",
                    systemImage: "link.badge.plus",
                    description: Text("Link library folders to external destinations for easy access in Obsidian or by agents.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(managedSymlinks) { symlink in
                        symlinkRow(symlink)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
        .padding()
        .onAppear { refreshSymlinks() }
        .sheet(isPresented: $showingSourcePicker) {
            SourcePickerSheet(
                libraryRoot: libraryRoot,
                onLink: { sourceRelativePath, destinationPath in
                    createLink(sourceRelativePath: sourceRelativePath, destinationPath: destinationPath)
                }
            )
        }
        .alert("Unlink Folder?", isPresented: $showingUnlinkConfirmation) {
            Button("Unlink", role: .destructive) {
                if let symlink = symlinkToUnlink {
                    unlinkFolder(symlink)
                }
            }
            Button("Cancel", role: .cancel) {
                symlinkToUnlink = nil
            }
        } message: {
            if let symlink = symlinkToUnlink {
                Text("Remove link from \(symlink.sourceRelativePath) to \(URL(fileURLWithPath: symlink.destinationPath).lastPathComponent)? The source files are not affected.")
            }
        }
    }

    @ViewBuilder
    private func symlinkRow(_ symlink: ManagedSymlink) -> some View {
        let health = symlinkHealthMap[symlink.id] ?? .healthy

        HStack(spacing: 12) {
            Circle()
                .fill(healthColor(health))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(symlink.label)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(symlink.sourceRelativePath)
                        .foregroundStyle(.secondary)
                    Text("→")
                        .foregroundStyle(.quaternary)
                    Text(abbreviatePath(symlink.destinationPath))
                        .foregroundStyle(health == .healthy ? .secondary : healthColor(health))
                }
                .font(.caption)
            }

            Spacer()

            if health != .healthy {
                Button("Repair") {
                    repairLink(symlink)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Reveal") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: symlink.destinationPath)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(health == .broken)

            Button("Unlink") {
                symlinkToUnlink = symlink
                showingUnlinkConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    private func healthColor(_ health: SymlinkHealth) -> Color {
        switch health {
        case .healthy: .green
        case .destinationMissing: .yellow
        case .broken: .red
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func refreshSymlinks() {
        managedSymlinks = appState.libraryConfig?.managedSymlinks ?? []
        for symlink in managedSymlinks {
            symlinkHealthMap[symlink.id] = symlinkService.checkHealth(symlink)
        }
        appState.symlinkHealthIssueCount = symlinkHealthMap.values.filter { $0 != .healthy }.count
    }

    private func createLink(sourceRelativePath: String, destinationPath: String) {
        guard let libRoot = libraryRoot else { return }
        do {
            let symlink = try symlinkService.createLink(
                sourceRelativePath: sourceRelativePath,
                destinationPath: destinationPath,
                libraryRoot: libRoot
            )
            appState.libraryConfig?.managedSymlinks.append(symlink)
            try saveConfig()
            refreshSymlinks()
        } catch {
            appState.userError = UserFacingError(
                title: "Couldn't link folder",
                message: error.localizedDescription
            )
        }
    }

    private func unlinkFolder(_ symlink: ManagedSymlink) {
        do {
            try symlinkService.removeLink(symlink)
            appState.libraryConfig?.managedSymlinks.removeAll { $0.id == symlink.id }
            try saveConfig()
            refreshSymlinks()
        } catch {
            appState.userError = UserFacingError(
                title: "Couldn't unlink folder",
                message: error.localizedDescription
            )
        }
        symlinkToUnlink = nil
    }

    private func repairLink(_ symlink: ManagedSymlink) {
        guard let libRoot = libraryRoot else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select New Destination"

        guard panel.runModal() == .OK, let newURL = panel.url else { return }
        let newDestPath = newURL.appendingPathComponent(URL(fileURLWithPath: symlink.destinationPath).lastPathComponent).path

        do {
            let repaired = try symlinkService.repairLink(symlink, newDestinationPath: newDestPath, libraryRoot: libRoot)
            if let index = appState.libraryConfig?.managedSymlinks.firstIndex(where: { $0.id == symlink.id }) {
                appState.libraryConfig?.managedSymlinks[index] = repaired
            }
            try saveConfig()
            refreshSymlinks()
        } catch {
            appState.userError = UserFacingError(
                title: "Couldn't repair link",
                message: error.localizedDescription
            )
        }
    }

    private func saveConfig() throws {
        guard let config = appState.libraryConfig else { return }
        let configURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}

// MARK: - Source Picker Sheet

private struct SourcePickerSheet: View {
    let libraryRoot: URL?
    let onLink: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource: String?

    private var sourceFolders: [(label: String, relativePath: String)] {
        var folders: [(String, String)] = [
            ("Notes", "notes"),
            ("Templates", "templates"),
            ("Text Cache", ".cache/text"),
        ]

        if let libRoot = libraryRoot {
            let symlinksDir = libRoot.appendingPathComponent(".symlinks")
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: symlinksDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) {
                for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        let slug = url.lastPathComponent
                        folders.append(("Project: \(slug)", ".symlinks/\(slug)"))
                    }
                }
            }
        }

        return folders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Source Folder")
                .font(.headline)

            List(sourceFolders, id: \.relativePath, selection: $selectedSource) { folder in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(folder.label)
                    Spacer()
                    Text(folder.relativePath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .tag(folder.relativePath)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Choose Destination…") {
                    pickDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSource == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }

    private func pickDestination() {
        guard let source = selectedSource else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Link"
        panel.message = "Choose where to create the symlink for \(source)"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let sourceName = URL(fileURLWithPath: source).lastPathComponent
        let finalDest = destURL.appendingPathComponent(sourceName).path

        onLink(source, finalDest)
        dismiss()
    }
}
