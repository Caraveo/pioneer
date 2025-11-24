import SwiftUI

struct AISettingsView: View {
    @ObservedObject var aiService: AIService
    @Environment(\.dismiss) var dismiss
    @State private var availableModels: [AIModel] = []
    @State private var isLoadingModels: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                // Provider Selection
                Section("AI Provider") {
                    Picker("Provider", selection: $aiService.configuration.selectedProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            HStack {
                                Image(systemName: provider.icon)
                                Text(provider.rawValue)
                            }
                            .tag(provider)
                        }
                    }
                    .onChange(of: aiService.configuration.selectedProvider) { _ in
                        loadModels()
                    }
                    
                    if aiService.configuration.selectedProvider.requiresAPIKey {
                        Text("API Key required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Local model - no API key needed")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                // API Keys
                if aiService.configuration.selectedProvider == .openai {
                    Section("OpenAI API Key") {
                        SecureField("sk-...", text: $aiService.configuration.openAIAPIKey)
                            .onChange(of: aiService.configuration.openAIAPIKey) { _ in
                                loadModels()
                            }
                    }
                }
                
                if aiService.configuration.selectedProvider == .anthropic {
                    Section("Anthropic API Key") {
                        SecureField("sk-ant-...", text: $aiService.configuration.anthropicAPIKey)
                            .onChange(of: aiService.configuration.anthropicAPIKey) { _ in
                                loadModels()
                            }
                    }
                }
                
                if aiService.configuration.selectedProvider == .google {
                    Section("Google API Key") {
                        SecureField("AIza...", text: $aiService.configuration.googleAPIKey)
                            .onChange(of: aiService.configuration.googleAPIKey) { _ in
                                loadModels()
                            }
                    }
                }
                
                // Model Selection
                Section("Model") {
                    if isLoadingModels {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if availableModels.isEmpty {
                        Text("No models available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Model", selection: $aiService.configuration.selectedModel) {
                            ForEach(availableModels) { model in
                                Text(model.name)
                                    .tag(model.id)
                            }
                        }
                    }
                    
                    if aiService.configuration.selectedProvider == .ollama {
                        TextField("Model Name", text: $aiService.configuration.ollamaModel)
                            .font(.caption)
                    }
                    
                    if aiService.configuration.selectedProvider == .mistystudio {
                        TextField("Model Name", text: $aiService.configuration.mistystudioModel)
                            .font(.caption)
                    }
                }
                
                // Generation Settings
                Section("Generation Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", aiService.configuration.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $aiService.configuration.temperature, in: 0...2, step: 0.1)
                    }
                    
                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        TextField("2000", value: $aiService.configuration.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    
                    Toggle("Use Context", isOn: $aiService.configuration.useContext)
                    Toggle("Include Node Connections", isOn: $aiService.configuration.includeNodeConnections)
                }
                
                // Prompt Templates
                Section("Prompt Templates") {
                    Picker("Template", selection: $aiService.selectedTemplate) {
                        ForEach(PromptTemplate.allCases) { template in
                            Text(template.rawValue)
                                .tag(template)
                        }
                    }
                    
                    if aiService.selectedTemplate != .custom {
                        Text(aiService.selectedTemplate.systemPrompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("AI Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadModels()
        }
    }
    
    private func loadModels() {
        isLoadingModels = true
        Task {
            let models = await aiService.listAvailableModels(for: aiService.configuration.selectedProvider)
            await MainActor.run {
                availableModels = models
                isLoadingModels = false
                
                // Auto-select first model if none selected
                if aiService.configuration.selectedModel.isEmpty, let firstModel = models.first {
                    aiService.configuration.selectedModel = firstModel.id
                }
            }
        }
    }
}

