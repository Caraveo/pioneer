import SwiftUI
import AppKit

struct ProjectSettingsView: View {
    @StateObject private var projectSettings = ProjectSettings.shared
    @State private var customPath: String = ""
    @State private var showPathPicker = false
    @State private var pathError: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Project Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Project Path Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Project Storage Location")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("This is where all your node project files are saved. The structure will be:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Show path structure
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(projectSettings.projectsBasePath)/")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("  └── {ProjectName}/")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("      └── {NodeId}/")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // Current path display
                        HStack {
                            Text("Current Path:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        HStack {
                            Text(projectSettings.projectsBasePath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button(action: {
                                showPathPicker = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("Change...")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                projectSettings.resetToDefault()
                                customPath = projectSettings.projectsBasePath
                                pathError = nil
                            }) {
                                Text("Reset to Default")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // Error message
                        if let error = pathError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Info
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Default: ~/PioneerApp/")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            customPath = projectSettings.projectsBasePath
        }
        .fileImporter(
            isPresented: $showPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let path = url.path
                    if projectSettings.validatePath(path) {
                        projectSettings.projectsBasePath = path
                        customPath = path
                        pathError = nil
                    } else {
                        pathError = "Invalid path. Please select a valid directory."
                    }
                }
            case .failure(let error):
                pathError = "Failed to select path: \(error.localizedDescription)"
            }
        }
    }
}

