import Foundation
import SwiftUI
import Combine

class ProjectManager: ObservableObject {
    @Published var nodes: [Node] = []
    @Published var selectedNode: Node?
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var connectingFromNodeId: UUID?
    @Published var hoveredConnectionPoint: (nodeId: UUID, isOutput: Bool)?
    
    private let pythonBridge = PythonBridge()
    let aiService = AIService()
    
    init() {
        // Create a default node for demonstration
        createDefaultNodes()
    }
    
    func createDefaultNodes() {
        let defaultNode = Node(
            name: "Example iPhone App",
            type: .iPhoneApp,
            position: CGPoint(x: 100, y: 100),
            code: """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    VStack {
                        Text("Hello, Pioneer!")
                            .font(.largeTitle)
                    }
                    .padding()
                }
            }
            """,
            language: .swift
        )
        nodes.append(defaultNode)
    }
    
    func createNewNode() {
        let newNode = Node(
            name: "New Node \(nodes.count + 1)",
            type: .custom,
            position: CGPoint(
                x: 200 + CGFloat(nodes.count) * 50,
                y: 200 + CGFloat(nodes.count) * 50
            ),
            code: "",
            language: .swift
        )
        nodes.append(newNode)
        selectedNode = newNode
        
        // If it's a Python node, create its virtual environment
        if newNode.language == .python {
            Task {
                await pythonBridge.ensureVirtualEnvironment(for: newNode)
            }
        }
    }
    
    func updateNode(_ node: Node) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            let oldLanguage = nodes[index].language
            nodes[index] = node
            
            // If language changed to Python, ensure virtual environment exists
            if node.language == .python && oldLanguage != .python {
                Task {
                    await pythonBridge.ensureVirtualEnvironment(for: node)
                }
            }
            
            // If requirements changed, update the environment
            if node.language == .python && node.pythonRequirements != nodes[index].pythonRequirements {
                Task {
                    await pythonBridge.updatePythonRequirements(for: node)
                }
            }
            
            if selectedNode?.id == node.id {
                selectedNode = node
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

