import SwiftUI

@main
struct PioneerApp: App {
    @StateObject private var projectManager = ProjectManager()
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @State private var showAISettings = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
                .preferredColorScheme(appearance.colorScheme)
                .sheet(isPresented: $showAISettings) {
                    AISettingsView(aiService: projectManager.aiService)
                }
                .onAppear {
                    // Ensure window is key when app appears
                    DispatchQueue.main.async {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let window = NSApplication.shared.keyWindow {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
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
                Button("New Node") {
                    projectManager.createNewNode()
                }
                .keyboardShortcut("n", modifiers: .command)
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


