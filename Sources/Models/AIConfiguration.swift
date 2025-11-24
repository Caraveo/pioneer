import Foundation
import SwiftUI

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google Gemini"
    case ollama = "Ollama"
    case mistystudio = "MistyStudio"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .openai: return "brain"
        case .anthropic: return "sparkles"
        case .google: return "g.circle.fill"
        case .ollama: return "server.rack"
        case .mistystudio: return "laptopcomputer"
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1"
        case .ollama: return "http://localhost:11434"
        case .mistystudio: return "http://localhost:11973"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openai, .anthropic, .google: return true
        case .ollama, .mistystudio: return false
        }
    }
}

struct AIModel: Identifiable, Codable {
    let id: String
    let name: String
    let provider: LLMProvider
    let contextWindow: Int?
    let supportsStreaming: Bool
    
    init(id: String, name: String, provider: LLMProvider, contextWindow: Int? = nil, supportsStreaming: Bool = true) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextWindow = contextWindow
        self.supportsStreaming = supportsStreaming
    }
}

struct AIConfiguration: Codable {
    var selectedProvider: LLMProvider = .openai
    var selectedModel: String = ""
    var openAIAPIKey: String = ""
    var anthropicAPIKey: String = ""
    var googleAPIKey: String = ""
    var ollamaModel: String = "llama2"
    var mistystudioModel: String = "mistral"
    var temperature: Double = 0.7
    var maxTokens: Int = 2000
    var useContext: Bool = true
    var includeNodeConnections: Bool = true
    
    static let `default` = AIConfiguration()
}

enum PromptTemplate: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case swiftUIApp = "SwiftUI App"
    case restAPI = "REST API"
    case databaseSchema = "Database Schema"
    case dockerfile = "Dockerfile"
    case kubernetes = "Kubernetes Manifest"
    case terraform = "Terraform Configuration"
    case cloudformation = "CloudFormation Template"
    case authentication = "Authentication System"
    case crudOperations = "CRUD Operations"
    case websocket = "WebSocket Server"
    case graphql = "GraphQL Schema"
    case microservice = "Microservice Architecture"
    
    var id: String { rawValue }
    
    var systemPrompt: String {
        switch self {
        case .custom:
            return "RETURN MARKUP CODE"
        case .swiftUIApp:
            return "You are an expert SwiftUI developer. Generate production-ready SwiftUI code. RETURN MARKUP CODE"
        case .restAPI:
            return "You are an expert API developer. Generate RESTful API code with proper error handling. RETURN MARKUP CODE"
        case .databaseSchema:
            return "You are a database architect. Generate optimized database schemas and migrations. RETURN MARKUP CODE"
        case .dockerfile:
            return "You are a DevOps engineer. Generate optimized Dockerfiles following best practices. RETURN MARKUP CODE"
        case .kubernetes:
            return "You are a Kubernetes expert. Generate production-ready K8s manifests. RETURN MARKUP CODE"
        case .terraform:
            return "You are an infrastructure engineer. Generate Terraform configurations following best practices. RETURN MARKUP CODE"
        case .cloudformation:
            return "You are an AWS expert. Generate CloudFormation templates following AWS best practices. RETURN MARKUP CODE"
        case .authentication:
            return "You are a security expert. Generate secure authentication and authorization code. RETURN MARKUP CODE"
        case .crudOperations:
            return "You are a backend developer. Generate complete CRUD operations with validation. RETURN MARKUP CODE"
        case .websocket:
            return "You are a real-time systems expert. Generate WebSocket server implementations. RETURN MARKUP CODE"
        case .graphql:
            return "You are a GraphQL expert. Generate type-safe GraphQL schemas and resolvers. RETURN MARKUP CODE"
        case .microservice:
            return "You are a microservices architect. Generate microservice architecture code. RETURN MARKUP CODE"
        }
    }
    
    var userPromptPrefix: String {
        switch self {
        case .swiftUIApp:
            return "Create a SwiftUI app that "
        case .restAPI:
            return "Create a REST API that "
        case .databaseSchema:
            return "Design a database schema for "
        case .dockerfile:
            return "Create a Dockerfile for "
        case .kubernetes:
            return "Create a Kubernetes manifest for "
        case .terraform:
            return "Create Terraform configuration for "
        case .cloudformation:
            return "Create CloudFormation template for "
        case .authentication:
            return "Implement authentication for "
        case .crudOperations:
            return "Implement CRUD operations for "
        case .websocket:
            return "Create a WebSocket server for "
        case .graphql:
            return "Create a GraphQL schema for "
        case .microservice:
            return "Design a microservice architecture for "
        case .custom:
            return ""
        }
    }
}


