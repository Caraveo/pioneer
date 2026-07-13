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
                .help("New Pod")
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Pod list — selection is UUID, never a raw array index
            List(selection: Binding(
                get: { projectManager.selectedPod?.id },
                set: { newId in
                    // Save current editor before switching (if still present)
                    if let current = projectManager.selectedPod,
                       current.selectedFileId != nil,
                       projectManager.pods.contains(where: { $0.id == current.id }) {
                        projectManager.saveCurrentPodFiles()
                    }
                    
                    guard let newId else {
                        // Don't clear selection here if the list is mid-delete;
                        // deletePod owns selection clearing. Only clear when the
                        // user explicitly deselects and the id is still valid to clear.
                        return
                    }
                    if let pod = projectManager.pods.first(where: { $0.id == newId }) {
                        projectManager.selectedPod = pod
                    }
                }
            )) {
                ForEach(projectManager.pods) { pod in
                    PodRowView(podId: pod.id)
                        .tag(pod.id)
                }
            }
            .listStyle(.sidebar)
            
            // Empty hierarchy: no extra Add Pod button — use header + or canvas “New Pod”
            if projectManager.pods.isEmpty {
                Text("No pods")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
    }
}

struct PodRowView: View {
    let podId: UUID
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showDeleteConfirm = false
    
    private var live: Pod? {
        projectManager.pods.first(where: { $0.id == podId })
    }
    
    private var isLastPod: Bool {
        projectManager.pods.count <= 1
    }
    
    var body: some View {
        // Snapshot for display; never index into pods[] by position
        let display = live
        let name = display?.name ?? "Pod"
        let type = display?.type ?? .custom
        let isRunning = display?.isRunning ?? false
        let hasConnections = !(display?.connections.isEmpty ?? true)
        
        return HStack {
            Circle()
                .fill(isRunning ? Color.green : Color.red.opacity(0.75))
                .frame(width: 7, height: 7)
            
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(type.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if hasConnections {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete Pod…", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .alert(isLastPod ? "Delete last pod?" : "Delete pod?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // Always delete by captured podId — never by list index
                projectManager.deletePod(id: podId)
            }
        } message: {
            if isLastPod {
                Text("“\(name)” is the only pod on this canvas. Deleting it leaves an empty project. You can add a new pod anytime. Continue?")
            } else {
                Text("Delete “\(name)”? This removes it from the canvas and its relationships. On-disk project files are not bulk-deleted.")
            }
        }
    }
}
