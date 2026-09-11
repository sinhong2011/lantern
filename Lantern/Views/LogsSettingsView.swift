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
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader
                        Divider().opacity(0.35)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible) { entry in
                                logRow(entry)
                                Divider().opacity(0.22)
                            }
                        }
                    }
                    .frame(minWidth: LogColumns.rowWidth, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 8) {
                Text(model.logs.fileURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Show in Finder") {
                    let url = model.logs.fileURL
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? Data().write(to: url)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .controlSize(.small)
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

    private var columnHeader: some View {
        HStack(spacing: LogColumns.spacing) {
            Text("Time").frame(width: LogColumns.time, alignment: .leading)
            Text("Kind").frame(width: LogColumns.kind, alignment: .leading)
            Text("Detail").frame(width: LogColumns.detail, alignment: .leading)
            Text("Host").frame(width: LogColumns.host, alignment: .leading)
            Text("Client").frame(width: LogColumns.client, alignment: .leading)
            Text("Status").frame(width: LogColumns.status, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.vertical, 4)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LogColumns.spacing) {
            Text(entry.timeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: LogColumns.time, alignment: .leading)

            Text(entry.kindText)
                .fontWeight(.semibold)
                .foregroundStyle(kindColor(entry))
                .frame(width: LogColumns.kind, alignment: .leading)

            Text(entry.detailText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: LogColumns.detail, alignment: .leading)
                .foregroundStyle(entry.isFailure ? LanternTheme.danger : .primary)

            Text(entry.hostText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: LogColumns.host, alignment: .leading)

            Text(entry.clientText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: LogColumns.client, alignment: .leading)

            Text(entry.statusText)
                .foregroundStyle(entry.isFailure ? LanternTheme.danger : LanternTheme.live)
                .lineLimit(1)
                .frame(width: LogColumns.status, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.copyLine)
    }

    private func kindColor(_ entry: LogEntry) -> Color {
        if entry.isFailure { return LanternTheme.danger }
        if case .access = entry { return LanternTheme.accent }
        return .secondary
    }

    private func copyVisible() {
        let text = visible.map(\.copyLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showToast("Copied \(visible.count) log lines")
    }
}

private enum LogColumns {
    static let spacing: CGFloat = 12
    static let time: CGFloat = 64
    static let kind: CGFloat = 72
    static let detail: CGFloat = 200
    static let host: CGFloat = 132
    static let client: CGFloat = 120
    static let status: CGFloat = 120

    static var rowWidth: CGFloat {
        time + kind + detail + host + client + status + spacing * 5
    }
}
