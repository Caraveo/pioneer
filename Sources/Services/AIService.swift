import Foundation
import AppKit

class AIService: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var lastResponse: String = ""
    @Published var configuration: AIConfiguration = .default {
        didSet {
            AIConfigurationManager().saveConfiguration(configuration)
        }
    }
    @Published var selectedTemplate: PromptTemplate = .custom
    
    private let configManager = AIConfigurationManager()
    
    init() {
        self.configuration = configManager.loadConfiguration()
    }
    
    private var llmService: LLMService {
        LLMService(configuration: configuration)
    }
    
    func generateCode(
        prompt: String,
        language: CodeLanguage,
        nodeContext: Node?,
        connectedNodes: [Node],
        allNodes: [Node]
    ) async -> String? {
        await MainActor.run {
            isProcessing = true
        }
        
        do {
            // Build node-specific system prompt
            let systemPrompt = buildNodeSpecificSystemPrompt(node: nodeContext, template: selectedTemplate)
            
            // Build user prompt with node-specific context
            var userPrompt = buildNodeSpecificUserPrompt(prompt: prompt, node: nodeContext, template: selectedTemplate)
            
            // Build context
            let context: LLMService.NodeContext? = {
                guard let nodeContext = nodeContext else { return nil }
                return LLMService.NodeContext(
                    currentNode: nodeContext,
                    connectedNodes: connectedNodes,
                    projectNodes: allNodes
                )
            }()
            
            // Generate code using LLM service
            let generatedCode = try await llmService.generateCode(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                language: language,
                context: context
            )
            
            await MainActor.run {
                isProcessing = false
                lastResponse = generatedCode
            }
            
            return generatedCode
        } catch {
            // Fallback to stub code if LLM fails
            print("LLM generation failed: \(error), using fallback")
            let generatedCode = generateStubCode(prompt: prompt, language: language, nodeContext: nodeContext)
            
            await MainActor.run {
                isProcessing = false
                lastResponse = generatedCode
            }
            
            return generatedCode
        }
    }
    
    func listAvailableModels(for provider: LLMProvider) async -> [AIModel] {
        let service = LLMService(configuration: configuration)
        return await service.listAvailableModels(for: provider)
    }
    
    private func buildNodeSpecificSystemPrompt(node: Node?, template: PromptTemplate) -> String {
        var basePrompt = template.systemPrompt
        
        guard let node = node else {
            return basePrompt
        }
        
        // Add node type-specific context
        var nodeContext = "\n\nNode Context:\n"
        nodeContext += "- Node Type: \(node.type.rawValue)\n"
        nodeContext += "- Node Name: \(node.name)\n"
        nodeContext += "- Language: \(node.language.rawValue)\n"
        
        if let projectPath = node.projectPath {
            nodeContext += "- Project Path: \(projectPath)\n"
        }
        
        // Add node type-specific instructions
        switch node.type {
        case .macOSApp:
            nodeContext += "- This is a macOS application. Generate native macOS code using SwiftUI.\n"
            nodeContext += "- Follow macOS Human Interface Guidelines.\n"
            nodeContext += "- Use AppKit and SwiftUI frameworks appropriately.\n"
            
        case .iPhoneApp:
            nodeContext += "- This is an iPhone/iPad application. Generate iOS code using SwiftUI.\n"
            nodeContext += "- Follow iOS Human Interface Guidelines.\n"
            nodeContext += "- Support both iPhone and iPad layouts.\n"
            nodeContext += "- Use UIKit and SwiftUI frameworks appropriately.\n"
            
        case .website:
            nodeContext += "- This is a web application. Generate HTML, CSS, and JavaScript.\n"
            nodeContext += "- Make it responsive and modern.\n"
            nodeContext += "- Use best practices for web development.\n"
            
        case .awsBackend:
            nodeContext += "- This is an AWS backend service. Generate infrastructure and server code.\n"
            nodeContext += "- Use AWS best practices and services (Lambda, API Gateway, DynamoDB, etc.).\n"
            nodeContext += "- Include proper error handling and logging.\n"
            
        case .custom:
            nodeContext += "- This is a custom project. Generate code appropriate for the selected language.\n"
        }
        
        // Add language-specific instructions
        switch node.language {
        case .python:
            nodeContext += "- Use Python best practices (PEP 8 style guide).\n"
            nodeContext += "- Include proper docstrings and type hints where appropriate.\n"
            nodeContext += "- Handle errors with try/except blocks.\n"
            
        case .swift:
            nodeContext += "- Use Swift best practices and SwiftUI patterns.\n"
            nodeContext += "- Follow Swift API Design Guidelines.\n"
            nodeContext += "- Use proper error handling with Result types or throws.\n"
            
        case .typescript, .javascript:
            nodeContext += "- Use modern ES6+ JavaScript/TypeScript features.\n"
            nodeContext += "- Follow TypeScript best practices if applicable.\n"
            nodeContext += "- Include proper error handling.\n"
            
        case .dockerfile:
            nodeContext += "- Generate optimized, production-ready Dockerfiles.\n"
            nodeContext += "- Use multi-stage builds when appropriate.\n"
            nodeContext += "- Follow Docker best practices.\n"
            
        case .kubernetes:
            nodeContext += "- Generate production-ready Kubernetes manifests.\n"
            nodeContext += "- Include proper resource limits and health checks.\n"
            nodeContext += "- Follow Kubernetes best practices.\n"
            
        case .terraform:
            nodeContext += "- Generate Terraform configurations following best practices.\n"
            nodeContext += "- Use variables and outputs appropriately.\n"
            nodeContext += "- Include proper state management considerations.\n"
            
        default:
            break
        }
        
        return basePrompt + nodeContext
    }
    
    private func buildNodeSpecificUserPrompt(prompt: String, node: Node?, template: PromptTemplate) -> String {
        var userPrompt = prompt
        
        // Add template prefix if applicable
        if template != .custom, !template.userPromptPrefix.isEmpty {
            userPrompt = template.userPromptPrefix + prompt
        }
        
        guard let node = node else {
            return userPrompt
        }
        
        // Add node-specific project context
        var projectContext = "\n\nProject Requirements:\n"
        projectContext += "- Project Name: \(node.name)\n"
        projectContext += "- This code will be part of a \(node.type.rawValue) project.\n"
        
        if let projectPath = node.projectPath {
            projectContext += "- Project is located at: \(projectPath)\n"
        }
        
        // Add connected nodes context if any
        // This will be handled by the context parameter, but we can add a note
        if !node.connections.isEmpty {
            projectContext += "- This node connects to other nodes in the system.\n"
        }
        
        return userPrompt + projectContext
    }
    
    private func generateStubCode(prompt: String, language: CodeLanguage, nodeContext: Node?) -> String {
        // This is a placeholder - replace with actual AI API integration
        // For now, return formatted code based on language
        
        switch language {
        case .swift:
            return """
            // Generated code for: \(prompt)
            import SwiftUI
            
            struct GeneratedView: View {
                var body: some View {
                    VStack {
                        Text("Generated from: \(prompt)")
                    }
                    .padding()
                }
            }
            """
            
        case .python:
            return """
            # Generated code for: \(prompt)
            def main():
                print("Generated from: \(prompt)")
            
            if __name__ == "__main__":
                main()
            """
            
        case .yaml:
            return """
            # Generated YAML for: \(prompt)
            apiVersion: v1
            kind: ConfigMap
            metadata:
              name: generated-config
            data:
              prompt: "\(prompt)"
            """
            
        case .json:
            return """
            {
              "generated": true,
              "prompt": "\(prompt)",
              "type": "generated_code"
            }
            """
            
        case .scaffolding:
            return """
            # Scaffolding template for: \(prompt)
            # This is a high-level structure template
            
            PROJECT_STRUCTURE:
              - src/
              - tests/
              - docs/
              - config/
            
            DEPENDENCIES:
              - Add your dependencies here
            
            CONFIGURATION:
              - Configure your project settings
            """
            
        case .dockerfile:
            return """
            # Generated Dockerfile for: \(prompt)
            FROM python:3.11-slim
            
            WORKDIR /app
            
            COPY requirements.txt .
            RUN pip install --no-cache-dir -r requirements.txt
            
            COPY . .
            
            CMD ["python", "main.py"]
            """
            
        case .kubernetes:
            return """
            # Generated Kubernetes manifest for: \(prompt)
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: generated-deployment
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: generated
              template:
                metadata:
                  labels:
                    app: generated
                spec:
                  containers:
                  - name: app
                    image: generated:latest
            """
            
        case .terraform:
            return """
            # Generated Terraform for: \(prompt)
            terraform {
              required_providers {
                aws = {
                  source  = "hashicorp/aws"
                  version = "~> 5.0"
                }
              }
            }
            
            resource "aws_instance" "generated" {
              ami           = "ami-0c55b159cbfafe1f0"
              instance_type = "t2.micro"
            }
            """
            
        case .cloudformation:
            return """
            # Generated CloudFormation for: \(prompt)
            AWSTemplateFormatVersion: '2010-09-09'
            Description: Generated template
            
            Resources:
              GeneratedResource:
                Type: AWS::EC2::Instance
                Properties:
                  ImageId: ami-0c55b159cbfafe1f0
                  InstanceType: t2.micro
            """
            
        case .typescript:
            return """
            // Generated TypeScript for: \(prompt)
            interface Generated {
              prompt: string;
            }
            
            const generated: Generated = {
              prompt: "\(prompt)"
            };
            
            export default generated;
            """
            
        case .javascript:
            return """
            // Generated JavaScript for: \(prompt)
            const generated = {
              prompt: "\(prompt)"
            };
            
            export default generated;
            """
            
        case .html:
            return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>Generated: \(prompt)</title>
            </head>
            <body>
                <h1>Generated from: \(prompt)</h1>
            </body>
            </html>
            """
            
        case .css:
            return """
            /* Generated CSS for: \(prompt) */
            .generated {
              display: flex;
              flex-direction: column;
              padding: 1rem;
            }
            """
            
        case .sql:
            return """
            -- Generated SQL for: \(prompt)
            CREATE TABLE generated (
                id SERIAL PRIMARY KEY,
                prompt TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            """
            
        case .bash:
            return """
            #!/bin/bash
            # Generated Bash script for: \(prompt)
            
            echo "Generated from: \(prompt)"
            """
            
        case .markdown:
            return """
            # Generated Markdown for: \(prompt)
            
            This is generated content based on your prompt.
            
            ## Features
            - Generated automatically
            - Based on: \(prompt)
            """
        }
    }
}


