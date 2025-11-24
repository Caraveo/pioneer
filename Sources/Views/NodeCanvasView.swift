import SwiftUI

struct NodeCanvasView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var draggedNodeId: UUID?
    @State private var initialDragPosition: CGPoint = .zero
    @State private var isPanning: Bool = false
    @State private var initialPanOffset: CGSize = .zero
    @State private var connectingToPoint: CGPoint?
    @State private var hoveredNodeId: UUID?
    @State private var mouseLocation: CGPoint = .zero
    @State private var aiPrompt: String = ""
    @State private var showAIResponse: Bool = false
    @State private var aiResponseMessage: String = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                }
                
                // Nodes and connections
                ZStack {
                    // Draw active connection being created
                    if let connectingFromId = projectManager.connectingFromNodeId,
                       let fromNode = projectManager.nodes.first(where: { $0.id == connectingFromId }) {
                        let fromPoint = getConnectionPoint(for: fromNode, isOutput: true)
                        // Use mouse location or hovered connection point
                        let toPoint = connectingToPoint ?? mouseLocation
                        ConnectionView(
                            from: fromPoint,
                            to: toPoint,
                            color: fromNode.type.color,
                            isTemporary: true
                        )
                    }
                    
                    // Draw connections first (behind nodes)
                    ForEach(projectManager.nodes) { node in
                        ForEach(node.connections, id: \.self) { targetId in
                            if let targetNode = projectManager.nodes.first(where: { $0.id == targetId }) {
                                ConnectionView(
                                    from: getConnectionPoint(for: node, isOutput: true),
                                    to: getConnectionPoint(for: targetNode, isOutput: false),
                                    color: node.type.color
                                )
                            }
                        }
                    }
                    
                    // Draw nodes
                    ForEach(projectManager.nodes) { node in
                        NodeView(
                            node: node,
                            hoveredConnectionPoint: projectManager.hoveredConnectionPoint
                        )
                            .position(
                                x: node.position.x + projectManager.canvasOffset.width,
                                y: node.position.y + projectManager.canvasOffset.height
                            )
                            .scaleEffect(projectManager.canvasScale)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                                            if !isDragging || draggedNodeId != node.id {
                                                // Start of drag - store initial position
                                                isDragging = true
                                                draggedNodeId = node.id
                                                initialDragPosition = node.position
                                            }
                                            
                                            // Calculate new position based on initial position and translation
                                            // Divide by canvas scale to account for zoom level
                                            let newX = initialDragPosition.x + (value.translation.width / projectManager.canvasScale)
                                            let newY = initialDragPosition.y + (value.translation.height / projectManager.canvasScale)
                                            
                                            projectManager.nodes[index].position = CGPoint(x: newX, y: newY)
                                        }
                                    }
                                    .onEnded { _ in
                                        if draggedNodeId == node.id {
                                            isDragging = false
                                            draggedNodeId = nil
                                            initialDragPosition = .zero
                                        }
                                    }
                            )
                            .onTapGesture {
                                projectManager.selectedNode = node
                            }
                            .onHover { hovering in
                                hoveredNodeId = hovering ? node.id : nil
                            }
                    }
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        projectManager.canvasScale = max(0.5, min(2.0, value))
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 5)
                    .modifiers(.command)
                    .onChanged { value in
                        // Only pan if not dragging a node and not connecting
                        if !isDragging && projectManager.connectingFromNodeId == nil {
                            if !isPanning {
                                isPanning = true
                                initialPanOffset = projectManager.canvasOffset
                            }
                            
                            // Calculate new offset based on initial offset and translation
                            projectManager.canvasOffset = CGSize(
                                width: initialPanOffset.width + value.translation.width,
                                height: initialPanOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        isPanning = false
                        initialPanOffset = .zero
                    }
            )
            .background(
                // Track mouse location for connection preview
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if projectManager.connectingFromNodeId != nil {
                                        // Convert to canvas coordinates
                                        mouseLocation = CGPoint(
                                            x: value.location.x - projectManager.canvasOffset.width,
                                            y: value.location.y - projectManager.canvasOffset.height
                                        )
                                    }
                                }
                        )
                }
            )
            
            // AI Prompt Input at the bottom
            VStack(spacing: 0) {
                Spacer()
                
                // AI Response Bubble
                if showAIResponse {
                    AIResponseBubble(message: aiResponseMessage) {
                        withAnimation {
                            showAIResponse = false
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                }
                
                // AI Prompt Input
                AIPromptInput(
                    prompt: $aiPrompt,
                    aiService: projectManager.aiService,
                    isProcessing: projectManager.aiService.isProcessing,
                    onSubmit: {
                        handleAIPrompt()
                    }
                )
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func handleAIPrompt() {
        guard !aiPrompt.isEmpty else { return }
        guard let selectedNode = projectManager.selectedNode else {
            // Show error - no node selected
            withAnimation {
                aiResponseMessage = "Please select a node first to generate code for it."
                showAIResponse = true
            }
            return
        }
        
        Task {
            // Get connected nodes
            let connectedNodeIds = selectedNode.connections
            let connectedNodes = projectManager.nodes.filter { connectedNodeIds.contains($0.id) }
            
            if let generatedCode = await projectManager.aiService.generateCode(
                prompt: aiPrompt,
                language: selectedNode.language,
                nodeContext: selectedNode,
                connectedNodes: connectedNodes,
                allNodes: projectManager.nodes
            ) {
                // Extract only the code (remove markdown if present)
                let codeOnly = extractCodeFromResponse(generatedCode)
                
                // Update the selected node's code
                if let index = projectManager.nodes.firstIndex(where: { $0.id == selectedNode.id }) {
                    projectManager.nodes[index].code = codeOnly
                    projectManager.selectedNode = projectManager.nodes[index]
                }
                
                // Show success message
                await MainActor.run {
                    withAnimation {
                        aiResponseMessage = "Code generated and added to \(selectedNode.name)"
                        showAIResponse = true
                        aiPrompt = "" // Clear prompt
                    }
                }
            } else {
                await MainActor.run {
                    withAnimation {
                        aiResponseMessage = "Failed to generate code. Please try again."
                        showAIResponse = true
                    }
                }
            }
        }
    }
    
    private func extractCodeFromResponse(_ response: String) -> String {
        // Remove markdown code blocks if present
        var code = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ```language blocks
        if code.hasPrefix("```") {
            let lines = code.components(separatedBy: .newlines)
            var codeLines: [String] = []
            var inCodeBlock = false
            
            for line in lines {
                if line.hasPrefix("```") {
                    inCodeBlock = !inCodeBlock
                    continue
                }
                if inCodeBlock || !code.hasPrefix("```") {
                    codeLines.append(line)
                }
            }
            code = codeLines.joined(separator: "\n")
        }
        
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridSize: CGFloat = 20
        let offset = projectManager.canvasOffset
        
        context.stroke(
            Path { path in
                for x in stride(from: 0, through: size.width, by: gridSize) {
                    path.move(to: CGPoint(x: x + offset.width, y: 0))
                    path.addLine(to: CGPoint(x: x + offset.width, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: gridSize) {
                    path.move(to: CGPoint(x: 0, y: y + offset.height))
                    path.addLine(to: CGPoint(x: size.width, y: y + offset.height))
                }
            },
            with: .color(.secondary.opacity(0.2)),
            lineWidth: 0.5
        )
    }
    
    private func getConnectionPoint(for node: Node, isOutput: Bool) -> CGPoint {
        let nodeWidth: CGFloat = 200
        let connectionY = node.position.y + 140 // Bottom of node
        let x = isOutput ? node.position.x + nodeWidth - 20 : node.position.x + 20
        return CGPoint(x: x, y: connectionY)
    }
}

struct NodeView: View {
    let node: Node
    let hoveredConnectionPoint: (nodeId: UUID, isOutput: Bool)?
    @EnvironmentObject var projectManager: ProjectManager
    
    var isSelected: Bool {
        projectManager.selectedNode?.id == node.id
    }
    
    var hasInputConnections: Bool {
        projectManager.nodes.contains { $0.connections.contains(node.id) }
    }
    
    var hasOutputConnections: Bool {
        !node.connections.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: node.type.icon)
                    .foregroundColor(node.type.color)
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            Divider()
            
            // Content preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: node.language == .swift ? "swift" : "python")
                        .font(.system(size: 10))
                    Text(node.language.rawValue)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                
                if !node.code.isEmpty {
                    Text(node.code.prefix(50) + (node.code.count > 50 ? "..." : ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 8)
            
            // Connection points
            HStack {
                // Input connection point (left side)
                ConnectionPointView(
                    node: node,
                    isOutput: false,
                    isConnected: hasInputConnections,
                    isHovered: hoveredConnectionPoint?.nodeId == node.id && hoveredConnectionPoint?.isOutput == false,
                    color: node.type.color
                )
                
                Spacer()
                
                // Output connection point (right side)
                ConnectionPointView(
                    node: node,
                    isOutput: true,
                    isConnected: hasOutputConnections,
                    isHovered: hoveredConnectionPoint?.nodeId == node.id && hoveredConnectionPoint?.isOutput == true,
                    color: node.type.color
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: isSelected ? 4 : 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? node.type.color : Color.clear, lineWidth: 2)
        )
    }
}

struct ConnectionPointView: View {
    let node: Node
    let isOutput: Bool
    let isConnected: Bool
    let isHovered: Bool
    let color: Color
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isDragging: Bool = false
    
    var isConnecting: Bool {
        projectManager.connectingFromNodeId != nil
    }
    
    var body: some View {
        Circle()
            .fill(isConnected ? color : Color.clear)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(isConnected ? color : color.opacity(0.5), lineWidth: isHovered ? 3 : 2)
            )
            .scaleEffect(isHovered ? 1.3 : 1.0)
            .animation(.spring(response: 0.2), value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !isDragging && isOutput {
                            isDragging = true
                            projectManager.startConnection(from: node.id)
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        // Connection will be completed on tap of input point
                        // Or cancel if not connected
                        if projectManager.connectingFromNodeId == node.id {
                            // Check if we're over an input point
                            // This would be handled by the canvas detecting the drop
                        }
                    }
            )
            .onTapGesture {
                if !isOutput && isConnecting {
                    // Complete connection to this input
                    if let connectingFrom = projectManager.connectingFromNodeId, connectingFrom != node.id {
                        projectManager.connectNodes(from: connectingFrom, to: node.id)
                        projectManager.endConnection()
                    } else {
                        // Cancel connection if clicking same node
                        projectManager.endConnection()
                    }
                } else if isOutput && !isConnecting {
                    // Start new connection from output
                    projectManager.startConnection(from: node.id)
                } else if isOutput && isConnecting && projectManager.connectingFromNodeId == node.id {
                    // Cancel connection if clicking output again
                    projectManager.endConnection()
                }
            }
            .contextMenu {
                if isConnected {
                    Button("Disconnect") {
                        if isOutput {
                            // Remove all connections from this node
                            if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                                projectManager.nodes[index].connections.removeAll()
                            }
                        } else {
                            // Remove connections to this node
                            for i in projectManager.nodes.indices {
                                projectManager.nodes[i].connections.removeAll { $0 == node.id }
                            }
                        }
                    }
                }
            }
            .onHover { hovering in
                if hovering {
                    projectManager.hoverConnectionPoint(nodeId: node.id, isOutput: isOutput)
                } else if projectManager.hoveredConnectionPoint?.nodeId == node.id {
                    projectManager.hoverConnectionPoint(nodeId: nil, isOutput: false)
                }
            }
    }
}

struct ConnectionView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var isTemporary: Bool = false
    
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        Path { path in
            let adjustedFrom = CGPoint(
                x: from.x + projectManager.canvasOffset.width,
                y: from.y + projectManager.canvasOffset.height
            )
            let adjustedTo = CGPoint(
                x: to.x + projectManager.canvasOffset.width,
                y: to.y + projectManager.canvasOffset.height
            )
            
            path.move(to: adjustedFrom)
            
            // Bezier curve for connection
            let controlPoint1 = CGPoint(
                x: adjustedFrom.x + (adjustedTo.x - adjustedFrom.x) * 0.5,
                y: adjustedFrom.y
            )
            let controlPoint2 = CGPoint(
                x: adjustedTo.x - (adjustedTo.x - adjustedFrom.x) * 0.5,
                y: adjustedTo.y
            )
            
            path.addCurve(
                to: adjustedTo,
                control1: controlPoint1,
                control2: controlPoint2
            )
        }
        .stroke(
            isTemporary ? color.opacity(0.4) : color.opacity(0.6),
            style: StrokeStyle(
                lineWidth: isTemporary ? 2 : 2,
                lineCap: .round,
                dash: isTemporary ? [5, 5] : []
            )
        )
    }
}

