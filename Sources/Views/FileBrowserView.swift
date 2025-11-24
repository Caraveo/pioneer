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
                                }
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
            path: "new_file.\(node.language.fileExtension)",
            name: "new_file.\(node.language.fileExtension)",
            content: "",
            language: node.language
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
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon(for: file.language))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(file.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1.0 : 0.0)
            .help("Delete file")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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

