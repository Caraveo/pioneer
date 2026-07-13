import Foundation

/// Generates and runs a dedicated Kubernetes Pod manifest for each Pioneer pod.
enum KubernetesManifestService {
    
    // MARK: - Public API
    
    /// Build a ready-to-edit Kubernetes Pod YAML for this Pioneer pod.
    static func generateYAML(
        id: UUID,
        name: String,
        framework: Framework,
        projectPath: String? = nil
    ) -> String {
        let k8sName = sanitizeK8sName(name, id: id)
        let image = containerImage(for: framework)
        let (command, args) = containerCommand(framework: framework, launchFile: framework.launchFile)
        let workDir = "/app"
        let hostPath = projectPath ?? "/tmp/pioneer-\(id.uuidString)"
        let envLines = environmentYAML(for: framework)
        
        var lines: [String] = []
        lines.append("# Pioneer Kubernetes Pod")
        lines.append("# Each Pioneer pod is its own K8s Pod.")
        lines.append("# NOTE: Pioneer Run injects CODE via kubectl cp (kind cannot use Mac hostPath).")
        lines.append("# hostPath below is documentary; runtime uses emptyDir + file injection.")
        lines.append("apiVersion: v1")
        lines.append("kind: Pod")
        lines.append("metadata:")
        lines.append("  name: \(k8sName)")
        lines.append("  labels:")
        lines.append("    app: pioneer")
        lines.append("    pioneer-pod: \"\(id.uuidString)\"")
        lines.append("    framework: \"\(framework.rawValue.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: ""))\"")
        lines.append("  annotations:")
        lines.append("    pioneer.io/name: \"\(escapeYAMLString(name))\"")
        lines.append("    pioneer.io/framework: \"\(escapeYAMLString(framework.rawValue))\"")
        lines.append("spec:")
        lines.append("  restartPolicy: Never")
        lines.append("  containers:")
        lines.append("    - name: main")
        lines.append("      image: \(image)")
        lines.append("      imagePullPolicy: IfNotPresent")
        lines.append("      workingDir: \(workDir)")
        if let command {
            let cmdList = ([command] + args).map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("      command: [\(cmdList)]")
        }
        lines.append("      volumeMounts:")
        lines.append("        - name: code")
        lines.append("          mountPath: \(workDir)")
        if !envLines.isEmpty {
            lines.append(contentsOf: envLines)
        }
        lines.append("      resources:")
        lines.append("        requests:")
        lines.append("          cpu: \"100m\"")
        lines.append("          memory: \"128Mi\"")
        lines.append("        limits:")
        lines.append("          cpu: \"1\"")
        lines.append("          memory: \"512Mi\"")
        lines.append("  volumes:")
        lines.append("    - name: code")
        lines.append("      hostPath:")
        lines.append("        path: \(hostPath)")
        lines.append("        type: DirectoryOrCreate")
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    static func generateYAML(for pod: Pod, projectPath: String? = nil) -> String {
        generateYAML(
            id: pod.id,
            name: pod.name,
            framework: pod.framework,
            projectPath: projectPath ?? pod.projectPath
        )
    }
    
    /// Relative path for the pod YAML inside the project directory.
    static let relativeYAMLPath = "k8s/pod.yaml"
    
    /// Write YAML to disk under the pod project path.
    @discardableResult
    static func writeYAML(_ yaml: String, to projectPath: URL) throws -> URL {
        let dir = projectPath.appendingPathComponent("k8s", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("pod.yaml")
        try yaml.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
    
    /// Sync pod CODE to disk, write YAML, then run with correct file context.
    /// - kind/minikube cannot see Mac hostPath, so we inject files via `kubectl cp` + `exec`.
    /// - Docker uses a real bind mount of the project directory.
    static func run(pod: Pod, yaml: String, projectPath: URL) async -> String {
        var log = ""
        
        // 1) Materialize CODE + launch file on disk (file context for the container)
        let sync = syncWorkspaceToDisk(pod: pod, projectPath: projectPath)
        log += sync.log
        if !sync.ok {
            return log + "❌ Cannot run: project files are missing on disk.\n"
        }
        
        // 2) Persist YAML (for editing / kubectl apply of the *user* manifest)
        do {
            let yamlURL = try writeYAML(yaml.isEmpty ? generateYAML(for: pod, projectPath: projectPath.path) : yaml, to: projectPath)
            log += "📄 Wrote \(yamlURL.path)\n"
        } catch {
            log += "⚠️ Could not write YAML: \(error.localizedDescription)\n"
        }
        
        let hasKubectl = await isCommandAvailable("kubectl")
        let hasDocker = await isCommandAvailable("docker")
        
        // 3) Prefer kubectl with file injection (correct for kind + Colima)
        if hasKubectl {
            log += await runWithKubectlInjectingFiles(pod: pod, projectPath: projectPath)
            return log
        }
        
        if hasDocker {
            log += "ℹ️ kubectl not found — running with Docker bind-mount\n"
            log += await runWithDocker(pod: pod, projectPath: projectPath)
            return log
        }
        
        log += """
        ❌ Neither kubectl nor docker is available.
        
        YAML saved at:
          \(projectPath.appendingPathComponent(relativeYAMLPath).path)
        
        """
        return log
    }
    
    /// Write every ProjectFile (and ensure launch file exists) under projectPath.
    static func syncWorkspaceToDisk(pod: Pod, projectPath: URL) -> (ok: Bool, log: String, launchRelative: String) {
        var log = ""
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: projectPath, withIntermediateDirectories: true)
        } catch {
            return (false, "⚠️ Could not create project dir: \(error.localizedDescription)\n", pod.framework.launchFile)
        }
        
        var files = pod.files
        // Ensure launch file is present in the in-memory file set
        let launchRel = pod.framework.launchFile
        if !files.contains(where: { $0.path == launchRel }) {
            let content = pod.code.isEmpty ? pod.framework.getTemplate(name: pod.name) : pod.code
            files.append(ProjectFile(
                path: launchRel,
                name: (launchRel as NSString).lastPathComponent,
                content: content,
                language: pod.framework.primaryLanguage
            ))
            log += "📝 Created missing launch file entry: \(launchRel)\n"
        }
        
        // If main file content is empty but pod.code is set, prefer pod.code
        if let idx = files.firstIndex(where: { $0.path == launchRel }),
           files[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !pod.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            files[idx].content = pod.code
        }
        
        var written: [String] = []
        for file in files {
            let fileURL = projectPath.appendingPathComponent(file.path)
            do {
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                written.append(file.path)
            } catch {
                log += "⚠️ Failed to write \(file.path): \(error.localizedDescription)\n"
            }
        }
        
        // Write YAML copy for completeness
        if !pod.kubernetesYAML.isEmpty {
            _ = try? writeYAML(pod.kubernetesYAML, to: projectPath)
        }
        
        let launchURL = projectPath.appendingPathComponent(launchRel)
        let launchExists = fm.fileExists(atPath: launchURL.path)
        
        log += "📦 Synced \(written.count) file(s) → \(projectPath.path)\n"
        for path in written.prefix(12) {
            log += "   • \(path)\n"
        }
        if written.count > 12 {
            log += "   • … +\(written.count - 12) more\n"
        }
        
        if !launchExists {
            log += "❌ Launch file missing after sync: \(launchRel)\n"
            return (false, log, launchRel)
        }
        
        // Show a short preview so the user can see content is real
        if let preview = try? String(contentsOf: launchURL, encoding: .utf8) {
            let first = preview.split(separator: "\n", omittingEmptySubsequences: false).prefix(3).joined(separator: "\n")
            log += "🔎 Launch file \(launchRel) ready (\(preview.count) bytes)\n"
            if !first.isEmpty {
                log += "   preview: \(first.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
            }
        }
        
        return (true, log, launchRel)
    }
    
    // MARK: - Images & commands
    
    static func containerImage(for framework: Framework) -> String {
        switch framework {
        case .purepy, .django, .flask, .fastapi:
            return "python:3.12-slim"
        case .nodejs, .express, .nestjs, .react, .vue, .angular, .nextjs, .reactNative:
            return "node:20-alpine"
        case .go:
            return "golang:1.22-alpine"
        case .rust:
            return "rust:1.78-slim"
        case .java, .spring, .androidJava, .kotlin, .jetpackCompose:
            return "eclipse-temurin:17-jdk"
        case .swift, .swiftui, .objectiveC:
            return "swift:5.10"
        case .flutter:
            return "ghcr.io/cirruslabs/flutter:stable"
        case .docker:
            return "docker:27-cli"
        case .kubernetes:
            return "bitnami/kubectl:latest"
        case .terraform:
            return "hashicorp/terraform:1.8"
        case .postgresql:
            return "postgres:16-alpine"
        case .mysql:
            return "mysql:8.4"
        case .mongodb:
            return "mongo:7"
        case .redis:
            return "redis:7-alpine"
        case .sqlite:
            return "keinos/sqlite3:latest"
        }
    }
    
    /// Returns (executable, args) for the container entrypoint.
    static func containerCommand(framework: Framework, launchFile: String) -> (String?, [String]) {
        let launch = launchFile
        switch framework {
        case .purepy:
            return ("python3", [launch])
        case .django:
            return ("python3", ["manage.py", "runserver", "0.0.0.0:8000"])
        case .flask:
            return ("python3", [launch])
        case .fastapi:
            return ("sh", ["-c", "pip install -q fastapi uvicorn && uvicorn main:app --host 0.0.0.0 --port 8000"])
        case .nodejs, .express:
            return ("node", [launch])
        case .nestjs, .angular, .react, .vue, .nextjs, .reactNative:
            return ("npm", ["start"])
        case .go:
            return ("go", ["run", launch])
        case .rust:
            return ("cargo", ["run"])
        case .java, .spring:
            return ("bash", ["-lc", "mvn -q exec:java || java \(launch)"])
        case .swift, .swiftui:
            return ("swift", [launch])
        case .objectiveC:
            return ("bash", ["-lc", "clang -fobjc-arc \(launch) -framework Foundation -o /tmp/app && /tmp/app"])
        case .kotlin, .jetpackCompose:
            return ("bash", ["-lc", "echo 'Android/Kotlin sources at \(launch) — build with Android SDK / Gradle on host or CI'"])
        case .androidJava:
            return ("bash", ["-lc", "echo 'Android Java sources at \(launch) — build with Android SDK / Gradle on host or CI'"])
        case .flutter:
            return ("bash", ["-lc", "flutter --version && echo 'Flutter app at \(launch)'"])
        case .docker:
            return ("docker", ["build", "-t", "pioneer-app", "."])
        case .kubernetes:
            return ("kubectl", ["apply", "-f", launch])
        case .terraform:
            return ("terraform", ["apply", "-auto-approve"])
        case .postgresql:
            // Official image runs postgres; init scripts live under sql/
            return (nil, [])
        case .mysql:
            return (nil, [])
        case .mongodb:
            return (nil, [])
        case .redis:
            return ("redis-server", [])
        case .sqlite:
            return ("sh", ["-c", "sqlite3 /data/app.db < \(launch) && sqlite3 /data/app.db '.tables'"])
        }
    }
    
    static func containerCommand(for pod: Pod) -> (String?, [String]) {
        containerCommand(framework: pod.framework, launchFile: pod.framework.launchFile)
    }
    
    // MARK: - kubectl / docker runners
    
    /// kind/minikube hostPath cannot see Mac paths. Start a hold pod, copy CODE in, exec the real command.
    private static func runWithKubectlInjectingFiles(pod: Pod, projectPath: URL) async -> String {
        let name = sanitizeK8sName(pod.name, id: pod.id)
        let image = containerImage(for: pod.framework)
        let (cmd, args) = containerCommand(for: pod)
        let launch = pod.framework.launchFile
        var out = "☸️  Running as Kubernetes Pod: \(name) (with file injection)\n"
        out += "   image: \(image)\n"
        out += "   source: \(projectPath.path) → /app\n"
        
        // Runtime pod: emptyDir at /app + sleep so we can kubectl cp then exec
        let runtimeYAML = """
        apiVersion: v1
        kind: Pod
        metadata:
          name: \(name)
          labels:
            app: pioneer
            pioneer-pod: "\(pod.id.uuidString)"
            pioneer.io/runner: "inject"
        spec:
          restartPolicy: Never
          containers:
            - name: main
              image: \(image)
              imagePullPolicy: IfNotPresent
              workingDir: /app
              command: ["sleep", "3600"]
              volumeMounts:
                - name: code
                  mountPath: /app
          volumes:
            - name: code
              emptyDir: {}
        """
        
        let runtimeFile = projectPath.appendingPathComponent("k8s/pod-run.yaml")
        do {
            try FileManager.default.createDirectory(at: runtimeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try runtimeYAML.write(to: runtimeFile, atomically: true, encoding: .utf8)
        } catch {
            return out + "❌ Could not write runtime YAML: \(error.localizedDescription)\n"
        }
        
        _ = await shell("kubectl delete pod \(shellQuote(name)) --ignore-not-found=true --wait=true 2>/dev/null; true")
        
        let apply = await shell("kubectl apply -f \(shellQuote(runtimeFile.path))")
        out += apply
        if apply.lowercased().contains("error") {
            // Fall back to Docker bind-mount if cluster apply fails
            if await isCommandAvailable("docker") {
                out += "⚠️ kubectl apply failed — falling back to Docker\n"
                out += await runWithDocker(pod: pod, projectPath: projectPath)
            }
            return out
        }
        
        out += "⏳ Waiting for pod to be Ready...\n"
        let wait = await shell("kubectl wait --for=condition=Ready pod/\(shellQuote(name)) --timeout=120s 2>&1")
        out += wait
        if wait.lowercased().contains("error") || wait.lowercased().contains("timed out") {
            let describe = await shell("kubectl describe pod \(shellQuote(name)) 2>&1 | tail -40")
            out += describe
            if await isCommandAvailable("docker") {
                out += "⚠️ Pod not Ready — falling back to Docker with bind-mount\n"
                _ = await shell("kubectl delete pod \(shellQuote(name)) --ignore-not-found=true --wait=false 2>/dev/null; true")
                out += await runWithDocker(pod: pod, projectPath: projectPath)
            }
            return out
        }
        
        // Copy project files into /app (trailing /. copies contents)
        out += "📤 Injecting project files into pod:/app ...\n"
        let cp = await shell("kubectl cp \(shellQuote(projectPath.path + "/.")) \(shellQuote(name + ":/app/")) 2>&1")
        if !cp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += cp
        }
        
        // Verify launch file is inside the pod
        let check = await shell("kubectl exec \(shellQuote(name)) -- ls -la /app/\(shellQuote(launch)) 2>&1 || kubectl exec \(shellQuote(name)) -- find /app -maxdepth 3 -type f 2>&1 | head -40")
        out += "📂 In-pod files:\n\(check)"
        
        // Execute real command
        var execParts: [String] = ["kubectl", "exec", name, "--"]
        if let cmd {
            execParts.append(cmd)
            execParts.append(contentsOf: args)
        } else {
            execParts.append(contentsOf: ["sh", "-c", "echo 'No command configured'"])
        }
        let execCmd = execParts.map { shellQuote($0) }.joined(separator: " ")
        out += "▶️  \(execParts.dropFirst(3).joined(separator: " "))\n"
        let execOut = await shell(execCmd)
        out += "—— output ——\n"
        out += execOut.isEmpty ? "(no output)\n" : execOut
        
        let status = await shell("kubectl get pod \(shellQuote(name)) -o wide 2>&1 || true")
        out += "\n—— status ——\n\(status)"
        
        // Leave pod running briefly for debug; delete to avoid clutter
        _ = await shell("kubectl delete pod \(shellQuote(name)) --ignore-not-found=true --wait=false 2>/dev/null; true")
        out += "🧹 Cleaned up pod \(name)\n"
        
        return out
    }
    
    private static func runWithDocker(pod: Pod, projectPath: URL) async -> String {
        let image = containerImage(for: pod.framework)
        let (cmd, args) = containerCommand(for: pod)
        let name = "pioneer-\(sanitizeK8sName(pod.name, id: pod.id))"
        let launch = projectPath.appendingPathComponent(pod.framework.launchFile)
        
        var out = "🐳 docker run \(image)\n"
        out += "   mount: \(projectPath.path) → /app\n"
        
        if !FileManager.default.fileExists(atPath: launch.path) {
            out += "❌ Launch file not on disk: \(launch.path)\n"
            return out
        }
        
        // Prefer Colima docker socket if present
        var envPrefix = ""
        let colimaSock = "\(NSHomeDirectory())/.colima/default/docker.sock"
        if FileManager.default.fileExists(atPath: colimaSock) {
            envPrefix = "DOCKER_HOST=unix://\(colimaSock) "
        }
        
        var parts = [
            "docker", "run", "--rm",
            "--name", name,
            "-v", "\(projectPath.path):/app",
            "-w", "/app"
        ]
        parts.append(image)
        if let cmd {
            parts.append(cmd)
            parts.append(contentsOf: args)
        }
        
        let command = envPrefix + parts.map { shellQuote($0) }.joined(separator: " ")
        out += await shell(command)
        return out
    }
    
    // MARK: - Helpers
    
    static func sanitizeK8sName(_ name: String, id: UUID) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: " ", with: "-")
        s = s.replacingOccurrences(of: "_", with: "-")
        s = String(s.map { ch in
            (ch.isLetter || ch.isNumber || ch == "-") ? ch : "-"
        })
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.isEmpty { s = "pod" }
        if s.first?.isNumber == true { s = "p-\(s)" }
        // K8s name max 63 chars
        let suffix = String(id.uuidString.prefix(8)).lowercased()
        let maxBase = 63 - 1 - suffix.count
        if s.count > maxBase {
            s = String(s.prefix(maxBase))
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return "\(s)-\(suffix)"
    }
    
