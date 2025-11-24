import Foundation
import SwiftUI
import Combine
import AppKit
import WebKit

class ProjectManager: ObservableObject {
    @Published var nodes: [Node] = []
    @Published var selectedNode: Node?
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var connectingFromNodeId: UUID?
    @Published var hoveredConnectionPoint: (nodeId: UUID, isOutput: Bool)?
    
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
    
    func saveProject(to url: URL) throws {
        let project = PioneerProject(
            nodes: nodes,
            canvasOffset: canvasOffset,
            canvasScale: canvasScale
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url)
        
        currentProjectPath = url
        projectName = url.deletingPathExtension().lastPathComponent
    }
    
    func loadProject(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let project = try decoder.decode(PioneerProject.self, from: data)
        
        nodes = project.nodes
        canvasOffset = project.canvasOffset
        canvasScale = project.canvasScale
        currentProjectPath = url
        projectName = url.deletingPathExtension().lastPathComponent
        
        // Initialize projects for all loaded nodes
        Task {
            for node in nodes {
                await initializeNodeProject(node: node)
            }
        }
    }
    
    func saveProjectAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "code")!]
        savePanel.nameFieldStringValue = projectName
        savePanel.title = "Save Pioneer Project"
        savePanel.prompt = "Save"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self.saveProject(to: url)
                } catch {
                    print("Failed to save project: \(error)")
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
            language: .swift
        )
        
        // Ensure main file exists
        let mainFile = defaultNode.getOrCreateMainFile()
        defaultNode.selectedFileId = mainFile.id
        
        nodes.append(defaultNode)
        
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
            language: .swift
        )
        
        // Get or create main file
        let mainFile = newNode.getOrCreateMainFile()
        newNode.selectedFileId = mainFile.id
        
        nodes.append(newNode)
        selectedNode = newNode
        
        // Create project structure for the node
        Task {
            await initializeNodeProject(node: newNode)
        }
    }
    
    private func initializeNodeProject(node: Node) async {
        do {
            // Ensure node has a main file
            if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                let mainFile = nodes[index].getOrCreateMainFile()
                if nodes[index].selectedFileId == nil {
                    nodes[index].selectedFileId = mainFile.id
                }
                
                // Create project structure
                try await nodeProjectService.createProjectStructure(for: nodes[index])
                
                // Get project path and update node
                let projectPath = nodeProjectService.getProjectPath(for: nodes[index])
                nodes[index].projectPath = projectPath.path
                
                // If it's a Python node, create its virtual environment
                if nodes[index].language == .python {
                    await pythonBridge.ensureVirtualEnvironment(for: nodes[index])
                }
                
                // Update selected node if it's the one we're working with
                if selectedNode?.id == node.id {
                    selectedNode = nodes[index]
                }
            }
        } catch {
            print("Failed to create project structure for node \(node.name): \(error)")
        }
    }
    
    func updateNode(_ node: Node) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            let oldLanguage = nodes[index].language
            let oldProjectPath = nodes[index].projectPath
            
            nodes[index] = node
            
            // Ensure main file exists when language changes
            if oldLanguage != node.language {
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
                        try await nodeProjectService.saveAllFiles(node: nodes[index], projectPath: nodeProjectService.getProjectPath(for: nodes[index]))
                    } catch {
                        print("Failed to save files: \(error)")
                    }
                }
            }
            
            // If language changed to Python, ensure virtual environment exists
            if node.language == .python && oldLanguage != .python {
                Task {
                    await pythonBridge.ensureVirtualEnvironment(for: nodes[index])
                }
            }
            
            // If requirements changed, update the environment
            if node.language == .python && node.pythonRequirements != nodes[index].pythonRequirements {
                Task {
                    await pythonBridge.updatePythonRequirements(for: nodes[index])
                }
            }
            
            if selectedNode?.id == node.id {
                selectedNode = nodes[index]
            }
        }
    }
    
    func openNodeProjectInFinder(_ node: Node) {
        nodeProjectService.openProjectInFinder(for: node)
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
                let projectPath = nodeProjectService.getProjectPath(for: nodes[index])
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
    
    /// Save current node's content from Monaco editor before switching
    /// This gets the latest content from the editor and saves it immediately
    func saveCurrentNodeFromEditor(webView: WKWebView?, completion: @escaping () -> Void) {
        guard let selectedNode = selectedNode,
              let index = nodes.firstIndex(where: { $0.id == selectedNode.id }),
              let fileId = selectedNode.selectedFileId,
              let webView = webView else {
            completion()
            return
        }
        
        // Get current content from Monaco editor
        let script = """
        if (window.monacoEditor) {
            window.monacoEditor.getValue();
        } else {
            "";
        }
        """
        
        webView.evaluateJavaScript(script) { result, error in
            let content = (result as? String) ?? ""
            
            // Update node with current Monaco content
            if let fileIndex = self.nodes[index].files.firstIndex(where: { $0.id == fileId }) {
                self.nodes[index].files[fileIndex].content = content
                if fileIndex == 0 {
                    self.nodes[index].code = content
                }
            }
            
            // Update selectedNode
            self.selectedNode = self.nodes[index]
            
            // Save to disk immediately
            Task {
                do {
                    let projectPath = self.nodeProjectService.getProjectPath(for: self.nodes[index])
                    try await self.nodeProjectService.saveAllFiles(node: self.nodes[index], projectPath: projectPath)
                    print("✅ Saved node \(self.nodes[index].name) before switching")
                } catch {
                    print("❌ Failed to save node files: \(error)")
                }
                completion()
            }
        }
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

