import Foundation

class LLMService {
    private let configuration: AIConfiguration
    
    init(configuration: AIConfiguration) {
        self.configuration = configuration
    }
    
    func listAvailableModels(for provider: LLMProvider) async -> [AIModel] {
        switch provider {
        case .openai:
            return await listOpenAIModels()
        case .anthropic:
            return await listAnthropicModels()
        case .google:
            return await listGoogleModels()
        case .ollama:
            return await listOllamaModels()
        case .mistystudio:
            return await listMistyStudioModels()
        }
    }
    
    func generateCode(
        prompt: String,
        systemPrompt: String,
        language: CodeLanguage,
        context: NodeContext?
    ) async throws -> String {
        switch configuration.selectedProvider {
        case .openai:
            return try await generateWithOpenAI(prompt: prompt, systemPrompt: systemPrompt, context: context)
        case .anthropic:
            return try await generateWithAnthropic(prompt: prompt, systemPrompt: systemPrompt, context: context)
        case .google:
            return try await generateWithGoogle(prompt: prompt, systemPrompt: systemPrompt, context: context)
        case .ollama:
            return try await generateWithOllama(prompt: prompt, systemPrompt: systemPrompt, context: context)
        case .mistystudio:
            return try await generateWithMistyStudio(prompt: prompt, systemPrompt: systemPrompt, context: context)
        }
    }
    
    // MARK: - OpenAI
    
