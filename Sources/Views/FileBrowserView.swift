import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Binding var selectedFileId: UUID?
    
    let node: Node
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text("Files")
                    .font(.headline)
                Spacer()
                Button(action: {
                    addNewFile()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Add File")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // File list
            if node.files.isEmpty {
                VStack {
                    Spacer()
                    Text("No files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Click + to add a file")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(node.files) { file in
                            FileRowView(
                                file: file,
                                isSelected: selectedFileId == file.id,
                                onSelect: {
                                    selectFile(file.id)
                                },
                                onDelete: {
                                    deleteFile(file.id)
                                },
                                node: node
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func selectFile(_ fileId: UUID) {
        // Save current file before switching
        projectManager.saveCurrentNodeFiles()
        
        selectedFileId = fileId
        if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
            projectManager.nodes[index].selectedFileId = fileId
            projectManager.selectedNode = projectManager.nodes[index]
        }
    }
    
    private func addNewFile() {
        // Save current file before adding new one
        projectManager.saveCurrentNodeFiles()
        
        let newFile = ProjectFile(
            path: "new_file.\(node.framework.primaryLanguage.fileExtension)",
            name: "new_file.\(node.framework.primaryLanguage.fileExtension)",
            content: "",
            language: node.framework.primaryLanguage
        )
        
        if let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }) {
            projectManager.nodes[index].files.append(newFile)
            projectManager.nodes[index].selectedFileId = newFile.id
            projectManager.selectedNode = projectManager.nodes[index]
        }
    }
    
    private func deleteFile(_ fileId: UUID) {
        // Save current file before deleting
        projectManager.saveCurrentNodeFiles()
        
        guard let index = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
              index < projectManager.nodes.count,
              let fileToDelete = projectManager.nodes[index].files.first(where: { $0.id == fileId }) else {
            return
        }
        
        // Don't allow deleting the last file (must keep at least one)
        if projectManager.nodes[index].files.count <= 1 {
            // Create a new main file if trying to delete the last one
            let mainFile = projectManager.nodes[index].getOrCreateMainFile()
            if mainFile.id != fileId {
                // Only delete if it's not the main file
                // Remove the file from the array
                projectManager.nodes[index].files.removeAll { $0.id == fileId }
                
                // Delete from disk
                Task {
                    do {
                        try await projectManager.nodeProjectService.deleteFile(node: projectManager.nodes[index], file: fileToDelete)
                    } catch {
                        print("Failed to delete file from disk: \(error)")
                    }
                }
            }
        } else {
            // Remove the file from the array
            projectManager.nodes[index].files.removeAll { $0.id == fileId }
            
            // Delete from disk
            Task {
                do {
                    try await projectManager.nodeProjectService.deleteFile(node: projectManager.nodes[index], file: fileToDelete)
                } catch {
                    print("Failed to delete file from disk: \(error)")
                }
            }
        }
        
        // If deleted file was selected, select first file or none
        if projectManager.nodes[index].selectedFileId == fileId {
            projectManager.nodes[index].selectedFileId = projectManager.nodes[index].files.first?.id
        }
        
        // Update selected node
        projectManager.selectedNode = projectManager.nodes[index]
        
        // Ensure at least one file exists (main file)
        if projectManager.nodes[index].files.isEmpty {
            let mainFile = projectManager.nodes[index].getOrCreateMainFile()
            projectManager.nodes[index].files.append(mainFile)
            projectManager.nodes[index].selectedFileId = mainFile.id
            projectManager.selectedNode = projectManager.nodes[index]
        }
    }
}

struct FileRowView: View {
    let file: ProjectFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let node: Node
    @EnvironmentObject var projectManager: ProjectManager
    
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon(for: file.language))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            if isRenaming {
                TextField("File name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        finishRenaming()
                    }
                    .onAppear {
                        renameText = file.name
                    }
            } else {
                Text(file.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(count: 2) {
                        startRenaming()
                    }
            }
            
            Spacer()
            
            if !isRenaming {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1.0 : 0.0)
                .help("Delete file")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onChange(of: isRenaming) { newValue in
            if !newValue && !renameText.isEmpty && renameText != file.name {
                finishRenaming()
            }
        }
    }
    
    private func startRenaming() {
        renameText = file.name
        isRenaming = true
    }
    
    private func finishRenaming() {
        guard let nodeIndex = projectManager.nodes.firstIndex(where: { $0.id == node.id }),
              let fileIndex = projectManager.nodes[nodeIndex].files.firstIndex(where: { $0.id == file.id }) else {
            isRenaming = false
            return
        }
        
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty && newName != file.name else {
            isRenaming = false
            return
        }
        
        let oldName = projectManager.nodes[nodeIndex].files[fileIndex].name
        let oldPath = projectManager.nodes[nodeIndex].files[fileIndex].path
        
        // Update file name and path
        projectManager.nodes[nodeIndex].files[fileIndex].name = newName
        
        // Update path - preserve directory structure but update filename
        let pathComponents = oldPath.split(separator: "/")
        if pathComponents.count > 1 {
            // Has directory structure, preserve it
            let directory = pathComponents.dropLast().joined(separator: "/")
            projectManager.nodes[nodeIndex].files[fileIndex].path = "\(directory)/\(newName)"
        } else {
            // Just filename, update it
            projectManager.nodes[nodeIndex].files[fileIndex].path = newName
        }
        
        // Rename file in file system if it exists
        if let projectPath = projectManager.nodes[nodeIndex].projectPath {
            let projectURL = URL(fileURLWithPath: projectPath)
            let oldFileURL = projectURL.appendingPathComponent(oldPath)
            let newFileURL = projectURL.appendingPathComponent(projectManager.nodes[nodeIndex].files[fileIndex].path)
            
            do {
                // Create directory if needed
                let newFileDir = newFileURL.deletingLastPathComponent()
                if newFileDir.path != projectURL.path {
                    try FileManager.default.createDirectory(at: newFileDir, withIntermediateDirectories: true)
                }
                
                // Move/rename file if it exists
                if FileManager.default.fileExists(atPath: oldFileURL.path) {
                    try FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
                }
            } catch {
                print("Failed to rename file: \(error)")
                // Revert changes on error
                projectManager.nodes[nodeIndex].files[fileIndex].name = oldName
                projectManager.nodes[nodeIndex].files[fileIndex].path = oldPath
            }
        }
        
        projectManager.selectedNode = projectManager.nodes[nodeIndex]
        isRenaming = false
    }
    
    private func fileIcon(for language: CodeLanguage) -> String {
        switch language {
        case .swift: return "swift"
        case .python: return "python"
        case .javascript, .typescript: return "curlybraces"
        case .html: return "h.square"
        case .css: return "c.square"
        case .json: return "curlybraces"
        case .yaml, .kubernetes, .cloudformation: return "doc.text"
        case .dockerfile: return "cube.box"
        case .terraform: return "mountain.2"
        case .sql: return "database"
        case .bash: return "terminal"
        case .markdown: return "doc.richtext"
        default: return "doc"
        }
    }
}

