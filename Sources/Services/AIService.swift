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
        framework: Framework,
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
            let userPrompt = buildNodeSpecificUserPrompt(prompt: prompt, node: nodeContext, template: selectedTemplate)
            
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
                language: framework.primaryLanguage,
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
            let generatedCode = generateStubCode(prompt: prompt, framework: framework, nodeContext: nodeContext)
            
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
        let basePrompt = template.systemPrompt
        
        guard let node = node else {
            return basePrompt
        }
        
        // Add node type-specific context
        var nodeContext = "\n\nNode Context:\n"
        nodeContext += "- Node Type: \(node.type.rawValue)\n"
        nodeContext += "- Node Name: \(node.name)\n"
        nodeContext += "- Framework: \(node.framework.rawValue)\n"
        
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
            
        case .service:
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
        
        // Add framework-specific instructions
        switch node.framework {
        case .django:
            nodeContext += "- Use Django best practices and conventions.\n"
            nodeContext += "- Follow Django project structure (apps, models, views, urls).\n"
            nodeContext += "- Use Django ORM for database operations.\n"
            
        case .flask:
            nodeContext += "- Use Flask best practices and blueprints.\n"
            nodeContext += "- Follow Flask project structure.\n"
            nodeContext += "- Use Flask-SQLAlchemy for database operations.\n"
            
        case .fastapi:
            nodeContext += "- Use FastAPI best practices with Pydantic models.\n"
            nodeContext += "- Include proper type hints and async/await patterns.\n"
            nodeContext += "- Use dependency injection for routes.\n"
            
        case .purepy:
            nodeContext += "- Use Python best practices (PEP 8 style guide).\n"
            nodeContext += "- Include proper docstrings and type hints.\n"
            nodeContext += "- Handle errors with try/except blocks.\n"
            
        case .nodejs, .express:
            nodeContext += "- Use Node.js best practices and async/await.\n"
            nodeContext += "- Follow Express.js conventions.\n"
            nodeContext += "- Include proper error handling middleware.\n"
            
        case .nestjs:
            nodeContext += "- Use NestJS best practices with decorators.\n"
            nodeContext += "- Follow NestJS module structure.\n"
            nodeContext += "- Use dependency injection and providers.\n"
            
        case .angular:
            nodeContext += "- Use Angular best practices with TypeScript.\n"
            nodeContext += "- Follow Angular component and service patterns.\n"
            nodeContext += "- Use RxJS for reactive programming.\n"
            
        case .react:
            nodeContext += "- Use React best practices with hooks.\n"
            nodeContext += "- Follow React component patterns.\n"
            nodeContext += "- Use functional components and hooks.\n"
            
        case .vue:
            nodeContext += "- Use Vue.js best practices with Composition API.\n"
            nodeContext += "- Follow Vue component patterns.\n"
            nodeContext += "- Use Vuex or Pinia for state management.\n"
            
        case .nextjs:
            nodeContext += "- Use Next.js best practices with App Router.\n"
            nodeContext += "- Follow Next.js file-based routing.\n"
            nodeContext += "- Use Server Components and Client Components appropriately.\n"
            
        case .swift, .swiftui:
            nodeContext += "- Use Swift best practices and SwiftUI patterns.\n"
            nodeContext += "- Follow Swift API Design Guidelines.\n"
            nodeContext += "- Use proper error handling with Result types or throws.\n"
            
        case .rust:
            nodeContext += "- Use Rust best practices and ownership patterns.\n"
            nodeContext += "- Follow Rust naming conventions.\n"
            nodeContext += "- Use Result types for error handling.\n"
            
        case .go:
            nodeContext += "- Use Go best practices and conventions.\n"
            nodeContext += "- Follow Go naming conventions.\n"
            nodeContext += "- Use proper error handling with error returns.\n"
            
        case .java, .spring:
            nodeContext += "- Use Java best practices and Spring patterns.\n"
            nodeContext += "- Follow Spring Boot conventions.\n"
            nodeContext += "- Use dependency injection and annotations.\n"
            
        case .docker:
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
    
    private func generateStubCode(prompt: String, framework: Framework, nodeContext: Node?) -> String {
        // This is a placeholder - replace with actual AI API integration
        // For now, return formatted code based on framework
        
        switch framework {
        case .swift, .swiftui:
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
            
        case .django, .flask, .fastapi, .purepy:
            return """
            # Generated code for: \(prompt)
            def main():
                print("Generated from: \(prompt)")
            
            if __name__ == "__main__":
                main()
            """
            
        case .nodejs, .express, .nestjs, .angular, .react, .vue, .nextjs:
            return """
            // Generated code for: \(prompt)
            console.log('Generated from: \(prompt)');
            """
            
        case .rust:
            return """
            // Generated code for: \(prompt)
            fn main() {
                println!("Generated from: \(prompt)");
            }
            """
            
        case .go:
            return """
            // Generated code for: \(prompt)
            package main
            
            import "fmt"
            
            func main() {
                fmt.Println("Generated from: \(prompt)")
            }
            """
            
        case .java, .spring:
            return """
            // Generated code for: \(prompt)
            public class Main {
                public static void main(String[] args) {
                    System.out.println("Generated from: \(prompt)");
                }
            }
            """
            
        case .docker:
            return """
            # Generated code for: \(prompt)
            FROM node:20-alpine
            WORKDIR /app
            COPY . .
            CMD ["node", "index.js"]
            """
            
        case .kubernetes:
            return """
            # Generated code for: \(prompt)
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: app
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: app
              template:
                metadata:
                  labels:
                    app: app
                spec:
                  containers:
                  - name: app
                    image: app:latest
            """
            
        case .terraform:
            return """
            # Generated code for: \(prompt)
            resource "aws_instance" "example" {
              ami           = "ami-0c55b159cbfafe1f0"
              instance_type = "t2.micro"
            }
            """
        }
    }
    
    // Legacy stub code generation for file-level languages (deprecated)
    private func generateStubCodeForLanguage(prompt: String, language: CodeLanguage) -> String {
        switch language {
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
        default:
            return """
            // Generated code for: \(prompt)
            // Language: \(language.rawValue)
            """
        }
    }
}


