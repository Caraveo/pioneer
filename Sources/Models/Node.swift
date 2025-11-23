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

struct Node: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: NodeType
    var position: CGPoint
    var code: String
    var language: CodeLanguage
    var connections: [UUID] // IDs of connected nodes
    var pythonEnvironmentPath: String? // Path to virtual environment for Python nodes
    var pythonRequirements: String // requirements.txt content for Python nodes
    
    init(id: UUID = UUID(), name: String, type: NodeType, position: CGPoint = .zero, code: String = "", language: CodeLanguage = .swift, connections: [UUID] = [], pythonEnvironmentPath: String? = nil, pythonRequirements: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.code = code
        self.language = language
        self.connections = connections
        self.pythonEnvironmentPath = pythonEnvironmentPath
        self.pythonRequirements = pythonRequirements
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

