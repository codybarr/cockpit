import SwiftUI

struct ClipboardHistorySettings: View {
    @ObservedObject var history: ClipboardHistory
    @State private var isClearConfirmationPresented = false
    @State private var isClearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Clipboard History", isOn: Binding(
                    get: { history.isEnabled },
                    set: { history.setEnabled($0) }
                ))
                .disabled(!history.isLoaded || isClearing)
                Spacer()
                Button("Clear History…") { isClearConfirmationPresented = true }
                    .disabled(isClearing)
            }
            Text("Keep the last 20 copies on this Mac (up to 25 MiB; 5 MiB per copy). Selecting an entry copies it for you to paste with ⌘V.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = history.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .alert("Clear clipboard history?", isPresented: $isClearConfirmationPresented) {
            Button("Clear History", role: .destructive) {
                isClearing = true
                Task {
                    await history.clear()
                    isClearing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Cockpit’s saved copies, not the current system clipboard or any referenced files.")
        }
    }
}
