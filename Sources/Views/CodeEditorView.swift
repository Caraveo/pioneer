import SwiftUI
import AppKit

struct CodeEditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var editorText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // File browser
            if let node = projectManager.selectedNode {
                FileBrowserView(
                    selectedFileId: Binding(
                        get: { node.selectedFileId },
                        set: { newId in
                            if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                                projectManager.nodes[index].selectedFileId = newId
                                projectManager.selectedNode = projectManager.nodes[index]
                            }
                        }
                    ),
                    node: node
                )
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                if let node = projectManager.selectedNode {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: node.type.icon)
                                .foregroundColor(node.type.color)
                            Text(node.selectedFile?.name ?? node.name)
                                .font(.headline)
                            
                            if let selectedFile = node.selectedFile {
                                Text(selectedFile.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("Language", selection: Binding(
                                get: { node.selectedFile?.language ?? node.language },
                                set: { newLanguage in
                                    if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                                       let fileId = node.selectedFileId,
                                       let fileIndex = projectManager.nodes[index].files.firstIndex(where: { $0.id == fileId }) {
                                        projectManager.nodes[index].files[fileIndex].language = newLanguage
                                        projectManager.selectedNode = projectManager.nodes[index]
                                    }
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
                            .frame(width: 150)
                            
                            Button(action: {
                                projectManager.openNodeProjectInFinder(node)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("Open Project")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderless)
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
                    
                    // Code editor with Monaco Editor (VSCode's editor)
                    if let selectedFile = node.selectedFile {
                        MonacoEditorView(
                            text: Binding(
                                get: {
                                    selectedFile.content
                                },
                                set: { newValue in
                                    if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                                       let fileId = node.selectedFileId,
                                       let fileIndex = projectManager.nodes[index].files.firstIndex(where: { $0.id == fileId }) {
                                        projectManager.nodes[index].files[fileIndex].content = newValue
                                        // Also update main code for backward compatibility
                                        if fileIndex == 0 {
                                            projectManager.nodes[index].code = newValue
                                        }
                                        projectManager.selectedNode = projectManager.nodes[index]
                                        
                                        // Save to project file
                                        Task {
                                            await saveFileToProject(node: projectManager.nodes[index], file: projectManager.nodes[index].files[fileIndex])
                                        }
                                    }
                                }
                            ),
                            language: selectedFile.language
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                    } else {
                        VStack {
                            Spacer()
                            Text("No file selected")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Select a file from the browser or add a new file")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                    }
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
    
    private func saveFileToProject(node: Node, file: ProjectFile) async {
        guard let projectPath = node.projectPath,
              let url = URL(string: projectPath) else {
            return
        }
        
        let fileURL = url.appendingPathComponent(file.path)
        let directory = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save file \(file.path): \(error)")
        }
    }
}

