import Foundation
import SwiftUI

enum PodType: String, Codable, CaseIterable, Identifiable {
    case macOSApp = "macOS App"
    case iOSApp = "iOS App"
    case androidApp = "Android App"
    case service = "Service"
    case database = "Database"
    case awsBackend = "AWS Backend"
    case custom = "Custom"
    
    var id: String { rawValue }
    
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
        case .awsBackend: return "server.rack"
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
        case .awsBackend: return .orange
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
        case .awsBackend:
            return "Cloud backend → Node, Python, Java, Go, Docker, K8s, Terraform"
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
        case .awsBackend: return .express
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
        case .awsBackend:
            return [
                .express, .nestjs, .nodejs, .fastapi, .flask, .django, .purepy,
                .go, .java, .spring, .docker, .kubernetes, .terraform
            ]
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
    
    // Backward compatibility: language property (deprecated, use framework)
    var language: CodeLanguage {
        get { framework.primaryLanguage }
        set { /* Ignored - use framework instead */ }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, position, code, framework, connections
        case projectPath, pythonEnvironmentPath, pythonRequirements
        case files, selectedFileId, kubernetesYAML
    }
    
    init(id: UUID = UUID(), name: String, type: PodType, position: CGPoint = .zero, code: String = "", framework: Framework = .swift, connections: [UUID] = [], projectPath: String? = nil, pythonEnvironmentPath: String? = nil, pythonRequirements: String = "", files: [ProjectFile] = [], selectedFileId: UUID? = nil, kubernetesYAML: String = "") {
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
        
        // Always ensure main file exists (even if files array is provided)
        // This guarantees every pod has at least one file
        if files.isEmpty {
            // Create main file with code or default template
            let mainFileContent: String
            if !code.isEmpty {
                mainFileContent = code
            } else {
                // Use framework template
                mainFileContent = framework.getTemplate(name: name)
            }
            
            let launchPath = framework.launchFile
            let launchFileName = (launchPath as NSString).lastPathComponent
            
            let mainFile = ProjectFile(
                path: launchPath,
                name: launchFileName,
                content: mainFileContent,
                language: framework.primaryLanguage
            )
            self.files = [mainFile]
            self.selectedFileId = mainFile.id
            // Sync code with main file
            self.code = mainFileContent
        } else if selectedFileId == nil {
            // If files exist but no file is selected, select the first one
            self.selectedFileId = files.first?.id
        }
        
        // Each Pioneer pod owns a Kubernetes Pod YAML
        if self.kubernetesYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.kubernetesYAML = KubernetesManifestService.generateYAML(
                id: self.id,
                name: self.name,
                framework: self.framework,
                projectPath: self.projectPath
            )
        }
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
        // Check if main file already exists
        let mainPath = framework.launchFile
        if let existingFile = files.first(where: { $0.path == mainPath }) {
            return existingFile
        }
        
        // Create new main file using framework template
        let mainFile = ProjectFile(
            path: mainPath,
            name: getMainFileName(for: framework),
            content: code.isEmpty ? framework.getTemplate(name: name) : code,
            language: framework.primaryLanguage
        )
        files.append(mainFile)
        selectedFileId = mainFile.id
        code = mainFile.content // Sync code with main file
        
        return mainFile
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

