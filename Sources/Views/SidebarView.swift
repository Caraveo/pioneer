import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Nodes")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Spacer()
                Button(action: {
                    projectManager.createNewNode()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Node list
            List(selection: Binding(
                get: { projectManager.selectedNode?.id },
                set: { newId in
                    // Get webView for current node before switching
                    if let currentNode = projectManager.selectedNode,
                       currentNode.selectedFileId != nil {
                        // Access webViewStore through a notification or callback
                        // For now, save immediately from nodes array
                        projectManager.saveCurrentNodeFiles()
                    }
                    
                    // Switch after brief delay to allow save
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let newId = newId {
                            if let index = projectManager.nodes.firstIndex(where: { $0.id == newId }) {
                                projectManager.selectedNode = projectManager.nodes[index]
                            }
                        }
                    }
                }
            )) {
                ForEach(projectManager.nodes) { node in
                    NodeRowView(node: node)
                        .tag(node.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct NodeRowView: View {
    let node: Node
    @EnvironmentObject var projectManager: ProjectManager
    
    // Get the current node from projectManager to ensure we always show the latest name
    private var currentNode: Node? {
        projectManager.nodes.first(where: { $0.id == node.id })
    }
    
    var body: some View {
        // Use currentNode if available, otherwise fallback to passed node
        let displayNode = currentNode ?? node
        
        return HStack {
            Image(systemName: displayNode.type.icon)
                .foregroundColor(displayNode.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayNode.name)
                    .font(.system(size: 13, weight: .medium))
                Text(displayNode.type.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !displayNode.connections.isEmpty {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete") {
                if let nodeToDelete = currentNode {
                    projectManager.deleteNode(nodeToDelete)
                } else {
                    projectManager.deleteNode(node)
                }
            }
        }
    }
}


