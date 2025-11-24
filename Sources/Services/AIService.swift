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
            // Build system prompt from template
            let systemPrompt = selectedTemplate.systemPrompt
            
            // Build user prompt with template prefix if applicable
            var userPrompt = prompt
            if selectedTemplate != .custom, !selectedTemplate.userPromptPrefix.isEmpty {
                userPrompt = selectedTemplate.userPromptPrefix + prompt
            }
            
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


