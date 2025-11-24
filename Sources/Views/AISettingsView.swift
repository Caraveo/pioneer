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
                Section {
                    Picker("Provider", selection: $aiService.configuration.selectedProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            HStack {
                                Image(systemName: provider.icon)
                                Text(provider.rawValue)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: aiService.configuration.selectedProvider) { _ in
                        loadModels()
                    }
                    
                    if aiService.configuration.selectedProvider.requiresAPIKey {
                        Text("API Key required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        Text("Local model - no API key needed")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.top, 4)
                    }
                } header: {
                    Text("AI Provider")
                }
                
                // API Keys
                if aiService.configuration.selectedProvider == .openai {
                    Section {
                        SecureField("sk-...", text: $aiService.configuration.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: aiService.configuration.openAIAPIKey) { _ in
                                loadModels()
                            }
                    } header: {
                        Text("OpenAI API Key")
                    }
                }
                
                if aiService.configuration.selectedProvider == .anthropic {
                    Section {
                        SecureField("sk-ant-...", text: $aiService.configuration.anthropicAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: aiService.configuration.anthropicAPIKey) { _ in
                                loadModels()
                            }
                    } header: {
                        Text("Anthropic API Key")
                    }
                }
                
                if aiService.configuration.selectedProvider == .google {
                    Section {
                        SecureField("AIza...", text: $aiService.configuration.googleAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: aiService.configuration.googleAPIKey) { _ in
                                loadModels()
                            }
                    } header: {
                        Text("Google API Key")
                    }
                }
                
                // Model Selection
                Section {
                    if isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if availableModels.isEmpty {
                        Text("No models available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        Picker("Model", selection: $aiService.configuration.selectedModel) {
                            ForEach(availableModels) { model in
                                Text(model.name)
                                    .tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    if aiService.configuration.selectedProvider == .ollama {
                        TextField("Model Name", text: $aiService.configuration.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .padding(.top, 4)
                    }
                    
                    if aiService.configuration.selectedProvider == .mistystudio {
                        TextField("Model Name", text: $aiService.configuration.mistystudioModel)
                            .textFieldStyle(.roundedBorder)
                            .padding(.top, 4)
                    }
                } header: {
                    Text("Model")
                }
                
                // Generation Settings
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Temperature")
                                .frame(width: 120, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.2f", aiService.configuration.temperature))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        Slider(value: $aiService.configuration.temperature, in: 0...2, step: 0.1)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Max Tokens")
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        TextField("2000", value: $aiService.configuration.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Use Context", isOn: $aiService.configuration.useContext)
                        .padding(.vertical, 4)
                    Toggle("Include Node Connections", isOn: $aiService.configuration.includeNodeConnections)
                        .padding(.vertical, 4)
                } header: {
                    Text("Generation Settings")
                }
                
                // Prompt Templates
                Section {
                    Picker("Template", selection: $aiService.selectedTemplate) {
                        ForEach(PromptTemplate.allCases) { template in
                            Text(template.rawValue)
                                .tag(template)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if aiService.selectedTemplate != .custom {
                        Text(aiService.selectedTemplate.systemPrompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Prompt Templates")
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
            .formStyle(.grouped)
        }
        .frame(minWidth: 600, idealWidth: 650, maxWidth: 700, minHeight: 650, idealHeight: 700, maxHeight: 800)
        .padding()
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

