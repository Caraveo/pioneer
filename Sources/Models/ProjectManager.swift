import Foundation
import SwiftUI
import Combine
import AppKit

enum ViewMode: String, CaseIterable {
    case nodeCanvas = "NODES"
    case editor = "EDITOR"
    
    var icon: String {
        switch self {
        case .nodeCanvas: return "square.grid.2x2"
        case .editor: return "doc.text"
        }
    }
}

@MainActor
class ProjectManager: ObservableObject {
    @Published var nodes: [Node] = []
    @Published var selectedNode: Node?
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var connectingFromNodeId: UUID?
    @Published var hoveredConnectionPoint: (nodeId: UUID, isOutput: Bool)?
    @Published var viewMode: ViewMode = .nodeCanvas
    
    private let pythonBridge = PythonBridge()
    let nodeProjectService = NodeProjectService()
    @Published var aiService = AIService()
    @Published var currentProjectPath: URL?
    @Published var projectName: String = "Untitled Project"
    
    init() {
        // Create a default node for demonstration
        createDefaultNodes()
    }
    
    // MARK: - Project Save/Load
    
    func saveProject(to url: URL) async throws {
        // First, save all node files to disk to ensure they're up to date
        // Capture values needed for async operations
        let nodesToSave = nodes
        let currentProjectName = projectName
        let service = nodeProjectService
        let currentCanvasOffset = canvasOffset
        let currentCanvasScale = canvasScale
        
        // Use async/await to save all files concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for node in nodesToSave {
                group.addTask {
                    let projectPath = service.getProjectPath(for: node, projectName: currentProjectName)
                    try await service.saveAllFiles(node: node, projectPath: projectPath)
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
                nodes: nodesToSave,
                canvasOffset: currentCanvasOffset,
                canvasScale: currentCanvasScale
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let projectData = try encoder.encode(project)
            
            let projectFile = tempDir.appendingPathComponent("project.json")
            try projectData.write(to: projectFile)
            
            // Copy all code files from all nodes (excluding environments)
            let codeDir = tempDir.appendingPathComponent("code")
            try FileManager.default.createDirectory(at: codeDir, withIntermediateDirectories: true)
            
            for node in nodesToSave {
                // Get the node's project path
                let nodeProjectPath = service.getProjectPath(for: node, projectName: currentProjectName)
                
                // Copy all files from the node's project directory, excluding environments
                if FileManager.default.fileExists(atPath: nodeProjectPath.path) {
                    let nodeCodeDir = codeDir.appendingPathComponent(node.id.uuidString)
                    try FileManager.default.createDirectory(at: nodeCodeDir, withIntermediateDirectories: true)
                    
                    try self.copyNodeFiles(
                        from: nodeProjectPath,
                        to: nodeCodeDir,
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
    
    /// Copy node files excluding environment directories
    nonisolated private func copyNodeFiles(from source: URL, to destination: URL, excluding: [String]) throws {
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
        
        nodes = project.nodes
        canvasOffset = project.canvasOffset
        canvasScale = project.canvasScale
        currentProjectPath = url
        projectName = url.deletingPathExtension().lastPathComponent
        
        // Restore code files for all nodes
        let codeDir = tempDir.appendingPathComponent("code")
        if FileManager.default.fileExists(atPath: codeDir.path) {
            for node in nodes {
                let nodeCodeDir = codeDir.appendingPathComponent(node.id.uuidString)
                if FileManager.default.fileExists(atPath: nodeCodeDir.path) {
                    // Get the node's project path
                    let nodeProjectPath = nodeProjectService.getProjectPath(for: node, projectName: projectName)
                    
                    // Copy files back to node's project directory
                    try restoreNodeFiles(from: nodeCodeDir, to: nodeProjectPath)
                }
            }
        }
        
        // Initialize projects for all loaded nodes (this will recreate environments if needed)
        Task {
            for node in nodes {
                await initializeNodeProject(node: node)
            }
        }
    }
    
    /// Restore node files from archive to project directory
    private func restoreNodeFiles(from source: URL, to destination: URL) throws {
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
        nodes = []
        canvasOffset = .zero
        canvasScale = 1.0
        selectedNode = nil
        currentProjectPath = nil
        projectName = "Untitled Project"
        
        // Create a default node
        createDefaultNodes()
    }
    
    func createDefaultNodes() {
        var defaultNode = Node(
            name: "Example iPhone App",
            type: .iPhoneApp,
            position: CGPoint(x: 100, y: 100),
            code: "",
            framework: .swiftui
        )
        
        // Ensure main file exists
        let mainFile = defaultNode.getOrCreateMainFile()
        defaultNode.selectedFileId = mainFile.id
        
        nodes.append(defaultNode)
        
        // Immediately create the directory for the default node
        let nodeProjectPath = nodeProjectService.getProjectPath(for: defaultNode, projectName: projectName)
        do {
            try FileManager.default.createDirectory(at: nodeProjectPath, withIntermediateDirectories: true)
            // Update node with project path immediately
            if let index = nodes.firstIndex(where: { $0.id == defaultNode.id }) {
                nodes[index].projectPath = nodeProjectPath.path
            }
        } catch {
            print("Failed to create default node directory: \(error)")
        }
        
        // Initialize project for default node
        Task {
            await initializeNodeProject(node: defaultNode)
        }
    }
    
    func createNewNode() {
        var newNode = Node(
            name: "New Node \(nodes.count + 1)",
            type: .custom,
            position: CGPoint(
                x: 200 + CGFloat(nodes.count) * 50,
                y: 200 + CGFloat(nodes.count) * 50
            ),
            code: "",
            framework: .swift
        )
        
        // Get or create main file
        let mainFile = newNode.getOrCreateMainFile()
        newNode.selectedFileId = mainFile.id
        
        nodes.append(newNode)
        selectedNode = newNode
        
        // Immediately create the directory for the node
        let nodeProjectPath = nodeProjectService.getProjectPath(for: newNode, projectName: projectName)
        do {
            try FileManager.default.createDirectory(at: nodeProjectPath, withIntermediateDirectories: true)
            // Update node with project path immediately
            if let index = nodes.firstIndex(where: { $0.id == newNode.id }) {
                nodes[index].projectPath = nodeProjectPath.path
                selectedNode = nodes[index]
            }
        } catch {
            print("Failed to create node directory: \(error)")
        }
        
        // Create project structure for the node
        Task {
            await initializeNodeProject(node: newNode)
        }
    }
    
            private func initializeNodeProject(node: Node) async {
                do {
                    // Create project structure (can be done off main thread)
                    try await nodeProjectService.createProjectStructure(for: node, projectName: projectName)
                    
                    // Get project path
                    let projectPath = nodeProjectService.getProjectPath(for: node, projectName: projectName)
            
            // If it's a Python framework, create its virtual environment
            if node.framework.needsEnvironment && [.django, .flask, .fastapi, .purepy].contains(node.framework) {
                await pythonBridge.ensureVirtualEnvironment(for: node)
            }
            
            // CRITICAL: All @Published property mutations must happen on main thread
            await MainActor.run {
                // Ensure node has a main file
                if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                    let mainFile = nodes[index].getOrCreateMainFile()
                    if nodes[index].selectedFileId == nil {
                        nodes[index].selectedFileId = mainFile.id
                    }
                    
                    // Update project path
                    nodes[index].projectPath = projectPath.path
                    
                    // Update selected node if it's the one we're working with
                    if selectedNode?.id == node.id {
                        selectedNode = nodes[index]
                    }
                }
            }
        } catch {
            print("Failed to create project structure for node \(node.name): \(error)")
        }
    }
    
    func updateNode(_ node: Node) {
        // CRITICAL: This must run on main thread since it mutates @Published properties
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        
        let oldFramework = nodes[index].framework
        let oldProjectPath = nodes[index].projectPath
        
        nodes[index] = node
        
        // Ensure main file exists when framework changes
        if oldFramework != node.framework {
            let mainFile = nodes[index].getOrCreateMainFile()
            if nodes[index].selectedFileId == nil {
                nodes[index].selectedFileId = mainFile.id
            }
        }
        
        // Ensure project structure exists
        if node.projectPath == nil || oldProjectPath != node.projectPath {
            Task {
                await initializeNodeProject(node: nodes[index])
            }
        } else {
            // Save all files to project
                    Task {
                        do {
                            try await nodeProjectService.saveAllFiles(node: nodes[index], projectPath: nodeProjectService.getProjectPath(for: nodes[index], projectName: projectName))
                        } catch {
                            print("Failed to save files: \(error)")
                        }
                    }
        }
        
        // If framework changed to Python-based, ensure virtual environment exists
        let pythonFrameworks: [Framework] = [.django, .flask, .fastapi, .purepy]
        if pythonFrameworks.contains(node.framework) && !pythonFrameworks.contains(oldFramework) {
            Task {
                await pythonBridge.ensureVirtualEnvironment(for: nodes[index])
            }
        }
        
        // If requirements changed, update the environment
        if pythonFrameworks.contains(node.framework) && node.pythonRequirements != nodes[index].pythonRequirements {
            Task {
                await pythonBridge.updatePythonRequirements(for: nodes[index])
            }
        }
        
        if selectedNode?.id == node.id {
            selectedNode = nodes[index]
        }
    }
    
    func openNodeProjectInFinder(_ node: Node) {
        nodeProjectService.openProjectInFinder(for: node, projectName: projectName)
    }
    
    /// Save the currently selected node's files to the nodes array
    func saveCurrentNodeFiles() {
        guard let selectedNode = selectedNode,
              let index = nodes.firstIndex(where: { $0.id == selectedNode.id }) else {
            return
        }
        
        // Update the node in the array with the current selectedNode's state
        // This ensures any changes in selectedNode are persisted to the array
        nodes[index] = selectedNode
        
        // Also ensure selectedNode is updated from array (in case array has newer data)
        self.selectedNode = nodes[index]
        
        // Save files to disk
        Task {
            do {
                let projectPath = nodeProjectService.getProjectPath(for: nodes[index], projectName: projectName)
                try await nodeProjectService.saveAllFiles(node: nodes[index], projectPath: projectPath)
            } catch {
                print("Failed to save node files: \(error)")
            }
        }
    }
    
    /// Force save current node by getting latest content from editor
    func forceSaveCurrentNode() {
        saveCurrentNodeFiles()
    }
    
    
    func deleteNode(_ node: Node) {
        nodes.removeAll { $0.id == node.id }
        // Remove connections to this node
        for i in nodes.indices {
            nodes[i].connections.removeAll { $0 == node.id }
        }
        if selectedNode?.id == node.id {
            selectedNode = nil
        }
    }
    
    func connectNodes(from sourceId: UUID, to targetId: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == sourceId }) else { return }
        if !nodes[index].connections.contains(targetId) {
            nodes[index].connections.append(targetId)
        }
    }
    
    func disconnectNodes(from sourceId: UUID, to targetId: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == sourceId }) else { return }
        nodes[index].connections.removeAll { $0 == targetId }
    }
    
    func startConnection(from nodeId: UUID) {
        connectingFromNodeId = nodeId
    }
    
    func endConnection() {
        connectingFromNodeId = nil
    }
    
    func hoverConnectionPoint(nodeId: UUID?, isOutput: Bool) {
        if let nodeId = nodeId {
            hoveredConnectionPoint = (nodeId, isOutput)
        } else {
            hoveredConnectionPoint = nil
        }
    }
    
    // Generation actions
    func generateiPhoneApp() {
        guard let selected = selectedNode else {
            print("No node selected for iPhone app generation")
            return
        }
        
        Task {
            await pythonBridge.generateiPhoneApp(node: selected)
        }
    }
    
    func generateWebsite() {
        guard let selected = selectedNode else {
            print("No node selected for website generation")
            return
        }
        
        Task {
            await pythonBridge.generateWebsite(node: selected)
        }
    }
    
    func deployBackendToAWS() {
        guard let selected = selectedNode else {
            print("No node selected for AWS deployment")
            return
        }
        
        Task {
            await pythonBridge.deployToAWS(node: selected)
        }
    }
}

