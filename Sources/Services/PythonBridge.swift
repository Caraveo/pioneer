import Foundation
import AppKit

class PythonBridge {
    private let pythonScriptsPath: URL
    private let environmentsPath: URL
    
    init() {
        // Get the path to Python scripts directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pioneerDir = homeDir.appendingPathComponent(".pioneer")
        
        let scriptsPath = pioneerDir.appendingPathComponent("PythonScripts")
        let envsPath = pioneerDir.appendingPathComponent("Environments")
        
        // Create directories if they don't exist
        try? FileManager.default.createDirectory(at: scriptsPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: envsPath, withIntermediateDirectories: true)
        
        self.pythonScriptsPath = scriptsPath
        self.environmentsPath = envsPath
        
        // Initialize Python scripts
        initializePythonScripts()
    }
    
    /// Get the virtual environment path for a pod
    func getVirtualEnvironmentPath(for pod: Pod) -> URL {
        return environmentsPath.appendingPathComponent(pod.id.uuidString)
    }
    
    /// Ensure a virtual environment exists for a Python pod
    func ensureVirtualEnvironment(for pod: Pod) async {
        let venvPath = getVirtualEnvironmentPath(for: pod)
        let venvPython = venvPath.appendingPathComponent("bin").appendingPathComponent("python3")
        
        // Check if virtual environment already exists
        if FileManager.default.fileExists(atPath: venvPython.path) {
            // Update requirements if needed
            await updatePythonRequirements(for: pod)
            return
        }
        
        // Create virtual environment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "venv", venvPath.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Update the pod with the environment path
                // Note: This would need to be handled by ProjectManager
                print("Created virtual environment for pod: \(pod.name) at \(venvPath.path)")
                
                // Install requirements if any
                if !pod.pythonRequirements.isEmpty {
                    await updatePythonRequirements(for: pod)
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let error = String(data: data, encoding: .utf8) {
                    print("Error creating virtual environment: \(error)")
                }
            }
        } catch {
            print("Failed to create virtual environment: \(error)")
        }
    }
    
    /// Update Python requirements for a pod
    func updatePythonRequirements(for pod: Pod) async {
        let venvPath = getVirtualEnvironmentPath(for: pod)
        let venvPip = venvPath.appendingPathComponent("bin").appendingPathComponent("pip3")
        
        guard FileManager.default.fileExists(atPath: venvPip.path) else {
            print("Virtual environment not found for pod: \(pod.name)")
            return
        }
        
        // Write requirements.txt
        let requirementsFile = venvPath.appendingPathComponent("requirements.txt")
        try? pod.pythonRequirements.write(to: requirementsFile, atomically: true, encoding: .utf8)
        
        // Install requirements
        let process = Process()
        process.executableURL = venvPip
        process.arguments = ["install", "-r", requirementsFile.path, "--upgrade"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("Requirements installation output: \(output)")
            }
        } catch {
            print("Failed to install requirements: \(error)")
        }
    }
    
    private func initializePythonScripts() {
        // Create main Python script for code generation
        let mainScript = """
        #!/usr/bin/env python3
        import json
        import sys
        import os
        from pathlib import Path

        def generate_iphone_app(node_data):
            \"\"\"Generate an iPhone app from pod data\"\"\"
            pod = json.loads(node_data)
            app_name = pod.get('name', 'GeneratedApp')
            code = pod.get('code', '')
            
            output_dir = Path(f"generated/{app_name}")
            output_dir.mkdir(parents=True, exist_ok=True)
            
            # Create SwiftUI app structure
            app_file = output_dir / f"{app_name}App.swift"
            content_file = output_dir / "ContentView.swift"
            
            with open(app_file, 'w') as f:
                f.write(f\"\"\"
        import SwiftUI

        @main
        struct {app_name}App: App {{
            var body: some Scene {{
                WindowGroup {{
                    ContentView()
                }}
            }}
        }}
        \"\"\")
            
            with open(content_file, 'w') as f:
                if code:
                    f.write(code)
                else:
                    f.write(f\"\"\"
        import SwiftUI

        struct ContentView: View {{
            var body: some View {{
                VStack {{
                    Text("Hello, {app_name}!")
                        .font(.largeTitle)
                }}
                .padding()
            }}
        }}
        \"\"\")
            
            print(f"Generated iPhone app: {output_dir.absolute()}")
            return str(output_dir.absolute())

        def generate_website(node_data):
            \"\"\"Generate a website from pod data\"\"\"
            pod = json.loads(node_data)
            site_name = pod.get('name', 'GeneratedSite')
            code = pod.get('code', '')
            
            output_dir = Path(f"generated/{site_name}")
            output_dir.mkdir(parents=True, exist_ok=True)
            
            # Create HTML structure
            index_file = output_dir / "index.html"
            css_file = output_dir / "style.css"
            js_file = output_dir / "script.js"
            
            with open(index_file, 'w') as f:
                if code:
                    f.write(code)
                else:
                    f.write(f\"\"\"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{site_name}</title>
            <link rel="stylesheet" href="style.css">
        </head>
        <body>
            <div class="container">
                <h1>Welcome to {site_name}</h1>
                <p>Generated by Pioneer</p>
            </div>
            <script src="script.js"></script>
        </body>
        </html>
        \"\"\")
            
            with open(css_file, 'w') as f:
                f.write(\"\"\"
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        \"\"\")
            
            with open(js_file, 'w') as f:
                f.write("// JavaScript for " + site_name + "\\n")
            
            print(f"Generated website: {output_dir.absolute()}")
            return str(output_dir.absolute())

        def deploy_to_aws(node_data):
            \"\"\"Deploy backend to AWS\"\"\"
            pod = json.loads(node_data)
            backend_name = pod.get('name', 'GeneratedBackend')
            
            # This is a stub - would integrate with AWS SDK
            print(f"Deploying {backend_name} to AWS...")
            print("(This is a placeholder - implement AWS deployment logic)")
            
            # Would typically:
            # 1. Create CloudFormation template
            # 2. Deploy Lambda functions
            # 3. Set up API Gateway
            # 4. Configure IAM roles
            # etc.
            
            return f"AWS deployment initiated for {backend_name}"

        if __name__ == "__main__":
            if len(sys.argv) < 3:
                print("Usage: python3 script.py <action> <node_json>")
                sys.exit(1)
            
            action = sys.argv[1]
            node_data = sys.argv[2]
            
            if action == "generate_iphone_app":
                result = generate_iphone_app(node_data)
            elif action == "generate_website":
                result = generate_website(node_data)
            elif action == "deploy_to_aws":
                result = deploy_to_aws(node_data)
            else:
                print(f"Unknown action: {action}")
                sys.exit(1)
            
            print(result)
        """
        
        let scriptURL = pythonScriptsPath.appendingPathComponent("generator.py")
        try? mainScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make script executable
        let process = Process()
        process.launchPath = "/bin/chmod"
        process.arguments = ["+x", scriptURL.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    func generateiPhoneApp(pod: Pod) async {
        await runPythonScript(action: "generate_iphone_app", pod: pod)
    }
    
    func generateWebsite(pod: Pod) async {
        await runPythonScript(action: "generate_website", pod: pod)
    }
    
    func deployToAWS(pod: Pod) async {
        await runPythonScript(action: "deploy_to_aws", pod: pod)
    }
    
    /// Execute Python code in a pod's virtual environment
    func executePythonCode(for pod: Pod) async -> String? {
        guard pod.language == .python else {
            return nil
        }
        
        // Ensure virtual environment exists
        await ensureVirtualEnvironment(for: pod)
        
        let venvPath = getVirtualEnvironmentPath(for: pod)
        let venvPython = venvPath.appendingPathComponent("bin").appendingPathComponent("python3")
        
        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            return "Error: Virtual environment not found"
        }
        
        // Write pod code to a temporary file
        let tempScript = venvPath.appendingPathComponent("node_script.py")
        do {
            try pod.code.write(to: tempScript, atomically: true, encoding: .utf8)
        } catch {
            return "Error: Failed to write script file: \(error.localizedDescription)"
        }
        
        // Execute the script in the virtual environment
        let process = Process()
        process.executableURL = venvPython
        process.arguments = [tempScript.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output
            }
            
            return process.terminationStatus == 0 ? "Execution completed successfully" : "Execution failed with exit code \(process.terminationStatus)"
        } catch {
            return "Error: Failed to execute script: \(error.localizedDescription)"
        }
    }
    
    private func runPythonScript(action: String, pod: Pod) async {
        // For Python pods, use their virtual environment
        if pod.language == .python {
            // Ensure virtual environment exists
            await ensureVirtualEnvironment(for: pod)
            
            let venvPath = getVirtualEnvironmentPath(for: pod)
            let venvPython = venvPath.appendingPathComponent("bin").appendingPathComponent("python3")
            
            guard FileManager.default.fileExists(atPath: venvPython.path) else {
                await MainActor.run {
                    showAlert(title: "Error", message: "Virtual environment not found for pod: \(pod.name)")
                }
                return
            }
            
            // Create a script that uses the generator functions
            let scriptContent = createPodExecutionScript(action: action, pod: pod)
            let scriptFile = venvPath.appendingPathComponent("execute.py")
            
            do {
                try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    showAlert(title: "Error", message: "Failed to create execution script: \(error.localizedDescription)")
                }
                return
            }
            
            // Run using the pod's virtual environment Python
            let process = Process()
            process.executableURL = venvPython
            process.arguments = [scriptFile.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("Python output (from venv): \(output)")
                    
                    await MainActor.run {
                        showAlert(title: "Generation Complete", message: output)
                    }
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Error", message: "Failed to run script: \(error.localizedDescription)")
                }
            }
        } else {
            // For non-Python pods, use system Python with shared generator script
            let scriptURL = pythonScriptsPath.appendingPathComponent("generator.py")
            
            // Convert pod to JSON
            let encoder = JSONEncoder()
            guard let podData = try? encoder.encode(pod),
                  let podJSON = String(data: podData, encoding: .utf8) else {
                await MainActor.run {
                    showAlert(title: "Error", message: "Failed to encode pod to JSON")
                }
                return
            }
            
            // Run Python script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptURL.path, action, podJSON]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("Python output: \(output)")
                    
                    await MainActor.run {
                        showAlert(title: "Generation Complete", message: output)
                    }
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Error", message: "Failed to run generation script: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createPodExecutionScript(action: String, pod: Pod) -> String {
        // Convert pod to JSON
        let encoder = JSONEncoder()
        guard let podData = try? encoder.encode(pod),
              let podJSON = String(data: podData, encoding: .utf8) else {
            return "# Error encoding pod"
        }
        
        // Include the generator functions and execute based on action
        return """
        #!/usr/bin/env python3
        import json
        import sys
        from pathlib import Path
        
        # Include generator functions
        \(getGeneratorFunctions())
        
        # Pod data
        node_data = '''\(podJSON)'''
        
        # Execute based on action
        pod = json.loads(node_data)
        
        if "\(action)" == "generate_iphone_app":
            result = generate_iphone_app(node_data)
        elif "\(action)" == "generate_website":
            result = generate_website(node_data)
        elif "\(action)" == "deploy_to_aws":
            result = deploy_to_aws(node_data)
        else:
            # Execute pod's own code
            exec(pod.get('code', ''))
            result = "Pod code executed successfully"
        
        print(result)
        """
    }
    
    private func getGeneratorFunctions() -> String {
        return """
        def generate_iphone_app(node_data):
            import json
            from pathlib import Path
            pod = json.loads(node_data)
            app_name = pod.get('name', 'GeneratedApp')
            code = pod.get('code', '')
            
            output_dir = Path("generated/" + app_name)
            output_dir.mkdir(parents=True, exist_ok=True)
            
            app_file = output_dir / (app_name + "App.swift")
            content_file = output_dir / "ContentView.swift"
            
            swift_app_code = '''import SwiftUI

        @main
        struct ''' + app_name + '''App: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }'''
            
            with open(app_file, 'w') as f:
                f.write(swift_app_code)
            
            with open(content_file, 'w') as f:
                if code:
                    f.write(code)
                else:
                    swift_content = '''import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello, ''' + app_name + '''!")
                        .font(.largeTitle)
                }
                .padding()
            }
        }'''
                    f.write(swift_content)
            
            return "Generated iPhone app: " + str(output_dir.absolute())

        def generate_website(node_data):
            import json
            from pathlib import Path
            pod = json.loads(node_data)
            site_name = pod.get('name', 'GeneratedSite')
            code = pod.get('code', '')
            
            output_dir = Path("generated/" + site_name)
            output_dir.mkdir(parents=True, exist_ok=True)
            
            index_file = output_dir / "index.html"
            css_file = output_dir / "style.css"
            js_file = output_dir / "script.js"
            
            with open(index_file, 'w') as f:
                if code:
                    f.write(code)
                else:
                    html_content = '''<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>''' + site_name + '''</title>
            <link rel="stylesheet" href="style.css">
        </head>
        <body>
            <div class="container">
                <h1>Welcome to ''' + site_name + '''</h1>
                <p>Generated by Pioneer</p>
            </div>
            <script src="script.js"></script>
        </body>
        </html>'''
                    f.write(html_content)
            
            with open(css_file, 'w') as f:
                f.write('''
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        ''')
            
            with open(js_file, 'w') as f:
                f.write("// JavaScript for " + site_name + "\\n")
            
            return "Generated website: " + str(output_dir.absolute())

        def deploy_to_aws(node_data):
            import json
            pod = json.loads(node_data)
            backend_name = pod.get('name', 'GeneratedBackend')
            return "AWS deployment initiated for " + backend_name
        """
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

