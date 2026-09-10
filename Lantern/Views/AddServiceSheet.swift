import SwiftUI

struct AddServiceSheet: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Field?
    @State private var showValidation = false
    @State private var listeningPorts: [ListeningPort] = []
    @State private var isScanningPorts = false
    @State private var selectedListeningPort: Int?
    @State private var confirmEditorRemove = false
    @State private var pendingRemoveAlias: ServiceAlias?

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

    private var matchedListening: ListeningPort? {
        guard let port = parsedPort else { return nil }
        return listeningPorts.first { $0.port == port }
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { model.cancelDraft() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .lanternButton()
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isEditing ? "Edit Service" : "Add Service")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Pick a listening port, or type one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 12) {
                fieldBlock(
                    title: "Name",
                    hint: nameValid ? "Becomes \(cleanedName).local" : "Letters, numbers, hyphen",
                    danger: showValidation && !nameValid
                ) {
                    TextField("web", text: $model.draftName)
                        .textFieldStyle(.plain)
                        .focused($focused, equals: .name)
                        .onChange(of: model.draftName) { _, newValue in
                            let cleaned = ServiceAlias.sanitizedName(newValue)
                            if cleaned != newValue { model.draftName = cleaned }
                        }
                }

                fieldBlock(
                    title: "Local port",
                    hint: portHint,
                    danger: showValidation && !portValid
                ) {
                    TextField("8080", text: Binding(
                        get: { model.draftPort },
                        set: { model.draftPort = $0; selectedListeningPort = Int($0) }
                    ))
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .port)
                    .font(.system(.body, design: .monospaced))
                }

                listeningPortsSection

                fieldBlock(title: "Notes", hint: "Optional") {
                    TextField("OrbStack compose web", text: $model.draftNotes)
                        .textFieldStyle(.plain)
                        .focused($focused, equals: .notes)
                }

                if nameValid {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(LanternTheme.accent)
                        Text(previewURL)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .lanternField()
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                if isEditing, let editing = model.editingAlias {
                    Button("Remove") {
                        confirmRemoveFromEditor(editing)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LanternTheme.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LanternTheme.danger.opacity(0.12)))
                }
                Spacer()
                Button("Cancel") { model.cancelDraft() }
                    .lanternButton(minWidth: 76)
                Button(isEditing ? "Save" : "Add") {
                    showValidation = true
                    guard canSave else { return }
                    model.saveDraft()
                }
                .lanternButton(prominent: true, minWidth: 76)
                .keyboardShortcut(.defaultAction)
                .opacity(canSave || !showValidation ? 1 : 0.55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Button("Cancel", role: .cancel) {
                pendingRemoveAlias = nil
            }
        } message: {
            Text("Stops advertising on your LAN.")
        }
        .onAppear {
            focused = .name
            Task { await refreshPorts() }
        }
    }

    private func confirmRemoveFromEditor(_ alias: ServiceAlias) {
        pendingRemoveAlias = alias
        confirmEditorRemove = true
    }

    private var listeningPortsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Listening now")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if isScanningPorts {
                    ProgressView().controlSize(.mini)
                }
                Button {
                    Task { await refreshPorts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isScanningPorts)
            }

            Group {
                if isScanningPorts && listeningPorts.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                } else if listeningPorts.isEmpty {
                    Text("No listening TCP ports. Publish a container port, then refresh.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(listeningPorts.prefix(40).enumerated()), id: \.element.id) { index, item in
                                Button { applyListeningPort(item) } label: {
                                    listeningRow(item)
                                }
                                .buttonStyle(.plain)
                                if index < min(listeningPorts.count, 40) - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.07))
                                        .frame(height: 1)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .lanternSurface(radius: LanternTheme.radiusL)
        }
    }

    private func listeningRow(_ item: ListeningPort) -> some View {
        let selected = selectedListeningPort == item.port
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? LanternTheme.accentMuted : Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: selected ? "checkmark" : "network")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? LanternTheme.accent : .secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.processName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.address)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(verbatim: LanternTheme.portText(item.port))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? LanternTheme.accent : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? LanternTheme.accent.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
    }

    private var portHint: String {
        if let matched = matchedListening {
            return "\(matched.processName) · \(matched.address)"
        }
        if let port = parsedPort, (1...65_535).contains(port) {
            return "Host port \(port)"
        }
        return "Pick from the list, or type 1–65535"
    }

    private var previewURL: String {
        let name = cleanedName
        let port = parsedPort ?? 8080
        if model.store.proxyEnabled && model.proxyRunning && model.store.proxyPort == 80 {
            return "http://\(name).local"
        }
        if model.store.proxyEnabled {
            return "http://\(name).local:\(model.store.proxyPort)"
        }
        return "http://\(name).local:\(port)"
    }

    private func applyListeningPort(_ item: ListeningPort) {
        model.draftPort = String(item.port)
        selectedListeningPort = item.port
        if model.draftName.isEmpty {
            let suggested = item.suggestedAliasName
            model.draftName = suggested.isEmpty ? "svc\(item.port)" : suggested
        }
        if model.draftNotes.isEmpty {
            model.draftNotes = item.processName
        }
        focused = .name
    }

    private func refreshPorts() async {
        isScanningPorts = true
        listeningPorts = await PortDiscovery.scanListeningPorts()
        selectedListeningPort = Int(model.draftPort)
        isScanningPorts = false
    }

    private func fieldBlock<Content: View>(
        title: String,
        hint: String,
        danger: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content()
                .lanternField()
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(danger ? LanternTheme.danger : Color.secondary.opacity(0.85))
        }
    }
}
