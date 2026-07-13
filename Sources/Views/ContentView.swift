import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("showHierarchy") private var showHierarchy = true
    @AppStorage("showPropertyBar") private var showPropertyBar = true
    @AppStorage("showMainToolbar") private var showMainToolbar = true
    
    var body: some View {
        HSplitView {
            // Hierarchy (pod list) — toggleable via View menu / toolbar
            if showHierarchy {
                SidebarView()
                    .frame(minWidth: 180, idealWidth: 250, maxWidth: 320)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // Main content area
            VStack(spacing: 0) {
                // Main toolbar (Play, modes, panel toggles) — View → Toolbar
                if showMainToolbar {
                    ToolbarView()
                        .frame(height: 44)
                        .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                }
                
                // Content based on view mode: PODS | CODE | YAML | GIT
                Group {
                    switch projectManager.viewMode {
                    case .podCanvas:
                        HSplitView {
                            PodCanvasView()
                                .frame(minWidth: 400)
                            
                            if showPropertyBar {
                                PropertyBarView()
                                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    
                    case .code:
                        // Code mode: optional properties on the right for the selected pod
                        HSplitView {
                            VStack(spacing: 0) {
                                CodeEditorView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                Divider()
                                
                                TerminalView()
                            }
                            .frame(minWidth: 400)
                            
                            if showPropertyBar {
                                PropertyBarView()
                                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)
                            }
                        }
                    
                    case .yaml:
                        HSplitView {
                            VStack(spacing: 0) {
                                YAMLEditorView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                Divider()
                                
                                TerminalView()
                            }
                            .frame(minWidth: 400)
                            
                            if showPropertyBar {
                                PropertyBarView()
                                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)
                            }
                        }
                    
                    case .git:
                        HSplitView {
                            GitView()
                                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                            
                            if showPropertyBar {
                                PropertyBarView()
                                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showHierarchy)
        .animation(.easeInOut(duration: 0.18), value: showPropertyBar)
        .animation(.easeInOut(duration: 0.18), value: showMainToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation { showHierarchy.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showHierarchy ? .none : .slash)
                        .opacity(showHierarchy ? 1 : 0.55)
                }
                .help(showHierarchy ? "Hide hierarchy (View menu)" : "Show hierarchy (View menu)")
                
                Button {
                    withAnimation { showPropertyBar.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showPropertyBar ? .none : .slash)
                        .opacity(showPropertyBar ? 1 : 0.55)
                }
                .help(showPropertyBar ? "Hide properties (View menu)" : "Show properties (View menu)")
                
                Button {
                    withAnimation { showMainToolbar.toggle() }
                } label: {
                    Image(systemName: "menubar.rectangle")
                        .symbolVariant(showMainToolbar ? .none : .slash)
                        .opacity(showMainToolbar ? 1 : 0.55)
                }
                .help(showMainToolbar ? "Hide toolbar (View menu)" : "Show toolbar (View menu)")
            }
            
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



