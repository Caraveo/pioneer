import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Pods")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Spacer()
                Button(action: {
                    projectManager.createNewPod()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Pod list
            List(selection: Binding(
                get: { projectManager.selectedPod?.id },
                set: { newId in
                    // Get webView for current pod before switching
                    if let currentPod = projectManager.selectedPod,
                       currentPod.selectedFileId != nil {
                        // Access webViewStore through a notification or callback
                        // For now, save immediately from pods array
                        projectManager.saveCurrentPodFiles()
                    }
                    
                    // Switch after brief delay to allow save
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let newId = newId {
                            if let index = projectManager.pods.firstIndex(where: { $0.id == newId }) {
                                projectManager.selectedPod = projectManager.pods[index]
                            }
                        }
                    }
                }
            )) {
                ForEach(projectManager.pods) { pod in
                    PodRowView(pod: pod)
                        .tag(pod.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct PodRowView: View {
    let pod: Pod
    @EnvironmentObject var projectManager: ProjectManager
    
    // Get the current pod from projectManager to ensure we always show the latest name
    private var currentPod: Pod? {
        projectManager.pods.first(where: { $0.id == pod.id })
    }
    
    var body: some View {
        // Use currentPod if available, otherwise fallback to passed pod
        let displayPod = currentPod ?? pod
        
        return HStack {
            Image(systemName: displayPod.type.icon)
                .foregroundColor(displayPod.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayPod.name)
                    .font(.system(size: 13, weight: .medium))
                Text(displayPod.type.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !displayPod.connections.isEmpty {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete") {
                if let podToDelete = currentPod {
                    projectManager.deletePod(podToDelete)
                } else {
                    projectManager.deletePod(pod)
                }
            }
        }
    }
}


