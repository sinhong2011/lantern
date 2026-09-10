import AppKit
import SwiftUI

struct AddServiceSheet: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Field?
    @State private var showValidation = false
    @State private var listeningPorts: [ListeningPort] = []
    @State private var isScanningPorts = false
    @State private var confirmEditorRemove = false
    @State private var pendingRemoveAlias: ServiceAlias?
    @State private var copiedLink = false

    private enum Field { case name, port, notes }

    private var isEditing: Bool { model.editingAlias != nil }
    private var cleanedName: String { ServiceAlias.sanitizedName(model.draftName) }
    private var parsedPort: Int? { Int(model.draftPort) }
    private var nameValid: Bool { !cleanedName.isEmpty }
    private var portValid: Bool {
        guard let port = parsedPort else { return false }
        return (1...65_535).contains(port)
    }
    private var canSave: Bool { nameValid && portValid }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 10) {
            headerCard

            detailsCard

            Spacer(minLength: 0)

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Remove \(pendingRemoveAlias?.hostName ?? "service")?",
            isPresented: $confirmEditorRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let alias = pendingRemoveAlias {
                    model.cancelDraft()
                    model.deleteAlias(alias)
                    model.showToast("Removed \(alias.hostName)")
                }
                pendingRemoveAlias = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoveAlias = nil }
        } message: {
            Text("Stops sharing this name on your LAN.")
        }
        .onAppear {
            if !isEditing { focused = .name }
            Task { await refreshPorts() }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 10) {
            Button(action: model.cancelDraft) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Back")

            Spacer(minLength: 8)

            Text(headerSubtitle)
                .font(.system(size: 13, weight: .semibold, design: nameValid ? .monospaced : .default))
                .foregroundStyle(nameValid ? .primary : .secondary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var headerSubtitle: String {
        if isEditing, nameValid {
            return cleanedName + ".local"
        }
        return "Pick a listening app, or type a port"
    }

    private var detailsCard: some View {
        @Bindable var model = model
        return LanternSection {
            EditorRow(title: "Label", symbol: "tag") {
                TextField("Probus / Vite", text: $model.draftNotes)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .notes)
                    .frame(minWidth: 0)
                    .multilineTextAlignment(.trailing)
            }

            rowDivider

            EditorRow(
                title: "Address",
                symbol: "globe",
                danger: showValidation && !nameValid
            ) {
                HStack(spacing: 4) {
                    TextField("probus", text: $model.draftName)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused, equals: .name)
                        .frame(minWidth: 0)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: model.draftName) { _, newValue in
                            let cleaned = ServiceAlias.sanitizedName(newValue)
                            if cleaned != newValue { model.draftName = cleaned }
                        }
                    Text(".local")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            rowDivider

            EditorRow(
                title: "Port",
                symbol: "cable.connector",
                danger: showValidation && !portValid
            ) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if let matched = matchedListeningPort {
                        Text(matched.processName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TextField("5173", text: $model.draftPort)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused, equals: .port)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .onSubmit(saveIfValid)
                    portPicker
                }
            }

            rowDivider

            linkRow
        }
    }

    private var matchedListeningPort: ListeningPort? {
        listeningPorts.first(where: { $0.port == parsedPort })
    }

    private var listeningPortSelection: Binding<Int> {
        Binding(
            get: { parsedPort ?? -1 },
            set: { newPort in
                guard let item = listeningPorts.first(where: { $0.port == newPort }) else { return }
                applyListeningPort(item)
            }
        )
    }

    private var portPicker: some View {
        Menu {
            if listeningPorts.isEmpty {
                Text(isScanningPorts ? "Scanning…" : "No listening apps")
            } else {
                Picker("Listening apps", selection: listeningPortSelection) {
                    ForEach(Array(listeningPorts.prefix(40))) { item in
                        Text(item.label)
                            .tag(item.port)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refreshPorts() }
            }
            .disabled(isScanningPorts)
        } label: {
            Group {
                if isScanningPorts {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pick a listening app")
        .accessibilityLabel("Listening apps")
    }

    private var linkRow: some View {
        Button(action: copyLink) {
            HStack(spacing: 10) {
                Image(systemName: copiedLink ? "checkmark" : "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(linkTitle)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(linkTitleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if canSave {
                    Text(copiedLink ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .help("Copy LAN URL")
        .animation(.easeOut(duration: 0.12), value: copiedLink)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            if isEditing, let editing = model.editingAlias {
                Button {
                    pendingRemoveAlias = editing
                    confirmEditorRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .lanternButton(destructive: true)
            } else {
                Text(footerStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(isEditing ? "Save" : "Add", action: saveIfValid)
                .lanternButton(prominent: true, minWidth: 72)
                .keyboardShortcut(.defaultAction)
                .opacity(canSave || !showValidation ? 1 : 0.55)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var footerStatus: String {
        if let matched = listeningPorts.first(where: { $0.port == parsedPort }) {
            return "\(matched.processName) is listening"
        }
        return isEditing ? "Editing service" : "New service"
    }

    private var linkTitle: String {
        if canSave { return previewURL }
        if showValidation && !nameValid { return "Letters, numbers, hyphen" }
        if showValidation && !portValid { return "Need a port from 1–65535" }
        return "LAN URL"
    }

    private var linkTitleColor: Color {
        if showValidation && !canSave { return LanternTheme.danger }
        return canSave ? .primary : .secondary
    }

    private var previewURL: String {
        let name = cleanedName
        let port = parsedPort ?? 8080
        if model.store.proxyEnabled && model.proxyRunning && model.store.proxyPort == 80 {
            return "http://\(name).local"
        }
        if model.store.proxyEnabled {
            return "http://\(name).local\(LanternTheme.portText(model.store.proxyPort))"
        }
        return "http://\(name).local\(LanternTheme.portText(port))"
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    private func copyLink() {
        guard canSave else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewURL, forType: .string)
        model.showToast("Copied \(previewURL)")
        copiedLink = true
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            copiedLink = false
        }
    }

    private func saveIfValid() {
        showValidation = true
        guard canSave else { return }
        model.saveDraft()
    }

    private func applyListeningPort(_ item: ListeningPort) {
        model.draftPort = String(item.port)
        if model.draftName.isEmpty {
            let suggested = item.suggestedAliasName
            model.draftName = suggested.isEmpty ? "svc\(item.port)" : suggested
        }
        if model.draftNotes.isEmpty {
            model.draftNotes = item.processName
        }
        focused = isEditing ? .port : .name
    }

    private func refreshPorts() async {
        isScanningPorts = true
        listeningPorts = await PortDiscovery.scanListeningPorts()
        isScanningPorts = false
    }
}

private struct EditorRow<Control: View>: View {
    let title: String
    let symbol: String
    var danger: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .foregroundStyle(danger ? LanternTheme.danger : .secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: 108, alignment: .leading)
                .lineLimit(1)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
