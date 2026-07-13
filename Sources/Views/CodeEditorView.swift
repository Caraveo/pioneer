import SwiftUI
import AppKit

struct CodeEditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var editorText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // File browser
            if let pod = projectManager.selectedPod {
                FileBrowserView(
                    selectedFileId: Binding(
                        get: {
                            // Always look up pod index fresh to avoid stale indices
                            guard let podIndex = projectManager.pods.firstIndex(where: { $0.id == pod.id }),
                                  podIndex < projectManager.pods.count else {
                                return nil
                            }
                            return projectManager.pods[podIndex].selectedFileId
                        },
                        set: { newId in
                            projectManager.saveCurrentPodFiles()
                            // Always look up pod index fresh
                            guard let podIndex = projectManager.pods.firstIndex(where: { $0.id == pod.id }),
                                  podIndex < projectManager.pods.count else {
                                return
                            }
                            projectManager.pods[podIndex].selectedFileId = newId
                            projectManager.selectedPod = projectManager.pods[podIndex]
                        }
                    ),
                    pod: {
                        // Always get fresh pod from array
                        guard let podIndex = projectManager.pods.firstIndex(where: { $0.id == pod.id }),
                              podIndex < projectManager.pods.count else {
                            return pod // Fallback to passed pod
                        }
                        return projectManager.pods[podIndex]
                    }()
                )
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                if let pod = projectManager.selectedPod {
                    // Always get fresh pod from array to avoid stale indices
                    let currentPod: Pod = {
                        guard let podIndex = projectManager.pods.firstIndex(where: { $0.id == pod.id }),
                              podIndex < projectManager.pods.count else {
                            return pod // Fallback to passed pod
                        }
                        return projectManager.pods[podIndex]
                    }()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: currentPod.type.icon)
                                .foregroundColor(currentPod.type.color)
                            Text(currentPod.selectedFile?.name ?? currentPod.name)
                                .font(.headline)
                            
                            if let selectedFile = currentPod.selectedFile {
                                Text(selectedFile.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("Language", selection: Binding(
                                get: { currentPod.selectedFile?.language ?? currentPod.framework.primaryLanguage },
                                set: { newLanguage in
                                    projectManager.saveCurrentPodFiles()
                                    // Always look up pod index fresh
                                    guard let podIndex = projectManager.pods.firstIndex(where: { $0.id == currentPod.id }),
                                          podIndex < projectManager.pods.count,
                                          let fileId = currentPod.selectedFileId,
                                          let fileIndex = projectManager.pods[podIndex].files.firstIndex(where: { $0.id == fileId }) else {
                                        return
                                    }
                                    projectManager.pods[podIndex].files[fileIndex].language = newLanguage
                                    projectManager.selectedPod = projectManager.pods[podIndex]
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
                                projectManager.openPodProjectInFinder(currentPod)
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
                        
                        Text(currentPod.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // Code editor with pure Swift NSTextView
                    if let selectedFile = currentPod.selectedFile {
                        let editorKey = "\(currentPod.id.uuidString)-\(selectedFile.id.uuidString)"
                        
                        SwiftCodeEditorView(
                            text: Binding(
                                get: {
                                    // Always get from the CURRENT pod's file - ensure isolation
                                    guard let currentPod = projectManager.selectedPod,
                                          let currentIndex = projectManager.pods.firstIndex(where: { $0.id == currentPod.id }),
                                          let fileId = currentPod.selectedFileId,
                                          let file = projectManager.pods[currentIndex].files.first(where: { $0.id == fileId }) else {
                                        return selectedFile.content
                                    }
                                    // Verify we're getting the right pod's content
                                    if currentPod.id != projectManager.pods[currentIndex].id {
                                        print("⚠️ WARNING: Pod ID mismatch! Expected \(currentPod.id), got \(projectManager.pods[currentIndex].id)")
                                    }
                                    return file.content
                                },
                                set: { newValue in
                                    // CRITICAL: Update ONLY the current pod's file - ensure isolation
                                    guard let currentPod = projectManager.selectedPod,
                                          let currentIndex = projectManager.pods.firstIndex(where: { $0.id == currentPod.id }),
                                          let fileId = currentPod.selectedFileId,
                                          let fileIndex = projectManager.pods[currentIndex].files.firstIndex(where: { $0.id == fileId }) else {
                                        print("⚠️ ERROR: Cannot update - pod or file not found")
                                        return
                                    }
                                    
                                    // Verify we're updating the right pod
                                    if currentPod.id != projectManager.pods[currentIndex].id {
                                        print("⚠️ WARNING: Updating wrong pod! Expected \(currentPod.id), got \(projectManager.pods[currentIndex].id)")
                                        return
                                    }
                                    
                                    // Update ONLY this pod's file
                                    projectManager.pods[currentIndex].files[fileIndex].content = newValue
                                    
                                    // Also update main code for backward compatibility
                                    if fileIndex == 0 {
                                        projectManager.pods[currentIndex].code = newValue
                                    }
                                    
                                    // Update selectedPod to match
                                    projectManager.selectedPod = projectManager.pods[currentIndex]
                                    
                                    // AUTO SAVE immediately to project file
                                    Task {
                                        await saveFileToProject(pod: projectManager.pods[currentIndex], file: projectManager.pods[currentIndex].files[fileIndex])
                                    }
                                }
                            ),
                            language: selectedFile.language,
                            editorInstanceId: editorKey
                        )
                        .id(editorKey) // Unique ID per pod+file - forces new instance
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                        .onChange(of: projectManager.selectedPod?.id) { _ in
                            // Save before switching pods
                            projectManager.saveCurrentPodFiles()
                        }
                        .onDisappear {
                            // Save when editor disappears
                            projectManager.saveCurrentPodFiles()
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
                        Text("No Pod Selected")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Select a pod from the sidebar or canvas to edit its code")
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
    
    private func saveFileToProject(pod: Pod, file: ProjectFile) async {
        guard let projectPath = pod.projectPath else {
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

