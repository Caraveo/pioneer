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
                set: { id in
                    if let id = id {
                        projectManager.selectedNode = projectManager.nodes.first { $0.id == id }
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
    
    var body: some View {
        HStack {
            Image(systemName: node.type.icon)
                .foregroundColor(node.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                Text(node.type.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !node.connections.isEmpty {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete") {
                projectManager.deleteNode(node)
            }
        }
    }
}

