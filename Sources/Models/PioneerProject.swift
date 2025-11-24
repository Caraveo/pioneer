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

extension CGSize: Codable {
    enum CodingKeys: String, CodingKey {
        case width, height
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(width: width, height: height)
    }
}

