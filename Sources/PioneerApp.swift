import SwiftUI
import AppKit

@main
struct PioneerApp: App {
    @StateObject private var projectManager = ProjectManager()
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @State private var showAISettings = false
    
    init() {
        // Activate app immediately when launched (especially from terminal)
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
                .preferredColorScheme(appearance.colorScheme)
                .sheet(isPresented: $showAISettings) {
                    AISettingsView(aiService: projectManager.aiService)
                }
                .background(WindowAccessor())
                .onAppear {
                    // Ensure window is key when app appears
                    activateWindow()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .onChange(of: projectManager.viewMode) { _ in
            // Activate window when view mode changes
            activateWindow()
        }
        .commands {
            // Add command to force window focus
            CommandGroup(after: .windowArrangement) {
                Button("Focus Editor") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    projectManager.newProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Divider()
                
                Button("New Node") {
                    projectManager.createNewNode()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .saveItem) {
                Button("Save Project As...") {
                    projectManager.saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
                if projectManager.currentProjectPath != nil {
                    Button("Save Project") {
                        if let url = projectManager.currentProjectPath {
                            do {
                                try projectManager.saveProject(to: url)
                            } catch {
                                print("Failed to save: \(error)")
                            }
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            
            CommandGroup(replacing: .importExport) {
                Button("Open Project...") {
                    projectManager.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandMenu("Generate") {
                Button("Generate iPhone App") {
                    projectManager.generateiPhoneApp()
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                
                Button("Generate Website") {
                    projectManager.generateWebsite()
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                
                Button("Deploy Backend to AWS") {
                    projectManager.deployBackendToAWS()
                }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .appSettings) {
                Button("AI Settings...") {
                    showAISettings = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
    
    private func activateWindow() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // Get all windows and bring them to front
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            
            // Also try to get the key window
            if let keyWindow = NSApplication.shared.keyWindow {
                keyWindow.makeKeyAndOrderFront(nil)
                keyWindow.orderFrontRegardless()
            }
        }
    }
}

// Helper view to access NSWindow
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case light, dark, system
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}


