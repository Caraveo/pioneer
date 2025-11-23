import SwiftUI
import AppKit

struct CodeEditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var editorText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if let node = projectManager.selectedNode {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: node.type.icon)
                            .foregroundColor(node.type.color)
                        Text(node.name)
                            .font(.headline)
                        
                        Spacer()
                        
                        Picker("Language", selection: Binding(
                            get: { node.language },
                            set: { newLanguage in
                                if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                                    projectManager.nodes[index].language = newLanguage
                                    projectManager.selectedNode = projectManager.nodes[index]
                                }
                            }
                        )) {
                            ForEach(CodeLanguage.allCases, id: \.self) { language in
                                Text(language.rawValue).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    Text(node.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Code editor
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextEditor(text: Binding(
                            get: {
                                projectManager.selectedNode?.code ?? ""
                            },
                            set: { newValue in
                                if let node = projectManager.selectedNode,
                                   let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                                    projectManager.nodes[index].code = newValue
                                    projectManager.selectedNode = projectManager.nodes[index]
                                }
                            }
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 400)
                        .padding(8)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Node Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select a node from the sidebar or canvas to edit its code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }
}

