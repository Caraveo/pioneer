import Foundation
import AppKit

/// Dual artifact from a single AI prompt for one Pioneer pod.
struct PodGenerationResult {
    var code: String
    var yaml: String
    var rawResponse: String
    
    var hasCode: Bool { !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasYAML: Bool { !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

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
    
    /// Generate **both** application CODE and Kubernetes Pod YAML for the selected pod in one prompt.
    /// CODE is constrained to the pod’s framework language/syntax; prompts include full pod context.
    func generateForPod(
        prompt: String,
        framework: Framework,
        podContext: Pod?,
        connectedPods: [Pod],
        allPods: [Pod]
    ) async -> PodGenerationResult? {
        await MainActor.run {
            isProcessing = true
        }
        
        // Always work off the pod’s actual framework when available
        let effectiveFramework = podContext?.framework ?? framework
        
        do {
            let systemPrompt = buildDualArtifactSystemPrompt(pod: podContext, template: selectedTemplate)
            let userPrompt = buildDualArtifactUserPrompt(prompt: prompt, pod: podContext, template: selectedTemplate)
            
            let context: LLMService.PodContext? = {
                guard let podContext = podContext else { return nil }
                return LLMService.PodContext(
                    currentPod: podContext,
                    connectedPods: connectedPods,
                    projectPods: allPods
                )
            }()
            
            let raw = try await llmService.generateCode(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                language: effectiveFramework.primaryLanguage,
                context: context
            )
            
            var result = Self.parseDualArtifactResponse(raw, pod: podContext)
            
            // Normalize CODE to the pod’s syntax/context
            if let pod = podContext {
                result.code = Self.normalizeGeneratedCode(result.code, for: pod)
                if !result.hasYAML {
                    result.yaml = KubernetesManifestService.generateYAML(for: pod, projectPath: pod.projectPath)
                } else {
                    result.yaml = Self.normalizeGeneratedYAML(result.yaml, for: pod)
                }
                
                // If model returned empty/non-code, fall back to a syntactically valid stub in that language
                if !result.hasCode {
                    result.code = generateStubCode(prompt: prompt, framework: effectiveFramework, podContext: pod)
                }
            }
            
            await MainActor.run {
                isProcessing = false
                lastResponse = raw
            }
            
            return result
        } catch {
            print("LLM generation failed: \(error), using dual-artifact fallback")
            let fallback = generateStubDualArtifact(prompt: prompt, framework: effectiveFramework, podContext: podContext)
            await MainActor.run {
                isProcessing = false
                lastResponse = fallback.rawResponse
            }
            return fallback
        }
    }
    
    /// Backward-compatible: returns only the CODE section of a dual generation.
    func generateCode(
        prompt: String,
        framework: Framework,
        podContext: Pod?,
        connectedPods: [Pod],
        allPods: [Pod]
    ) async -> String? {
        let result = await generateForPod(
            prompt: prompt,
            framework: framework,
            podContext: podContext,
            connectedPods: connectedPods,
            allPods: allPods
        )
        return result?.code
    }
    
    func listAvailableModels(for provider: LLMProvider) async -> [AIModel] {
        let service = LLMService(configuration: configuration)
        return await service.listAvailableModels(for: provider)
    }
    
    // MARK: - Dual CODE + YAML prompts (pod-scoped, language-correct)
    
    private func buildDualArtifactSystemPrompt(pod: Pod?, template: PromptTemplate) -> String {
        var system = """
        You are Pioneer’s dual-artifact code generator for ONE selected pod.
        
        HARD RULES:
        1) All CODE must be valid, parseable source in the EXACT language of the selected pod’s framework.
        2) Do NOT mix languages (no Python when the pod is Swift, no Swift when the pod is Python, etc.).
        3) Do NOT emit pseudocode, prose, bullet lists, or markdown inside ===CODE===.
        4) Do NOT wrap CODE or YAML in markdown fences (no ```).
        5) Generate ONLY for the SELECTED pod — use its name, type, framework, files, and paths as ground truth.
        6) Each Pioneer pod is its OWN Kubernetes Pod (kind: Pod). Do not create Deployments unless the user asked.
        
        OUTPUT FORMAT (exact markers, nothing else outside them):
        ===CODE===
        <complete launch-file source — proper syntax for the pod language>
        ===YAML===
        <complete Kubernetes Pod YAML for THIS pod>
        ===END===
        """
        
        if template != .custom {
            system += "\n\nTemplate style guidance (still obey language rules):\n\(template.systemPrompt)\n"
        }
        
        guard let pod = pod else {
            system += "\nNo pod selected — still return ===CODE=== and ===YAML=== placeholders.\n"
            return system
        }
        
        system += "\n\n" + Self.syntaxContract(for: pod)
        system += "\n" + Self.podIdentityBlock(pod)
        system += "\n" + frameworkGuidance(for: pod)
        system += "\n" + Self.languageIdioms(for: pod.framework)
        
        // Canonical skeleton so the model mirrors real syntax
        let skeleton = pod.framework.getTemplate(name: pod.name)
        if !skeleton.isEmpty {
            system += "\nREFERENCE SKELETON (match this language/style; replace body to fulfill the user request):\n"
            system += skeleton.prefix(1200) + "\n"
        }
        
        return system
    }
    
    private func buildDualArtifactUserPrompt(prompt: String, pod: Pod?, template: PromptTemplate) -> String {
        var user = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if template != .custom, !template.userPromptPrefix.isEmpty {
            user = template.userPromptPrefix + user
        }
        
        guard let pod = pod else {
            return """
            User request: \(user)
            
            Return ===CODE=== and ===YAML=== only. CODE must be real source, not prose.
            """
        }
        
        let lang = Self.languageName(for: pod.framework)
        let ext = Self.fileExtension(for: pod.framework)
        let launch = pod.framework.launchFile
        
        var ctx = """
        
        ═══════════════════════════════════════
        SELECTED POD CONTEXT (authoritative)
        ═══════════════════════════════════════
        \(Self.podIdentityBlock(pod))
        
        SYNTAX CONTRACT:
        - Language: \(lang)
        - Launch file: \(launch) (extension .\(ext))
        - Every line in ===CODE=== must be valid \(lang) for that file path
        - Fulfill the user request WHILE remaining in this language and pod context
        
        USER REQUEST:
        \(user)
        
        """
        
        // Full file tree + contents for this pod only
        ctx += Self.podFilesContext(pod)
        
        if !pod.kubernetesYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let yamlPreview = String(pod.kubernetesYAML.prefix(2000))
            ctx += "\nEXISTING KUBERNETES YAML (improve/replace; keep kind: Pod for this pod):\n\(yamlPreview)\n"
        }
        
        if !pod.connections.isEmpty {
            ctx += "\nCONNECTED PODS (context only — do NOT generate code for them):\n"
            // names resolved later in LLM context; list ids here as fallback
            for id in pod.connections {
                ctx += "- connected pod id: \(id.uuidString)\n"
            }
        }
        
        if !pod.pythonRequirements.isEmpty, [.django, .flask, .fastapi, .purepy].contains(pod.framework) {
            ctx += "\nPython requirements.txt:\n\(pod.pythonRequirements)\n"
        }
        
        ctx += """
        
        TASK:
        1) Write complete, syntactically correct \(lang) source for \(launch) implementing the user request for pod "\(pod.name)".
        2) Write Kubernetes Pod YAML that runs that code for this pod only (image/command matching \(pod.framework.rawValue)).
        3) Respond with ===CODE=== / ===YAML=== / ===END=== only — no commentary.
        """
        
        return ctx
    }
    
    // MARK: - Pod / language context builders
    
    private static func podIdentityBlock(_ pod: Pod) -> String {
        let image = KubernetesManifestService.containerImage(for: pod.framework)
        let (cmd, args) = KubernetesManifestService.containerCommand(for: pod)
        let k8sName = KubernetesManifestService.sanitizeK8sName(pod.name, id: pod.id)
        let lang = languageName(for: pod.framework)
        
        var s = """
        - Pod id: \(pod.id.uuidString)
        - Pod name: \(pod.name)
        - Pod type: \(pod.type.rawValue)
        - Framework: \(pod.framework.rawValue)
        - Language: \(lang)
        - Launch file: \(pod.framework.launchFile)
        - K8s pod name: \(k8sName)
        - Container image: \(image)
        """
        if let cmd {
            s += "\n- Container command: \(cmd) \(args.joined(separator: " "))"
        }
        if let path = pod.projectPath {
            s += "\n- Project path: \(path)"
        }
        s += "\n- Type → framework assumption: \(pod.type.frameworkHint)"
        return s
    }
    
    private static func podFilesContext(_ pod: Pod) -> String {
        var s = "\nPOD FILE TREE (\(pod.files.count) file(s)) — edit/replace launch file; stay consistent:\n"
        if pod.files.isEmpty {
            s += "  (no files yet — create launch file \(pod.framework.launchFile))\n"
            if !pod.code.isEmpty {
                s += "\nEXISTING MAIN CODE (pod.code):\n\(String(pod.code.prefix(4000)))\n"
            }
            return s
        }
        
        for file in pod.files.prefix(20) {
            let selected = file.id == pod.selectedFileId ? " [selected]" : ""
            let isLaunch = file.path == pod.framework.launchFile ? " [LAUNCH]" : ""
            s += "  • \(file.path) (\(file.language.rawValue))\(isLaunch)\(selected) — \(file.content.count) bytes\n"
        }
        if pod.files.count > 20 {
            s += "  … +\(pod.files.count - 20) more files\n"
        }
        
        // Include launch + selected file bodies for real context
        let launchPath = pod.framework.launchFile
        if let launch = pod.files.first(where: { $0.path == launchPath }) ?? pod.files.first {
            s += "\nLAUNCH FILE CONTENT (\(launch.path)) — base your CODE on this context:\n"
            s += String(launch.content.prefix(5000))
            s += "\n"
        } else if !pod.code.isEmpty {
            s += "\nEXISTING MAIN CODE:\n\(String(pod.code.prefix(5000)))\n"
        }
        
        if let selected = pod.selectedFile, selected.path != launchPath {
            s += "\nALSO SELECTED FILE (\(selected.path)) for additional context:\n"
            s += String(selected.content.prefix(2500))
            s += "\n"
        }
        
        return s
    }
    
    private static func syntaxContract(for pod: Pod) -> String {
        let lang = languageName(for: pod.framework)
        let ext = fileExtension(for: pod.framework)
        return """
        SYNTAX CONTRACT FOR THIS POD:
        - Target language: \(lang)
        - File path: \(pod.framework.launchFile)
        - Expected extension: .\(ext)
        - CODE section must compile/run as \(lang) (proper keywords, braces/indentation, imports, entrypoint).
        - Forbidden in CODE: markdown, ``` fences, English explanations, other languages, incomplete stubs with “...”.
        - Use real identifiers (no foo/bar placeholders unless requested).
        - Keep package/module names consistent with existing files when present.
        """
    }
    
    private static func languageName(for framework: Framework) -> String {
        switch framework {
        case .purepy, .django, .flask, .fastapi: return "Python 3"
        case .nodejs, .express: return "JavaScript (Node.js)"
        case .react, .reactNative: return "JavaScript (React/JSX)"
        case .vue: return "JavaScript (Vue SFC or JS)"
        case .angular, .nestjs, .nextjs: return "TypeScript/JavaScript"
        case .swift, .swiftui: return "Swift"
        case .objectiveC: return "Objective-C"
        case .kotlin, .jetpackCompose: return "Kotlin"
        case .androidJava, .java, .spring: return "Java"
        case .go: return "Go"
        case .rust: return "Rust"
        case .flutter: return "Dart (Flutter)"
        case .docker: return "Dockerfile"
        case .kubernetes: return "YAML (Kubernetes)"
        case .terraform: return "HCL (Terraform)"
        case .postgresql, .mysql, .sqlite: return "SQL"
        case .mongodb: return "MongoDB shell (JavaScript)"
        case .redis: return "Redis CLI commands"
        case .vault: return "Markdown / vault layout docs"
        case .minio, .s3, .nfs, .seaweedfs: return "dotenv / storage config"
        case .localVolume: return "YAML (Kubernetes PVC)"
        case .environment: return "dotenv / environment keys"
        }
    }
    
    private static func fileExtension(for framework: Framework) -> String {
        let path = framework.launchFile
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty { return ext }
        return framework.primaryLanguage.fileExtension
    }
    
    private static func languageIdioms(for framework: Framework) -> String {
        switch framework {
        case .purepy:
            return "IDIOMS: PEP 8, `def main():` + `if __name__ == \"__main__\":`, type hints OK, no JS/Swift.\n"
        case .django:
            return "IDIOMS: Django views/urls/models style, valid Python only.\n"
        case .flask:
            return "IDIOMS: Flask app + routes, `if __name__ == \"__main__\"`, valid Python only.\n"
        case .fastapi:
            return "IDIOMS: FastAPI app, path operations, Pydantic models, valid Python only.\n"
        case .nodejs, .express:
            return "IDIOMS: CommonJS or ESM consistently; valid JS; no Python indentation blocks.\n"
        case .react, .reactNative:
            return "IDIOMS: React function components, JSX well-formed, export default.\n"
        case .vue:
            return "IDIOMS: Vue SFC or createApp entry; valid JS/HTML sections.\n"
        case .angular, .nestjs, .nextjs:
            return "IDIOMS: TS/JS modules, decorators where Nest/Angular, valid syntax.\n"
        case .swiftui:
            return "IDIOMS: `import SwiftUI`, `App` + `View`, `@main`, valid Swift.\n"
        case .swift:
            return "IDIOMS: `import Foundation` (or SwiftUI if needed), valid Swift statements.\n"
        case .objectiveC:
            return "IDIOMS: `#import`, `@autoreleasepool`, `int main(...)`, Objective-C message syntax.\n"
        case .kotlin, .jetpackCompose:
            return "IDIOMS: `package`, Android Activity/Composable, valid Kotlin.\n"
        case .androidJava, .java:
            return "IDIOMS: `package`/`public class`, methods with braces, valid Java.\n"
        case .spring:
            return "IDIOMS: Spring Boot `@SpringBootApplication`, valid Java.\n"
        case .go:
            return "IDIOMS: `package main`, `func main()`, valid Go.\n"
        case .rust:
            return "IDIOMS: `fn main() { }`, valid Rust.\n"
        case .flutter:
            return "IDIOMS: `void main()`, `runApp`, valid Dart.\n"
        case .docker:
            return "IDIOMS: Dockerfile instructions FROM/WORKDIR/COPY/CMD.\n"
        case .kubernetes:
            return "IDIOMS: valid Kubernetes YAML with apiVersion/kind/metadata/spec.\n"
        case .terraform:
            return "IDIOMS: valid HCL resource/provider blocks.\n"
        case .postgresql:
            return "IDIOMS: PostgreSQL SQL — CREATE TABLE, indexes, valid SQL only.\n"
        case .mysql:
            return "IDIOMS: MySQL SQL dialect — valid SQL only.\n"
        case .sqlite:
            return "IDIOMS: SQLite SQL — valid SQL only.\n"
        case .mongodb:
            return "IDIOMS: mongosh JS — db.collection.insertOne/find, valid JS.\n"
        case .redis:
            return "IDIOMS: redis-cli commands SET/GET/SADD, one command per line.\n"
        case .vault:
            return "IDIOMS: document vault layout under data/buckets, mount path /vault, index.json optional.\n"
        case .minio:
            return "IDIOMS: MinIO env MINIO_ROOT_USER/PASSWORD, S3_ENDPOINT for clients, KEY=value only.\n"
        case .s3:
            return "IDIOMS: AWS/S3 env keys AWS_REGION, S3_BUCKET, optional S3_ENDPOINT for compat APIs.\n"
        case .localVolume:
            return "IDIOMS: Kubernetes PVC YAML apiVersion/kind PersistentVolumeClaim, storage size/class.\n"
        case .nfs:
            return "IDIOMS: NFS_SERVER, NFS_PATH, mount options as KEY=value.\n"
        case .seaweedfs:
            return "IDIOMS: SeaweedFS master/volume/filer/S3 ports as KEY=value.\n"
        case .environment:
            return "IDIOMS: KEY=value lines, comments with #, group by Public/Private/Developer scopes.\n"
        }
    }
    
    private func frameworkGuidance(for pod: Pod) -> String {
        var s = "POD TYPE GUIDANCE:\n"
        s += pod.type.frameworkHint + "\n"
        s += "Use framework \(pod.framework.rawValue) only — do not switch stacks.\n"
        return s
    }
    
    // MARK: - Normalize model output to proper syntax context
    
    static func normalizeGeneratedCode(_ raw: String, for pod: Pod) -> String {
        var code = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Drop leading prose lines before the first code-looking line
        code = stripLeadingProse(code, framework: pod.framework)
        
        // Reject obvious wrong-language dumps for common cases
        if looksLikeWrongLanguage(code, framework: pod.framework) {
            // Prefer existing pod code over wrong-language output
            if let existing = pod.files.first(where: { $0.path == pod.framework.launchFile })?.content,
               !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return existing
            }
            if !pod.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return pod.code
            }
            return pod.framework.getTemplate(name: pod.name)
        }
        
