import SwiftUI
import AppKit

/// Dedicated YAML view for the selected pod's Kubernetes Pod manifest.
struct YAMLEditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var localYAML: String = ""
    @State private var isDirty: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let pod = projectManager.selectedPod,
               let podIndex = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                header(pod: projectManager.pods[podIndex], podIndex: podIndex)
                Divider()
                
                SwiftCodeEditorView(
                    text: Binding(
                        get: {
                            if isDirty { return localYAML }
                            return projectManager.pods[podIndex].kubernetesYAML
                        },
                        set: { newValue in
                            localYAML = newValue
                            isDirty = true
                            projectManager.pods[podIndex].kubernetesYAML = newValue
                            projectManager.selectedPod = projectManager.pods[podIndex]
                        }
                    ),
                    language: .yaml,
                    editorInstanceId: "yaml-\(pod.id.uuidString)"
                )
                .id("yaml-\(pod.id.uuidString)")
                .onAppear {
                    ensureYAML(podIndex: podIndex)
                    localYAML = projectManager.pods[podIndex].kubernetesYAML
                    isDirty = false
                }
                .onChange(of: projectManager.selectedPod?.id) { _ in
                    if let id = projectManager.selectedPod?.id,
                       let idx = projectManager.pods.firstIndex(where: { $0.id == id }) {
                        ensureYAML(podIndex: idx)
                        localYAML = projectManager.pods[idx].kubernetesYAML
                        isDirty = false
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Pod Selected")
                        .font(.headline)
                    Text("Select a pod to edit its Kubernetes Pod YAML")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func header(pod: Pod, podIndex: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("YAML")
                    .font(.headline)
                Text("\(pod.name) · Kubernetes Pod · \(pod.framework.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                regenerate(podIndex: podIndex)
            } label: {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .help("Regenerate YAML from framework, name, and project path")
            .buttonStyle(.bordered)
            
            Button {
                saveToDisk(podIndex: podIndex)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Write k8s/pod.yaml into the pod project folder")
            
            if let path = pod.projectPath {
                Text(KubernetesManifestService.relativeYAMLPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .help(path)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func ensureYAML(podIndex: Int) {
        guard podIndex < projectManager.pods.count else { return }
        if projectManager.pods[podIndex].kubernetesYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            regenerate(podIndex: podIndex)
        }
    }
    
    private func regenerate(podIndex: Int) {
        guard podIndex < projectManager.pods.count else { return }
        var pod = projectManager.pods[podIndex]
        pod.kubernetesYAML = KubernetesManifestService.generateYAML(
            for: pod,
            projectPath: pod.projectPath
        )
        projectManager.pods[podIndex] = pod
        projectManager.selectedPod = pod
        localYAML = pod.kubernetesYAML
        isDirty = false
        saveToDisk(podIndex: podIndex)
    }
    
    private func saveToDisk(podIndex: Int) {
        guard podIndex < projectManager.pods.count else { return }
        let pod = projectManager.pods[podIndex]
        let projectPath: URL
        if let path = pod.projectPath {
            projectPath = URL(fileURLWithPath: path)
        } else {
            projectPath = projectManager.podProjectService.getProjectPath(
                for: pod,
                projectName: projectManager.projectName
            )
        }
        do {
            try KubernetesManifestService.writeYAML(pod.kubernetesYAML, to: projectPath)
            if projectManager.pods[podIndex].projectPath == nil {
                projectManager.pods[podIndex].projectPath = projectPath.path
                projectManager.selectedPod = projectManager.pods[podIndex]
            }
        } catch {
            print("Failed to save pod YAML: \(error)")
        }
    }
}
