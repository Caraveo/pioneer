import Foundation
import SwiftUI

class FrameworkManager: ObservableObject {
    @Published var enabledFrameworks: Set<Framework> = Set(Framework.allCases)
    
    private let userDefaultsKey = "enabledFrameworks"
    
    init() {
        loadEnabledFrameworks()
    }
    
    func isEnabled(_ framework: Framework) -> Bool {
        return enabledFrameworks.contains(framework)
    }
    
    func setEnabled(_ framework: Framework, enabled: Bool) {
        if enabled {
            enabledFrameworks.insert(framework)
        } else {
            enabledFrameworks.remove(framework)
        }
        saveEnabledFrameworks()
    }
    
    var availableFrameworks: [Framework] {
        return Framework.allCases.filter { enabledFrameworks.contains($0) }
    }
    
    private func loadEnabledFrameworks() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let frameworkStrings = try? JSONDecoder().decode([String].self, from: data) {
            enabledFrameworks = Set(frameworkStrings.compactMap { Framework(rawValue: $0) })
        } else {
            // Default: all frameworks enabled
            enabledFrameworks = Set(Framework.allCases)
        }
    }
    
    private func saveEnabledFrameworks() {
        let frameworkStrings = enabledFrameworks.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(frameworkStrings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