        return code
    }
    
    static func normalizeGeneratedYAML(_ raw: String, for pod: Pod) -> String {
        var yaml = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        yaml = stripLeadingProse(yaml, framework: .kubernetes)
        if !yaml.contains("apiVersion") || !yaml.lowercased().contains("kind:") {
            return KubernetesManifestService.generateYAML(for: pod, projectPath: pod.projectPath)
        }
        return yaml
    }
    
    private static func stripLeadingProse(_ text: String, framework: Framework) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let firstCode = lines.firstIndex(where: { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            // prose-ish
            if t.hasPrefix("Here ") || t.hasPrefix("Sure") || t.hasPrefix("I'll ") || t.hasPrefix("I will") {
                return false
            }
            return looksLikeCodeLine(t, framework: framework)
        }) else {
            return text
        }
        return lines[firstCode...].joined(separator: "\n")
    }
    
    private static func looksLikeCodeLine(_ line: String, framework: Framework) -> Bool {
        switch framework {
        case .purepy, .django, .flask, .fastapi:
            return line.hasPrefix("#") || line.hasPrefix("import ") || line.hasPrefix("from ") || line.hasPrefix("def ") || line.hasPrefix("class ") || line.hasPrefix("@")
        case .swift, .swiftui:
            return line.hasPrefix("import ") || line.hasPrefix("struct ") || line.hasPrefix("class ") || line.hasPrefix("enum ") || line.hasPrefix("@") || line.hasPrefix("func ")
        case .objectiveC:
            return line.hasPrefix("#import") || line.hasPrefix("@") || line.hasPrefix("int main")
        case .nodejs, .express, .react, .vue, .angular, .nextjs, .nestjs, .reactNative:
            return line.hasPrefix("import ") || line.hasPrefix("const ") || line.hasPrefix("let ") || line.hasPrefix("var ") || line.hasPrefix("function ") || line.hasPrefix("export ") || line.hasPrefix("module.exports") || line.hasPrefix("/*") || line.hasPrefix("//") || line.hasPrefix("<")
        case .go:
            return line.hasPrefix("package ") || line.hasPrefix("import ") || line.hasPrefix("func ")
        case .rust:
            return line.hasPrefix("fn ") || line.hasPrefix("use ") || line.hasPrefix("mod ") || line.hasPrefix("pub ")
        case .java, .spring, .androidJava:
            return line.hasPrefix("package ") || line.hasPrefix("import ") || line.hasPrefix("public ") || line.hasPrefix("class ")
        case .kotlin, .jetpackCompose:
            return line.hasPrefix("package ") || line.hasPrefix("import ") || line.hasPrefix("class ") || line.hasPrefix("fun ") || line.hasPrefix("@")
        case .flutter:
            return line.hasPrefix("import ") || line.hasPrefix("void ") || line.hasPrefix("class ")
        case .docker:
            return line.uppercased().hasPrefix("FROM ") || line.uppercased().hasPrefix("RUN ") || line.uppercased().hasPrefix("CMD ")
        case .kubernetes, .terraform:
            return line.hasPrefix("apiVersion") || line.hasPrefix("kind:") || line.hasPrefix("resource ") || line.hasPrefix("terraform ") || line.hasPrefix("metadata:")
        case .postgresql, .mysql, .sqlite:
            let u = line.uppercased()
            return u.hasPrefix("--") || u.hasPrefix("CREATE ") || u.hasPrefix("INSERT ") || u.hasPrefix("ALTER ") || u.hasPrefix("SELECT ")
        case .mongodb:
            return line.hasPrefix("//") || line.hasPrefix("db") || line.hasPrefix("print")
        case .redis:
            let u = line.uppercased()
            return u.hasPrefix("#") || u.hasPrefix("SET ") || u.hasPrefix("GET ") || u.hasPrefix("SADD ")
        case .vault, .localVolume:
            return line.hasPrefix("#") || line.hasPrefix("apiVersion") || line.hasPrefix("kind:") || line.hasPrefix("-") || line.hasPrefix("```") || line.contains("/")
        case .minio, .s3, .nfs, .seaweedfs:
            return line.hasPrefix("#") || line.contains("=")
        case .environment:
            return line.hasPrefix("#") || line.contains("=")
        }
    }
    
    private static func looksLikeWrongLanguage(_ code: String, framework: Framework) -> Bool {
        let sample = String(code.prefix(800)).lowercased()
        guard sample.count > 40 else { return false }
        
        let hasPython = sample.contains("def ") || sample.contains("if __name__") || sample.contains("import os")
        let hasSwift = sample.contains("import swiftui") || sample.contains("struct ") && sample.contains(": view")
        let hasJS = sample.contains("console.log") || sample.contains("module.exports") || sample.contains("require(")
        let hasGo = sample.contains("package main") && sample.contains("func main")
        
        switch framework {
        case .purepy, .django, .flask, .fastapi:
            // Wrong if clearly Swift/JS without python markers
            if (hasSwift || (hasJS && !hasPython)) && !hasPython { return true }
        case .swift, .swiftui:
            if hasPython && !hasSwift && !sample.contains("import ") { return true }
            if sample.contains("def ") && !sample.contains("func ") { return true }
        case .nodejs, .express, .react, .vue, .angular, .nextjs, .nestjs, .reactNative:
            if hasPython && !hasJS { return true }
        case .go:
            if hasPython && !hasGo { return true }
        default:
            break
        }
        return false
    }
    
    // MARK: - Parse dual response
    
    static func parseDualArtifactResponse(_ raw: String, pod: Pod?) -> PodGenerationResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Preferred: ===CODE=== / ===YAML=== markers
        if let parsed = parseMarkedSections(text) {
            return PodGenerationResult(
                code: stripFences(parsed.code),
                yaml: stripFences(parsed.yaml),
                rawResponse: raw
            )
        }
        
        // Fallback: fenced blocks — prefer language-tagged yaml vs code
        let fences = extractFencedBlocks(text)
        var code = ""
        var yaml = ""
        
        for block in fences {
            let lang = block.language.lowercased()
            if yaml.isEmpty && (lang.contains("yaml") || lang.contains("yml") || block.content.contains("kind: Pod") || block.content.contains("apiVersion:")) {
                yaml = block.content
            } else if code.isEmpty {
                code = block.content
            } else if yaml.isEmpty {
                // second block as yaml if first was code
                yaml = block.content
            }
        }
        
        if code.isEmpty && yaml.isEmpty {
            // Entire response as code; synthesize yaml from pod
            code = stripFences(text)
            if let pod {
                yaml = KubernetesManifestService.generateYAML(for: pod, projectPath: pod.projectPath)
            }
        } else if code.isEmpty, let pod {
            code = pod.code
        } else if yaml.isEmpty, let pod {
            yaml = KubernetesManifestService.generateYAML(for: pod, projectPath: pod.projectPath)
        }
        
        return PodGenerationResult(code: code, yaml: yaml, rawResponse: raw)
    }
    
    private static func parseMarkedSections(_ text: String) -> (code: String, yaml: String)? {
        guard let codeRange = text.range(of: "===CODE===", options: .caseInsensitive),
              let yamlRange = text.range(of: "===YAML===", options: .caseInsensitive) else {
            return nil
        }
        
        let endRange = text.range(of: "===END===", options: .caseInsensitive)
        
        let codeStart = codeRange.upperBound
        let codeEnd = yamlRange.lowerBound
        guard codeStart < codeEnd else { return nil }
        
        var code = String(text[codeStart..<codeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let yamlStart = yamlRange.upperBound
        let yamlEnd = endRange?.lowerBound ?? text.endIndex
        guard yamlStart <= yamlEnd else { return nil }
        var yaml = String(text[yamlStart..<yamlEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If markers were reversed (YAML first)
        if codeRange.lowerBound > yamlRange.lowerBound {
            swap(&code, &yaml)
        }
        
        return (code, yaml)
    }
    
    private struct FencedBlock {
        let language: String
        let content: String
    }
    
    private static func extractFencedBlocks(_ text: String) -> [FencedBlock] {
        var blocks: [FencedBlock] = []
        var search = text.startIndex
        while let open = text.range(of: "```", range: search..<text.endIndex) {
            let afterOpen = open.upperBound
            guard let close = text.range(of: "```", range: afterOpen..<text.endIndex) else { break }
            let headerAndBody = String(text[afterOpen..<close.lowerBound])
            var language = ""
            var content = headerAndBody
            if let nl = headerAndBody.firstIndex(of: "\n") {
                language = String(headerAndBody[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                content = String(headerAndBody[headerAndBody.index(after: nl)...])
            }
            blocks.append(FencedBlock(
                language: language,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            search = close.upperBound
        }
        return blocks
    }
    
    private static func stripFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNL = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNL)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
    
    private func generateStubDualArtifact(prompt: String, framework: Framework, podContext: Pod?) -> PodGenerationResult {
        let code = generateStubCode(prompt: prompt, framework: framework, podContext: podContext)
        let yaml: String
        if let pod = podContext {
            yaml = KubernetesManifestService.generateYAML(for: pod, projectPath: pod.projectPath)
        } else {
            yaml = """
            apiVersion: v1
            kind: Pod
            metadata:
              name: pioneer-generated
            spec:
              restartPolicy: Never
              containers:
                - name: main
                  image: \(KubernetesManifestService.containerImage(for: framework))
                  workingDir: /app
            """
        }
        let raw = "===CODE===\n\(code)\n===YAML===\n\(yaml)\n===END==="
        return PodGenerationResult(code: code, yaml: yaml, rawResponse: raw)
    }
    
    private func generateStubCode(prompt: String, framework: Framework, podContext: Pod?) -> String {
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
            
        case .objectiveC:
            return """
            // Generated code for: \(prompt)
            #import <Foundation/Foundation.h>
            int main(int argc, const char * argv[]) {
                @autoreleasepool { NSLog(@"Generated from: \(prompt)"); }
                return 0;
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
            
        case .nodejs, .express, .nestjs, .angular, .react, .vue, .nextjs, .reactNative:
            return """
            // Generated code for: \(prompt)
            console.log('Generated from: \(prompt)');
            """
            
        case .kotlin, .jetpackCompose:
            return """
            // Generated code for: \(prompt)
            package com.example.app
            fun main() { println("Generated from: \(prompt)") }
            """
            
        case .androidJava:
            return """
            // Generated code for: \(prompt)
            package com.example.app;
            public class MainActivity {
                public static void main(String[] args) {
                    System.out.println("Generated from: \(prompt)");
                }
            }
            """
            
        case .flutter:
            return """
            // Generated code for: \(prompt)
            void main() {
              print('Generated from: \(prompt)');
            }
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
            
        case .postgresql, .mysql, .sqlite:
            return """
            -- Generated schema for: \(prompt)
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            );
            """
            
        case .mongodb:
            return """
            // Generated seed for: \(prompt)
            db = db.getSiblingDB('app');
            db.items.insertOne({ name: "\(prompt)", createdAt: new Date() });
            """
            
        case .redis:
            return """
            # Generated redis for: \(prompt)
            SET app:note "\(prompt)"
            """
            
        case .environment:
            return """
            # Inference env for: \(prompt)
            API_BASE_URL=http://localhost:8000
            DEBUG=true
            """
            
        case .vault:
            return """
            # Vault layout for: \(prompt)
            # Root: /vault  ·  buckets: public, private, uploads

            data/
              buckets/
                public/
                private/
                uploads/
              index.json
            """
            
        case .minio:
            return """
            # MinIO for: \(prompt)
            MINIO_ROOT_USER=minioadmin
            MINIO_ROOT_PASSWORD=minioadmin
            MINIO_VOLUMES=/data
            S3_ENDPOINT=http://minio:9000
            S3_BUCKET=app
            """
            
        case .s3:
            return """
            # S3 for: \(prompt)
            AWS_REGION=us-east-1
            AWS_ACCESS_KEY_ID=
            AWS_SECRET_ACCESS_KEY=
            S3_BUCKET=app
            S3_PREFIX=uploads/
            """
            
        case .localVolume:
            return """
            apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: vault-data
            spec:
              accessModes: [ReadWriteOnce]
              resources:
                requests:
                  storage: 10Gi
            """
            
        case .nfs:
            return """
            # NFS for: \(prompt)
            NFS_SERVER=nfs.local
            NFS_PATH=/exports/app
            VAULT_MOUNT_PATH=/vault
            """
            
        case .seaweedfs:
            return """
            # SeaweedFS for: \(prompt)
            SEAWEED_MASTER=:9333
            SEAWEED_VOLUME=:8080
            SEAWEED_FILER=:8888
            SEAWEED_S3=:8333
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


