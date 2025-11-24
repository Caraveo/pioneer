import SwiftUI
import AppKit
import WebKit

struct CodeEditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var editorText: String = ""
    @State private var isEditing: Bool = false
    @State private var monacoWebView: WKWebView?
    
    var body: some View {
        HStack(spacing: 0) {
            // File browser
            if let node = projectManager.selectedNode,
               let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                FileBrowserView(
                    selectedFileId: Binding(
                        get: { projectManager.nodes[nodeIndex].selectedFileId },
                        set: { newId in
                            projectManager.saveCurrentNodeFiles()
                            projectManager.nodes[nodeIndex].selectedFileId = newId
                            projectManager.selectedNode = projectManager.nodes[nodeIndex]
                        }
                    ),
                    node: projectManager.nodes[nodeIndex]
                )
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                if let node = projectManager.selectedNode,
                   let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
                    let currentNode = projectManager.nodes[nodeIndex]
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
                                get: { currentNode.selectedFile?.language ?? currentNode.language },
                                set: { newLanguage in
                                    projectManager.saveCurrentNodeFiles()
                                    if let fileId = currentNode.selectedFileId,
                                       let fileIndex = projectManager.nodes[nodeIndex].files.firstIndex(where: { $0.id == fileId }) {
                                        projectManager.nodes[nodeIndex].files[fileIndex].language = newLanguage
                                        projectManager.selectedNode = projectManager.nodes[nodeIndex]
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
                    
                    // Code editor with Monaco Editor (VSCode's editor)
                    if let selectedFile = currentNode.selectedFile {
                        MonacoEditorView(
                            text: Binding(
                                get: {
                                    // Always get from the nodes array to ensure we have latest
                                    if let fileId = currentNode.selectedFileId,
                                       let file = projectManager.nodes[nodeIndex].files.first(where: { $0.id == fileId }) {
                                        return file.content
                                    }
                                    return selectedFile.content
                                },
                                set: { newValue in
                                    // Update both the nodes array and selectedNode
                                    if let fileId = currentNode.selectedFileId,
                                       let fileIndex = projectManager.nodes[nodeIndex].files.firstIndex(where: { $0.id == fileId }) {
                                        // Update in nodes array
                                        projectManager.nodes[nodeIndex].files[fileIndex].content = newValue
                                        
                                        // Also update main code for backward compatibility
                                        if fileIndex == 0 {
                                            projectManager.nodes[nodeIndex].code = newValue
                                        }
                                        
                                        // Update selectedNode to match
                                        projectManager.selectedNode = projectManager.nodes[nodeIndex]
                                        
                                        // Save to project file
                                        Task {
                                            await saveFileToProject(node: projectManager.nodes[nodeIndex], file: projectManager.nodes[nodeIndex].files[fileIndex])
                                        }
                                    }
                                }
                            ),
                            language: selectedFile.language,
                            onWebViewReady: { webView in
                                monacoWebView = webView
                            }
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                        .onChange(of: projectManager.selectedNode?.id) { oldId in
                            // Before switching, get current content from Monaco and save
                            if let oldId = oldId,
                               let oldNodeIndex = projectManager.nodes.firstIndex(where: { $0.id == oldId }),
                               let webView = monacoWebView {
                                Task {
                                    // Get current content from Monaco editor
                                    let script = """
                                    if (window.monacoEditor) {
                                        window.monacoEditor.getValue();
                                    } else {
                                        "";
                                    }
                                    """
                                    
                                    if let content = await withCheckedContinuation({ continuation in
                                        webView.evaluateJavaScript(script) { result, error in
                                            continuation.resume(returning: result as? String)
                                        }
                                    }) {
                                        // Update node with current Monaco content
                                        if let fileId = projectManager.nodes[oldNodeIndex].selectedFileId,
                                           let fileIndex = projectManager.nodes[oldNodeIndex].files.firstIndex(where: { $0.id == fileId }) {
                                            projectManager.nodes[oldNodeIndex].files[fileIndex].content = content
                                            if fileIndex == 0 {
                                                projectManager.nodes[oldNodeIndex].code = content
                                            }
                                        }
                                        
                                        // Save files
                                        projectManager.saveCurrentNodeFiles()
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            // Save when editor disappears - get content from Monaco first
                            if let webView = monacoWebView {
                                Task {
                                    let script = """
                                    if (window.monacoEditor) {
                                        window.monacoEditor.getValue();
                                    } else {
                                        "";
                                    }
                                    """
                                    
                                    if let content = await withCheckedContinuation({ continuation in
                                        webView.evaluateJavaScript(script) { result, error in
                                            continuation.resume(returning: result as? String)
                                        }
                                    }),
                                       let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == currentNode.id }),
                                       let fileId = currentNode.selectedFileId,
                                       let fileIndex = projectManager.nodes[nodeIndex].files.firstIndex(where: { $0.id == fileId }) {
                                        projectManager.nodes[nodeIndex].files[fileIndex].content = content
                                        if fileIndex == 0 {
                                            projectManager.nodes[nodeIndex].code = content
                                        }
                                        projectManager.saveCurrentNodeFiles()
                                    }
                                }
                            }
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

