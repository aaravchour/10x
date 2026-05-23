import SwiftUI

struct ConnectionsSettingsView: View {
    @State private var service = LLMConnectionService.shared
    @State private var showingAddSheet = false
    @State private var editingConnection: LLMConnection?
    @State private var testingConnectionIDs: Set<UUID> = []
    @State private var testResults: [UUID: LLMConnectionTestResult] = [:]

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Connections") {
                Button {
                    editingConnection = nil
                    showingAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add Connection")
                            .font(Theme.geist(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                            .fill(Theme.accent.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                            .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            routingPanel

            if service.connections.isEmpty {
                emptyState
            } else {
                connectionsList
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ConnectionEditorSheet(connection: editingConnection)
        }
    }

    private var routingPanel: some View {
        SettingsPanel("Generation Routing") {
            HStack(alignment: .center, spacing: Theme.spacingLG) {
                Image(systemName: service.activeConnection == nil ? "cloud" : "bolt.horizontal.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(service.activeConnection == nil ? Theme.textSecondary : Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(service.activeConnection?.displayName ?? "Default 10x backend")
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(service.activeConnection == nil
                         ? "No direct provider is active. Requests use the hosted backend."
                         : "New generations use this direct provider before falling back to hosted billing flows.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if service.activeConnection != nil {
                    Button {
                        service.setActive(nil)
                    } label: {
                        Text("Use Backend")
                            .font(Theme.geist(12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                    .fill(Theme.surfaceInset)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        SettingsPanel("Direct Providers") {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                HStack(alignment: .top, spacing: Theme.spacingLG) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.10))
                        Image(systemName: "network")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bring your own LLM")
                            .font(Theme.geist(18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Connect OpenAI, Claude, OpenRouter, or a local Ollama server. Once a connection is active, generation streams directly through that provider.")
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    editingConnection = nil
                    showingAddSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add First Connection")
                            .font(Theme.geist(13, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                            .fill(Theme.accent)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectionsList: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            providerSummaryStrip

            HStack(alignment: .firstTextBaseline) {
                Text("Saved Connections")
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(service.connections.count) total")
                    .font(Theme.geistMono(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            ForEach(service.connections) { connection in
                connectionCard(connection)
            }
        }
    }

    private var providerSummaryStrip: some View {
        HStack(spacing: Theme.spacingSM) {
            ForEach(LLMProvider.allCases) { provider in
                providerSummaryItem(provider)
            }
        }
    }

    private func providerSummaryItem(_ provider: LLMProvider) -> some View {
        let count = service.connections.filter { $0.provider == provider }.count
        let activeCount = service.connections.filter { $0.provider == provider && service.activeConnectionID == $0.id }.count

        return HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(activeCount > 0 ? Theme.accent : Theme.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(Theme.geist(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text("\(count)")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill(activeCount > 0 ? Theme.accent.opacity(0.08) : Theme.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(activeCount > 0 ? Theme.accent.opacity(0.20) : Theme.separator, lineWidth: 1)
        )
    }

    private func connectionCard(_ connection: LLMConnection) -> some View {
        let isSelected = service.activeConnectionID == connection.id
        let isReady = service.isUsable(connection)
        let validation = service.validationMessage(for: connection)
        let isTesting = testingConnectionIDs.contains(connection.id)
        let result = testResults[connection.id]

        return VStack(alignment: .leading, spacing: Theme.spacingLG) {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                providerIcon(connection.provider, highlighted: isSelected && isReady)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                        Text(connection.displayName)
                            .font(Theme.geist(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        connectionChip(connection.provider.displayName, color: Theme.textSecondary, filled: false)

                        if isSelected && isReady {
                            connectionChip("Active", color: Theme.accent, filled: true)
                        } else if isSelected {
                            connectionChip("Selected", color: Theme.warning, filled: true)
                        } else if !isReady {
                            connectionChip("Needs Setup", color: Theme.warning, filled: true)
                        } else {
                            connectionChip("Ready", color: Theme.success, filled: false)
                        }
                    }

                    connectionMetadataGrid(connection, validation: validation)
                }

                Spacer()

                Menu {
                    if !isSelected {
                        Button {
                            service.setActive(connection)
                        } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                        .disabled(!isReady)
                    } else {
                        Button {
                            service.setActive(nil)
                        } label: {
                            Label("Deactivate", systemImage: "xmark.circle")
                        }
                    }

                    Button {
                        testConnection(connection)
                    } label: {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(isTesting)

                    Button {
                        editingConnection = connection
                        showingAddSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        service.delete(connection)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .fill(Theme.surfaceInset)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            if let result {
                connectionTestBanner(result)
            }

            HStack(spacing: Theme.spacingSM) {
                Button {
                    if isSelected {
                        service.setActive(nil)
                    } else {
                        service.setActive(connection)
                    }
                } label: {
                    Label(isSelected ? "Deactivate" : "Use for Generation", systemImage: isSelected ? "power" : "bolt.horizontal")
                }
                .buttonStyle(ConnectionActionButtonStyle(kind: isSelected ? .secondary : .primary))
                .disabled(!isReady && !isSelected)

                Button {
                    testConnection(connection)
                } label: {
                    if isTesting {
                        Label("Testing...", systemImage: "hourglass")
                    } else {
                        Label("Test", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .buttonStyle(ConnectionActionButtonStyle(kind: .secondary))
                .disabled(isTesting)

                Button {
                    editingConnection = connection
                    showingAddSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(ConnectionActionButtonStyle(kind: .secondary))

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.055) : Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.22) : Theme.separator, lineWidth: 1)
        )
    }

    private func providerIcon(_ provider: LLMProvider, highlighted: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill(highlighted ? Theme.accent.opacity(0.12) : Theme.surfaceInset)
            Image(systemName: provider.iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlighted ? Theme.accent : Theme.textSecondary)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(highlighted ? Theme.accent.opacity(0.22) : Theme.separator, lineWidth: 1)
        )
    }

    private func connectionMetadataGrid(_ connection: LLMConnection, validation: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Theme.spacingSM) {
                metadataItem("Model", value: connection.model, monospace: true)
                metadataItem("Key", value: service.hasAPIKey(for: connection) ? "Saved" : "None")
            }

            HStack(spacing: Theme.spacingSM) {
                metadataItem("Base URL", value: connection.effectiveBaseURL, monospace: true)
                metadataItem("State", value: connection.isEnabled ? "Enabled" : "Disabled")
            }

            if let validation {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(validation)
                        .font(Theme.geist(11, weight: .medium))
                }
                .foregroundStyle(Theme.warning)
                .padding(.top, 2)
            }
        }
    }

    private func metadataItem(_ label: String, value: String, monospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.geistMono(9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Text(value.isEmpty ? "Not set" : value)
                .font(monospace ? Theme.geistMono(11, weight: .medium) : Theme.geist(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionChip(_ text: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.geistMono(10, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(filled ? color.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(color.opacity(filled ? 0 : 0.18), lineWidth: 1)
        )
    }

    private func connectionTestBanner(_ result: LLMConnectionTestResult) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(result.isSuccess ? Theme.success : Theme.warning)
                .padding(.top, 1)

            Text(result.message)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(result.isSuccess ? Theme.textSecondary : Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill((result.isSuccess ? Theme.success : Theme.warning).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke((result.isSuccess ? Theme.success : Theme.warning).opacity(0.18), lineWidth: 1)
        )
    }

    private func testConnection(_ connection: LLMConnection) {
        guard !testingConnectionIDs.contains(connection.id) else { return }
        testingConnectionIDs.insert(connection.id)
        testResults[connection.id] = nil

        Task {
            let result = await service.test(connection)
            await MainActor.run {
                testResults[connection.id] = result
                testingConnectionIDs.remove(connection.id)
            }
        }
    }
}

private struct ConnectionActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.geist(12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(kind == .primary ? .black : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .fill(kind == .primary ? Theme.accent : Theme.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .stroke(kind == .primary ? Color.clear : Theme.separator, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

// MARK: - Editor Sheet

struct ConnectionEditorSheet: View {
    let connection: LLMConnection?
    @Environment(\.dismiss) private var dismiss
    @State private var service = LLMConnectionService.shared
    @State private var name = ""
    @State private var provider: LLMProvider = .openai
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var isEnabled = true
    @State private var isTesting = false
    @State private var testResult: LLMConnectionTestResult?
    @State private var isFetchingModels = false
    @State private var fetchedOllamaModels: [String] = []
    @State private var modelFetchMessage: String?
    @FocusState private var focusedField: ConnectionField?

    private enum ConnectionField: Hashable {
        case name, apiKey, baseURL, model
    }

    private var isEditing: Bool { connection != nil }

    init(connection: LLMConnection? = nil) {
        self.connection = connection
        if let connection {
            _name = State(initialValue: connection.name)
            _provider = State(initialValue: connection.provider)
            _baseURL = State(initialValue: connection.baseURL)
            _model = State(initialValue: connection.model)
            _isEnabled = State(initialValue: connection.isEnabled)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            formContent
            footer
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(Theme.surface)
        .onAppear {
            if isEditing, let connection {
                apiKey = LLMConnectionService.apiKey(for: connection.id)
            } else {
                applyProviderDefaults(for: provider, clearKey: false)
            }
            refreshModelsIfNeeded()
        }
        .onChange(of: baseURL) { _, _ in
            guard provider == .ollama else { return }
            fetchedOllamaModels = []
            modelFetchMessage = nil
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Connection" : "New Connection")
                .font(Theme.geist(18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Theme.surfaceElevated)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacingXL)
        .background(Theme.surface)
        .overlay(
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                providerPicker
                providerHint
                nameField
                modelField
                apiKeyField
                baseURLField
                enabledToggle
                if let testResult {
                    testResultView(testResult)
                }
            }
            .padding(Theme.spacingXL)
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Provider")
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.spacingSM),
                    GridItem(.flexible(), spacing: Theme.spacingSM)
                ],
                spacing: Theme.spacingSM
            ) {
                ForEach(LLMProvider.allCases) { option in
                    providerOptionButton(option)
                }
            }
        }
    }

    private func providerOptionButton(_ option: LLMProvider) -> some View {
        let isSelected = provider == option

        return Button {
            guard provider != option else { return }
            provider = option
            applyProviderDefaults(for: option, clearKey: true)
            refreshModelsIfNeeded(for: option)
            testResult = nil
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: option.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 18)

                Text(option.displayName)
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.10) : Theme.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.26) : Theme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var providerHint: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 1)

            Text(provider.setupHint)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill(Theme.surfaceInset)
        )
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Name (optional)")
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            TextField("e.g. Work OpenAI", text: $name)
                .font(Theme.geist(13))
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, 10)
                .background(Theme.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
                .focused($focusedField, equals: .name)
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(alignment: .center) {
                Text("Model")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if provider == .ollama {
                    Button {
                        fetchOllamaModels()
                    } label: {
                        HStack(spacing: 5) {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(isFetchingModels ? "Fetching" : "Refresh Local Models")
                                .font(Theme.geist(11, weight: .medium))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingModels)
                }
            }

            VStack(spacing: Theme.spacingSM) {
                Picker("Model", selection: $model) {
                    ForEach(modelOptions, id: \.self) { m in
                        Text(m).tag(m)
                    }
                    Text("Custom").tag("")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if !modelOptions.contains(model) {
                    TextField(provider.modelPlaceholder, text: $model)
                        .font(Theme.geist(13))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                        .focused($focusedField, equals: .model)
                }

                if provider == .ollama {
                    Text(ollamaModelHelperText)
                        .font(Theme.geist(11))
                        .foregroundStyle(modelFetchMessage == nil ? Theme.textTertiary : Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(provider.apiKeyLabel)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            SecureField("sk-...", text: $apiKey)
                .font(Theme.geist(13))
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, 10)
                .background(Theme.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
                .focused($focusedField, equals: .apiKey)

            if !provider.requiresAPIKey {
                Text("Leave blank unless your local server requires an authorization header.")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var baseURLField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(provider.baseURLLabel)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            TextField(provider.defaultBaseURL, text: $baseURL)
                .font(Theme.geist(13))
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, 10)
                .background(Theme.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
                .focused($focusedField, equals: .baseURL)
        }
    }

    private var enabledToggle: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enabled")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Disabled connections stay saved but cannot be selected for generation.")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .toggleStyle(.switch)
    }

    private func testResultView(_ result: LLMConnectionTestResult) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isSuccess ? Theme.accent : Theme.warning)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            Text(result.message)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(result.isSuccess ? Theme.textPrimary : Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill((result.isSuccess ? Theme.accent : Theme.warning).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke((result.isSuccess ? Theme.accent : Theme.warning).opacity(0.18), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: Theme.spacingMD) {
            Spacer()

            Button {
                testConnection()
            } label: {
                HStack(spacing: 6) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .font(Theme.geist(13, weight: .medium))
                }
                .foregroundStyle(canSave ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                        .fill(Theme.surfaceInset)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isTesting)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(Theme.geist(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                Text(isEditing ? "Save" : "Add Connection")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                            .fill(canSave ? Theme.accent : Theme.accent.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(Theme.spacingXL)
        .background(Theme.surface)
        .overlay(
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var canSave: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && URL(string: effectiveBaseURL) != nil
    }

    private var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    private var modelOptions: [String] {
        if provider == .ollama {
            let localModels = fetchedOllamaModels
            return localModels.isEmpty ? provider.defaultModels : localModels
        }
        return provider.defaultModels
    }

    private var ollamaModelHelperText: String {
        if let modelFetchMessage {
            return modelFetchMessage
        }
        if fetchedOllamaModels.isEmpty {
            return "Showing starter suggestions until local models are fetched from \(effectiveBaseURL)."
        }
        return "Showing \(fetchedOllamaModels.count) local model\(fetchedOllamaModels.count == 1 ? "" : "s") from \(effectiveBaseURL). Custom local model names are still allowed."
    }

    private func save() {
        let newConnection = draftConnection()

        if isEditing {
            service.update(newConnection)
        } else {
            service.add(newConnection)
        }

        dismiss()
    }

    private func testConnection() {
        guard !isTesting else { return }
        testResult = nil
        isTesting = true

        Task {
            let result = await service.test(draftConnection())
            await MainActor.run {
                testResult = result
                isTesting = false
            }
        }
    }

    private func draftConnection() -> LLMConnection {
        LLMConnection(
            id: connection?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: provider,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled
        )
    }

    private func applyProviderDefaults(for provider: LLMProvider, clearKey: Bool) {
        model = provider.defaultModels.first ?? provider.modelPlaceholder
        baseURL = provider.defaultBaseURL
        fetchedOllamaModels = []
        modelFetchMessage = nil
        if clearKey {
            apiKey = ""
        }
    }

    private func refreshModelsIfNeeded(for selectedProvider: LLMProvider? = nil) {
        guard (selectedProvider ?? provider) == .ollama else { return }
        fetchOllamaModels()
    }

    private func fetchOllamaModels() {
        guard provider == .ollama, !isFetchingModels else { return }
        isFetchingModels = true
        modelFetchMessage = nil

        Task {
            let result = await service.fetchModels(for: draftConnection())
            await MainActor.run {
                fetchedOllamaModels = result.models
                modelFetchMessage = result.message
                if !result.models.isEmpty && (model.isEmpty || !result.models.contains(model)) {
                    model = result.models[0]
                }
                isFetchingModels = false
            }
        }
    }
}
