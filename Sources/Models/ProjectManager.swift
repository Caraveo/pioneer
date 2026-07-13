import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable {
    case podCanvas = "PODS"
    case code = "CODE"
    case yaml = "YAML"
    case git = "GIT"
    
    var icon: String {
        switch self {
        case .podCanvas: return "square.grid.2x2"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .yaml: return "shippingbox"
        case .git: return "arrow.triangle.branch"
        }
    }
}

@MainActor
class ProjectManager: ObservableObject {
    @Published var pods: [Pod] = []
    @Published var selectedPod: Pod?
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var connectingFromPodId: UUID?
    @Published var hoveredConnectionPoint: (podId: UUID, isOutput: Bool)?
    @Published var viewMode: ViewMode = .podCanvas
    
    private let pythonBridge = PythonBridge()
    let podProjectService = PodProjectService()
    @Published var aiService = AIService()
    @Published var currentProjectPath: URL?
    @Published var projectName: String = "Untitled Project"
    /// True while Play All is executing pods sequentially.
    @Published var isFleetRunning: Bool = false
    /// Latest fleet / per-pod run log (shown in terminal consumers if desired).
    @Published var lastRunLog: String = ""
    /// Rocket (cloud) launch state
    @Published var isRocketLaunching: Bool = false
    @Published var cloudProviders: [CloudProviderStatus] = []
    @Published var rocketLog: String = ""
    
    init() {
        // Create a default pod for demonstration
        createDefaultPods()
        Task { await refreshCloudProviders() }
    }
    
    // MARK: - Rocket (cloud launch)
    
    func refreshCloudProviders() async {
        let detected = await CloudLaunchService.detectAll()
        await MainActor.run {
            cloudProviders = detected
        }
    }
    
    private func projectURL(for pod: Pod) -> URL {
        if let path = pod.projectPath {
            return URL(fileURLWithPath: path)
        }
        return podProjectService.getProjectPath(for: pod, projectName: projectName)
    }
    
    func rocketLaunchSelected(provider: CloudProviderKind) async {
        guard let pod = selectedPod else {
            await MainActor.run { rocketLog = "Select a pod first, then hit Rocket.\n" }
            return
        }
        await MainActor.run {
            isRocketLaunching = true
            rocketLog = "🚀 Preparing launch…\n"
        }
        saveCurrentPodFiles()
        // Ensure files on disk
        let url = projectURL(for: pod)
        try? await podProjectService.saveAllFiles(pod: pod, projectPath: url)
        
        let result = await CloudLaunchService.launch(pod: pod, projectPath: url, provider: provider)
        await MainActor.run {
            rocketLog = result.log
            lastRunLog += result.log
            if result.success {
                setPodRunning(id: pod.id, true)
            }
            isRocketLaunching = false
        }
    }
    
    func rocketLaunchAll(provider: CloudProviderKind) async {
        await MainActor.run {
            isRocketLaunching = true
            rocketLog = "🚀 Fleet rocket armed…\n"
        }
        saveCurrentPodFiles()
        
        let snapshot = pods
        let log = await CloudLaunchService.launchFleet(
            pods: snapshot,
            projectPathFor: { [weak self] pod in
                guard let self else {
                    return URL(fileURLWithPath: NSTemporaryDirectory())
                }
                // projectURL is MainActor — resolve path string on main
                return self.projectURL(for: pod)
            },
            provider: provider
        )
        
        await MainActor.run {
            rocketLog = log
            lastRunLog += log
            for p in snapshot {
                // Mark non-failed pods live if log suggests success for that name
                if log.contains("🟢") || log.contains("✅") {
                    if !log.contains("🔴 \(p.name)") {
                        setPodRunning(id: p.id, true)
                    }
                }
            }
            isRocketLaunching = false
        }
    }
    
    // MARK: - Runtime (Play / status)
    
