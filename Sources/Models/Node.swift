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
    
    init(id: UUID = UUID(), name: String, type: NodeType, position: CGPoint = .zero, code: String = "", language: CodeLanguage = .swift, connections: [UUID] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.code = code
        self.language = language
        self.connections = connections
    }
}

enum CodeLanguage: String, Codable, CaseIterable {
    case swift = "Swift"
    case python = "Python"
    
    var fileExtension: String {
        switch self {
        case .swift: return "swift"
        case .python: return "py"
        }
    }
    
    var syntaxHighlighting: String {
        return rawValue.lowercased()
    }
}

