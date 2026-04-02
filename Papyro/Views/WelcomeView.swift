import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryManager.self) private var libraryManager

    @State private var libraryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("ResearchLibrary").path
    }()
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "books.vertical.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Papyro")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A lightweight, local-first reference manager.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Library Location")
                    .font(.headline)

                HStack {
                    TextField("Library path", text: $libraryPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose Folder...") {
                        chooseFolder()
                    }
                }

                Text("Papyro will create its folder structure here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 500)

            Button("Create Library") {
                createLibrary()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 400)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a location for your Papyro library."

        if panel.runModal() == .OK, let url = panel.url {
            libraryPath = url.path
        }
    }

    private func createLibrary() {
        let url = URL(fileURLWithPath: libraryPath)
        do {
            try libraryManager.setupLibrary(at: url)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
