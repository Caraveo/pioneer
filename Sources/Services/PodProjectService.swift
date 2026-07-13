import Foundation
import AppKit

class PodProjectService {
    private let projectSettings = ProjectSettings.shared
    
    init() {
        // Ensure base directory exists
        let basePath = projectSettings.projectsBasePath
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: basePath), withIntermediateDirectories: true)
    }
    
    /// Get the project directory path for a pod
    func getProjectPath(for pod: Pod, projectName: String? = nil) -> URL {
        // Use project name from ProjectManager if available, otherwise use "Untitled Project"
        let projectName = projectName ?? "Untitled Project"
        return projectSettings.getProjectPath(projectName: projectName, podId: pod.id)
    }
    
    /// Create project structure for a pod
    func createProjectStructure(for pod: Pod, projectName: String? = nil) async throws {
        let projectPath = getProjectPath(for: pod, projectName: projectName)
        
        // Create project directory
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        // Create framework-specific project structure
        switch pod.framework {
        case .django, .flask, .fastapi, .purepy:
            try await createPythonProjectStructure(pod: pod, projectPath: projectPath)
        case .swift, .swiftui, .objectiveC:
            try await createSwiftProjectStructure(pod: pod, projectPath: projectPath)
        case .nodejs, .express, .nestjs, .reactNative:
            try await createJavaScriptProjectStructure(pod: pod, projectPath: projectPath)
        case .angular, .react, .vue, .nextjs:
            try await createFrontendProjectStructure(pod: pod, projectPath: projectPath)
        case .rust:
            try await createRustProjectStructure(pod: pod, projectPath: projectPath)
        case .go:
            try await createGoProjectStructure(pod: pod, projectPath: projectPath)
        case .java, .spring:
            try await createJavaProjectStructure(pod: pod, projectPath: projectPath)
        case .kotlin, .jetpackCompose, .androidJava, .flutter:
            try await createBasicProjectStructure(pod: pod, projectPath: projectPath)
        case .docker, .kubernetes, .terraform:
            try await createBasicProjectStructure(pod: pod, projectPath: projectPath)
        case .postgresql, .mysql, .mongodb, .redis, .sqlite:
            try await createBasicProjectStructure(pod: pod, projectPath: projectPath)
        }
        
        // Save all files in the pod's codebase
        try await saveAllFiles(pod: pod, projectPath: projectPath)
    }
    
    /// Save all files in a pod's codebase
    func saveAllFiles(pod: Pod, projectPath: URL) async throws {
        for file in pod.files {
            let fileURL = projectPath.appendingPathComponent(file.path)
            let directory = fileURL.deletingLastPathComponent()
            
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func createPythonProjectStructure(pod: Pod, projectPath: URL) async throws {
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
        if !pod.pythonRequirements.isEmpty {
            try pod.pythonRequirements.write(to: projectPath.appendingPathComponent("requirements.txt"), atomically: true, encoding: .utf8)
        }
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        \(pod.type.rawValue) project
        
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
    
    private func createSwiftProjectStructure(pod: Pod, projectPath: URL) async throws {
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
            name: "\(pod.projectDirectoryName)",
            platforms: [
                .macOS(.v13),
                .iOS(.v16)
            ],
            products: [
                .executable(
                    name: "\(pod.projectDirectoryName)",
                    targets: ["\(pod.projectDirectoryName)"]
                )
            ],
            targets: [
                .executableTarget(
                    name: "\(pod.projectDirectoryName)",
                    path: "Sources"
                )
            ]
        )
        """
        try packageSwift.write(to: projectPath.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        \(pod.type.rawValue) project
        
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
    
    private func createJavaScriptProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create Node.js/TypeScript project structure
        let srcDir = projectPath.appendingPathComponent("src")
        let distDir = projectPath.appendingPathComponent("dist")
        
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        
        // Get current Node.js version using Volta (or system default)
        let nodeVersion = await getNodeVersion()
        
        // Create package.json with Volta configuration
        let isTypeScript = [.angular, .nestjs, .nextjs].contains(pod.framework) || pod.framework.primaryLanguage == .typescript
        var packageJson: [String: Any] = [
            "name": pod.projectDirectoryName.lowercased(),
            "version": "1.0.0",
            "description": pod.name,
            "main": "src/index.\(isTypeScript ? "ts" : "js")",
            "scripts": [
                "start": isTypeScript ? "ts-pod src/index.ts" : "pod src/index.js",
                "build": isTypeScript ? "tsc" : "echo 'No build step needed'"
            ],
            "keywords": [],
            "author": "",
            "license": "ISC"
        ]
        
        // Add Volta configuration to package.json
        if !nodeVersion.isEmpty {
            packageJson["volta"] = [
                "pod": nodeVersion
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
                voltaProcess.arguments = ["-c", "volta list pod 2>/dev/null | head -1 | awk '{print $2}' || echo ''"]
                
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
                    // Volta not available, fall through to system pod
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
                        // Pod is installed, get version
                        let versionProcess = Process()
                        versionProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                        versionProcess.arguments = ["-c", "pod --version | sed 's/v//'"]
                        
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
                    // Pod not found
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
                process.arguments = ["-c", "cd '\(projectPath.path)' && volta pin pod@\(version)"]
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
    
    private func createWebProjectStructure(pod: Pod, projectPath: URL) async throws {
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
                <title>\(pod.name)</title>
                <link rel="stylesheet" href="css/style.css">
            </head>
            <body>
                <h1>\(pod.name)</h1>
                <script src="js/script.js"></script>
            </body>
            </html>
            """
            try indexHTML.write(to: projectPath.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        }
    }
    
    private func createBasicProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create basic structure for other languages
        let srcDir = projectPath.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        \(pod.type.rawValue) project
        
        Framework: \(pod.framework.rawValue)
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private func createRustProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create Cargo.toml
        let cargoToml = """
        [package]
        name = "\(pod.projectDirectoryName.lowercased())"
        version = "1.0.0"
        edition = "2021"
        
        [dependencies]
        """
        try cargoToml.write(to: projectPath.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        
        // Create src directory
        let srcDir = projectPath.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        Rust project
        
        ## Build
        ```bash
        cargo build
        ```
        
        ## Run
        ```bash
        cargo run
        ```
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private func createGoProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create go.mod
        let goMod = """
        module \(pod.projectDirectoryName.lowercased())
        
        go 1.21
        """
        try goMod.write(to: projectPath.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        Go project
        
        ## Build
        ```bash
        go build
        ```
        
        ## Run
        ```bash
        go run main.go
        ```
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private func createJavaProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create Maven structure
        let srcMainJava = projectPath.appendingPathComponent("src/main/java")
        let srcTestJava = projectPath.appendingPathComponent("src/test/java")
        
        try FileManager.default.createDirectory(at: srcMainJava, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: srcTestJava, withIntermediateDirectories: true)
        
        // Create pom.xml for Maven
        let pomXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="http://maven.apache.org/POM/4.0.0"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                 http://maven.apache.org/xsd/maven-4.0.0.xsd">
            <modelVersion>4.0.0</modelVersion>
            
            <groupId>com.example</groupId>
            <artifactId>\(pod.projectDirectoryName.lowercased())</artifactId>
            <version>1.0.0</version>
            
            <properties>
                <maven.compiler.source>17</maven.compiler.source>
                <maven.compiler.target>17</maven.compiler.target>
            </properties>
        </project>
        """
        try pomXml.write(to: projectPath.appendingPathComponent("pom.xml"), atomically: true, encoding: .utf8)
        
        // Create README.md
        let readme = """
        # \(pod.name)
        
        Java project
        
        ## Build
        ```bash
        mvn compile
        ```
        
        ## Run
        ```bash
        mvn exec:java
        ```
        """
        try readme.write(to: projectPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }
    
    private func createFrontendProjectStructure(pod: Pod, projectPath: URL) async throws {
        // Create frontend project structure (React, Vue, Angular, Next.js)
        let srcDir = projectPath.appendingPathComponent("src")
        let publicDir = projectPath.appendingPathComponent("public")
        
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: publicDir, withIntermediateDirectories: true)
        
        // Get current Node.js version using Volta
        let nodeVersion = await getNodeVersion()
        
        // Create package.json
        var packageJson: [String: Any] = [
            "name": pod.projectDirectoryName.lowercased(),
            "version": "1.0.0",
            "description": pod.name,
            "scripts": [
                "dev": "next dev",
                "build": "next build",
                "start": "next start"
            ],
            "keywords": [],
            "author": "",
            "license": "ISC"
        ]
        
        // Add framework-specific dependencies
        switch pod.framework {
        case .react:
            packageJson["dependencies"] = [
                "react": "^18.2.0",
                "react-dom": "^18.2.0"
            ]
        case .vue:
            packageJson["dependencies"] = [
                "vue": "^3.3.0"
            ]
        case .angular:
            // Angular uses angular.json, handled separately
            break
        case .nextjs:
            packageJson["dependencies"] = [
                "next": "^14.0.0",
                "react": "^18.2.0",
                "react-dom": "^18.2.0"
            ]
        default:
            break
        }
        
        // Add Volta configuration
        if !nodeVersion.isEmpty {
            packageJson["volta"] = [
                "pod": nodeVersion
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
        .next/
        dist/
        build/
        .env
        *.log
        """
        try gitignore.write(to: projectPath.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
    
    func saveMainCodeFile(pod: Pod, projectPath: URL) async throws {
        // Use the pod's main file path
        let mainPath = pod.getMainFilePath(for: pod.framework)
        
        // Find the main file in the pod's files
        guard let mainFile = pod.files.first(where: { $0.path == mainPath }) else {
            // Create main file if it doesn't exist
            var newPod = pod
            let createdFile = newPod.getOrCreateMainFile()
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
    
    /// Get project files for a pod
    func getProjectFiles(for pod: Pod) -> [URL] {
        guard let projectPath = pod.projectPath else {
            return []
        }
        let url = URL(fileURLWithPath: projectPath)
        
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
    func deleteFile(pod: Pod, file: ProjectFile) async throws {
        guard let projectPath = pod.projectPath else {
            return
        }
        let url = URL(fileURLWithPath: projectPath)
        
        let fileURL = url.appendingPathComponent(file.path)
        
        // Check if file exists before trying to delete
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Open project in Finder
    func openProjectInFinder(for pod: Pod, projectName: String? = nil) {
        let projectPath = getProjectPath(for: pod, projectName: projectName)
        NSWorkspace.shared.open(projectPath)
    }
}

