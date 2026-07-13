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
                
                // Content based on view mode: PODS | CODE | YAML | GIT
                Group {
                    switch projectManager.viewMode {
                    case .podCanvas:
                        HSplitView {
                            PodCanvasView()
                                .frame(minWidth: 400)
                            
                            PropertyBarView()
                                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                        }
                    
                    case .code:
                        VStack(spacing: 0) {
                            CodeEditorView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Divider()
                            
                            TerminalView()
                        }
                    
                    case .yaml:
                        VStack(spacing: 0) {
                            YAMLEditorView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Divider()
                            
                            TerminalView()
                        }
                    
                    case .git:
                        GitView()
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



