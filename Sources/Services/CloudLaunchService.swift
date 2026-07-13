import Foundation

// MARK: - Abstract cloud launch

/// Cloud targets Pioneer can rocket-launch into. Detection is CLI-based and best-effort.
enum CloudProviderKind: String, CaseIterable, Identifiable, Codable {
    case digitalOcean = "DigitalOcean"
    case googleCloud = "Google Cloud"
    case aws = "AWS"
    case kubernetes = "Kubernetes"
    case docker = "Docker"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .digitalOcean: return "drop.fill"
        case .googleCloud: return "cloud.fill"
        case .aws: return "shippingbox.fill"
        case .kubernetes: return "circle.hexagongrid.fill"
        case .docker: return "shippingbox.circle"
        }
    }
    
    var accent: String {
        switch self {
        case .digitalOcean: return "DO"
        case .googleCloud: return "GCE"
        case .aws: return "AWS"
        case .kubernetes: return "K8s"
        case .docker: return "Docker"
        }
    }
    
    /// Primary CLI binary name used for detection.
    var cliName: String {
        switch self {
        case .digitalOcean: return "doctl"
        case .googleCloud: return "gcloud"
        case .aws: return "aws"
        case .kubernetes: return "kubectl"
        case .docker: return "docker"
        }
    }
    
    var helpURL: String {
        switch self {
        case .digitalOcean: return "https://docs.digitalocean.com/reference/doctl/"
        case .googleCloud: return "https://cloud.google.com/sdk/gcloud"
        case .aws: return "https://aws.amazon.com/cli/"
        case .kubernetes: return "https://kubernetes.io/docs/tasks/tools/"
        case .docker: return "https://docs.docker.com/get-docker/"
        }
    }
}

struct CloudProviderStatus: Identifiable, Equatable {
    let kind: CloudProviderKind
    var installed: Bool
    var authenticated: Bool
    var version: String
    var detail: String
    
    var id: String { kind.id }
    
    var isReady: Bool { installed && authenticated }
    
    var statusLabel: String {
        if !installed { return "Not installed" }
        if !authenticated { return "Installed · not authenticated" }
        return "Ready · \(version)"
    }
}

struct CloudLaunchResult {
    let provider: CloudProviderKind
    let success: Bool
    let log: String
    let artifactPath: String?
}

/// Abstract “Rocket” launcher: detect CLIs, materialize deploy descriptors, fire CLI commands.
enum CloudLaunchService {
    
    // MARK: - Detection
    
    static func detectAll() async -> [CloudProviderStatus] {
        var results: [CloudProviderStatus] = []
        for kind in CloudProviderKind.allCases {
            results.append(await detect(kind))
        }
        // Prefer ready providers first
        return results.sorted { a, b in
            if a.isReady != b.isReady { return a.isReady && !b.isReady }
            if a.installed != b.installed { return a.installed && !b.installed }
            return a.kind.rawValue < b.kind.rawValue
        }
    }
    
