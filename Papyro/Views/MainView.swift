import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showHealthBanner = false
    @State private var showPendingBanner = true

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showPendingBanner && coordinator.pendingPapers.count > 0 {
                    pendingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showHealthBanner {
                    healthBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .alert(item: $appState.userError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onKeyPress("1") {
            setSelectedPaperStatus(.toRead)
        }
        .onKeyPress("2") {
            setSelectedPaperStatus(.reading)
        }
        .onKeyPress("3") {
            setSelectedPaperStatus(.archived)
        }
        .onKeyPress("e", phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return openOrCreateNote()
        }
        .onAppear {
            if appState.symlinkHealthIssueCount > 0 {
                withAnimation { showHealthBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation { showHealthBanner = false }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingBanner: some View {
        let count = coordinator.pendingPapers.count
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            Text("\(count) \(count == 1 ? "paper needs" : "papers need") metadata")
                .font(.callout)
            Spacer()
            Button(coordinator.isResolvingPending ? "Resolving…" : "Resolve") {
                Task { await coordinator.resolveAllPending() }
            }
            .disabled(coordinator.isResolvingPending)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var healthBanner: some View {
        let count = appState.symlinkHealthIssueCount
        Button {
            showHealthBanner = false
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(count) linked \(count == 1 ? "folder" : "folders") \(count == 1 ? "needs" : "need") attention")
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func openOrCreateNote() -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        guard let paper = coordinator.papers.first(where: { $0.id == paperId }) else { return .ignored }

        if let notePath = paper.notePath, let config = appState.libraryConfig {
            let noteURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent(notePath)
            if FileManager.default.fileExists(atPath: noteURL.path) {
                NSWorkspace.shared.open(noteURL)
                return .handled
            }
        }

        switch coordinator.createNote(for: paperId) {
        case .success(let noteURL):
            NSWorkspace.shared.open(noteURL)
        case .failure(let error):
            appState.userError = UserFacingError(
                title: "Couldn't create note",
                message: error.localizedDescription
            )
        }
        return .handled
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: paperId, status: status)
        return .handled
    }
}