    func setPodRunning(id: UUID, _ running: Bool) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        var pod = pods[index]
        pod.isRunning = running
        pods[index] = pod
        if selectedPod?.id == id {
            selectedPod = pod
        }
    }
    
    /// Click status indicator: toggle green ↔ red locally.
    /// Turning off also best-effort stops the K8s pod; turning on runs that pod.
    func togglePodRunning(id: UUID) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        let currently = pods[index].isRunning
        if currently {
            setPodRunning(id: id, false)
            let name = KubernetesManifestService.sanitizeK8sName(pods[index].name, id: id)
            Task {
                _ = await KubernetesManifestService.stopPod(named: name)
            }
        } else {
            Task {
                await runSinglePod(id: id)
            }
        }
    }
    
    /// Play: run all pods (including Inference env check) in dependency-ish order.
    func playAllPods() {
        guard !isFleetRunning else { return }
        Task { await runFleet() }
    }
    
    func stopAllPods() {
        Task {
            await MainActor.run { isFleetRunning = false }
            for pod in pods where pod.isRunning {
                setPodRunning(id: pod.id, false)
                let name = KubernetesManifestService.sanitizeK8sName(pod.name, id: pod.id)
                _ = await KubernetesManifestService.stopPod(named: name)
            }
            await MainActor.run {
                lastRunLog += "\n⏹ Stopped all pods\n"
            }
        }
    }
    
    private func runFleet() async {
        await MainActor.run {
            isFleetRunning = true
            lastRunLog = "▶️ Play all — running \(pods.count) pod(s)…\n"
        }
        saveCurrentPodFiles()
        
        // Order: Inference first, then databases, then services, then clients
        let ordered = pods.sorted { a, b in
            runtimePriority(a) < runtimePriority(b)
        }
        
        for pod in ordered {
            let log = await runSinglePod(id: pod.id)
            await MainActor.run {
                lastRunLog += log + "\n"
            }
        }
        
        await MainActor.run {
            isFleetRunning = false
            lastRunLog += "✅ Fleet run finished\n"
        }
    }
    
    private func runtimePriority(_ pod: Pod) -> Int {
        switch pod.type {
        case .inference: return 0
        case .database, .vault: return 1
        case .service, .awsBackend: return 2
        case .iOSApp, .androidApp, .macOSApp: return 3
        case .custom: return 4
        }
    }
    
    @discardableResult
    func runSinglePod(id: UUID) async -> String {
        guard let index = await MainActor.run(body: { pods.firstIndex(where: { $0.id == id }) }) else {
            return "Pod not found\n"
        }
        var pod = await MainActor.run { pods[index] }
        
        await MainActor.run { setPodRunning(id: id, true) }
        
        let workingDirectory: URL
        if let path = pod.projectPath {
            workingDirectory = URL(fileURLWithPath: path)
        } else {
            workingDirectory = podProjectService.getProjectPath(for: pod, projectName: projectName)
        }
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        
        // Refresh latest
        if let live = await MainActor.run(body: { pods.first(where: { $0.id == id }) }) {
            pod = live
        }
        
        var mutable = pod
        _ = mutable.getOrCreateMainFile()
        pod = mutable
        await MainActor.run {
            if let i = pods.firstIndex(where: { $0.id == id }) {
                pods[i] = pod
            }
        }
        
        do {
            try await podProjectService.saveAllFiles(pod: pod, projectPath: workingDirectory)
        } catch {
            await MainActor.run { setPodRunning(id: id, false) }
            return "❌ \(pod.name): failed to save — \(error.localizedDescription)\n"
        }
        
        // Inference hub: materialize .env only (no long-running container required)
        if pod.type == .inference {
            let env = Pod.makeEnvFileContent(name: pod.name, bindings: pod.environmentVariables)
            let envURL = workingDirectory.appendingPathComponent(".env")
            try? env.write(to: envURL, atomically: true, encoding: .utf8)
            try? KubernetesManifestService.writeYAML(pod.kubernetesYAML, to: workingDirectory)
            // Keep green — hub is "active"
            return "🟣 Inference “\(pod.name)” active — \(pod.environmentVariables.count) env key(s), .env written\n"
        }
        
        var yaml = pod.kubernetesYAML
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            yaml = KubernetesManifestService.generateYAML(for: pod, projectPath: workingDirectory.path)
        }
        
        let output = await KubernetesManifestService.run(
            pod: pod,
            yaml: yaml,
            projectPath: workingDirectory
        )
        
        let failed = output.lowercased().contains("❌")
            || output.lowercased().contains("error:")
            || output.lowercased().contains("syntaxerror")
            || output.contains("command terminated with exit code")
        
        if failed {
            await MainActor.run { setPodRunning(id: id, false) }
            return "🔴 \(pod.name) failed\n\(output)"
        }
        
        // Stay green: treated as running/healthy after successful start
        return "🟢 \(pod.name) running\n\(output)"
    }
    
    // MARK: - Project Save/Load
    
    func saveProject(to url: URL) async throws {
        // First, save all pod files to disk to ensure they're up to date
        // Capture values needed for async operations
        let podsToSave = pods
        let currentProjectName = projectName
        let service = podProjectService
        let currentCanvasOffset = canvasOffset
        let currentCanvasScale = canvasScale
        
        // Use async/await to save all files concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for pod in podsToSave {
                group.addTask {
                    let projectPath = service.getProjectPath(for: pod, projectName: currentProjectName)
                    try await service.saveAllFiles(pod: pod, projectPath: projectPath)
                }
            }
            
            // Wait for all tasks to complete, propagating any errors
            try await group.waitForAll()
        }
        
        // Perform heavy file operations on background thread
        try await Task.detached(priority: .userInitiated) {
            // Create a temporary directory for the archive
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                // Clean up temp directory
                try? FileManager.default.removeItem(at: tempDir)
            }
            
            // Save project metadata
            let project = PioneerProject(
                pods: podsToSave,
                canvasOffset: currentCanvasOffset,
                canvasScale: currentCanvasScale
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let projectData = try encoder.encode(project)
            
            let projectFile = tempDir.appendingPathComponent("project.json")
            try projectData.write(to: projectFile)
            
            // Copy all code files from all pods (excluding environments)
            let codeDir = tempDir.appendingPathComponent("code")
            try FileManager.default.createDirectory(at: codeDir, withIntermediateDirectories: true)
            
            for pod in podsToSave {
                // Get the pod's project path
                let podProjectPath = service.getProjectPath(for: pod, projectName: currentProjectName)
                
                // Copy all files from the pod's project directory, excluding environments
                if FileManager.default.fileExists(atPath: podProjectPath.path) {
                    let podCodeDir = codeDir.appendingPathComponent(pod.id.uuidString)
                    try FileManager.default.createDirectory(at: podCodeDir, withIntermediateDirectories: true)
                    
                    try self.copyPodFiles(
                        from: podProjectPath,
                        to: podCodeDir,
                        excluding: [
                            "node_modules",
                            ".venv",
                            "venv",
                            "__pycache__",
                            ".pytest_cache",
                            ".mypy_cache",
                            "dist",
                            "build",
                            ".next",
                            ".swiftpm",
                            "target", // Rust
                            ".git"
                        ]
                    )
                }
            }
            
            // Create zip archive
            let zipURL = tempDir.appendingPathComponent("project.zip")
            try self.createZipArchive(from: tempDir, to: zipURL, excluding: ["project.zip"])
            
            // Move zip to final location
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: zipURL, to: url)
        }.value
        
        // Update UI on main thread
        await MainActor.run {
            currentProjectPath = url
            projectName = url.deletingPathExtension().lastPathComponent
        }
    }
    
    /// Copy pod files excluding environment directories
    nonisolated private func copyPodFiles(from source: URL, to destination: URL, excluding: [String]) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            // Check if this path should be excluded
            let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
            let pathComponents = relativePath.split(separator: "/")
            
            var shouldExclude = false
            for component in pathComponents {
                if excluding.contains(String(component)) {
                    shouldExclude = true
                    enumerator.skipDescendants()
                    break
                }
            }
            
            if shouldExclude {
                continue
            }
            
            // Get file attributes
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            
            let destURL = destination.appendingPathComponent(relativePath)
            
            if resourceValues.isDirectory == true {
                // Create directory
                try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else if resourceValues.isRegularFile == true {
                // Copy file
                try fileManager.copyItem(at: fileURL, to: destURL)
            }
        }
    }
    
    /// Create a zip archive from a directory
    nonisolated private func createZipArchive(from sourceDir: URL, to zipURL: URL, excluding: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var arguments = ["-r", "-q", zipURL.path]
        // Add all files except excluded ones
        arguments.append(".")
        
        // Configure process on main thread (Process properties must be set on main thread)
        if Thread.isMainThread {
            process.currentDirectoryURL = sourceDir
            process.arguments = arguments
        } else {
            DispatchQueue.main.sync {
                process.currentDirectoryURL = sourceDir
                process.arguments = arguments
            }
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ProjectManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive: \(error)"])
        }
    }
    
    func loadProject(from url: URL) throws {
        // Create a temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract zip archive
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tempDir.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ProjectManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract archive: \(error)"])
        }
        
        // Load project metadata
        let projectFile = tempDir.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectFile)
        let decoder = JSONDecoder()
        let project = try decoder.decode(PioneerProject.self, from: data)
        
        pods = project.pods
        canvasOffset = project.canvasOffset
        canvasScale = project.canvasScale
        currentProjectPath = url
        projectName = url.deletingPathExtension().lastPathComponent
        
        // Restore code files for all pods
        let codeDir = tempDir.appendingPathComponent("code")
        if FileManager.default.fileExists(atPath: codeDir.path) {
            for pod in pods {
                let podCodeDir = codeDir.appendingPathComponent(pod.id.uuidString)
                if FileManager.default.fileExists(atPath: podCodeDir.path) {
                    // Get the pod's project path
                    let podProjectPath = podProjectService.getProjectPath(for: pod, projectName: projectName)
                    
                    // Copy files back to pod's project directory
                    try restorePodFiles(from: podCodeDir, to: podProjectPath)
                }
            }
        }
        
        // Initialize projects for all loaded pods (this will recreate environments if needed)
        Task {
            for pod in pods {
                await initializePodProject(pod: pod)
            }
        }
    }
    
    /// Restore pod files from archive to project directory
    private func restorePodFiles(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // Create destination directory if it doesn't exist
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            
            let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
            let destURL = destination.appendingPathComponent(relativePath)
            
            if resourceValues.isDirectory == true {
                // Create directory
                try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else if resourceValues.isRegularFile == true {
                // Copy file
                let destDir = destURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: fileURL, to: destURL)
            }
        }
    }
    
    func saveProjectAs() {
        let savePanel = NSSavePanel()
        // Pioneer project archives use `.core` (legacy `.code` still opens below)
        var types: [UTType] = []
        if let core = UTType(filenameExtension: "core") {
            types.append(core)
        }
        savePanel.allowedContentTypes = types.isEmpty ? [.data] : types
        savePanel.nameFieldStringValue = projectName
        savePanel.title = "Save Pioneer Project"
        savePanel.prompt = "Save"
        savePanel.message = "Pioneer projects use the .core extension"
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = savePanel.url {
                // Ensure .core extension even if the panel omitted it
                let finalURL: URL
                if url.pathExtension.lowercased() == "core" {
                    finalURL = url
                } else if url.pathExtension.lowercased() == "code" {
                    finalURL = url.deletingPathExtension().appendingPathExtension("core")
                } else if url.pathExtension.isEmpty {
                    finalURL = url.appendingPathExtension("core")
                } else {
                    finalURL = url.deletingPathExtension().appendingPathExtension("core")
                }
                Task { @MainActor in
                    do {
                        try await self.saveProject(to: finalURL)
                    } catch {
                        print("Failed to save project: \(error)")
                    }
                }
            }
        }
    }
    
    func openProject() {
        let openPanel = NSOpenPanel()
        // Prefer `.core`; still accept legacy `.code` archives
        var types: [UTType] = []
        if let core = UTType(filenameExtension: "core") { types.append(core) }
        if let legacy = UTType(filenameExtension: "code") { types.append(legacy) }
        openPanel.allowedContentTypes = types.isEmpty ? [.data] : types
        openPanel.title = "Open Pioneer Project"
        openPanel.prompt = "Open"
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Open a .core project (legacy .code also supported)"
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    try self.loadProject(from: url)
                } catch {
                    print("Failed to load project: \(error)")
                }
            }
        }
    }
    
    func newProject() {
        pods = []
        canvasOffset = .zero
        canvasScale = 1.0
        selectedPod = nil
        currentProjectPath = nil
        projectName = "Untitled Project"
        
        // Create a default pod
        createDefaultPods()
    }
    
    func createDefaultPods() {
        var defaultPod = Pod(
            name: "Example Service",
            type: .service,
            position: CGPoint(x: 100, y: 100),
            code: "",
            framework: .purepy
        )
        
        // Ensure main file exists
        let mainFile = defaultPod.getOrCreateMainFile()
        defaultPod.selectedFileId = mainFile.id
        
        pods.append(defaultPod)
        
        // Immediately create the directory for the default pod
        let podProjectPath = podProjectService.getProjectPath(for: defaultPod, projectName: projectName)
        do {
            try FileManager.default.createDirectory(at: podProjectPath, withIntermediateDirectories: true)
            // Update pod with project path immediately
            if let index = pods.firstIndex(where: { $0.id == defaultPod.id }) {
                pods[index].projectPath = podProjectPath.path
            }
        } catch {
            print("Failed to create default pod directory: \(error)")
        }
        
        // Initialize project for default pod
        Task {
            await initializePodProject(pod: defaultPod)
        }
    }
    
    func createNewPod() {
        var newPod = Pod(
            name: "New Pod \(pods.count + 1)",
            type: .service,
            position: CGPoint(
                x: 200 + CGFloat(pods.count) * 50,
                y: 200 + CGFloat(pods.count) * 50
            ),
            code: "",
            framework: .purepy
        )
        
        // Get or create main file
        let mainFile = newPod.getOrCreateMainFile()
        newPod.selectedFileId = mainFile.id
        
        pods.append(newPod)
        selectedPod = newPod
        
        // Immediately create the directory for the pod
        let podProjectPath = podProjectService.getProjectPath(for: newPod, projectName: projectName)
        do {
            try FileManager.default.createDirectory(at: podProjectPath, withIntermediateDirectories: true)
            // Update pod with project path immediately
            if let index = pods.firstIndex(where: { $0.id == newPod.id }) {
                pods[index].projectPath = podProjectPath.path
                selectedPod = pods[index]
            }
        } catch {
            print("Failed to create pod directory: \(error)")
        }
        
        // Create project structure for the pod
        Task {
            await initializePodProject(pod: newPod)
        }
    }
    
            private func initializePodProject(pod: Pod) async {
                do {
                    // Create project structure (can be done off main thread)
                    try await podProjectService.createProjectStructure(for: pod, projectName: projectName)
                    
                    // Get project path
                    let projectPath = podProjectService.getProjectPath(for: pod, projectName: projectName)
            
            // If it's a Python framework, create its virtual environment
            if pod.framework.needsEnvironment && [.django, .flask, .fastapi, .purepy].contains(pod.framework) {
                await pythonBridge.ensureVirtualEnvironment(for: pod)
            }
            
            // Each pod is its own git repository (team-scale boundary: Android / Apple / Web)
            let podName = await MainActor.run { () -> String in
                pods.first(where: { $0.id == pod.id })?.name ?? pod.name
            }
            // Save files before first commit
            if let latest = await MainActor.run(body: { pods.first(where: { $0.id == pod.id }) }) {
                try? await podProjectService.saveAllFiles(pod: latest, projectPath: projectPath)
            }
            _ = await GitService.ensureRepository(at: projectPath, podName: podName)
            
            // CRITICAL: All @Published property mutations must happen on main thread
            await MainActor.run {
                // Ensure pod has a main file
                if let index = pods.firstIndex(where: { $0.id == pod.id }) {
                    let mainFile = pods[index].getOrCreateMainFile()
                    if pods[index].selectedFileId == nil {
                        pods[index].selectedFileId = mainFile.id
                    }
                    
                    // Update project path and refresh K8s YAML hostPath
                    pods[index].projectPath = projectPath.path
                    pods[index].regenerateKubernetesYAML()
                    try? KubernetesManifestService.writeYAML(
                        pods[index].kubernetesYAML,
                        to: projectPath
                    )
                    
                    // Update selected pod if it's the one we're working with
                    if selectedPod?.id == pod.id {
                        selectedPod = pods[index]
                    }
                }
            }
        } catch {
            print("Failed to create project structure for pod \(pod.name): \(error)")
        }
    }
    
    /// Wipe on-disk project files (keep `.git`) and rescaffold for the pod’s current framework.
    private func wipeAndRescaffoldPod(_ pod: Pod) async {
        let projectPath = podProjectService.getProjectPath(for: pod, projectName: projectName)
        let fm = FileManager.default
        
        // Clear everything under the pod folder except git metadata
        if fm.fileExists(atPath: projectPath.path) {
            if let items = try? fm.contentsOfDirectory(at: projectPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for item in items {
                    if item.lastPathComponent == ".git" { continue }
                    try? fm.removeItem(at: item)
                }
            }
            // Also remove non-git hidden files/dirs (e.g. .env leftover) but keep .git
            if let all = try? fm.contentsOfDirectory(at: projectPath, includingPropertiesForKeys: nil, options: []) {
                for item in all where item.lastPathComponent != ".git" {
                    try? fm.removeItem(at: item)
                }
            }
        } else {
            try? fm.createDirectory(at: projectPath, withIntermediateDirectories: true)
        }
        
        // Use the latest in-memory wiped pod (single starter file)
        let latest = await MainActor.run { pods.first(where: { $0.id == pod.id }) ?? pod }
        
        do {
            try await podProjectService.createProjectStructure(for: latest, projectName: projectName)
            try await podProjectService.saveAllFiles(pod: latest, projectPath: projectPath)
            try KubernetesManifestService.writeYAML(latest.kubernetesYAML, to: projectPath)
        } catch {
            print("Failed to wipe/rescaffold pod \(pod.name): \(error)")
        }
        
        if latest.framework.needsEnvironment && [.django, .flask, .fastapi, .purepy].contains(latest.framework) {
            await pythonBridge.ensureVirtualEnvironment(for: latest)
        }
        
        await MainActor.run {
            if let index = pods.firstIndex(where: { $0.id == pod.id }) {
                var p = pods[index]
                p.projectPath = projectPath.path
                pods[index] = p
                // Force CODE editor / browser to refresh wiped files
                selectedPod = p
            }
        }
    }
    
    /// Confirmed Wipe Pod: delete all code/files and rebuild from the new framework template.
    func wipePodToFramework(id: UUID, newFramework: Framework) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        
        var pod = pods[index]
        // Hard reset in-memory codebase for the editor
        pod.switchToFramework(newFramework)
        pods[index] = pod
        selectedPod = pod
        
        // Wipe disk and write only the new scaffold
        Task {
            await wipeAndRescaffoldPod(pod)
        }
    }
    
    func updatePod(_ pod: Pod) {
        // CRITICAL: This must run on main thread since it mutates @Published properties
        guard let index = pods.firstIndex(where: { $0.id == pod.id }) else { return }
        
        let oldFramework = pods[index].framework
        let oldProjectPath = pods[index].projectPath
        let oldName = pods[index].name
        
        // Framework change must go through wipePodToFramework (explicit wipe)
        if oldFramework != pod.framework {
            wipePodToFramework(id: pod.id, newFramework: pod.framework)
            // Preserve any non-framework fields already on `pod` after wipe started
            if let i = pods.firstIndex(where: { $0.id == pod.id }) {
                var wiped = pods[i]
                wiped.name = pod.name
                wiped.type = pod.type
                wiped.position = pod.position
                wiped.connections = pod.connections
                pods[i] = wiped
                selectedPod = wiped
            }
            return
        }
        
        pods[index] = pod
        
        if oldName != pod.name || oldProjectPath != pod.projectPath {
            // Keep metadata in YAML in sync when name/path change
            pods[index].regenerateKubernetesYAML()
            if let path = pods[index].projectPath {
                try? KubernetesManifestService.writeYAML(
                    pods[index].kubernetesYAML,
                    to: URL(fileURLWithPath: path)
                )
            }
        } else {
            // Soft repair: ensure launch file content matches framework language
            _ = pods[index].getOrCreateMainFile()
            if let path = pods[index].projectPath {
                try? KubernetesManifestService.writeYAML(
                    pods[index].kubernetesYAML,
                    to: URL(fileURLWithPath: path)
                )
            }
            Task {
                do {
                    let projectPath = podProjectService.getProjectPath(for: pods[index], projectName: projectName)
                    try await podProjectService.saveAllFiles(pod: pods[index], projectPath: projectPath)
                } catch {
                    print("Failed to save files: \(error)")
                }
            }
        }
        
        // If framework changed to Python-based, ensure virtual environment exists
        let pythonFrameworks: [Framework] = [.django, .flask, .fastapi, .purepy]
        if pythonFrameworks.contains(pod.framework) && !pythonFrameworks.contains(oldFramework) {
            Task {
                await pythonBridge.ensureVirtualEnvironment(for: pods[index])
            }
        }
        
        // If requirements changed, update the environment
        if pythonFrameworks.contains(pod.framework) && pod.pythonRequirements != pods[index].pythonRequirements {
            Task {
                await pythonBridge.updatePythonRequirements(for: pods[index])
            }
        }
        
        if selectedPod?.id == pod.id {
            selectedPod = pods[index]
        }
    }
    
    func openPodProjectInFinder(_ pod: Pod) {
        podProjectService.openProjectInFinder(for: pod, projectName: projectName)
    }
    
    /// Save the currently selected pod's files to the pods array
    func saveCurrentPodFiles() {
        guard let selectedPod = selectedPod,
              let index = pods.firstIndex(where: { $0.id == selectedPod.id }) else {
            return
        }
        
        // Update the pod in the array with the current selectedPod's state
        // This ensures any changes in selectedPod are persisted to the array
        pods[index] = selectedPod
        
        // Also ensure selectedPod is updated from array (in case array has newer data)
        self.selectedPod = pods[index]
        
        // Save files to disk
        Task {
            do {
                let projectPath = podProjectService.getProjectPath(for: pods[index], projectName: projectName)
                try await podProjectService.saveAllFiles(pod: pods[index], projectPath: projectPath)
            } catch {
                print("Failed to save pod files: \(error)")
            }
        }
    }
    
    /// Force save current pod by getting latest content from editor
    func forceSaveCurrentPod() {
        saveCurrentPodFiles()
    }
    
    
    /// Remove a pod safely (no crash when deleting the last one).
    /// PropertyBar / editors bind by id; never leave `selectedPod` pointing at a removed pod.
    func deletePod(_ pod: Pod) {
        deletePod(id: pod.id)
    }
    
    func deletePod(id: UUID) {
        // Clear connection / drag state that referenced this pod
        if connectingFromPodId == id {
            connectingFromPodId = nil
        }
        if hoveredConnectionPoint?.podId == id {
            hoveredConnectionPoint = nil
        }
        
        // Drop relationships pointing at this pod (full reassignment for @Published)
        var next = pods.filter { $0.id != id }
        for i in next.indices {
            next[i].connections.removeAll { $0 == id }
        }
        
        let wasSelected = selectedPod?.id == id
        let fallback = next.first
        
        // 1) Drop selection first so PropertyBar / CodeEditor unmount before pods mutates.
        //    Stale Bindings that closed over a removed index caused EXC_BAD_INSTRUCTION.
        if wasSelected {
            selectedPod = nil
        } else if let sel = selectedPod, !next.contains(where: { $0.id == sel.id }) {
            selectedPod = nil
        }
        
        // 2) Mutate the array
        pods = next
        
        if next.isEmpty {
            selectedPod = nil
            viewMode = .podCanvas
            return
        }
        
        // 3) Reselect on the next run-loop turn so SwiftUI finishes tearing down the
        //    old PropertyBar tree (and any AttributeGraph nodes that held indices).
        if wasSelected, let fallback {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Only reselect if nothing else took selection in the meantime
                if self.selectedPod == nil,
                   self.pods.contains(where: { $0.id == fallback.id }) {
                    self.selectedPod = self.pods.first(where: { $0.id == fallback.id })
                }
            }
        }
    }
    
    /// Apply an Inference wizard plan: virtual Inference hub + stack pods + relationship wires.
    func applyInferencePlan(_ plan: InferencePlan) {
        let origin = CGPoint(
            x: 200 + CGFloat(pods.count) * 20,
            y: 160 + CGFloat(pods.count) * 10
        )
        
        var created: [String: UUID] = [:] // blueprint name → id
        var newPods: [Pod] = []
        
        for bp in plan.podBlueprints {
            let pos = CGPoint(x: origin.x + bp.position.x - 420, y: origin.y + bp.position.y - 120)
            var pod: Pod
            if bp.type == .inference {
                let envContent = Pod.makeEnvFileContent(name: bp.name, bindings: plan.env)
                pod = Pod(
                    name: bp.name,
                    type: .inference,
                    position: pos,
                    code: envContent,
                    framework: .environment,
                    environmentVariables: plan.env
                )
                // Ensure files match env
                if let idx = pod.files.firstIndex(where: { $0.path == ".env" }) {
                    pod.files[idx].content = envContent
                }
                pod.kubernetesYAML = Pod.makeInferenceConfigMapYAML(name: bp.name, id: pod.id, bindings: plan.env)
            } else {
                pod = Pod(
                    name: bp.name,
                    type: bp.type,
                    position: pos,
                    code: "",
                    framework: bp.framework
                )
            }
            created[bp.name] = pod.id
            newPods.append(pod)
        }
        
        // Wire relationships from plan assumptions:
        // clients → API, API → DB, Node → DB, Web → Node (or API), Inference → all
        func id(_ suffix: String) -> UUID? {
            created.first(where: { $0.key.hasSuffix(suffix) || $0.key.contains(suffix) })?.value
        }
        
        let apiId = created["\(plan.productName) API"]
        let dbId = created["\(plan.productName) DB"]
        let nodeId = created["\(plan.productName) Node"]
        let webId = created["\(plan.productName) Web"]
        let iosId = created["\(plan.productName) iOS"]
        let androidId = created["\(plan.productName) Android"]
        let inferenceId = created["\(plan.productName) Inference"]
        
        func link(_ from: UUID?, _ to: UUID?) {
            guard let from, let to, let idx = newPods.firstIndex(where: { $0.id == from }) else { return }
            if !newPods[idx].connections.contains(to) {
                newPods[idx].connections.append(to)
            }
        }
        
        // iOS / Android → API
        link(iosId, apiId)
        link(androidId, apiId)
        // API → DB
        link(apiId, dbId)
        // Node BFF → DB and API
        link(nodeId, dbId)
        link(nodeId, apiId)
        // Web → Node (if present) else API
        if nodeId != nil {
            link(webId, nodeId)
        } else {
            link(webId, apiId)
        }
        // Inference hub fans out to every runtime pod (env ownership)
        for p in newPods where p.type != .inference {
            link(inferenceId, p.id)
        }
        
        pods.append(contentsOf: newPods)
        if let inf = newPods.first(where: { $0.type == .inference }) {
            selectedPod = inf
        } else {
            selectedPod = newPods.first
        }
        viewMode = .podCanvas
        
        // Scaffold each new pod on disk
        for p in newPods {
            Task {
                await initializePodProject(pod: p)
            }
        }
    }
    
    /// Update env keys on an Inference hub and sync `.env` + ConfigMap YAML + disk files.
    func updateInferenceEnvironment(id: UUID, bindings: [EnvBinding]) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        guard pods[index].type == .inference else { return }
        
        var pod = pods[index]
        pod.environmentVariables = bindings
        
        let envContent = Pod.makeEnvFileContent(name: pod.name, bindings: bindings)
        pod.code = envContent
        pod.kubernetesYAML = Pod.makeInferenceConfigMapYAML(name: pod.name, id: pod.id, bindings: bindings)
        
        if let fi = pod.files.firstIndex(where: { $0.path == ".env" || $0.name == ".env" }) {
            pod.files[fi].content = envContent
            pod.selectedFileId = pod.files[fi].id
        } else if let fi = pod.files.indices.first {
            pod.files[fi].content = envContent
            pod.files[fi].path = ".env"
            pod.files[fi].name = ".env"
            pod.selectedFileId = pod.files[fi].id
        } else {
            let main = ProjectFile(
                path: ".env",
                name: ".env",
                content: envContent,
                language: .bash
            )
            pod.files = [main]
            pod.selectedFileId = main.id
        }
        
        pods[index] = pod
        if selectedPod?.id == id {
            selectedPod = pod
        }
        
        // Persist .env + YAML when the pod has a project path
        if let path = pod.projectPath {
            let projectURL = URL(fileURLWithPath: path)
            let envURL = projectURL.appendingPathComponent(".env")
            Task {
                try? FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
                try? envContent.write(to: envURL, atomically: true, encoding: .utf8)
                try? KubernetesManifestService.writeYAML(
                    pod.kubernetesYAML,
                    to: projectURL
                )
                try? await podProjectService.saveAllFiles(pod: pod, projectPath: projectURL)
            }
        }
    }
    
    /// Move a pod on the canvas (full reassignment so `@Published` notifies SwiftUI).
    func movePod(id: UUID, to position: CGPoint) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        var pod = pods[index]
        pod.position = position
        pods[index] = pod
        if selectedPod?.id == id {
            selectedPod = pod
        }
    }
    
    func connectPods(from sourceId: UUID, to targetId: UUID) {
        guard sourceId != targetId,
              let index = pods.firstIndex(where: { $0.id == sourceId }) else { return }
        var pod = pods[index]
        if !pod.connections.contains(targetId) {
            pod.connections.append(targetId)
            pods[index] = pod
            if selectedPod?.id == sourceId {
                selectedPod = pod
            }
        }
    }
    
    func disconnectPods(from sourceId: UUID, to targetId: UUID) {
        guard let index = pods.firstIndex(where: { $0.id == sourceId }) else { return }
        var pod = pods[index]
        pod.connections.removeAll { $0 == targetId }
        pods[index] = pod
        if selectedPod?.id == sourceId {
            selectedPod = pod
        }
    }
    
    func startConnection(from podId: UUID) {
        connectingFromPodId = podId
    }
    
    func endConnection() {
        connectingFromPodId = nil
    }
    
    func hoverConnectionPoint(podId: UUID?, isOutput: Bool) {
        if let podId = podId {
            hoveredConnectionPoint = (podId, isOutput)
        } else {
            hoveredConnectionPoint = nil
        }
    }
    
    // Generation actions
    func generateiPhoneApp() {
        guard let selected = selectedPod else {
            print("No pod selected for iPhone app generation")
            return
        }
        
        Task {
            await pythonBridge.generateiPhoneApp(pod: selected)
        }
    }
    
    func generateWebsite() {
        guard let selected = selectedPod else {
            print("No pod selected for website generation")
            return
        }
        
        Task {
            await pythonBridge.generateWebsite(pod: selected)
        }
    }
    
    func deployBackendToAWS() {
        guard let selected = selectedPod else {
            print("No pod selected for AWS deployment")
            return
        }
        
        Task {
            await pythonBridge.deployToAWS(pod: selected)
        }
    }
}

