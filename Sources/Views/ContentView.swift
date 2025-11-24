import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    
    var body: some View {
        HSplitView {
            // Sidebar
            SidebarView()
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // Main content area
            VStack(spacing: 0) {
                // Toolbar
                ToolbarView()
                    .frame(height: 44)
                    .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Content based on view mode
                Group {
                    switch projectManager.viewMode {
                    case .ai:
                        // AI Mode - Show AI interface
                        AIModeView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    case .nodeCanvas:
                        // Node Canvas Mode - Show node canvas and editor
                        HSplitView {
                            // Node canvas
                            NodeCanvasView()
                                .frame(minWidth: 400)
                            
                            // Code editor
                            CodeEditorView()
                                .frame(minWidth: 300, idealWidth: 400, maxWidth: 600)
                        }
                    
                    case .editor:
                        // Editor Mode - Show only code editor
                        CodeEditorView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue.capitalized, systemImage: mode == .light ? "sun.max" : mode == .dark ? "moon" : "circle.lefthalf.filled")
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}



