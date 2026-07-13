import Foundation
import SwiftUI

enum EnvScope: String, Codable, CaseIterable, Identifiable {
    case publicKey = "Public"
    case privateKey = "Private"
    case developer = "Developer"
    case production = "Production"
    case shared = "Shared"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .publicKey: return "key"
        case .privateKey: return "lock.fill"
        case .developer: return "hammer"
        case .production: return "server.rack"
        case .shared: return "link"
        }
    }
}

/// Environment binding owned by an Inference (virtual) pod and distributed to the stack.
struct EnvBinding: Identifiable, Codable, Hashable {
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
}

enum PodType: String, Codable, CaseIterable, Identifiable {
    case macOSApp = "macOS App"
    case iOSApp = "iOS App"
    case androidApp = "Android App"
    case service = "Service"
    case database = "Database"
    /// File / object storage hub (local vault, MinIO, S3, NFS, PVC).
    case vault = "Vault"
    case awsBackend = "AWS Backend"
    /// Virtual hub: env vars, secrets scopes, and stack inference — not a runtime app pod.
    case inference = "Inference"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    /// Virtual pods don't run as app containers; they coordinate the graph.
    var isVirtual: Bool { self == .inference }
    
    /// Migrate legacy project files that stored "iPhone App".
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "iPhone App", "iOS App":
            self = .iOSApp
        default:
            self = PodType(rawValue: raw) ?? .custom
        }
    }
    
    var icon: String {
        switch self {
        case .macOSApp: return "desktopcomputer"
        case .iOSApp: return "iphone"
        case .androidApp: return "smartphone"
        case .service: return "globe"
        case .database: return "cylinder.split.1x2"
        case .vault: return "externaldrive.fill.badge.timemachine"
        case .awsBackend: return "server.rack"
        case .inference: return "brain.head.profile"
        case .custom: return "square.stack"
        }
    }
    
    var color: Color {
        switch self {
        case .macOSApp: return .blue
        case .iOSApp: return .purple
        case .androidApp: return .green
        case .service: return Color(red: 0.2, green: 0.7, blue: 0.5)
        case .database: return Color(red: 0.2, green: 0.45, blue: 0.75)
        case .vault: return Color(red: 0.15, green: 0.55, blue: 0.65)
        case .awsBackend: return .orange
        case .inference: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .custom: return .gray
        }
    }
    
    /// Short hint shown under the type picker.
    var frameworkHint: String {
        switch self {
        case .macOSApp:
            return "Desktop app → SwiftUI, Swift, or Objective-C"
        case .iOSApp:
            return "iPhone/iPad → SwiftUI, Swift, Objective-C, React Native, Flutter"
        case .androidApp:
            return "Android → Kotlin, Jetpack Compose, Java, React Native, Flutter"
        case .service:
            return "API / web service → Python (default), Node, Go, Java, frontends…"
        case .database:
            return "Data store → PostgreSQL, MySQL, MongoDB, Redis, SQLite"
        case .vault:
            return "File storage → Vault (default), MinIO, S3, Local Volume, NFS, SeaweedFS"
        case .awsBackend:
            return "Cloud backend → Node, Python, Java, Go, Docker, K8s, Terraform"
        case .inference:
            return "Virtual hub → env keys, public/private scopes, stack wiring"
        case .custom:
            return "Any enabled framework"
        }
    }
    
    /// Default framework when this pod type is selected.
    var defaultFramework: Framework {
        switch self {
        case .macOSApp: return .swiftui
        case .iOSApp: return .swiftui
        case .androidApp: return .kotlin
        case .service: return .purepy
        case .database: return .postgresql
        case .vault: return .vault
        case .awsBackend: return .express
        case .inference: return .environment
        case .custom: return .purepy
        }
    }
    
    /// Frameworks that make sense for this pod type (ordered by preference).
    var compatibleFrameworks: [Framework] {
        switch self {
        case .macOSApp:
            return [.swiftui, .swift, .objectiveC]
        case .iOSApp:
            return [.swiftui, .swift, .objectiveC, .reactNative, .flutter]
        case .androidApp:
            return [.kotlin, .jetpackCompose, .androidJava, .reactNative, .flutter]
        case .service:
            return [
                .purepy, .fastapi, .flask, .django,
                .nodejs, .express, .nestjs,
                .react, .vue, .angular, .nextjs, .go, .rust, .java, .spring
            ]
        case .database:
            return [.postgresql, .mysql, .mongodb, .redis, .sqlite]
        case .vault:
            return [.vault, .minio, .s3, .localVolume, .nfs, .seaweedfs]
        case .awsBackend:
            return [
                .express, .nestjs, .nodejs, .fastapi, .flask, .django, .purepy,
                .go, .java, .spring, .docker, .kubernetes, .terraform
            ]
        case .inference:
            return [.environment]
        case .custom:
            return Framework.allCases
        }
    }
    
    func isCompatible(with framework: Framework) -> Bool {
        compatibleFrameworks.contains(framework)
    }
    
    /// Pick a valid framework when type changes (keep current if still allowed).
    func resolvedFramework(current: Framework) -> Framework {
        if isCompatible(with: current) { return current }
        return defaultFramework
    }
}

