import Foundation
import SwiftUI

class ProjectSettings: ObservableObject {
    static let shared = ProjectSettings()
    
    @Published var projectsBasePath: String {
        didSet {
            UserDefaults.standard.set(projectsBasePath, forKey: "projectsBasePath")
        }
    }
    
    private let defaultPath: String = {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("PioneerApp").path
    }()
    
    init() {
        // Load saved path or use default
        if let savedPath = UserDefaults.standard.string(forKey: "projectsBasePath"), !savedPath.isEmpty {
            self.projectsBasePath = savedPath
        } else {
            self.projectsBasePath = defaultPath
        }
    }
    
    /// Get the full path for a project
    func getProjectPath(projectName: String, nodeId: UUID) -> URL {
        let baseURL = URL(fileURLWithPath: projectsBasePath)
        let projectDir = baseURL.appendingPathComponent(projectName)
        let nodeDir = projectDir.appendingPathComponent(nodeId.uuidString)
        return nodeDir
    }
    
    /// Reset to default path
    func resetToDefault() {
        projectsBasePath = defaultPath
    }
    
    /// Validate that the path exists or can be created
    func validatePath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        
        // Check if path exists
        if fileManager.fileExists(atPath: path) {
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        } else {
            // Try to create it
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                return true
            } catch {
                return false
            }
        }
    }
}

