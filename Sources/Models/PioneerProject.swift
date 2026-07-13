import Foundation

struct PioneerProject: Codable {
    var pods: [Pod]
    var canvasOffset: CGSize
    var canvasScale: CGFloat
    var version: String = "1.0"
    var created: Date
    var modified: Date
    
    /// Keep JSON key `nodes` so existing .core / legacy .code project archives still load.
    enum CodingKeys: String, CodingKey {
        case pods = "nodes"
        case canvasOffset
        case canvasScale
        case version
        case created
        case modified
    }
    
    init(pods: [Pod] = [], canvasOffset: CGSize = .zero, canvasScale: CGFloat = 1.0) {
        self.pods = pods
        self.canvasOffset = canvasOffset
        self.canvasScale = canvasScale
        self.created = Date()
        self.modified = Date()
    }
}

// CGSize already conforms to Codable in CoreGraphics, no extension needed

