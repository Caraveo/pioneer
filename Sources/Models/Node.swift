import Foundation
import SwiftUI

enum NodeType: String, Codable, CaseIterable, Identifiable {
    case macOSApp = "macOS App"
    case iPhoneApp = "iPhone App"
    case service = "Service"
    case awsBackend = "AWS Backend"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .macOSApp: return "desktopcomputer"
        case .iPhoneApp: return "iphone"
        case .service: return "globe"
        case .awsBackend: return "server.rack"
        case .custom: return "square.stack"
        }
    }
    
    var color: Color {
        switch self {
        case .macOSApp: return .blue
        case .iPhoneApp: return .purple
        case .service: return .green
        case .awsBackend: return .orange
        case .custom: return .gray
        }
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

struct Node: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: NodeType
    var position: CGPoint
    var code: String // Main/entry file content (for backward compatibility)
    var framework: Framework // Framework/Infrastructure choice
    var connections: [UUID] // IDs of connected nodes
    var projectPath: String? // Path to this node's project directory
    var pythonEnvironmentPath: String? // Path to virtual environment for Python nodes
    var pythonRequirements: String // requirements.txt content for Python nodes
    var files: [ProjectFile] // All files in this node's codebase
    var selectedFileId: UUID? // Currently selected file
    
    // Backward compatibility: language property (deprecated, use framework)
    var language: CodeLanguage {
        get { framework.primaryLanguage }
        set { /* Ignored - use framework instead */ }
    }
    
    init(id: UUID = UUID(), name: String, type: NodeType, position: CGPoint = .zero, code: String = "", framework: Framework = .swift, connections: [UUID] = [], projectPath: String? = nil, pythonEnvironmentPath: String? = nil, pythonRequirements: String = "", files: [ProjectFile] = [], selectedFileId: UUID? = nil) {
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
        
        // Always ensure main file exists (even if files array is provided)
        // This guarantees every node has at least one file
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
    
    /// Get or create the main file for this node
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
    private static func getDefaultCodeTemplate(for language: CodeLanguage, nodeName: String, directoryName: String) -> String {
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
                        Text("Hello, \(nodeName)!")
                            .font(.largeTitle)
                    }
                    .padding()
                }
            }
            """
        case .python:
            return """
            # \(nodeName)
            # Main entry point

            def main():
                print("Hello, \(nodeName)!")

            if __name__ == "__main__":
                main()
            """
        case .javascript:
            return """
            // \(nodeName)
            // Main entry point

            console.log('Hello, \(nodeName)!');
            """
        case .typescript:
            return """
            // \(nodeName)
            // Main entry point

            console.log('Hello, \(nodeName)!');
            """
        case .html:
            return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>\(nodeName)</title>
            </head>
            <body>
                <h1>\(nodeName)</h1>
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
        case .python: return "python"
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
        case .sql: return "database"
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