    private func listOpenAIModels() async -> [AIModel] {
        guard !configuration.openAIAPIKey.isEmpty else { return [] }
        
        // Default OpenAI models
        return [
            AIModel(id: "gpt-4-turbo-preview", name: "GPT-4 Turbo", provider: .openai, contextWindow: 128000),
            AIModel(id: "gpt-4", name: "GPT-4", provider: .openai, contextWindow: 8192),
            AIModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: .openai, contextWindow: 16385),
        ]
    }
    
    private func generateWithOpenAI(prompt: String, systemPrompt: String, context: NodeContext?) async throws -> String {
        guard !configuration.openAIAPIKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        let model = configuration.selectedModel.isEmpty ? "gpt-4-turbo-preview" : configuration.selectedModel
        let url = URL(string: "\(LLMProvider.openai.baseURL)/chat/completions")!
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add context if available
        if let context = context, configuration.useContext {
            let contextPrompt = buildContextPrompt(context: context)
            messages.append(["role": "user", "content": contextPrompt])
        }
        
        messages.append(["role": "user", "content": prompt])
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens
        ]
        
        return try await makeRequest(url: url, method: "POST", body: body, apiKey: configuration.openAIAPIKey)
    }
    
    // MARK: - Anthropic
    
    private func listAnthropicModels() async -> [AIModel] {
        guard !configuration.anthropicAPIKey.isEmpty else { return [] }
        
        return [
            AIModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", provider: .anthropic, contextWindow: 200000),
            AIModel(id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", provider: .anthropic, contextWindow: 200000),
            AIModel(id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", provider: .anthropic, contextWindow: 200000),
        ]
    }
    
    private func generateWithAnthropic(prompt: String, systemPrompt: String, context: NodeContext?) async throws -> String {
        guard !configuration.anthropicAPIKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        let model = configuration.selectedModel.isEmpty ? "claude-3-sonnet-20240229" : configuration.selectedModel
        let url = URL(string: "\(LLMProvider.anthropic.baseURL)/messages")!
        
        var messages: [[String: Any]] = []
        
        // Add context if available
        if let context = context, configuration.useContext {
            let contextPrompt = buildContextPrompt(context: context)
            messages.append(["role": "user", "content": contextPrompt])
        }
        
        messages.append(["role": "user", "content": prompt])
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": configuration.maxTokens,
            "system": systemPrompt,
            "messages": messages,
            "temperature": configuration.temperature
        ]
        
        return try await makeAnthropicRequest(url: url, body: body, apiKey: configuration.anthropicAPIKey)
    }
    
    // MARK: - Google Gemini
    
    private func listGoogleModels() async -> [AIModel] {
        guard !configuration.googleAPIKey.isEmpty else { return [] }
        
        return [
            AIModel(id: "gemini-pro", name: "Gemini Pro", provider: .google, contextWindow: 32768),
            AIModel(id: "gemini-pro-vision", name: "Gemini Pro Vision", provider: .google, contextWindow: 16384),
        ]
    }
    
    private func generateWithGoogle(prompt: String, systemPrompt: String, context: NodeContext?) async throws -> String {
        guard !configuration.googleAPIKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        let model = configuration.selectedModel.isEmpty ? "gemini-pro" : configuration.selectedModel
        let url = URL(string: "\(LLMProvider.google.baseURL)/models/\(model):generateContent?key=\(configuration.googleAPIKey)")!
        
        var fullPrompt = systemPrompt + "\n\n" + prompt
        
        // Add context if available
        if let context = context, configuration.useContext {
            let contextPrompt = buildContextPrompt(context: context)
            fullPrompt = contextPrompt + "\n\n" + fullPrompt
        }
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": configuration.temperature,
                "maxOutputTokens": configuration.maxTokens
            ]
        ]
        
        return try await makeGoogleRequest(url: url, body: body)
    }
    
    // MARK: - Ollama
    
    private func listOllamaModels() async -> [AIModel] {
        guard let url = URL(string: "\(LLMProvider.ollama.baseURL)/api/tags") else {
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let name = model["name"] as? String else { return nil }
                    return AIModel(id: name, name: name, provider: .ollama)
                }
            }
        } catch {
            print("Failed to list Ollama models: \(error)")
        }
        
        // Return default if API fails
        return [
            AIModel(id: "llama2", name: "Llama 2", provider: .ollama),
            AIModel(id: "mistral", name: "Mistral", provider: .ollama),
            AIModel(id: "codellama", name: "Code Llama", provider: .ollama),
        ]
    }
    
    private func generateWithOllama(prompt: String, systemPrompt: String, context: NodeContext?) async throws -> String {
        let model = configuration.ollamaModel.isEmpty ? "llama2" : configuration.ollamaModel
        let url = URL(string: "\(LLMProvider.ollama.baseURL)/api/generate")!
        
        var fullPrompt = systemPrompt + "\n\n" + prompt
        
        // Add context if available
        if let context = context, configuration.useContext {
            let contextPrompt = buildContextPrompt(context: context)
            fullPrompt = contextPrompt + "\n\n" + fullPrompt
        }
        
        let body: [String: Any] = [
            "model": model,
            "prompt": fullPrompt,
            "stream": false,
            "options": [
                "temperature": configuration.temperature,
                "num_predict": configuration.maxTokens
            ]
        ]
        
        return try await makeOllamaRequest(url: url, body: body)
    }
    
    // MARK: - MistyStudio
    
    private func listMistyStudioModels() async -> [AIModel] {
        guard let url = URL(string: "\(LLMProvider.mistystudio.baseURL)/api/v1/models") else {
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let id = model["id"] as? String else { return nil }
                    return AIModel(id: id, name: id, provider: .mistystudio)
                }
            }
        } catch {
            print("Failed to list MistyStudio models: \(error)")
        }
        
        // Return default if API fails
        return [
            AIModel(id: "mistral", name: "Mistral", provider: .mistystudio),
        ]
    }
    
    private func generateWithMistyStudio(prompt: String, systemPrompt: String, context: NodeContext?) async throws -> String {
        let model = configuration.mistystudioModel.isEmpty ? "mistral" : configuration.mistystudioModel
        let url = URL(string: "\(LLMProvider.mistystudio.baseURL)/api/v1/chat/completions")!
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add context if available
        if let context = context, configuration.useContext {
            let contextPrompt = buildContextPrompt(context: context)
            messages.append(["role": "user", "content": contextPrompt])
        }
        
        messages.append(["role": "user", "content": prompt])
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens
        ]
        
        return try await makeRequest(url: url, method: "POST", body: body, apiKey: nil)
    }
    
    // MARK: - Context Building
    
    struct NodeContext {
        let currentNode: Node
        let connectedNodes: [Node]
        let projectNodes: [Node]
    }
    
    private func buildContextPrompt(context: NodeContext) -> String {
        var prompt = "Context about the current project:\n\n"
        
        if configuration.includeNodeConnections && !context.connectedNodes.isEmpty {
            prompt += "Connected Nodes:\n"
            for node in context.connectedNodes {
                prompt += "- \(node.name) (\(node.type.rawValue)): \(node.framework.rawValue)\n"
                if !node.code.isEmpty {
                    prompt += "  Code preview: \(node.code.prefix(100))...\n"
                }
            }
            prompt += "\n"
        }
        
        prompt += "Current Node:\n"
        prompt += "- Name: \(context.currentNode.name)\n"
        prompt += "- Type: \(context.currentNode.type.rawValue)\n"
        prompt += "- Framework: \(context.currentNode.framework.rawValue)\n"
        
        if !context.currentNode.code.isEmpty {
            prompt += "- Existing code: \(context.currentNode.code.prefix(200))...\n"
        }
        
        return prompt
    }
    
    // MARK: - HTTP Helpers
    
    private func makeRequest(url: URL, method: String, body: [String: Any], apiKey: String?) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.requestFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return content
    }
    
    private func makeAnthropicRequest(url: URL, body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("anthropic-version-2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.requestFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return text
    }
    
    private func makeGoogleRequest(url: URL, body: [String: Any]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.requestFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return text
    }
    
    private func makeOllamaRequest(url: URL, body: [String: Any]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.requestFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return response
    }
}

enum LLMError: Error {
    case missingAPIKey
    case requestFailed
    case invalidResponse
    case modelNotFound
}


