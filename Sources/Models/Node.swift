import Foundation
import SwiftUI

enum NodeType: String, Codable, CaseIterable, Identifiable {
    case macOSApp = "macOS App"
    case iPhoneApp = "iPhone App"
    case website = "Website"
    case awsBackend = "AWS Backend"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .macOSApp: return "desktopcomputer"
        case .iPhoneApp: return "iphone"
        case .website: return "globe"
        case .awsBackend: return "server.rack"
        case .custom: return "square.stack"
        }
    }
    
    var color: Color {
        switch self {
        case .macOSApp: return .blue
        case .iPhoneApp: return .purple
        case .website: return .green
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
    var language: CodeLanguage
    var connections: [UUID] // IDs of connected nodes
    var projectPath: String? // Path to this node's project directory
    var pythonEnvironmentPath: String? // Path to virtual environment for Python nodes
    var pythonRequirements: String // requirements.txt content for Python nodes
    var files: [ProjectFile] // All files in this node's codebase
    var selectedFileId: UUID? // Currently selected file
    
    init(id: UUID = UUID(), name: String, type: NodeType, position: CGPoint = .zero, code: String = "", language: CodeLanguage = .swift, connections: [UUID] = [], projectPath: String? = nil, pythonEnvironmentPath: String? = nil, pythonRequirements: String = "", files: [ProjectFile] = [], selectedFileId: UUID? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.code = code
        self.language = language
        self.connections = connections
        self.projectPath = projectPath
        self.pythonEnvironmentPath = pythonEnvironmentPath
        self.pythonRequirements = pythonRequirements
        self.files = files
        self.selectedFileId = selectedFileId
        
        // Initialize with main file if files is empty
        if files.isEmpty && !code.isEmpty {
            let mainFile = ProjectFile(
                path: getMainFilePath(for: language),
                name: getMainFileName(for: language),
                content: code,
                language: language
            )
            self.files = [mainFile]
            self.selectedFileId = mainFile.id
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
    
    /// Get main file path for a language
    private func getMainFilePath(for language: CodeLanguage) -> String {
        switch language {
        case .python: return "src/main.py"
        case .swift: return "Sources/main.swift"
        case .typescript: return "src/index.ts"
        case .javascript: return "src/index.js"
        case .html: return "index.html"
        case .css: return "css/style.css"
        case .dockerfile: return "Dockerfile"
        case .kubernetes, .yaml: return "\(projectDirectoryName).yaml"
        case .terraform: return "main.tf"
        case .cloudformation: return "template.yaml"
        case .json: return "config.json"
        case .sql: return "schema.sql"
        case .bash: return "script.sh"
        case .markdown: return "README.md"
        case .scaffolding: return "scaffold.txt"
        }
    }
    
    /// Get main file name for a language
    private func getMainFileName(for language: CodeLanguage) -> String {
        switch language {
        case .python: return "main.py"
        case .swift: return "main.swift"
        case .typescript: return "index.ts"
        case .javascript: return "index.js"
        case .html: return "index.html"
        case .css: return "style.css"
        case .dockerfile: return "Dockerfile"
        case .kubernetes, .yaml: return "\(projectDirectoryName).yaml"
        case .terraform: return "main.tf"
        case .cloudformation: return "template.yaml"
        case .json: return "config.json"
        case .sql: return "schema.sql"
        case .bash: return "script.sh"
        case .markdown: return "README.md"
        case .scaffolding: return "scaffold.txt"
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
}

