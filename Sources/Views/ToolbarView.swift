import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            
            // Tab Switcher (Center)
            ViewModeSwitcher(selectedMode: $projectManager.viewMode)
            
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

struct ViewModeSwitcher: View {
    @Binding var selectedMode: ViewMode
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    selectedMode = mode
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selectedMode == mode ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == mode ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}


