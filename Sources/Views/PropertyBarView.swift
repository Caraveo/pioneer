import SwiftUI

struct PropertyBarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @StateObject private var frameworkManager = FrameworkManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Properties")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                if let selectedPod = projectManager.selectedPod {
                    Text(selectedPod.name)
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
            
            Divider()
            
            // Properties
            if let selectedPod = projectManager.selectedPod,
               let podIndex = projectManager.pods.firstIndex(where: { $0.id == selectedPod.id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Pod Type → constrains Framework options
                        PropertySection(title: "Pod Type") {
                            Picker("Type", selection: Binding(
                                get: { projectManager.pods[podIndex].type },
                                set: { newType in
                                    applyPodType(newType, podIndex: podIndex)
                                }
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
                            
                            Text(projectManager.pods[podIndex].type.frameworkHint)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        // Framework filtered by Pod Type (+ user enable flags)
                        PropertySection(title: "Framework") {
                            let type = projectManager.pods[podIndex].type
                            let options = frameworkManager.availableFrameworks(for: type)
                            
                            Picker("Framework", selection: Binding(
                                get: {
                                    let current = projectManager.pods[podIndex].framework
                                    if options.contains(current) { return current }
                                    return type.defaultFramework
                                },
                                set: { newFramework in
                                    projectManager.pods[podIndex].framework = newFramework
                                    projectManager.updatePod(projectManager.pods[podIndex])
                                }
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
                            
                            Text("Assumed stack for \(type.rawValue). Each pod is its own Kubernetes Pod.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        PropertySection(title: "Kubernetes") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Image: \(KubernetesManifestService.containerImage(for: projectManager.pods[podIndex].framework))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    projectManager.pods[podIndex].regenerateKubernetesYAML()
                                    projectManager.selectedPod = projectManager.pods[podIndex]
                                    if let path = projectManager.pods[podIndex].projectPath {
                                        try? KubernetesManifestService.writeYAML(
                                            projectManager.pods[podIndex].kubernetesYAML,
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
                                Text("This pod is its own git repository — Android, Apple, and Web teams scale independently.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button {
                                    projectManager.selectedPod = projectManager.pods[podIndex]
                                    projectManager.viewMode = .git
                                } label: {
                                    Label("Open Git", systemImage: "arrow.triangle.branch")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                        
                        // Position
                        PropertySection(title: "Position") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("X:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("X", value: Binding(
                                        get: { Double(projectManager.pods[podIndex].position.x) },
                                        set: { newX in
                                            projectManager.pods[podIndex].position.x = CGFloat(newX)
                                            projectManager.selectedPod = projectManager.pods[podIndex]
                                        }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack {
                                    Text("Y:")
                                        .frame(width: 30, alignment: .leading)
                                    TextField("Y", value: Binding(
                                        get: { Double(projectManager.pods[podIndex].position.y) },
                                        set: { newY in
                                            projectManager.pods[podIndex].position.y = CGFloat(newY)
                                            projectManager.selectedPod = projectManager.pods[podIndex]
                                        }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Connections
                        PropertySection(title: "Connections") {
                            VStack(alignment: .leading, spacing: 4) {
                                if selectedPod.connections.isEmpty {
                                    Text("No connections")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(selectedPod.connections, id: \.self) { connectionId in
                                        if let connectedPod = projectManager.pods.first(where: { $0.id == connectionId }) {
                                            HStack {
                                                Image(systemName: connectedPod.type.icon)
                                                    .foregroundColor(connectedPod.type.color)
                                                Text(connectedPod.name)
                                                    .font(.caption)
                                                Spacer()
                                                Button(action: {
                                                    projectManager.disconnectPods(from: selectedPod.id, to: connectionId)
                                                }) {
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
                        
                        // Python Requirements (if Python framework)
                        if [.django, .flask, .fastapi, .purepy].contains(selectedPod.framework) {
                            Divider()
                            
                            PropertySection(title: "Python Requirements") {
                                TextEditor(text: Binding(
                                    get: { projectManager.pods[podIndex].pythonRequirements },
                                    set: { newRequirements in
                                        projectManager.pods[podIndex].pythonRequirements = newRequirements
                                        projectManager.updatePod(projectManager.pods[podIndex])
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
                        
                        // Project Path
                        PropertySection(title: "Project Path") {
                            if let projectPath = selectedPod.projectPath {
                                Text(projectPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                
                                Button(action: {
                                    projectManager.openPodProjectInFinder(selectedPod)
                                }) {
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
                        
                        // Files
                        PropertySection(title: "Files") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(selectedPod.files) { file in
                                    HStack {
                                        Image(systemName: file.language.icon)
                                            .foregroundColor(file.language.color)
                                        Text(file.name)
                                            .font(.caption)
                                        Spacer()
                                        if file.id == selectedPod.selectedFileId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                                .font(.system(size: 10))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        projectManager.pods[podIndex].selectedFileId = file.id
                                        projectManager.selectedPod = projectManager.pods[podIndex]
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack {
                    Spacer()
                    Text("Select a pod to view its properties")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }
    
    /// When Pod Type changes, snap Framework to a compatible default if needed.
    private func applyPodType(_ newType: PodType, podIndex: Int) {
        guard podIndex < projectManager.pods.count else { return }
        let previous = projectManager.pods[podIndex].framework
        let resolved = newType.resolvedFramework(current: previous)
        
        projectManager.pods[podIndex].type = newType
        if resolved != previous {
            projectManager.pods[podIndex].framework = resolved
            // Rebuild launch file + K8s assumptions for the new stack
            projectManager.updatePod(projectManager.pods[podIndex])
        } else {
            projectManager.selectedPod = projectManager.pods[podIndex]
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

