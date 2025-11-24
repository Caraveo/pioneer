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
                    case .nodeCanvas:
                        // Node Canvas Mode - Show node canvas and property bar
                        HSplitView {
                            // Node canvas
                            NodeCanvasView()
                                .frame(minWidth: 400)
                            
                            // Property bar
                            PropertyBarView()
                                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                        }
                    
                    case .editor:
                        // Editor Mode - Show code editor with terminal at bottom
                        VStack(spacing: 0) {
                            // Code editor (takes remaining space)
                            CodeEditorView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Divider()
                            
                            // Terminal at bottom (spans full width)
                            TerminalView()
                        }
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



