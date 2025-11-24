import SwiftUI

struct PropertyBarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Properties")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                if let selectedNode = projectManager.selectedNode {
                    Text(selectedNode.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else {
                    Text("No Node Selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Properties
            if let selectedNode = projectManager.selectedNode,
               let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == selectedNode.id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Node Type
                        PropertySection(title: "Node Type") {
                            Picker("Type", selection: Binding(
                                get: { projectManager.nodes[nodeIndex].type },
                                set: { newType in
                                    projectManager.nodes[nodeIndex].type = newType
                                    projectManager.selectedNode = projectManager.nodes[nodeIndex]
                                }
                            )) {
                                ForEach(NodeType.allCases) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Divider()
                        
                        // Language
                        PropertySection(title: "Language") {
                            Picker("Language", selection: Binding(
                                get: { projectManager.nodes[nodeIndex].language },
                                set: { newLanguage in
                                    projectManager.nodes[nodeIndex].language = newLanguage
                                    projectManager.updateNode(projectManager.nodes[nodeIndex])
                                }
                            )) {
                                ForEach(CodeLanguage.allCases, id: \.self) { language in
                                    HStack {
                                        Image(systemName: language.icon)
                                        Text(language.rawValue)
                                    }
                                    .tag(language)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Divider()
                        
                        // Position
                        PropertySection(title: "Position") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("X:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("X", value: Binding(
                                        get: { Double(projectManager.nodes[nodeIndex].position.x) },
                                        set: { newX in
                                            projectManager.nodes[nodeIndex].position.x = CGFloat(newX)
                                            projectManager.selectedNode = projectManager.nodes[nodeIndex]
                                        }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack {
                                    Text("Y:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("Y", value: Binding(
                                        get: { Double(projectManager.nodes[nodeIndex].position.y) },
                                        set: { newY in
                                            projectManager.nodes[nodeIndex].position.y = CGFloat(newY)
                                            projectManager.selectedNode = projectManager.nodes[nodeIndex]
                                        }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Connections
                        PropertySection(title: "Connections") {
                            VStack(alignment: .leading, spacing: 4) {
                                if selectedNode.connections.isEmpty {
                                    Text("No connections")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(selectedNode.connections, id: \.self) { connectionId in
                                        if let connectedNode = projectManager.nodes.first(where: { $0.id == connectionId }) {
                                            HStack {
                                                Image(systemName: connectedNode.type.icon)
                                                    .foregroundColor(connectedNode.type.color)
                                                Text(connectedNode.name)
                                                    .font(.caption)
                                                Spacer()
                                                Button(action: {
                                                    projectManager.disconnectNodes(from: selectedNode.id, to: connectionId)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Python Requirements (if Python node)
                        if selectedNode.language == .python {
                            Divider()
                            
                            PropertySection(title: "Python Requirements") {
                                TextEditor(text: Binding(
                                    get: { projectManager.nodes[nodeIndex].pythonRequirements },
                                    set: { newRequirements in
                                        projectManager.nodes[nodeIndex].pythonRequirements = newRequirements
                                        projectManager.updateNode(projectManager.nodes[nodeIndex])
                                    }
                                ))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 100)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                        
                        Divider()
                        
                        // Project Path
                        PropertySection(title: "Project Path") {
                            if let projectPath = selectedNode.projectPath {
                                Text(projectPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                
                                Button(action: {
                                    projectManager.openNodeProjectInFinder(selectedNode)
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text("Open in Finder")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Text("Not initialized")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Files
                        PropertySection(title: "Files") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(selectedNode.files) { file in
                                    HStack {
                                        Image(systemName: file.language.icon)
                                            .foregroundColor(file.language.color)
                                        Text(file.name)
                                            .font(.caption)
                                        Spacer()
                                        if file.id == selectedNode.selectedFileId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                                .font(.system(size: 10))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        projectManager.nodes[nodeIndex].selectedFileId = file.id
                                        projectManager.selectedNode = projectManager.nodes[nodeIndex]
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack {
                    Spacer()
                    Text("Select a node to view its properties")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }
}

struct PropertySection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            content
        }
    }
}

