import Foundation

struct PioneerProject: Codable {
    var nodes: [Node]
    var canvasOffset: CGSize
    var canvasScale: CGFloat
    var version: String = "1.0"
    var created: Date
    var modified: Date
    
    init(nodes: [Node] = [], canvasOffset: CGSize = .zero, canvasScale: CGFloat = 1.0) {
        self.nodes = nodes
        self.canvasOffset = canvasOffset
        self.canvasScale = canvasScale
        self.created = Date()
        self.modified = Date()
    }
}

// CGSize already conforms to Codable in CoreGraphics, no extension needed

