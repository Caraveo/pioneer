import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Play button with menu
            Menu {
                Button(action: {
                    projectManager.generateiPhoneApp()
                }) {
                    Label("Generate iPhone App", systemImage: "iphone")
                }
                
                Button(action: {
                    projectManager.generateWebsite()
                }) {
                    Label("Generate Website", systemImage: "globe")
                }
                
                Divider()
                
                Button(action: {
                    projectManager.deployBackendToAWS()
                }) {
                    Label("Deploy Backend to AWS", systemImage: "server.rack")
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Generate")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
            
            // Project name
            if !projectManager.projectName.isEmpty {
                Text(projectManager.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
            
            // Canvas controls
            HStack(spacing: 8) {
                Button(action: {
                    projectManager.canvasOffset = .zero
                    projectManager.canvasScale = 1.0
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reset View")
                
                Text("Zoom: \(Int(projectManager.canvasScale * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}


