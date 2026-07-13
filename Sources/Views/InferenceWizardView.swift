import SwiftUI

/// Multi-step wizard that creates an **Inference** virtual pod + a realistic stack
/// (e.g. iOS → Python API → MySQL ← Node.js | Web) with scoped env vars.
struct InferenceWizardView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var step = 0
    @State private var productName = "My Product"
    @State private var includeIOS = true
    @State private var includeAndroid = false
    @State private var includeWeb = true
    @State private var includeNodeBFF = true
    @State private var apiFramework: Framework = .fastapi
    @State private var databaseFramework: Framework = .mysql
    @State private var envRows: [EditableEnv] = EditableEnv.defaults
    
    private let steps = ["Product", "Clients", "Backend", "Environment", "Review"]
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepIndicator
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: productStep
                    case 1: clientsStep
                    case 2: backendStep
                    case 3: environmentStep
                    default: reviewStep
                    }
                }
                .padding(20)
            }
            
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
            VStack(alignment: .leading, spacing: 2) {
                Text("INFERENCE")
                    .font(.headline)
                Text("Virtual hub · stack wiring · env keys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, title in
                HStack(spacing: 4) {
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.caption2.weight(i == step ? .semibold : .regular))
                        .foregroundStyle(i == step ? .primary : .secondary)
                }
                if i < steps.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: 24)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
            }
            Spacer()
            if step < steps.count - 1 {
                Button("Next") { withAnimation { step += 1 } }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 0 && productName.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Create Inference Graph") {
                    projectManager.applyInferencePlan(buildPlan())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Steps
    
    private var productStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you building?")
                .font(.title3.weight(.semibold))
            Text("Inference will place a virtual hub on the canvas and wire real pods around it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Product name", text: $productName)
                .textFieldStyle(.roundedBorder)
            infoCard(
                title: "Assumption",
                body: "Classic product graph: mobile/web clients → API → database, with optional Node BFF. Inference holds env vars for the whole stack."
            )
        }
    }
    
    private var clientsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which clients?")
                .font(.title3.weight(.semibold))
            Toggle("iOS (SwiftUI)", isOn: $includeIOS)
            Toggle("Android (Kotlin)", isOn: $includeAndroid)
            Toggle("Web (React)", isOn: $includeWeb)
            Toggle("Node.js edge / BFF", isOn: $includeNodeBFF)
            infoCard(
                title: "Topology preview",
                body: topologyPreview
            )
        }
    }
    
    private var backendStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API & database")
                .font(.title3.weight(.semibold))
            Picker("API", selection: $apiFramework) {
                Text("Python · FastAPI").tag(Framework.fastapi)
                Text("Python · Flask").tag(Framework.flask)
                Text("Python").tag(Framework.purepy)
                Text("Node · Express").tag(Framework.express)
            }
            .pickerStyle(.radioGroup)
            
            Picker("Database", selection: $databaseFramework) {
                Text("MySQL").tag(Framework.mysql)
                Text("PostgreSQL").tag(Framework.postgresql)
                Text("MongoDB").tag(Framework.mongodb)
                Text("SQLite").tag(Framework.sqlite)
                Text("Redis").tag(Framework.redis)
            }
            .pickerStyle(.radioGroup)
            
            infoCard(
                title: "Default assumption",
                body: "iOS → Python API → MySQL ← Node.js | Web — API is the system of record; Node BFF fronts the web client."
            )
        }
    }
    
    private var environmentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Environment variables")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    envRows.append(EditableEnv(key: "NEW_KEY", value: "", scope: .shared, note: ""))
                } label: {
                    Label("Add key", systemImage: "plus")
                }
            }
            Text("Scopes: Public (safe to ship), Private (secrets), Developer, Production, Shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ForEach($envRows) { $row in
                HStack(spacing: 8) {
                    TextField("KEY", text: $row.key)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("value", text: $row.value)
                        .textFieldStyle(.roundedBorder)
                    Picker("Scope", selection: $row.scope) {
                        ForEach(EnvScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .frame(width: 110)
                    Button(role: .destructive) {
                        envRows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.title3.weight(.semibold))
            Text(topologyPreview)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            
            Text("Pods to create")
                .font(.subheadline.weight(.semibold))
            ForEach(buildPlan().podBlueprints, id: \.name) { bp in
                HStack {
                    Image(systemName: bp.type.icon)
                        .foregroundStyle(bp.type.color)
                    Text(bp.name)
                    Text("· \(bp.framework.rawValue)")
                        .foregroundStyle(.secondary)
                    if bp.type == .inference {
                        Text("VIRTUAL")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.2)))
                    }
                }
            }
            
            Text("\(envRows.count) env key(s) will live on the Inference hub and seed `.env`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var topologyPreview: String {
        var lines: [String] = []
        if includeIOS { lines.append("iOS") }
        if includeAndroid { lines.append("Android") }
        let clients = lines.joined(separator: " + ")
        let api = apiFramework.rawValue
        let db = databaseFramework.rawValue
        var mid = "→ \(api) → \(db)"
        if includeNodeBFF {
            mid += " ← Node.js"
        }
        if includeWeb {
            mid += " | Web"
        }
        if clients.isEmpty {
            return "API\(mid)"
        }
        return "\(clients) \(mid)"
    }
    
    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
    
    private func buildPlan() -> InferencePlan {
        InferencePlan(
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            includeIOS: includeIOS,
            includeAndroid: includeAndroid,
            includeWeb: includeWeb,
            includeNodeBFF: includeNodeBFF,
            apiFramework: apiFramework,
            databaseFramework: databaseFramework,
            env: envRows.map {
                EnvBinding(key: $0.key, value: $0.value, scope: $0.scope, note: $0.note)
            }
        )
    }
}

