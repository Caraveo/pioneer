import SwiftUI

/// Popup editor for an Inference pod’s environment keys (scopes, values, notes).
/// Opened by double-clicking the Inference node or the Properties “Edit Environment” button.
struct InferenceEnvEditorView: View {
    let podId: UUID
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var rows: [EditableEnv] = []
    @State private var podName: String = "Inference"
    @State private var didLoad = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Environment keys on this Inference hub seed `.env` and ConfigMap data for the stack.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text("Keys")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            rows.append(EditableEnv(key: "NEW_KEY", value: "", scope: .shared, note: ""))
                        } label: {
                            Label("Add key", systemImage: "plus")
                        }
                    }
                    
                    Text("Scopes: Public (safe to ship), Private (secrets), Developer, Production, Shared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if rows.isEmpty {
                        Text("No keys yet — add API URLs, secrets, and flags for the stack.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("KEY", text: $row.key)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minWidth: 140)
                                
                                TextField("value", text: $row.value)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                
                                Picker("Scope", selection: $row.scope) {
                                    ForEach(EnvScope.allCases) { s in
                                        Label(s.rawValue, systemImage: s.icon).tag(s)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                
                                Button(role: .destructive) {
                                    rows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove key")
                            }
                            
                            TextField("Note (optional)", text: $row.note)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    
                    // Live .env preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview · .env")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(previewEnv)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .onAppear { loadIfNeeded() }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
            VStack(alignment: .leading, spacing: 2) {
                Text("Environment Editor")
                    .font(.headline)
                Text(podName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(rows.count) key\(rows.count == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.purple.opacity(0.15)))
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var footer: some View {
        HStack {
            Button("Reset to defaults") {
                rows = EditableEnv.defaults
            }
            .help("Replace with the standard Inference starter keys")
            
            Spacer()
            
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            
            Button("Save Environment") {
                save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(rows.contains { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var previewEnv: String {
        let bindings = rows.map {
            EnvBinding(id: $0.id, key: $0.key, value: $0.value, scope: $0.scope, note: $0.note)
        }
        return Pod.makeEnvFileContent(name: podName, bindings: bindings)
    }
    
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let pod = projectManager.pods.first(where: { $0.id == podId }) else { return }
        podName = pod.name
        if pod.environmentVariables.isEmpty {
            rows = EditableEnv.defaults
        } else {
            rows = pod.environmentVariables.map {
                EditableEnv(id: $0.id, key: $0.key, value: $0.value, scope: $0.scope, note: $0.note)
            }
        }
    }
    
    private func save() {
        let bindings = rows
            .map {
                EnvBinding(
                    id: $0.id,
                    key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: $0.value,
                    scope: $0.scope,
                    note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.key.isEmpty }
        projectManager.updateInferenceEnvironment(id: podId, bindings: bindings)
    }
}