struct ProjectFile: Identifiable, Codable {
    let id: UUID
    var path: String // Relative path from project root
    var name: String
    var content: String
    var language: CodeLanguage
    
    init(id: UUID = UUID(), path: String, name: String, content: String = "", language: CodeLanguage) {
        self.id = id
        self.path = path
        self.name = name
        self.content = content
        self.language = language
    }
}

struct Pod: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: PodType
    var position: CGPoint
    var code: String // Main/entry file content (for backward compatibility)
    var framework: Framework // Framework/Infrastructure choice
    var connections: [UUID] // IDs of connected pods
    var projectPath: String? // Path to this pod's project directory
    var pythonEnvironmentPath: String? // Path to virtual environment for Python pods
    var pythonRequirements: String // requirements.txt content for Python pods
    var files: [ProjectFile] // All files in this pod's codebase
    var selectedFileId: UUID? // Currently selected file
    /// Dedicated Kubernetes Pod manifest for this Pioneer pod (edited in YAML view).
    var kubernetesYAML: String
    /// Env keys / secrets (especially for Inference virtual pods).
    var environmentVariables: [EnvBinding]
    /// Local runtime indicator (green = running/active, red = stopped). Not persisted.
    var isRunning: Bool = false
    
    // Backward compatibility: language property (deprecated, use framework)
    var language: CodeLanguage {
        get { framework.primaryLanguage }
        set { /* Ignored - use framework instead */ }
    }
    
    var isVirtual: Bool { type.isVirtual }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, position, code, framework, connections
        case projectPath, pythonEnvironmentPath, pythonRequirements
        case files, selectedFileId, kubernetesYAML, environmentVariables
    }
    
    init(id: UUID = UUID(), name: String, type: PodType, position: CGPoint = .zero, code: String = "", framework: Framework = .swift, connections: [UUID] = [], projectPath: String? = nil, pythonEnvironmentPath: String? = nil, pythonRequirements: String = "", files: [ProjectFile] = [], selectedFileId: UUID? = nil, kubernetesYAML: String = "", environmentVariables: [EnvBinding] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.code = code
        self.framework = framework
        self.connections = connections
        self.projectPath = projectPath
        self.pythonEnvironmentPath = pythonEnvironmentPath
        self.pythonRequirements = pythonRequirements
        self.files = files
        self.selectedFileId = selectedFileId
        self.kubernetesYAML = kubernetesYAML
        self.environmentVariables = environmentVariables
        self.isRunning = false
        
        // Always ensure main file exists (even if files array is provided)
        // This guarantees every pod has at least one file
        if files.isEmpty {
            // Create main file with code or default template
            let mainFileContent: String
            if !code.isEmpty {
                mainFileContent = code
            } else if type == .inference {
                mainFileContent = Self.makeEnvFileContent(name: name, bindings: environmentVariables)
            } else {
                // Use framework template
                mainFileContent = framework.getTemplate(name: name)
            }
            
            let launchPath = type == .inference ? ".env" : framework.launchFile
            let launchFileName = (launchPath as NSString).lastPathComponent
            
            let mainFile = ProjectFile(
                path: launchPath,
                name: launchFileName,
                content: mainFileContent,
                language: type == .inference ? .bash : framework.primaryLanguage
            )
            self.files = [mainFile]
            self.selectedFileId = mainFile.id
            // Sync code with main file
            self.code = mainFileContent
        } else if selectedFileId == nil {
            // If files exist but no file is selected, select the first one
            self.selectedFileId = files.first?.id
        }
        
        // Each Pioneer pod owns a Kubernetes Pod YAML (Inference uses ConfigMap-style docs)
        if self.kubernetesYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if type == .inference {
                self.kubernetesYAML = Self.makeInferenceConfigMapYAML(name: name, id: id, bindings: environmentVariables)
            } else {
                self.kubernetesYAML = KubernetesManifestService.generateYAML(
                    id: self.id,
                    name: self.name,
                    framework: self.framework,
                    projectPath: self.projectPath
                )
            }
        }
    }
    
    static func makeEnvFileContent(name: String, bindings: [EnvBinding]) -> String {
        var lines = [
            "# \(name) — Inference environment",
            "# Scopes: Public | Private | Developer | Production | Shared",
            ""
        ]
        if bindings.isEmpty {
            lines += [
                "# Example keys (fill via Inference wizard)",
                "API_BASE_URL=http://localhost:8000",
                "DATABASE_URL=mysql://user:pass@db:3306/app",
                "# PRIVATE",
                "JWT_SECRET=change-me",
                "API_PRIVATE_KEY=",
                "# PUBLIC",
                "API_PUBLIC_KEY=",
                "# DEVELOPER",
                "DEBUG=true",
                "LOG_LEVEL=debug"
            ]
        } else {
            var lastScope: EnvScope?
            for b in bindings {
                if b.scope != lastScope {
                    lines.append("# \(b.scope.rawValue.uppercased())")
                    lastScope = b.scope
                }
                let comment = b.note.isEmpty ? "" : "  # \(b.note)"
                lines.append("\(b.key)=\(b.value)\(comment)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    static func makeInferenceConfigMapYAML(name: String, id: UUID, bindings: [EnvBinding]) -> String {
        let safe = name.lowercased().replacingOccurrences(of: " ", with: "-")
        var dataLines: [String] = []
        for b in bindings where b.scope != .privateKey {
            // Private values stay out of ConfigMap docs by default
            dataLines.append("  \(b.key): \"\(b.value.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if dataLines.isEmpty {
            dataLines = ["  API_BASE_URL: \"http://localhost:8000\""]
        }
        return """
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: \(safe)-inference
          labels:
            app: pioneer
            pioneer-pod: "\(id.uuidString)"
            pioneer.io/virtual: "inference"
        data:
        \(dataLines.joined(separator: "\n"))
        """
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(PodType.self, forKey: .type)
        position = try c.decode(CGPoint.self, forKey: .position)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        framework = try c.decodeIfPresent(Framework.self, forKey: .framework) ?? .swift
        connections = try c.decodeIfPresent([UUID].self, forKey: .connections) ?? []
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        pythonEnvironmentPath = try c.decodeIfPresent(String.self, forKey: .pythonEnvironmentPath)
        pythonRequirements = try c.decodeIfPresent(String.self, forKey: .pythonRequirements) ?? ""
        files = try c.decodeIfPresent([ProjectFile].self, forKey: .files) ?? []
        selectedFileId = try c.decodeIfPresent(UUID.self, forKey: .selectedFileId)
        kubernetesYAML = try c.decodeIfPresent(String.self, forKey: .kubernetesYAML) ?? ""
        environmentVariables = try c.decodeIfPresent([EnvBinding].self, forKey: .environmentVariables) ?? []
        isRunning = false
        
        if files.isEmpty {
            let mainFileContent = code.isEmpty ? framework.getTemplate(name: name) : code
            let launchPath = framework.launchFile
            let launchFileName = (launchPath as NSString).lastPathComponent
            let mainFile = ProjectFile(
                path: launchPath,
                name: launchFileName,
                content: mainFileContent,
                language: framework.primaryLanguage
            )
            files = [mainFile]
            selectedFileId = mainFile.id
            code = mainFileContent
        } else if selectedFileId == nil {
            selectedFileId = files.first?.id
        }
        
        if kubernetesYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kubernetesYAML = KubernetesManifestService.generateYAML(
                id: id,
                name: name,
                framework: framework,
                projectPath: projectPath
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(position, forKey: .position)
        try c.encode(code, forKey: .code)
        try c.encode(framework, forKey: .framework)
        try c.encode(connections, forKey: .connections)
        try c.encodeIfPresent(projectPath, forKey: .projectPath)
        try c.encodeIfPresent(pythonEnvironmentPath, forKey: .pythonEnvironmentPath)
        try c.encode(pythonRequirements, forKey: .pythonRequirements)
        try c.encode(files, forKey: .files)
        try c.encodeIfPresent(selectedFileId, forKey: .selectedFileId)
        try c.encode(kubernetesYAML, forKey: .kubernetesYAML)
        try c.encode(environmentVariables, forKey: .environmentVariables)
    }
    
    /// Refresh Kubernetes YAML from current name/framework/path (overwrites YAML view content).
    mutating func regenerateKubernetesYAML() {
        kubernetesYAML = KubernetesManifestService.generateYAML(
            id: id,
            name: name,
            framework: framework,
            projectPath: projectPath
        )
    }
    
    /// Copy for the “Wipe Pod?” confirmation before a framework switch.
    func wipePodSummary(to newFramework: Framework) -> String {
        let old = framework
        return """
        This will wipe all code and files in this pod and start fresh for \(newFramework.rawValue).
        
        From: \(old.rawValue) → \(newFramework.rawValue)
        New launch file: \(newFramework.launchFile)
        
        What gets removed:
        • All files currently in this pod’s codebase
        • Current CODE editor contents
        • Generated project files for the old stack (on disk, under this pod’s folder)
        
        What gets created:
        • A clean \(newFramework.rawValue) starter at \(newFramework.launchFile)
        • New Kubernetes YAML for this pod
        • Fresh project scaffolding for \(newFramework.rawValue)
        
        Pod name, type, position, and connections are kept.
        Git history in the pod folder is not deleted (you can still recover via GIT if committed).
        """
    }
    
    /// Hard switch: wipe all pod files and install a clean template for the new framework.
    mutating func switchToFramework(_ newFramework: Framework) {
        framework = newFramework
        let template = newFramework.getTemplate(name: name)
        let launchPath = newFramework.launchFile
        let launchName = (launchPath as NSString).lastPathComponent
        let language = newFramework.primaryLanguage
        
        // Brand-new file list so the CODE editor cannot keep stale tabs/content
        let mainFile = ProjectFile(
            id: UUID(),
            path: launchPath,
            name: launchName,
            content: template,
            language: language
        )
        files = [mainFile]
        selectedFileId = mainFile.id
        code = template
        isRunning = false
        pythonRequirements = ""
        pythonEnvironmentPath = nil
        regenerateKubernetesYAML()
    }
    
    /// Get the project directory name (sanitized)
    var projectDirectoryName: String {
        name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
    
    /// Get the currently selected file
    var selectedFile: ProjectFile? {
        guard let selectedFileId = selectedFileId else { return files.first }
        return files.first { $0.id == selectedFileId }
    }
    
    /// Get main file path for a framework (launch file)
    func getMainFilePath(for framework: Framework) -> String {
        return framework.launchFile
    }
    
    /// Get main file name for a framework
    func getMainFileName(for framework: Framework) -> String {
        return (framework.launchFile as NSString).lastPathComponent
    }
    
    /// Get or create the main file for this pod
    mutating func getOrCreateMainFile() -> ProjectFile {
        let mainPath = framework.launchFile
        let language = framework.primaryLanguage
        let template = framework.getTemplate(name: name)
        
        if let existingIndex = files.firstIndex(where: { $0.path == mainPath }) {
            // Repair wrong-language content left over from a prior framework
            if Self.contentLooksIncompatible(files[existingIndex].content, with: framework) {
                files[existingIndex].content = template
                files[existingIndex].language = language
                code = template
            } else if files[existingIndex].language != language {
                files[existingIndex].language = language
            }
            selectedFileId = files[existingIndex].id
            return files[existingIndex]
        }
        
        // Prefer template over stale `code` when it doesn't match this framework
        let body: String
        if code.isEmpty || Self.contentLooksIncompatible(code, with: framework) {
            body = template
        } else {
            body = code
        }
        
        let mainFile = ProjectFile(
            path: mainPath,
            name: getMainFileName(for: framework),
            content: body,
            language: language
        )
        files.append(mainFile)
        selectedFileId = mainFile.id
        code = mainFile.content
        
        return mainFile
    }
    
    /// Heuristic: true when file body clearly doesn't match the framework language.
    static func contentLooksIncompatible(_ content: String, with framework: Framework) -> Bool {
        let sample = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count > 8 else { return false }
        let lower = sample.lowercased()
        
        let looksPython = sample.hasPrefix("#") && (lower.contains("def ") || lower.contains("import ") || lower.contains("pure python") || lower.contains("if __name__"))
            || lower.contains("def main(") || lower.contains("if __name__")
        let looksJS = lower.contains("console.log") || lower.contains("require(") || lower.contains("module.exports")
            || sample.hasPrefix("//") && (lower.contains("function") || lower.contains("const ") || lower.contains("node.js"))
        let looksSwift = lower.contains("import swiftui") || lower.contains("import foundation") || lower.contains("struct ") && lower.contains(": view")
        let looksSQL = sample.hasPrefix("--") || lower.hasPrefix("create table")
        
        switch framework {
        case .nodejs, .express, .nestjs, .angular, .react, .vue, .nextjs, .reactNative:
            return looksPython || looksSwift || looksSQL
        case .purepy, .django, .flask, .fastapi:
            return (looksJS && !looksPython) || looksSwift
        case .swift, .swiftui:
            return looksPython || (looksJS && !looksSwift)
        case .postgresql, .mysql, .sqlite:
            return looksPython || looksJS || looksSwift
        default:
            // If code is pure Python comments/body but framework isn't Python, treat as incompatible
            if looksPython && ![Framework.purepy, .django, .flask, .fastapi].contains(framework) {
                return true
            }
            return false
        }
    }
    
    /// Get default code template for a language (static helper)
    private static func getDefaultCodeTemplate(for language: CodeLanguage, podName: String, directoryName: String) -> String {
        switch language {
        case .swift:
            return """
            import SwiftUI

            @main
            struct \(directoryName): App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }

            struct ContentView: View {
                var body: some View {
                    VStack {
                        Text("Hello, \(podName)!")
                            .font(.largeTitle)
                    }
                    .padding()
                }
            }
            """
        case .python:
            return """
            # \(podName)
            # Main entry point

            def main():
                print("Hello, \(podName)!")

            if __name__ == "__main__":
                main()
            """
        case .javascript:
            return """
            // \(podName)
            // Main entry point

            console.log('Hello, \(podName)!');
            """
        case .typescript:
            return """
            // \(podName)
            // Main entry point

            console.log('Hello, \(podName)!');
            """
        case .html:
            return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>\(podName)</title>
            </head>
            <body>
                <h1>\(podName)</h1>
            </body>
            </html>
            """
        default:
            return ""
        }
    }
    
    /// Get default code template for a language (instance method)
    private func getDefaultCodeForLanguage(_ language: CodeLanguage) -> String {
        switch language {
        case .swift:
            return """
            import SwiftUI

            @main
            struct \(projectDirectoryName): App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }

            struct ContentView: View {
                var body: some View {
                    VStack {
                        Text("Hello, \(name)!")
                            .font(.largeTitle)
                    }
                    .padding()
                }
            }
            """
        case .python:
            return """
            # \(name)
            # Main entry point

            def main():
                print("Hello, \(name)!")

            if __name__ == "__main__":
                main()
            """
        case .javascript:
            return """
            // \(name)
            // Main entry point

            console.log('Hello, \(name)!');
            """
        case .typescript:
            return """
            // \(name)
            // Main entry point

            console.log('Hello, \(name)!');
            """
        case .html:
            return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>\(name)</title>
            </head>
            <body>
                <h1>\(name)</h1>
            </body>
            </html>
            """
        default:
            return ""
        }
    }
}

enum CodeLanguage: String, Codable, CaseIterable {
    case swift = "Swift"
    case python = "Python"
    case yaml = "YAML"
    case json = "JSON"
    case scaffolding = "Scaffolding"
    case dockerfile = "Dockerfile"
    case kubernetes = "Kubernetes"
    case terraform = "Terraform"
    case cloudformation = "CloudFormation"
    case typescript = "TypeScript"
    case javascript = "JavaScript"
    case html = "HTML"
    case css = "CSS"
    case sql = "SQL"
    case bash = "Bash"
    case markdown = "Markdown"
    
    var fileExtension: String {
        switch self {
        case .swift: return "swift"
        case .python: return "py"
        case .yaml: return "yaml"
        case .json: return "json"
        case .scaffolding: return "scaffold"
        case .dockerfile: return "Dockerfile"
        case .kubernetes: return "yaml"
        case .terraform: return "tf"
        case .cloudformation: return "yaml"
        case .typescript: return "ts"
        case .javascript: return "js"
        case .html: return "html"
        case .css: return "css"
        case .sql: return "sql"
        case .bash: return "sh"
        case .markdown: return "md"
        }
    }
    
    var syntaxHighlighting: String {
        return rawValue.lowercased()
    }
    
    var icon: String {
        switch self {
        case .swift: return "swift"
        case .python: return "p.square"
        case .yaml: return "doc.text"
        case .json: return "curlybraces"
        case .scaffolding: return "square.stack.3d.up"
        case .dockerfile: return "cube.box"
        case .kubernetes: return "k.circle"
        case .terraform: return "mountain.2"
        case .cloudformation: return "cloud"
        case .typescript: return "t.square"
        case .javascript: return "j.square"
        case .html: return "h.square"
        case .css: return "c.square"
        case .sql: return "tablecells"
        case .bash: return "terminal"
        case .markdown: return "doc.richtext"
        }
    }
    
    var color: Color {
        switch self {
        case .swift: return Color(red: 1.0, green: 0.58, blue: 0.0) // Orange
        case .python: return Color(red: 0.2, green: 0.6, blue: 0.9) // Blue
        case .yaml: return Color(red: 0.9, green: 0.2, blue: 0.2) // Red
        case .json: return Color(red: 0.9, green: 0.7, blue: 0.1) // Yellow
        case .scaffolding: return Color(red: 0.5, green: 0.5, blue: 0.5) // Gray
        case .dockerfile: return Color(red: 0.1, green: 0.7, blue: 0.9) // Cyan
        case .kubernetes: return Color(red: 0.3, green: 0.5, blue: 0.9) // Blue
        case .terraform: return Color(red: 0.6, green: 0.3, blue: 0.9) // Purple
        case .cloudformation: return Color(red: 0.9, green: 0.5, blue: 0.1) // Orange
        case .typescript: return Color(red: 0.2, green: 0.5, blue: 0.8) // Blue
        case .javascript: return Color(red: 0.9, green: 0.8, blue: 0.1) // Yellow
        case .html: return Color(red: 0.9, green: 0.3, blue: 0.1) // Orange
        case .css: return Color(red: 0.2, green: 0.6, blue: 0.8) // Blue
        case .sql: return Color(red: 0.4, green: 0.6, blue: 0.9) // Blue
        case .bash: return Color(red: 0.2, green: 0.7, blue: 0.3) // Green
        case .markdown: return Color(red: 0.3, green: 0.3, blue: 0.3) // Dark Gray
        }
    }
}