// MARK: - Wizard models

struct EditableEnv: Identifiable {
    let id: UUID
    var key: String
    var value: String
    var scope: EnvScope
    var note: String
    
    init(id: UUID = UUID(), key: String, value: String = "", scope: EnvScope = .shared, note: String = "") {
        self.id = id
        self.key = key
        self.value = value
        self.scope = scope
        self.note = note
    }
    
    static let defaults: [EditableEnv] = [
        EditableEnv(key: "API_BASE_URL", value: "http://localhost:8000", scope: .publicKey, note: "Client-facing API"),
        EditableEnv(key: "API_PUBLIC_KEY", value: "", scope: .publicKey, note: "Publishable key"),
        EditableEnv(key: "API_PRIVATE_KEY", value: "", scope: .privateKey, note: "Server only"),
        EditableEnv(key: "JWT_SECRET", value: "dev-only-change-me", scope: .privateKey, note: "Auth signing"),
        EditableEnv(key: "DATABASE_URL", value: "mysql://app:app@db:3306/app", scope: .privateKey, note: "Primary DB"),
        EditableEnv(key: "DEBUG", value: "true", scope: .developer, note: "Local verbosity"),
        EditableEnv(key: "LOG_LEVEL", value: "debug", scope: .developer, note: ""),
        EditableEnv(key: "NODE_ENV", value: "development", scope: .shared, note: "Web / Node BFF")
    ]
}

struct InferencePodBlueprint {
    var name: String
    var type: PodType
    var framework: Framework
    var position: CGPoint
}

struct InferencePlan {
    var productName: String
    var includeIOS: Bool
    var includeAndroid: Bool
    var includeWeb: Bool
    var includeNodeBFF: Bool
    var apiFramework: Framework
    var databaseFramework: Framework
    var env: [EnvBinding]
    
    var podBlueprints: [InferencePodBlueprint] {
        var list: [InferencePodBlueprint] = []
        // Layout: clients left, inference center-top, api mid, db right, node/web bottom
        list.append(.init(name: "\(productName) Inference", type: .inference, framework: .environment, position: CGPoint(x: 420, y: 120)))
        
        if includeIOS {
            list.append(.init(name: "\(productName) iOS", type: .iOSApp, framework: .swiftui, position: CGPoint(x: 160, y: 220)))
        }
        if includeAndroid {
            list.append(.init(name: "\(productName) Android", type: .androidApp, framework: .kotlin, position: CGPoint(x: 160, y: 380)))
        }
        
        list.append(.init(name: "\(productName) API", type: .service, framework: apiFramework, position: CGPoint(x: 420, y: 300)))
        list.append(.init(name: "\(productName) DB", type: .database, framework: databaseFramework, position: CGPoint(x: 700, y: 300)))
        
        if includeNodeBFF {
            list.append(.init(name: "\(productName) Node", type: .service, framework: .nodejs, position: CGPoint(x: 420, y: 480)))
        }
        if includeWeb {
            list.append(.init(name: "\(productName) Web", type: .service, framework: .react, position: CGPoint(x: 160, y: 480)))
        }
        return list
    }
}
