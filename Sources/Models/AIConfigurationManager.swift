import Foundation

class AIConfigurationManager {
    private let userDefaults = UserDefaults.standard
    private let configurationKey = "pioneer.ai.configuration"
    
    func loadConfiguration() -> AIConfiguration {
        guard let data = userDefaults.data(forKey: configurationKey),
              let config = try? JSONDecoder().decode(AIConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
    
    func saveConfiguration(_ configuration: AIConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }
}


