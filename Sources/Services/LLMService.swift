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
        case .grok:
            return await listGrokModels()
        }
    }
    
    func generateCode(
        prompt: String,
        systemPrompt: String,
        language: CodeLanguage,
        context: PodContext?
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
        case .grok:
            return try await generateWithGrokCLI(prompt: prompt, systemPrompt: systemPrompt, context: context)
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
    
    private func generateWithOpenAI(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
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
    
    private func generateWithAnthropic(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
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
    
    private func generateWithGoogle(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
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
    
    private func generateWithOllama(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
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
    
    private func generateWithMistyStudio(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
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
    
    struct PodContext {
        let currentPod: Pod
        let connectedPods: [Pod]
        let projectPods: [Pod]
    }
    
    private func buildContextPrompt(context: PodContext) -> String {
        let pod = context.currentPod
        let lang = pod.framework.primaryLanguage.rawValue
        
        var prompt = """
        AUTHORITATIVE SELECTED POD CONTEXT
        Generate CODE + YAML only for this pod. CODE must be valid \(lang) for \(pod.framework.rawValue).
        
        - Name: \(pod.name)
        - Type: \(pod.type.rawValue) (\(pod.type.frameworkHint))
        - Framework: \(pod.framework.rawValue)
        - Language: \(lang)
        - Launch file: \(pod.framework.launchFile)
        - Id: \(pod.id.uuidString)
        
        """
        
        if let path = pod.projectPath {
            prompt += "- Project path: \(path)\n"
        }
        
        // File inventory + launch body (primary syntax context)
        if !pod.files.isEmpty {
            prompt += "\nFiles in this pod:\n"
            for file in pod.files.prefix(15) {
                let mark = file.path == pod.framework.launchFile ? " [LAUNCH]" : ""
                prompt += "- \(file.path) (\(file.language.rawValue))\(mark)\n"
            }
            if let launch = pod.files.first(where: { $0.path == pod.framework.launchFile }) ?? pod.files.first {
                prompt += "\nLaunch file body (preserve language/style):\n\(String(launch.content.prefix(3500)))\n"
            }
        } else if !pod.code.isEmpty {
            prompt += "\nExisting code:\n\(String(pod.code.prefix(3500)))\n"
        }
        
        if !pod.kubernetesYAML.isEmpty {
            prompt += "\nExisting YAML preview:\n\(String(pod.kubernetesYAML.prefix(1500)))\n"
        }
        
        if configuration.includePodConnections && !context.connectedPods.isEmpty {
            prompt += "\nConnected pods (context only — do not rewrite them):\n"
            for other in context.connectedPods {
                prompt += "- \(other.name) | \(other.type.rawValue) | \(other.framework.rawValue)\n"
                if !other.code.isEmpty {
                    prompt += "  preview: \(other.code.prefix(120))…\n"
                }
            }
        }
        
        // Light graph of sibling pods for architecture awareness
        if context.projectPods.count > 1 {
            prompt += "\nOther pods in project (do not generate for them):\n"
            for other in context.projectPods where other.id != pod.id {
                prompt += "- \(other.name) (\(other.framework.rawValue))\n"
            }
        }
        
        prompt += "\nRemember: ===CODE=== must be pure \(lang) source matching \(pod.framework.launchFile).\n"
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

// MARK: - Grok CLI

extension LLMService {
    /// Resolve path to the `grok` binary (custom path, common install locations, or PATH).
    static func resolveGrokCLIPath(configured: String = "") -> String? {
        let candidates: [String] = {
            var list: [String] = []
            if !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                list.append(configured)
            }
            let home = NSHomeDirectory()
            list.append(contentsOf: [
                "\(home)/.grok/bin/grok",
                "\(home)/.local/bin/grok",
                "/usr/local/bin/grok",
                "/opt/homebrew/bin/grok"
            ])
            return list
        }()
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Fall back to PATH lookup
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "command -v grok"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }
    
    static func isGrokCLIInstalled(configuredPath: String = "") -> Bool {
        resolveGrokCLIPath(configured: configuredPath) != nil
    }
    
    private func listGrokModels() async -> [AIModel] {
        guard let grokPath = Self.resolveGrokCLIPath(configured: configuration.grokCLIPath) else {
            return []
        }
        
        // Prefer `grok models` when available
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: grokPath)
        process.arguments = ["models"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":\(NSHomeDirectory())/.grok/bin:\(NSHomeDirectory())/.local/bin:/usr/local/bin:/opt/homebrew/bin"
        process.environment = env
        
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var models: [AIModel] = []
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // lines like: "  * grok-4.5 (default)" or "  - grok-composer-2.5-fast"
                guard trimmed.hasPrefix("*") || trimmed.hasPrefix("-") else { continue }
                var token = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if let space = token.firstIndex(of: " ") {
                    token = String(token[..<space])
                } else {
                    token = String(token)
                }
                if !token.isEmpty {
                    models.append(AIModel(id: token, name: token, provider: .grok, contextWindow: 128000))
                }
            }
            if !models.isEmpty { return models }
        } catch {
            // fall through to defaults
        }
        
        let fallback = configuration.grokModel.isEmpty ? "grok-4.5" : configuration.grokModel
        return [
            AIModel(id: fallback, name: "\(fallback) (Grok CLI)", provider: .grok, contextWindow: 128000),
            AIModel(id: "grok-4.5", name: "grok-4.5", provider: .grok, contextWindow: 128000),
            AIModel(id: "grok-composer-2.5-fast", name: "grok-composer-2.5-fast", provider: .grok, contextWindow: 128000)
        ]
    }
    
    private func generateWithGrokCLI(prompt: String, systemPrompt: String, context: PodContext?) async throws -> String {
        guard let grokPath = Self.resolveGrokCLIPath(configured: configuration.grokCLIPath) else {
            throw LLMError.grokCLINotFound
        }
        
        var fullPrompt = systemPrompt
        fullPrompt += "\n\nYou generate BOTH application CODE and Kubernetes Pod YAML for ONE Pioneer pod.\n"
        fullPrompt += "CODE must use correct syntax for that pod’s language/framework only (no mixed languages, no prose).\n"
        fullPrompt += "Use ===CODE=== / ===YAML=== / ===END=== markers. No tool use — answer directly.\n"
        
        if let context = context, configuration.useContext {
            fullPrompt += "\n\n" + buildContextPrompt(context: context)
        }
        fullPrompt += "\n\nUser request:\n\(prompt)"
        
        let model = configuration.selectedModel.isEmpty
            ? (configuration.grokModel.isEmpty ? "grok-4.5" : configuration.grokModel)
            : configuration.selectedModel
        
        // Headless single-turn generation via Grok CLI
        // Disable agent tools so we get a pure text completion.
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: grokPath)
        process.arguments = [
            "-p", fullPrompt,
            "-m", model,
            "--max-turns", "1",
            "--output-format", "plain",
            "--disallowed-tools", "Agent,run_terminal_cmd,web_search,web_fetch,search_replace,write,read_file,grep,list_dir,spawn_subagent",
            "--verbatim"
        ]
        
        var env = ProcessInfo.processInfo.environment
        let extras = [
            "\(NSHomeDirectory())/.grok/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin"
        ]
        env["PATH"] = extras.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        process.environment = env
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                
                if proc.terminationStatus != 0 && stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: LLMError.requestFailed)
                    return
                }
                
                let result = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty {
                    // Some versions may print only to stderr
                    let fallback = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if fallback.isEmpty {
                        continuation.resume(throwing: LLMError.invalidResponse)
                    } else {
                        continuation.resume(returning: fallback)
                    }
                    return
                }
                continuation.resume(returning: result)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LLMError.requestFailed)
                }
            }
        }
    }
}

enum LLMError: Error {
    case missingAPIKey
    case requestFailed
    case invalidResponse
    case modelNotFound
    case grokCLINotFound
}


