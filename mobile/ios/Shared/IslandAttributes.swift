import ActivityKit
import Foundation

// The Dynamic Island's content: exactly the "island" object
// src/mobile/notify.bend emits, and the content-state the hub pushes.
struct IslandAttributes: ActivityAttributes {
    struct Line: Codable, Hashable {
        let thread: String
        let title: String
        let doing: String
    }

    struct ContentState: Codable, Hashable {
        let running: Int
        let headline: String
        let lines: [Line]
    }
}
