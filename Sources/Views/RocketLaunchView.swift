import SwiftUI

/// Rocket control: detect cloud CLIs and launch pods abstractly.
struct RocketMenuButton: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showPanel = false
    
    var body: some View {
        Button {
            showPanel = true
            Task { await projectManager.refreshCloudProviders() }
        } label: {
            Group {
                if projectManager.isRocketLaunching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "rocket.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 28, height: 22)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .help("Rocket — launch to DigitalOcean / GCE / AWS / K8s / Docker")
        .disabled(projectManager.isRocketLaunching)
        .popover(isPresented: $showPanel, arrowEdge: .bottom) {
            RocketLaunchPanel()
                .environmentObject(projectManager)
        }
    }
}

struct RocketLaunchPanel: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selectedProvider: CloudProviderKind?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "rocket.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rocket Launch")
                        .font(.headline)
                    Text("Abstract cloud deploy · CLI detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await projectManager.refreshCloudProviders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-scan CLIs")
            }
            
            if projectManager.cloudProviders.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Detecting cloud CLIs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("PROVIDERS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                
                ForEach(projectManager.cloudProviders) { status in
                    providerRow(status)
                }
            }
            
            Divider()
            
            HStack(spacing: 8) {
                Button {
                    Task {
                        await projectManager.rocketLaunchSelected(provider: effectiveProvider)
                    }
                } label: {
                    Label("Launch selected", systemImage: "rocket")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(projectManager.selectedPod == nil || projectManager.isRocketLaunching)
                
                Button {
                    Task {
                        await projectManager.rocketLaunchAll(provider: effectiveProvider)
                    }
                } label: {
                    Label("Launch all", systemImage: "flame")
                }
                .buttonStyle(.bordered)
                .disabled(projectManager.isRocketLaunching || projectManager.pods.isEmpty)
            }
            
            if let sel = projectManager.selectedPod {
                Text("Target: \(sel.name) · \(sel.framework.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a pod on the canvas, or Launch all.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if !projectManager.rocketLog.isEmpty {
                ScrollView {
                    Text(projectManager.rocketLog)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if selectedProvider == nil {
                selectedProvider = CloudLaunchService.preferred(from: projectManager.cloudProviders)
            }
            if projectManager.cloudProviders.isEmpty {
                Task { await projectManager.refreshCloudProviders() }
            }
        }
    }
    
    private var effectiveProvider: CloudProviderKind {
        selectedProvider
            ?? CloudLaunchService.preferred(from: projectManager.cloudProviders)
            ?? .docker
    }
    
    private func providerRow(_ status: CloudProviderStatus) -> some View {
        Button {
            selectedProvider = status.kind
        } label: {
            HStack(spacing: 10) {
                Image(systemName: status.kind.icon)
                    .foregroundStyle(status.isReady ? Color.orange : Color.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(status.kind.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(status.kind.accent)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(status.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(status.isReady ? Color.green : Color.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Circle()
                    .fill(status.isReady ? Color.green : (status.installed ? Color.orange : Color.red.opacity(0.7)))
                    .frame(width: 8, height: 8)
                
                if selectedProvider == status.kind {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedProvider == status.kind
                          ? Color.orange.opacity(0.1)
                          : Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}
