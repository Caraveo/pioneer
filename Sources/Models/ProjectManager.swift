import Foundation
import SwiftUI
import Combine
import AppKit

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
    
    init() {
        // Create a default pod for demonstration
        createDefaultPods()
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
        savePanel.allowedContentTypes = [.init(filenameExtension: "code")!]
        savePanel.nameFieldStringValue = projectName
        savePanel.title = "Save Pioneer Project"
        savePanel.prompt = "Save"
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = savePanel.url {
                Task { @MainActor in
                    do {
                        try await self.saveProject(to: url)
                    } catch {
                        print("Failed to save project: \(error)")
                    }
                }
            }
        }
    }
    
    func openProject() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.init(filenameExtension: "code")!]
        openPanel.title = "Open Pioneer Project"
        openPanel.prompt = "Open"
        openPanel.allowsMultipleSelection = false
        
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
    
    func updatePod(_ pod: Pod) {
        // CRITICAL: This must run on main thread since it mutates @Published properties
        guard let index = pods.firstIndex(where: { $0.id == pod.id }) else { return }
        
        let oldFramework = pods[index].framework
        let oldProjectPath = pods[index].projectPath
        let oldName = pods[index].name
        
        pods[index] = pod
        
        // Ensure main file exists when framework changes
        if oldFramework != pod.framework {
            let mainFile = pods[index].getOrCreateMainFile()
            if pods[index].selectedFileId == nil {
                pods[index].selectedFileId = mainFile.id
            }
            // Framework defines container image + entrypoint → refresh K8s YAML
            pods[index].regenerateKubernetesYAML()
        } else if oldName != pod.name || oldProjectPath != pod.projectPath {
            // Keep metadata in YAML in sync when name/path change
            pods[index].regenerateKubernetesYAML()
        }
        
        // Persist k8s/pod.yaml beside project code
        if let path = pods[index].projectPath {
            try? KubernetesManifestService.writeYAML(
                pods[index].kubernetesYAML,
                to: URL(fileURLWithPath: path)
            )
        }
        
        // Ensure project structure exists
        if pod.projectPath == nil || oldProjectPath != pod.projectPath {
            Task {
                await initializePodProject(pod: pods[index])
            }
        } else {
            // Save all files to project
                    Task {
                        do {
                            try await podProjectService.saveAllFiles(pod: pods[index], projectPath: podProjectService.getProjectPath(for: pods[index], projectName: projectName))
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
    
    
    func deletePod(_ pod: Pod) {
        pods.removeAll { $0.id == pod.id }
        // Remove connections to this pod
        for i in pods.indices {
            pods[i].connections.removeAll { $0 == pod.id }
        }
        if selectedPod?.id == pod.id {
            selectedPod = nil
        }
    }
    
    func connectPods(from sourceId: UUID, to targetId: UUID) {
        guard let index = pods.firstIndex(where: { $0.id == sourceId }) else { return }
        if !pods[index].connections.contains(targetId) {
            pods[index].connections.append(targetId)
        }
    }
    
    func disconnectPods(from sourceId: UUID, to targetId: UUID) {
        guard let index = pods.firstIndex(where: { $0.id == sourceId }) else { return }
        pods[index].connections.removeAll { $0 == targetId }
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

