import SwiftUI

struct PropertyBarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @StateObject private var frameworkManager = FrameworkManager()
    
    @State private var pendingFramework: Framework?
    @State private var showFrameworkConfirm = false
    @State private var frameworkConfirmMessage = ""
    
    @State private var pendingPodType: PodType?
    @State private var showTypeConfirm = false
    @State private var typeConfirmMessage = ""
    @State private var typeChangeWillWipe = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteId: UUID?
    @State private var pendingDeleteName = ""
    @State private var pendingDeleteIsLast = false
    
    /// Selected id only if it still exists in `pods` — never drive UI off a dangling selection.
    private var safeSelectedId: UUID? {
        guard let id = projectManager.selectedPod?.id,
              projectManager.pods.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            
            if let podId = safeSelectedId {
                // Keyed by pod id so SwiftUI discards the whole editor tree on delete
                PodPropertiesEditor(
                    podId: podId,
                    frameworkManager: frameworkManager,
                    onRequestFrameworkChange: { fw in
                        requestFrameworkChange(fw, podId: podId)
                    },
                    onRequestTypeChange: { type in
                        requestPodTypeChange(type, podId: podId)
                    },
                    onRequestDelete: {
                        requestDelete(podId: podId)
                    }
                )
                .id(podId)
                .environmentObject(projectManager)
            } else {
                emptyState
            }
        }
        .alert("Wipe Pod?", isPresented: $showFrameworkConfirm) {
            Button("Cancel", role: .cancel) { pendingFramework = nil }
            Button("Wipe Pod", role: .destructive) { confirmFrameworkSwitch() }
        } message: {
            Text(frameworkConfirmMessage)
        }
        .alert(typeChangeWillWipe ? "Wipe Pod?" : "Change pod type?", isPresented: $showTypeConfirm) {
            Button("Cancel", role: .cancel) {
                pendingPodType = nil
                typeChangeWillWipe = false
            }
            Button(typeChangeWillWipe ? "Wipe Pod" : "Change Type", role: typeChangeWillWipe ? .destructive : nil) {
                confirmPodTypeChange()
            }
        } message: {
            Text(typeConfirmMessage)
        }
        .alert(
            pendingDeleteIsLast ? "Delete last pod?" : "Delete pod?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeleteId = nil
            }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId {
                    projectManager.deletePod(id: id)
                }
                pendingDeleteId = nil
            }
        } message: {
            if pendingDeleteIsLast {
                Text("“\(pendingDeleteName)” is the only pod. Deleting it leaves an empty project. You can add a new pod anytime.")
            } else {
                Text("Delete “\(pendingDeleteName)”? It will be removed from the canvas and its relationships.")
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)
            
            if let podId = safeSelectedId,
               let name = projectManager.pods.first(where: { $0.id == podId })?.name {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                Text("No Pod Selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyState: some View {
        VStack {
            Spacer()
            Text(projectManager.pods.isEmpty
                 ? "No pods — add one from the sidebar"
                 : "Select a pod to view its properties")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Framework confirm
    
    private func requestFrameworkChange(_ newFramework: Framework, podId: UUID) {
        guard let pod = projectManager.pods.first(where: { $0.id == podId }) else { return }
        guard newFramework != pod.framework else { return }
        pendingFramework = newFramework
        frameworkConfirmMessage = pod.wipePodSummary(to: newFramework)
        showFrameworkConfirm = true
    }
    
    private func confirmFrameworkSwitch() {
        guard let newFramework = pendingFramework,
              let podId = projectManager.selectedPod?.id else {
            pendingFramework = nil
            return
        }
        projectManager.wipePodToFramework(id: podId, newFramework: newFramework)
        pendingFramework = nil
    }
    
    // MARK: - Type confirm
    
    private func requestPodTypeChange(_ newType: PodType, podId: UUID) {
        guard let pod = projectManager.pods.first(where: { $0.id == podId }) else { return }
        guard newType != pod.type else { return }
        
        let resolved = newType.resolvedFramework(current: pod.framework)
        pendingPodType = newType
        typeChangeWillWipe = resolved != pod.framework
        
        if typeChangeWillWipe {
            typeConfirmMessage = """
            Changing type to \(newType.rawValue) will also change the framework and wipe this pod’s work.
            
            \(pod.wipePodSummary(to: resolved))
            """
        } else {
            typeConfirmMessage = """
            Change type from \(pod.type.rawValue) to \(newType.rawValue)?
            
            Framework stays \(pod.framework.rawValue). Files are not wiped.
            """
        }
        showTypeConfirm = true
    }
    
    private func confirmPodTypeChange() {
        guard let newType = pendingPodType,
              let podId = projectManager.selectedPod?.id,
              let index = projectManager.pods.firstIndex(where: { $0.id == podId }) else {
            pendingPodType = nil
            typeChangeWillWipe = false
            return
        }
        let previous = projectManager.pods[index].framework
        let resolved = newType.resolvedFramework(current: previous)
        
        if resolved != previous {
            var p = projectManager.pods[index]
            p.type = newType
            projectManager.pods[index] = p
            projectManager.selectedPod = p
            projectManager.wipePodToFramework(id: podId, newFramework: resolved)
        } else {
            var p = projectManager.pods[index]
            p.type = newType
            projectManager.pods[index] = p
            projectManager.selectedPod = p
        }
        pendingPodType = nil
        typeChangeWillWipe = false
    }
    
    private func requestDelete(podId: UUID) {
        guard let pod = projectManager.pods.first(where: { $0.id == podId }) else { return }
        pendingDeleteId = podId
        pendingDeleteName = pod.name
        pendingDeleteIsLast = projectManager.pods.count <= 1
        showDeleteConfirm = true
    }
}

// MARK: - Editor content (bound by pod id — never uses stale indices)

struct PodPropertiesEditor: View {
    let podId: UUID
    @ObservedObject var frameworkManager: FrameworkManager
    var onRequestFrameworkChange: (Framework) -> Void
    var onRequestTypeChange: (PodType) -> Void
    var onRequestDelete: () -> Void
    
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showEnvEditor = false
    
    /// Safe live snapshot; nil if pod was deleted mid-update.
    private var live: Pod? {
        projectManager.pods.first(where: { $0.id == podId })
    }
    
    var body: some View {
        Group {
            if let pod = live {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if pod.type == .inference || pod.isVirtual {
                            PropertySection(title: "Environment") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(pod.environmentVariables.count) key\(pod.environmentVariables.count == 1 ? "" : "s") on this Inference hub")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !pod.environmentVariables.isEmpty {
                                        ForEach(pod.environmentVariables.prefix(6)) { binding in
                                            HStack(spacing: 6) {
                                                Image(systemName: binding.scope.icon)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                Text(binding.key)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(binding.scope.rawValue)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if pod.environmentVariables.count > 6 {
                                            Text("+\(pod.environmentVariables.count - 6) more…")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Button {
                                        showEnvEditor = true
                                    } label: {
                                        Label("Edit Environment…", systemImage: "key.fill")
                                            .font(.caption)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(red: 0.55, green: 0.35, blue: 0.95))
                                    .help("Open the env editor popup (same as double-click on the Inference node)")
                                }
                            }
                            
                            Divider()
                        }
                        
                        PropertySection(title: "Pod Type") {
                            Picker("Type", selection: Binding(
                                get: { live?.type ?? .custom },
                                set: { onRequestTypeChange($0) }
                            )) {
                                ForEach(PodType.allCases) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text(pod.type.frameworkHint)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Framework") {
                            let options = frameworkManager.availableFrameworks(for: pod.type)
                            Picker("Framework", selection: Binding(
                                get: {
                                    let current = live?.framework ?? pod.framework
                                    return options.contains(current) ? current : pod.type.defaultFramework
                                },
                                set: { onRequestFrameworkChange($0) }
                            )) {
                                ForEach(options, id: \.self) { framework in
                                    HStack {
                                        Image(systemName: framework.icon)
                                        Text(framework.rawValue)
                                    }
                                    .tag(framework)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text("Switching framework wipes this pod’s code and rebuilds a clean starter (confirm required).")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Kubernetes") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Image: \(KubernetesManifestService.containerImage(for: pod.framework))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    mutate { $0.regenerateKubernetesYAML() }
                                    if let path = live?.projectPath, let yaml = live?.kubernetesYAML {
                                        try? KubernetesManifestService.writeYAML(
                                            yaml,
                                            to: URL(fileURLWithPath: path)
                                        )
                                    }
                                    projectManager.viewMode = .yaml
                                } label: {
                                    Label("Open YAML", systemImage: "shippingbox")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Git") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This pod is its own git repository — teams scale independently.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button {
                                    if let p = live { projectManager.selectedPod = p }
                                    projectManager.viewMode = .git
                                } label: {
                                    Label("Open Git", systemImage: "arrow.triangle.branch")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Position") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("X:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("X", value: Binding(
                                        get: { Double(live?.position.x ?? 0) },
                                        set: { x in mutate { $0.position.x = CGFloat(x) } }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                                HStack {
                                    Text("Y:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("Y", value: Binding(
                                        get: { Double(live?.position.y ?? 0) },
                                        set: { y in mutate { $0.position.y = CGFloat(y) } }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Connections") {
                            VStack(alignment: .leading, spacing: 4) {
                                if pod.connections.isEmpty {
                                    Text("No connections")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(pod.connections, id: \.self) { connectionId in
                                        if let connectedPod = projectManager.pods.first(where: { $0.id == connectionId }) {
                                            HStack {
                                                Image(systemName: connectedPod.type.icon)
                                                    .foregroundColor(connectedPod.type.color)
                                                Text(connectedPod.name)
                                                    .font(.caption)
                                                Spacer()
                                                Button {
                                                    projectManager.disconnectPods(from: podId, to: connectionId)
                                                } label: {
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
                        
                        if [.django, .flask, .fastapi, .purepy].contains(pod.framework) {
                            Divider()
                            PropertySection(title: "Python Requirements") {
                                TextEditor(text: Binding(
                                    get: { live?.pythonRequirements ?? "" },
                                    set: { value in
                                        mutate { $0.pythonRequirements = value }
                                        if let p = live { projectManager.updatePod(p) }
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
                        
                        PropertySection(title: "Project Path") {
                            if let projectPath = pod.projectPath {
                                Text(projectPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                
                                Button {
                                    if let p = live {
                                        projectManager.openPodProjectInFinder(p)
                                    }
                                } label: {
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
                        
                        PropertySection(title: "Files") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(pod.files) { file in
                                    HStack {
                                        Image(systemName: file.language.icon)
                                            .foregroundColor(file.language.color)
                                        Text(file.name)
                                            .font(.caption)
                                        Spacer()
                                        if file.id == pod.selectedFileId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                                .font(.system(size: 10))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        mutate { $0.selectedFileId = file.id }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Danger zone") {
                            Button(role: .destructive) {
                                onRequestDelete()
                            } label: {
                                Label("Delete Pod…", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .sheet(isPresented: $showEnvEditor) {
                    InferenceEnvEditorView(podId: podId)
                        .environmentObject(projectManager)
                }
            } else {
                // Pod vanished mid-frame — show empty, do not trap
                Color.clear
            }
        }
    }
    
    /// Mutate pod by id with full array reassignment (never use a stale index).
    private func mutate(_ body: (inout Pod) -> Void) {
        guard let index = projectManager.pods.firstIndex(where: { $0.id == podId }),
              projectManager.pods.indices.contains(index) else { return }
        var pod = projectManager.pods[index]
        body(&pod)
        // Re-resolve index in case array shifted mid-mutation
        guard let fresh = projectManager.pods.firstIndex(where: { $0.id == podId }) else { return }
        projectManager.pods[fresh] = pod
        if projectManager.selectedPod?.id == podId {
            projectManager.selectedPod = pod
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