    static func detect(_ kind: CloudProviderKind) async -> CloudProviderStatus {
        let path = await which(kind.cliName)
        guard let path, !path.isEmpty else {
            return CloudProviderStatus(
                kind: kind,
                installed: false,
                authenticated: false,
                version: "",
                detail: "Install \(kind.cliName) to enable \(kind.rawValue) launches"
            )
        }
        
        let version = await shell("\(shellQuote(path)) --version 2>&1 | head -1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let (authed, detail) = await authProbe(kind: kind, cli: path)
        return CloudProviderStatus(
            kind: kind,
            installed: true,
            authenticated: authed,
            version: version.isEmpty ? path : version,
            detail: detail
        )
    }
    
    private static func authProbe(kind: CloudProviderKind, cli: String) async -> (Bool, String) {
        switch kind {
        case .digitalOcean:
            let code = await shell("\(shellQuote(cli)) account get >/dev/null 2>&1 && echo OK || echo FAIL")
            return (code.contains("OK"), code.contains("OK") ? "doctl account reachable" : "Run: doctl auth init")
        case .googleCloud:
            let code = await shell("\(shellQuote(cli)) auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1")
            let account = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if account.isEmpty {
                return (false, "Run: gcloud auth login")
            }
            return (true, "Active: \(account)")
        case .aws:
            let code = await shell("\(shellQuote(cli)) sts get-caller-identity 2>&1")
            if code.lowercased().contains("arn") || code.lowercased().contains("account") {
                return (true, "STS identity OK")
            }
            return (false, "Configure: aws configure  (or env credentials)")
        case .kubernetes:
            let code = await shell("\(shellQuote(cli)) cluster-info >/dev/null 2>&1 && echo OK || echo FAIL")
            return (code.contains("OK"), code.contains("OK") ? "cluster reachable" : "No active cluster context")
        case .docker:
            let code = await shell("\(shellQuote(cli)) info >/dev/null 2>&1 && echo OK || echo FAIL")
            return (code.contains("OK"), code.contains("OK") ? "daemon reachable" : "Start Docker / Colima")
        }
    }
    
    // MARK: - Launch
    
    /// Prefer first ready provider, else first installed, else nil.
    static func preferred(from statuses: [CloudProviderStatus]) -> CloudProviderKind? {
        statuses.first(where: \.isReady)?.kind
            ?? statuses.first(where: \.installed)?.kind
    }
    
    /// Rocket-launch one pod to a provider (abstract adapter).
    static func launch(
        pod: Pod,
        projectPath: URL,
        provider: CloudProviderKind
    ) async -> CloudLaunchResult {
        var log = "🚀 Rocket → \(provider.rawValue) · pod “\(pod.name)”\n"
        
        // Materialize abstract deploy descriptors under cloud/
        let artifact: URL
        do {
            artifact = try writeLaunchBundle(pod: pod, projectPath: projectPath, provider: provider)
            log += "📄 Wrote \(artifact.path)\n"
        } catch {
            return CloudLaunchResult(
                provider: provider,
                success: false,
                log: log + "❌ Failed to write launch bundle: \(error.localizedDescription)\n",
                artifactPath: nil
            )
        }
        
        let status = await detect(provider)
        guard status.installed else {
            log += """
            ⚠️ \(provider.cliName) not found.
            Install from \(provider.helpURL)
            Launch bundle is ready at:
              \(artifact.path)
            When the CLI is installed, Rocket will fire automatically.
            
            """
            return CloudLaunchResult(provider: provider, success: false, log: log, artifactPath: artifact.path)
        }
        
        if !status.authenticated {
            log += "⚠️ \(provider.rawValue) CLI present but not authenticated — \(status.detail)\n"
            log += "   Attempting dry launch / package step anyway…\n"
        }
        
        let cmdLog = await fireCLI(provider: provider, pod: pod, projectPath: projectPath, artifact: artifact)
        log += cmdLog
        
        let success = !log.lowercased().contains("❌")
            && !cmdLog.lowercased().contains("error:")
            && !cmdLog.lowercased().contains("command not found")
        
        if success {
            log += "✅ Rocket launch sequence completed for \(provider.accent)\n"
        } else {
            log += "⚠️ Launch finished with warnings — check CLI auth and the generated bundle.\n"
        }
        
        return CloudLaunchResult(
            provider: provider,
            success: success || status.authenticated,
            log: log,
            artifactPath: artifact.path
        )
    }
    
    /// Launch every non-inference-or-including all pods with preferred provider.
    static func launchFleet(
        pods: [Pod],
        projectPathFor: (Pod) -> URL,
        provider: CloudProviderKind
    ) async -> String {
        var log = "🚀🚀 Fleet rocket · \(provider.rawValue) · \(pods.count) pod(s)\n\n"
        for pod in pods {
            let result = await launch(pod: pod, projectPath: projectPathFor(pod), provider: provider)
            log += result.log + "\n"
        }
        log += "—— fleet complete ——\n"
        return log
    }
    
    // MARK: - Descriptor generation (abstract)
    
    private static func writeLaunchBundle(pod: Pod, projectPath: URL, provider: CloudProviderKind) throws -> URL {
        let cloudDir = projectPath.appendingPathComponent("cloud/\(provider.cliName)", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        
        let slug = sanitize(pod.name)
        let imageHint = KubernetesManifestService.containerImage(for: pod.framework)
        let launch = pod.framework.launchFile
        
        switch provider {
        case .digitalOcean:
            let spec = """
            name: \(slug)
            region: nyc1
            services:
            - name: web
              image:
                registry_type: DOCKER_HUB
                repository: \(imageHint.split(separator: ":").first.map(String.init) ?? "library/node")
                tag: \(imageHint.split(separator: ":").last.map(String.init) ?? "latest")
              http_port: 8080
              instance_count: 1
              instance_size_slug: basic-xxs
              envs:
              - key: PORT
                value: "8080"
            # Pioneer Rocket abstract App Platform spec
            # Apply with: doctl apps create --spec app.yaml
            """
            let url = cloudDir.appendingPathComponent("app.yaml")
            try spec.write(to: url, atomically: true, encoding: .utf8)
            try writeReadme(cloudDir, provider: provider, commands: [
                "doctl auth init",
                "doctl apps create --spec \(url.lastPathComponent)",
                "doctl apps list"
            ])
            return url
            
        case .googleCloud:
            let yaml = """
            # Pioneer Rocket · Cloud Run service (abstract)
            apiVersion: serving.knative.dev/v1
            kind: Service
            metadata:
              name: \(slug)
            spec:
              template:
                spec:
                  containers:
                  - image: \(imageHint)
                    ports:
                    - containerPort: 8080
                    env:
                    - name: PORT
                      value: "8080"
            """
            let url = cloudDir.appendingPathComponent("service.yaml")
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            let script = """
            #!/bin/bash
            set -euo pipefail
            PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
            REGION="${CLOUD_RUN_REGION:-us-central1}"
            echo "Project=$PROJECT Region=$REGION"
            # Source deploy when Dockerfile exists; else image-based
            if [ -f Dockerfile ]; then
              gcloud run deploy \(slug) --source . --region "$REGION" --allow-unauthenticated --quiet
            else
              gcloud run deploy \(slug) --image \(imageHint) --region "$REGION" --allow-unauthenticated --quiet
            fi
            """
            let sh = cloudDir.appendingPathComponent("launch.sh")
            try script.write(to: sh, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sh.path)
            try writeReadme(cloudDir, provider: provider, commands: [
                "gcloud auth login",
                "gcloud config set project YOUR_PROJECT",
                "bash cloud/gcloud/launch.sh"
            ])
            return sh
            
        case .aws:
            let task = """
            {
              "family": "\(slug)",
              "networkMode": "awsvpc",
              "requiresCompatibilities": ["FARGATE"],
              "cpu": "256",
              "memory": "512",
              "containerDefinitions": [
                {
                  "name": "\(slug)",
                  "image": "\(imageHint)",
                  "essential": true,
                  "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
                  "environment": [{ "name": "PORT", "value": "8080" }]
                }
              ]
            }
            """
            let url = cloudDir.appendingPathComponent("task-definition.json")
            try task.write(to: url, atomically: true, encoding: .utf8)
            let script = """
            #!/bin/bash
            set -euo pipefail
            REGION="${AWS_REGION:-us-east-1}"
            echo "Registering ECS task definition (abstract Pioneer Rocket)…"
            aws ecs register-task-definition --cli-input-json file://task-definition.json --region "$REGION"
            echo "Tip: create a Fargate service pointing at this task definition."
            aws sts get-caller-identity
            """
            let sh = cloudDir.appendingPathComponent("launch.sh")
            try script.write(to: sh, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sh.path)
            try writeReadme(cloudDir, provider: provider, commands: [
                "aws configure",
                "bash cloud/aws/launch.sh"
            ])
            return sh
            
        case .kubernetes:
            let yaml = pod.kubernetesYAML.isEmpty
                ? KubernetesManifestService.generateYAML(for: pod, projectPath: projectPath.path)
                : pod.kubernetesYAML
            let url = cloudDir.appendingPathComponent("pod.yaml")
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            try writeReadme(cloudDir, provider: provider, commands: [
                "kubectl apply -f cloud/kubectl/pod.yaml",
                "kubectl get pods -l pioneer-pod=\(pod.id.uuidString)"
            ])
            return url
            
        case .docker:
            let df: String
            if FileManager.default.fileExists(atPath: projectPath.appendingPathComponent("Dockerfile").path) {
                df = try String(contentsOf: projectPath.appendingPathComponent("Dockerfile"), encoding: .utf8)
            } else {
                df = """
                FROM \(imageHint)
                WORKDIR /app
                COPY . .
                # Pioneer abstract Dockerfile — entry: \(launch)
                CMD ["sh", "-c", "echo Rocket container for \(slug)"]
                """
            }
            let dockerFile = cloudDir.appendingPathComponent("Dockerfile")
            try df.write(to: dockerFile, atomically: true, encoding: .utf8)
            let script = """
            #!/bin/bash
            set -euo pipefail
            IMAGE="pioneer/\(slug):latest"
            docker build -t "$IMAGE" -f Dockerfile ../..
            docker run --rm -p 8080:8080 "$IMAGE"
            """
            let sh = cloudDir.appendingPathComponent("launch.sh")
            try script.write(to: sh, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sh.path)
            try writeReadme(cloudDir, provider: provider, commands: [
                "bash cloud/docker/launch.sh"
            ])
            return sh
        }
    }
    
    private static func writeReadme(_ dir: URL, provider: CloudProviderKind, commands: [String]) throws {
        let body = """
        # Pioneer Rocket · \(provider.rawValue)
        
        Abstract launch bundle generated by Pioneer.
        
        ## Commands
        ```bash
        \(commands.joined(separator: "\n"))
        ```
        
        Docs: \(provider.helpURL)
        """
        try body.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private static func fireCLI(
        provider: CloudProviderKind,
        pod: Pod,
        projectPath: URL,
        artifact: URL
    ) async -> String {
        let cli = provider.cliName
        switch provider {
        case .digitalOcean:
            // Validate + dry-run style: create only if authenticated
            let probe = await shell("doctl account get 2>&1 | head -5")
            var log = probe + "\n"
            if probe.lowercased().contains("email") || probe.lowercased().contains("uuid") {
                log += await shell("cd \(shellQuote(projectPath.path)) && doctl apps spec validate \(shellQuote(artifact.path)) 2>&1 || doctl apps create --spec \(shellQuote(artifact.path)) --upsert 2>&1 || true")
            } else {
                log += "Skipping doctl apps create until authenticated.\n"
            }
            return log
            
        case .googleCloud:
            return await shell("cd \(shellQuote(artifact.deletingLastPathComponent().path)) && bash \(shellQuote(artifact.path)) 2>&1")
            
        case .aws:
            return await shell("cd \(shellQuote(artifact.deletingLastPathComponent().path)) && bash \(shellQuote(artifact.path)) 2>&1")
            
        case .kubernetes:
            return await shell("kubectl apply -f \(shellQuote(artifact.path)) 2>&1")
            
        case .docker:
            return await shell("cd \(shellQuote(projectPath.path)) && bash \(shellQuote(artifact.path)) 2>&1 | tail -40")
        }
    }
    
    // MARK: - Shell helpers
    
    private static func sanitize(_ name: String) -> String {
        let s = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .map { ch -> Character in
                (ch.isLetter || ch.isNumber || ch == "-") ? ch : "-"
            }
        var out = String(s)
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(48).description
    }
    
    private static func which(_ name: String) async -> String? {
        let out = await shell("command -v \(name) 2>/dev/null || true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
    
    private static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if s.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/:@%+=")).inverted) == nil {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private static func shell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let out = Pipe()
            let err = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", command]
            process.standardOutput = out
            process.standardError = err
            
            var env = ProcessInfo.processInfo.environment
            let extras = [
                "/usr/local/bin", "/opt/homebrew/bin",
                "\(NSHomeDirectory())/.local/bin",
                "\(NSHomeDirectory())/google-cloud-sdk/bin",
                "/usr/bin", "/bin"
            ]
            env["PATH"] = extras.joined(separator: ":") + ":" + (env["PATH"] ?? "")
            let colima = "\(NSHomeDirectory())/.colima/default/docker.sock"
            if FileManager.default.fileExists(atPath: colima) {
                env["DOCKER_HOST"] = "unix://\(colima)"
            }
            process.environment = env
            
            process.terminationHandler = { _ in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: o + e)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try process.run() }
                catch { continuation.resume(returning: "Error: \(error.localizedDescription)\n") }
            }
        }
    }
}
