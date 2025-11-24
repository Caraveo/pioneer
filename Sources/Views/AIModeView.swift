import SwiftUI

struct AIModeView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var aiPrompt: String = ""
    @State private var aiResponse: String = ""
    @State private var isGenerating: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // AI Prompt Input Area
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.top)
                
                Text("Ask AI to generate code, create nodes, or help with your project")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Prompt input
                HStack(spacing: 12) {
                    TextField("Enter your prompt...", text: $aiPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...10)
                        .disabled(isGenerating)
                    
                    Button(action: {
                        handleAIPrompt()
                    }) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiPrompt.isEmpty || isGenerating)
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // AI Response Area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if aiResponse.isEmpty && !isGenerating {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No response yet")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Enter a prompt above to get started")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else if isGenerating {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Generating response...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        // Display response
                        Text(aiResponse)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    private func handleAIPrompt() {
        guard !aiPrompt.isEmpty else { return }
        
        isGenerating = true
        aiResponse = ""
        
        Task {
            // Get context from selected node if available
            let selectedNode = projectManager.selectedNode
            let connectedNodes = selectedNode?.connections.compactMap { id in
                projectManager.nodes.first { $0.id == id }
            } ?? []
            
            if let generatedCode = await projectManager.aiService.generateCode(
                prompt: aiPrompt,
                language: selectedNode?.language ?? .swift,
                nodeContext: selectedNode,
                connectedNodes: connectedNodes,
                allNodes: projectManager.nodes
            ) {
                await MainActor.run {
                    aiResponse = generatedCode
                    isGenerating = false
                }
            } else {
                await MainActor.run {
                    aiResponse = "Failed to generate response. Please try again."
                    isGenerating = false
                }
            }
        }
    }
}

