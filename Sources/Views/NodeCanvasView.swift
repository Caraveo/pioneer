import SwiftUI

struct NodeCanvasView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var draggedNodeId: UUID?
    @State private var initialDragPosition: CGPoint = .zero
    @State private var isPanning: Bool = false
    @State private var initialPanOffset: CGSize = .zero
    @State private var connectingFrom: UUID?
    @State private var hoveredNodeId: UUID?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                }
                
                // Nodes and connections
                ZStack {
                    // Draw connections first (behind nodes)
                    ForEach(projectManager.nodes) { node in
                        ForEach(node.connections, id: \.self) { targetId in
                            if let targetNode = projectManager.nodes.first(where: { $0.id == targetId }) {
                                ConnectionView(
                                    from: node.position,
                                    to: targetNode.position,
                                    color: node.type.color
                                )
                            }
                        }
                    }
                    
                    // Draw nodes
                    ForEach(projectManager.nodes) { node in
                        NodeView(node: node)
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
                        // Only pan if not dragging a node
                        if !isDragging {
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
        }
        .background(Color(NSColor.textBackgroundColor))
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
}

struct NodeView: View {
    let node: Node
    @EnvironmentObject var projectManager: ProjectManager
    
    var isSelected: Bool {
        projectManager.selectedNode?.id == node.id
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
                Circle()
                    .fill(node.type.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                
                Spacer()
                
                if !node.connections.isEmpty {
                    Circle()
                        .fill(node.type.color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
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

struct ConnectionView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    
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
        .stroke(color.opacity(0.6), lineWidth: 2)
    }
}

