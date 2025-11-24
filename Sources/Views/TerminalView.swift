import SwiftUI
import AppKit

struct TerminalView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var terminalOutput: String = ""
    @State private var currentCommand: String = ""
    @State private var isRunning: Bool = false
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    
    private var effectiveColorScheme: ColorScheme {
        if appearance == .system {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
            return isDark ? .dark : .light
        } else {
            return appearance == .dark ? .dark : .light
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                Text("Terminal")
                    .font(.headline)
                Spacer()
                Button(action: clearTerminal) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Clear Terminal")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Terminal content
            VStack(spacing: 0) {
                // Output area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(terminalOutput.isEmpty ? "Terminal ready. Type a command and press Enter." : terminalOutput)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                                .id("output")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(effectiveColorScheme == .dark 
                        ? Color(NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
                        : Color(NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)))
                    .onChange(of: terminalOutput) { _ in
                        withAnimation {
                            proxy.scrollTo("output", anchor: .bottom)
                        }
                    }
                }
                
                Divider()
                
                // Input area
                HStack(spacing: 8) {
                    Text(getPrompt())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter command...", text: $currentCommand)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit {
                            executeCommand()
                        }
                        .disabled(isRunning)
                    
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(height: 200)
    }
    
    private func getPrompt() -> String {
        guard let node = projectManager.selectedNode else {
            return "$ "
        }
        
        if let projectPath = node.projectPath,
           let url = URL(string: projectPath) {
            let path = url.lastPathComponent
            return "\(path) $ "
        }
        
        return "\(node.name) $ "
    }
    
    private func executeCommand() {
        guard !currentCommand.isEmpty, !isRunning else { return }
        
        let command = currentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        
        // Add command to output
        appendOutput("\(getPrompt())\(command)\n")
        
        // Clear input
        currentCommand = ""
        isRunning = true
        
        // Execute command
        Task {
            let output = await runCommand(command)
            await MainActor.run {
                appendOutput(output)
                isRunning = false
            }
        }
    }
    
    private func runCommand(_ command: String) async -> String {
        guard let node = projectManager.selectedNode else {
            return "Error: No node selected\n"
        }
        
        // Get working directory
        let workingDirectory: URL
        if let projectPath = node.projectPath,
           let url = URL(string: projectPath) {
            workingDirectory = url
        } else {
            // Fallback to node's project path from service
            workingDirectory = projectManager.nodeProjectService.getProjectPath(for: node)
        }
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory
        
        // Set up pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Read output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            var result = ""
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                result += output
            }
            
            if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                result += error
            }
            
            if result.isEmpty {
                result = process.terminationStatus == 0 ? "" : "Command exited with status \(process.terminationStatus)\n"
            }
            
            return result
        } catch {
            return "Error: \(error.localizedDescription)\n"
        }
    }
    
    private func appendOutput(_ text: String) {
        terminalOutput += text
    }
    
    private func clearTerminal() {
        terminalOutput = ""
    }
}

