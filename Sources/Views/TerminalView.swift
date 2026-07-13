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
                
                // Play button
                Button(action: runProject) {
                    HStack(spacing: 4) {
                        Image(systemName: isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(isRunning ? "Stop" : "Run")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectManager.selectedPod == nil)
                .help("Run Project")
                
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
        guard let pod = projectManager.selectedPod else {
            return "$ "
        }
        
        if let projectPath = pod.projectPath {
            let url = URL(fileURLWithPath: projectPath)
            let path = url.lastPathComponent
            return "\(path) $ "
        }
        
        return "\(pod.name) $ "
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
        Task { @MainActor in
            let output = await runCommand(command)
            appendOutput(output)
            isRunning = false
        }
    }
    
    private func runCommand(_ command: String) async -> String {
        guard let pod = projectManager.selectedPod else {
            return "Error: No pod selected\n"
        }
        
        // Get working directory
        let workingDirectory: URL
        if let projectPath = pod.projectPath {
            workingDirectory = URL(fileURLWithPath: projectPath)
        } else {
            // Fallback to pod's project path from service
            workingDirectory = projectManager.podProjectService.getProjectPath(for: pod, projectName: projectManager.projectName)
        }
        
        // Validate working directory exists, create if needed
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory)
        
        if !directoryExists || !isDirectory.boolValue {
            // Try to create the directory
            do {
                try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            } catch {
                return "Error: Working directory does not exist and could not be created: \(workingDirectory.path)\n\(error.localizedDescription)\n"
            }
        }
        
        return await runCommand(command, workingDirectory: workingDirectory)
    }
    
    private func appendOutput(_ text: String) {
        terminalOutput += text
    }
    
    private func clearTerminal() {
        terminalOutput = ""
    }
    
    private func runProject() {
        if isRunning {
            isRunning = false
            if let id = projectManager.selectedPod?.id {
                projectManager.setPodRunning(id: id, false)
            }
            return
        }
        
        guard let pod = projectManager.selectedPod else { return }
        
        projectManager.saveCurrentPodFiles()
        isRunning = true
        appendOutput("\n🚀 Running pod: \(pod.name) (\(pod.framework.rawValue))\n")
        
        Task {
            let output = await projectManager.runSinglePod(id: pod.id)
            await MainActor.run {
                appendOutput(output)
                isRunning = false
            }
        }
    }
    
    private func runPythonProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Use virtual environment if available
        if let venvPath = pod.pythonEnvironmentPath {
            let venvURL = URL(fileURLWithPath: venvPath)
            if FileManager.default.fileExists(atPath: venvURL.appendingPathComponent("bin/python3").path) {
                let pythonPath = venvURL.appendingPathComponent("bin/python3")
                return await runCommand("\(pythonPath.path) \(mainFile.path)", workingDirectory: workingDirectory)
            }
        }
        
        // Try to use venv in project directory
        let venvPython = workingDirectory.appendingPathComponent("venv/bin/python3")
        if FileManager.default.fileExists(atPath: venvPython.path) {
            return await runCommand("\(venvPython.path) \(mainFile.path)", workingDirectory: workingDirectory)
        } else {
            // Use system Python
            return await runCommand("python3 \(mainFile.path)", workingDirectory: workingDirectory)
        }
    }
    
    private func runJavaScriptProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Check for package.json
        let packageJson = workingDirectory.appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: packageJson.path) {
            // Check if node_modules exists
            let nodeModules = workingDirectory.appendingPathComponent("node_modules")
            if !FileManager.default.fileExists(atPath: nodeModules.path) {
                await MainActor.run {
                    appendOutput("Installing dependencies...\n")
                }
                let installOutput = await runCommand("npm install", workingDirectory: workingDirectory)
                await MainActor.run {
                    appendOutput(installOutput)
                }
            }
            // Try npm start first, then node
            let startOutput = await runCommand("npm start", workingDirectory: workingDirectory)
            if startOutput.contains("Error") || startOutput.contains("Missing script") {
                return await runCommand("node \(mainFile.path)", workingDirectory: workingDirectory)
            }
            return startOutput
        } else {
            // Direct node execution
            return await runCommand("node \(mainFile.path)", workingDirectory: workingDirectory)
        }
    }
    
    private func runSwiftProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Swift projects need to be compiled first
        let executableName = "\(pod.name.replacingOccurrences(of: " ", with: "_"))"
        let compileOutput = await runCommand("swiftc \(mainFile.path) -o \(executableName)", workingDirectory: workingDirectory)
        
        if compileOutput.contains("error:") {
            return compileOutput
        }
        
        // Run the compiled executable
        let runOutput = await runCommand("./\(executableName)", workingDirectory: workingDirectory)
        return compileOutput + runOutput
    }
    
    private func runWebProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // For HTML, open in browser or start a simple server
        let htmlFile = workingDirectory.appendingPathComponent(mainFile.path)
        if FileManager.default.fileExists(atPath: htmlFile.path) {
            // Open in default browser
            NSWorkspace.shared.open(htmlFile)
            return "Opening \(mainFile.name) in browser...\n"
        } else {
            return "Error: HTML file not found at \(mainFile.path)\n"
        }
    }
    
    private func runRustProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Rust projects use cargo
        return await runCommand("cargo run", workingDirectory: workingDirectory)
    }
    
    private func runGoProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Go projects use go run
        return await runCommand("go run \(mainFile.path)", workingDirectory: workingDirectory)
    }
    
    private func runJavaProject(pod: Pod, workingDirectory: URL, mainFile: ProjectFile) async -> String {
        // Java projects use Maven
        return await runCommand("mvn exec:java", workingDirectory: workingDirectory)
    }
    
    private func runCommand(_ command: String, workingDirectory: URL) async -> String {
        // Validate working directory exists, create if needed
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory)
        
        if !directoryExists || !isDirectory.boolValue {
            // Try to create the directory
            do {
                try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            } catch {
                return "Error: Working directory does not exist and could not be created: \(workingDirectory.path)\n\(error.localizedDescription)\n"
            }
        }
        
        return await withCheckedContinuation { continuation in
            // Create and configure process on main thread
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Configure process - must be done on main thread
            // Use async to avoid deadlock if already on main thread
            if Thread.isMainThread {
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.currentDirectoryURL = workingDirectory
                process.standardOutput = outputPipe
                process.standardError = errorPipe
            } else {
                DispatchQueue.main.sync {
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = ["-c", command]
                    process.currentDirectoryURL = workingDirectory
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                }
            }
            
            // Set up termination handler
            process.terminationHandler = { process in
                // Read output after process finishes
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
                
                continuation.resume(returning: result)
            }
            
            // Run process on background thread to avoid blocking
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)\n")
                }
            }
        }
    }
}
