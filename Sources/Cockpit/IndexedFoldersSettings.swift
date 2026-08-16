import AppKit
import SwiftUI

@MainActor
final class IndexedFoldersSettings: ObservableObject {
    @Published private(set) var folders: [URL] = []
    @Published var errorMessage: String?

    private let index: any FilenameIndexing

    init(index: any FilenameIndexing) {
        self.index = index
        reload()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Index"
        panel.message = "Cockpit searches filenames only in folders you choose."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Indexed Folder"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try index.addIndexedFolder(folder)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ folder: URL) {
        do {
            try index.removeIndexedFolder(folder)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry(_ folder: URL) {
        do {
            try index.retry(folder: folder)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func state(for folder: URL) -> IndexedFolderState { index.folderState(for: folder) }

    private func reload() {
        folders = index.indexedFolders
    }
}

@MainActor
final class IndexedFoldersWindowController: NSWindowController {
    init(index: any FilenameIndexing) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Indexed Folders"
        window.contentMaxSize = NSSize(width: 900, height: 600)
        window.center()
        let hostingView = NSHostingView(rootView: IndexedFoldersView(settings: IndexedFoldersSettings(index: index)))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct IndexedFoldersView: View {
    @ObservedObject var settings: IndexedFoldersSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Indexed folders")
                .font(.title2.weight(.semibold))
            Text("Cockpit does not search all of macOS. It searches filenames only in the folders you select; file contents and Spotlight are never searched.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(settings.folders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.path).lineLimit(1)
                        Spacer()
                        if settings.state(for: folder) == .unavailable {
                            Text("Unavailable").foregroundStyle(.red)
                            Button("Retry") { settings.retry(folder) }
                        }
                        Button("Remove") { settings.remove(folder) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if settings.folders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark").font(.title)
                        Text("No indexed folders").font(.headline)
                        Text("Add a folder to make its filenames searchable with an apostrophe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = settings.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Add Folder…") { settings.chooseFolder() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
