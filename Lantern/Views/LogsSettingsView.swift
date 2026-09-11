import AppKit
import SwiftUI

struct LogsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selectedHost: String?
    @State private var kind: LogKindFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Kind", selection: $kind) {
                ForEach(LogKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                TextField(searchPrompt, text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Service", selection: $selectedHost) {
                    Text("All").tag(Optional<String>.none)
                    ForEach(model.store.aliases) { alias in
                        Text(alias.hostName).tag(Optional(alias.hostName))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 140)
                Button("Copy") { copyVisible() }
                    .disabled(visible.isEmpty)
                Button("Clear", role: .destructive) { model.logs.clear() }
                    .disabled(model.logs.entries.isEmpty)
            }

            if visible.isEmpty {
                Text(emptyCopy)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { entry in
                            switch entry {
                            case .access(let event):
                                accessRow(event)
                            case .activity(let event):
                                activityRow(event)
                            }
                            Divider().opacity(0.35)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var visible: [LogEntry] {
        model.logs.filtered(kind: kind, host: selectedHost, query: query)
    }

    private var searchPrompt: String {
        kind == .activity ? "Search activity" : "Search path, host, client"
    }

    private var emptyCopy: String {
        if !model.logs.entries.isEmpty { return "No matches." }
        switch kind {
        case .activity: return "Broadcast, bind, and service changes will show up here."
        case .access: return "Hits to name.local will show up here."
        case .all: return "Hits and app events will show up here."
        }
    }

    private func accessRow(_ event: AccessEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.timeText)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(event.method)
                .fontWeight(.semibold)
                .frame(width: 44, alignment: .leading)
            Text(event.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(event.displayHost)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(event.displayClient)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(event.outcome.label)
                .foregroundStyle(event.outcome.isFailure ? LanternTheme.danger : LanternTheme.live)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.copyLine)
    }

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.timeText)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(event.label)
                .fontWeight(.semibold)
                .frame(width: 72, alignment: .leading)
            Text(event.message)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(event.isFailure ? LanternTheme.danger : .primary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.copyLine)
    }

    private func copyVisible() {
        let text = visible.map(\.copyLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showToast("Copied \(visible.count) log lines")
    }
}
