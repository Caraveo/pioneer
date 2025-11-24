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
                        get: {
                            // Always look up node index fresh to avoid stale indices
                            guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                                  nodeIndex < projectManager.nodes.count else {
                                return nil
                            }
                            return projectManager.nodes[nodeIndex].selectedFileId
                        },
                        set: { newId in
                            projectManager.saveCurrentNodeFiles()
                            // Always look up node index fresh
                            guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                                  nodeIndex < projectManager.nodes.count else {
                                return
                            }
                            projectManager.nodes[nodeIndex].selectedFileId = newId
                            projectManager.selectedNode = projectManager.nodes[nodeIndex]
                        }
                    ),
                    node: {
                        // Always get fresh node from array
                        guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                              nodeIndex < projectManager.nodes.count else {
                            return node // Fallback to passed node
                        }
                        return projectManager.nodes[nodeIndex]
                    }()
                )
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                if let node = projectManager.selectedNode {
                    // Always get fresh node from array to avoid stale indices
                    let currentNode: Node = {
                        guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
                              nodeIndex < projectManager.nodes.count else {
                            return node // Fallback to passed node
                        }
                        return projectManager.nodes[nodeIndex]
                    }()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: currentNode.type.icon)
                                .foregroundColor(currentNode.type.color)
                            Text(currentNode.selectedFile?.name ?? currentNode.name)
                                .font(.headline)
                            
                            if let selectedFile = currentNode.selectedFile {
                                Text(selectedFile.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("Language", selection: Binding(
                                get: { currentNode.selectedFile?.language ?? currentNode.framework.primaryLanguage },
                                set: { newLanguage in
                                    projectManager.saveCurrentNodeFiles()
                                    // Always look up node index fresh
                                    guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == currentNode.id }),
                                          nodeIndex < projectManager.nodes.count,
                                          let fileId = currentNode.selectedFileId,
                                          let fileIndex = projectManager.nodes[nodeIndex].files.firstIndex(where: { $0.id == fileId }) else {
                                        return
                                    }
                                    projectManager.nodes[nodeIndex].files[fileIndex].language = newLanguage
                                    projectManager.selectedNode = projectManager.nodes[nodeIndex]
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
                                projectManager.openNodeProjectInFinder(currentNode)
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
                        
                        Text(currentNode.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // Code editor with pure Swift NSTextView
                    if let selectedFile = currentNode.selectedFile {
                        let editorKey = "\(currentNode.id.uuidString)-\(selectedFile.id.uuidString)"
                        
                        SwiftCodeEditorView(
                            text: Binding(
                                get: {
                                    // Always get from the CURRENT node's file - ensure isolation
                                    guard let currentNode = projectManager.selectedNode,
                                          let currentIndex = projectManager.nodes.firstIndex(where: { $0.id == currentNode.id }),
                                          let fileId = currentNode.selectedFileId,
                                          let file = projectManager.nodes[currentIndex].files.first(where: { $0.id == fileId }) else {
                                        return selectedFile.content
                                    }
                                    // Verify we're getting the right node's content
                                    if currentNode.id != projectManager.nodes[currentIndex].id {
                                        print("⚠️ WARNING: Node ID mismatch! Expected \(currentNode.id), got \(projectManager.nodes[currentIndex].id)")
                                    }
                                    return file.content
                                },
                                set: { newValue in
                                    // CRITICAL: Update ONLY the current node's file - ensure isolation
                                    guard let currentNode = projectManager.selectedNode,
                                          let currentIndex = projectManager.nodes.firstIndex(where: { $0.id == currentNode.id }),
                                          let fileId = currentNode.selectedFileId,
                                          let fileIndex = projectManager.nodes[currentIndex].files.firstIndex(where: { $0.id == fileId }) else {
                                        print("⚠️ ERROR: Cannot update - node or file not found")
                                        return
                                    }
                                    
                                    // Verify we're updating the right node
                                    if currentNode.id != projectManager.nodes[currentIndex].id {
                                        print("⚠️ WARNING: Updating wrong node! Expected \(currentNode.id), got \(projectManager.nodes[currentIndex].id)")
                                        return
                                    }
                                    
                                    // Update ONLY this node's file
                                    projectManager.nodes[currentIndex].files[fileIndex].content = newValue
                                    
                                    // Also update main code for backward compatibility
                                    if fileIndex == 0 {
                                        projectManager.nodes[currentIndex].code = newValue
                                    }
                                    
                                    // Update selectedNode to match
                                    projectManager.selectedNode = projectManager.nodes[currentIndex]
                                    
                                    // AUTO SAVE immediately to project file
                                    Task {
                                        await saveFileToProject(node: projectManager.nodes[currentIndex], file: projectManager.nodes[currentIndex].files[fileIndex])
                                    }
                                }
                            ),
                            language: selectedFile.language,
                            editorInstanceId: editorKey
                        )
                        .id(editorKey) // Unique ID per node+file - forces new instance
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                        .onChange(of: projectManager.selectedNode?.id) { _ in
                            // Save before switching nodes
                            projectManager.saveCurrentNodeFiles()
                        }
                        .onDisappear {
                            // Save when editor disappears
                            projectManager.saveCurrentNodeFiles()
                        }
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
        guard let projectPath = node.projectPath else {
            return
        }
        
        let url = URL(fileURLWithPath: projectPath)
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

