import Foundation
import AppKit

class NodeProjectService {
    private let projectsBasePath: URL
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pioneerDir = homeDir.appendingPathComponent(".pioneer")
        let projectsPath = pioneerDir.appendingPathComponent("Projects")
        
        // Create projects directory if it doesn't exist
        try? FileManager.default.createDirectory(at: projectsPath, withIntermediateDirectories: true)
        
        self.projectsBasePath = projectsPath
    }
    
    /// Get the project directory path for a node
    func getProjectPath(for node: Node) -> URL {
        return projectsBasePath.appendingPathComponent(node.id.uuidString)
    }
    
    /// Create project structure for a node
    func createProjectStructure(for node: Node) async throws {
        let projectPath = getProjectPath(for: node)
        
        // Create project directory
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        // Create language-specific project structure
        switch node.language {
        case .python:
            try await createPythonProjectStructure(node: node, projectPath: projectPath)
        case .swift:
            try await createSwiftProjectStructure(node: node, projectPath: projectPath)
        case .typescript, .javascript:
            try await createJavaScriptProjectStructure(node: node, projectPath: projectPath)
        case .html, .css:
            try await createWebProjectStructure(node: node, projectPath: projectPath)
        default:
            // Create basic structure for other languages
            try await createBasicProjectStructure(node: node, projectPath: projectPath)
        }
        
        // Save all files in the node's codebase
        try await saveAllFiles(node: node, projectPath: projectPath)
    }
    
    /// Save all files in a node's codebase
    func saveAllFiles(node: Node, projectPath: URL) async throws {
        for file in node.files {
            let fileURL = projectPath.appendingPathComponent(file.path)
            let directory = fileURL.deletingLastPathComponent()
            
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func createPythonProjectStructure(node: Node, projectPath: URL) async throws {
        // Create standard Python project structure
        let srcDir = projectPath.appendingPathComponent("src")
        let testsDir = projectPath.appendingPathComponent("tests")
        let docsDir = projectPath.appendingPathComponent("docs")
        
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        
        // Create __init__.py files
        try "".write(to: srcDir.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try "".write(to: testsDir.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        
        // Create requirements.txt if not empty
        if !node.pythonRequirements.isEmpty {
            try node.pythonRequirements.write(to: projectPath.appendingPathComponent("requirements.txt"), atomically: true, encoding: .utf8)
        }
        
        // Create README.md
        let readme = """
        # \(node.name)
        
        \(node.type.rawValue) project
        
        ## Setup
        
        ```bash
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
        ```
        
        ## Run
        
        ```bash
        python src/main.py
        ```
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        
        // Create .gitignore
        let gitignore = """
        __pycache__/
        *.py[cod]
        *$py.class
        *.so
        .Python
        venv/
        env/
        ENV/
        .pytest_cache/
        .mypy_cache/
        .coverage
        htmlcov/
        dist/
        build/
        *.egg-info/
        """
        try gitignore.write(to: projectPath.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
    
    private func createSwiftProjectStructure(node: Node, projectPath: URL) async throws {
        // Create Swift project structure
        let sourcesDir = projectPath.appendingPathComponent("Sources")
        let testsDir = projectPath.appendingPathComponent("Tests")
        
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        
        // Create Package.swift
        let packageSwift = """
        // swift-tools-version: 5.9
        import PackageDescription
        
        let package = Package(
            name: "\(node.projectDirectoryName)",
            platforms: [
                .macOS(.v13),
                .iOS(.v16)
            ],
            products: [
                .executable(
                    name: "\(node.projectDirectoryName)",
                    targets: ["\(node.projectDirectoryName)"]
                )
            ],
            targets: [
                .executableTarget(
                    name: "\(node.projectDirectoryName)",
                    path: "Sources"
                )
            ]
        )
        """
        try packageSwift.write(to: projectPath.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        
        // Create README.md
        let readme = """
        # \(node.name)
        
        \(node.type.rawValue) project
        
        ## Build
        
        ```bash
        swift build
        ```
        
        ## Run
        
        ```bash
        swift run
        ```
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private func createJavaScriptProjectStructure(node: Node, projectPath: URL) async throws {
        // Create Node.js/TypeScript project structure
        let srcDir = projectPath.appendingPathComponent("src")
        let distDir = projectPath.appendingPathComponent("dist")
        
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        
        // Get current Node.js version using Volta (or system default)
        let nodeVersion = await getNodeVersion()
        
        // Create package.json with Volta configuration
        var packageJson: [String: Any] = [
            "name": node.projectDirectoryName.lowercased(),
            "version": "1.0.0",
            "description": node.name,
            "main": "src/index.\(node.language == .typescript ? "ts" : "js")",
            "scripts": [
                "start": node.language == .typescript ? "ts-node src/index.ts" : "node src/index.js",
                "build": node.language == .typescript ? "tsc" : "echo 'No build step needed'"
            ],
            "keywords": [],
            "author": "",
            "license": "ISC"
        ]
        
        // Add Volta configuration to package.json
        if !nodeVersion.isEmpty {
            packageJson["volta"] = [
                "node": nodeVersion
            ] as [String: Any]
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: packageJson, options: .prettyPrinted)
        try jsonData.write(to: projectPath.appendingPathComponent("package.json"))
        
        // Pin Node.js version using Volta if available
        if await isVoltaInstalled() {
            await pinNodeVersion(projectPath: projectPath, version: nodeVersion)
        }
        
        // Create .gitignore
        let gitignore = """
        node_modules/
        dist/
        build/
        .env
        *.log
        """
        try gitignore.write(to: projectPath.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
    
    /// Check if Volta is installed
    private func isVoltaInstalled() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                process.arguments = ["volta"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Get current Node.js version (using Volta if available, otherwise system)
    private func getNodeVersion() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // First try to get version from Volta
                let voltaProcess = Process()
                voltaProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                voltaProcess.arguments = ["-c", "volta list node 2>/dev/null | head -1 | awk '{print $2}' || echo ''"]
                
                let voltaPipe = Pipe()
                voltaProcess.standardOutput = voltaPipe
                voltaProcess.standardError = Pipe()
                
                do {
                    try voltaProcess.run()
                    voltaProcess.waitUntilExit()
                    
                    let data = voltaPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8),
                       !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                        return
                    }
                } catch {
                    // Volta not available, fall through to system node
                }
                
                // Fallback to system Node.js version
                let nodeProcess = Process()
                nodeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                nodeProcess.arguments = ["node"]
                
                let nodePipe = Pipe()
                nodeProcess.standardOutput = nodePipe
                nodeProcess.standardError = Pipe()
                
                do {
                    try nodeProcess.run()
                    nodeProcess.waitUntilExit()
                    
                    if nodeProcess.terminationStatus == 0 {
                        // Node is installed, get version
                        let versionProcess = Process()
                        versionProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                        versionProcess.arguments = ["-c", "node --version | sed 's/v//'"]
                        
                        let versionPipe = Pipe()
                        versionProcess.standardOutput = versionPipe
                        versionProcess.standardError = Pipe()
                        
                        try versionProcess.run()
                        versionProcess.waitUntilExit()
                        
                        let versionData = versionPipe.fileHandleForReading.readDataToEndOfFile()
                        if let version = String(data: versionData, encoding: .utf8) {
                            continuation.resume(returning: version.trimmingCharacters(in: .whitespacesAndNewlines))
                            return
                        }
                    }
                } catch {
                    // Node not found
                }
                
                // Default to latest LTS if nothing found
                continuation.resume(returning: "20.11.0")
            }
        }
    }
    
    /// Pin Node.js version using Volta
    private func pinNodeVersion(projectPath: URL, version: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", "cd '\(projectPath.path)' && volta pin node@\(version)"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    // Ignore errors - Volta pin might fail if version doesn't exist
                }
                
                continuation.resume()
            }
        }
    }
    
    private func createWebProjectStructure(node: Node, projectPath: URL) async throws {
        // Create web project structure
        let cssDir = projectPath.appendingPathComponent("css")
        let jsDir = projectPath.appendingPathComponent("js")
        let imagesDir = projectPath.appendingPathComponent("images")
        
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        
        // Create basic index.html if not exists
        if !FileManager.default.fileExists(atPath: projectPath.appendingPathComponent("index.html").path) {
            let indexHTML = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>\(node.name)</title>
                <link rel="stylesheet" href="css/style.css">
            </head>
            <body>
                <h1>\(node.name)</h1>
                <script src="js/script.js"></script>
            </body>
            </html>
            """
            try indexHTML.write(to: projectPath.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        }
    }
    
    private func createBasicProjectStructure(node: Node, projectPath: URL) async throws {
        // Create basic structure for other languages
        let srcDir = projectPath.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        
        // Create README.md
        let readme = """
        # \(node.name)
        
        \(node.type.rawValue) project
        
        Language: \(node.language.rawValue)
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    func saveMainCodeFile(node: Node, projectPath: URL) async throws {
        // Use the node's main file path
        let mainPath = node.getMainFilePath(for: node.language)
        let mainFileName = node.getMainFileName(for: node.language)
        
        // Find the main file in the node's files
        guard let mainFile = node.files.first(where: { $0.path == mainPath }) else {
            // Create main file if it doesn't exist
            var newNode = node
            let createdFile = newNode.getOrCreateMainFile()
            let fileURL = projectPath.appendingPathComponent(createdFile.path)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try createdFile.content.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        
        let fileURL = projectPath.appendingPathComponent(mainFile.path)
        let directory = fileURL.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try mainFile.content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// Get project files for a node
    func getProjectFiles(for node: Node) -> [URL] {
        guard let projectPath = node.projectPath,
              let url = URL(string: projectPath) else {
            return []
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.hasDirectoryPath {
                    continue
                }
                files.append(fileURL)
            }
        }
        return files
    }
    
    /// Delete a file from the project directory
    func deleteFile(node: Node, file: ProjectFile) async throws {
        guard let projectPath = node.projectPath,
              let url = URL(string: projectPath) else {
            return
        }
        
        let fileURL = url.appendingPathComponent(file.path)
        
        // Check if file exists before trying to delete
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Open project in Finder
    func openProjectInFinder(for node: Node) {
        let projectPath = getProjectPath(for: node)
        NSWorkspace.shared.open(projectPath)
    }
}