    private static func escapeYAMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    private static func environmentYAML(for framework: Framework) -> [String] {
        switch framework {
        case .flask:
            return [
                "      env:",
                "        - name: FLASK_APP",
                "          value: \"app.py\"",
                "        - name: PYTHONUNBUFFERED",
                "          value: \"1\""
            ]
        case .django, .fastapi, .purepy:
            return [
                "      env:",
                "        - name: PYTHONUNBUFFERED",
                "          value: \"1\""
            ]
        case .nodejs, .express, .nestjs, .react, .vue, .angular, .nextjs, .reactNative:
            return [
                "      env:",
                "        - name: NODE_ENV",
                "          value: \"development\""
            ]
        default:
            return []
        }
    }
    
    private static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if s.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/:@%+=")).inverted) == nil {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private static func isCommandAvailable(_ name: String) async -> Bool {
        let result = await shell("command -v \(name) >/dev/null 2>&1 && echo yes || echo no")
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }
    
    private static func shell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", command]
            process.standardOutput = outPipe
            process.standardError = errPipe
            
            // Prefer user PATH for homebrew/kubectl/docker/grok
            var env = ProcessInfo.processInfo.environment
            let extras = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "\(NSHomeDirectory())/.local/bin",
                "\(NSHomeDirectory())/.grok/bin",
                "/usr/bin",
                "/bin"
            ]
            let path = extras.joined(separator: ":") + ":" + (env["PATH"] ?? "")
            env["PATH"] = path
            // Colima Docker socket (so docker works when GUI app isn't used)
            let colimaSock = "\(NSHomeDirectory())/.colima/default/docker.sock"
            if FileManager.default.fileExists(atPath: colimaSock) {
                env["DOCKER_HOST"] = "unix://\(colimaSock)"
            }
            process.environment = env
            
            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                var result = out
                if !err.isEmpty { result += err }
                if result.isEmpty && proc.terminationStatus != 0 {
                    result = "Command exited with status \(proc.terminationStatus)\n"
                }
                continuation.resume(returning: result)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)\n")
                }
            }
        }
    }
}
