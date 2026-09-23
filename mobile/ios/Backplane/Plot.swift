import Foundation
import Observation

// Plots from the hub (src/core/plot.bend) as GPU-ready geometry. Nothing
// is decided here: which chunks, their order, colour and opacity come from
// the hub, the fade and zoom range from the screen. A plot message lists
// each chunk as the index of one this app holds (the last plot applied) or
// the chunk itself; applying it is Plot.apply (law plot_delta_exact), so
// `held` always mirrors what the hub thinks this connection holds.

// One chunk, decoded once: capsules (ax ay bx by r, micrometres; a dot is
// a capsule of no length) and fill triangles (x y, three per triangle).
final class PlotChunk: @unchecked Sendable {
    let layer: Int
    let color: UInt32
    let alpha: Float
    var caps: [Float] = []
    var tris: [Float] = []

    init(layer: Int, color: UInt32, alpha: Float) {
        self.layer = layer
        self.color = color
        self.alpha = alpha
    }

    // "d": 6-bit digits (base64url), 5 bits each, low first; bit 5 set
    // while more follow. Numbers are zigzag deltas (Enc.pts)
    static func numbers(_ d: String) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(d.utf8.count / 2)
        var acc: UInt32 = 0, sh: UInt32 = 0
        for c in d.utf8 {
            let v: UInt32
            switch c {
            case 65...90: v = UInt32(c) - 65
            case 97...122: v = UInt32(c) - 71
            case 48...57: v = UInt32(c) + 4
            case 45: v = 62
            default: v = 63
            }
            acc |= (v & 31) << sh
            if v >= 32 { sh += 5 } else { out.append(acc); acc = 0; sh = 0 }
        }
        return out
    }

    static func decode(_ o: [String: Any]) -> PlotChunk {
        let c = PlotChunk(layer: o["l"] as? Int ?? 0, color: UInt32(o["c"] as? Int ?? 0), alpha: Float(o["a"] as? Int ?? 255) / 255)
        let mode = o["m"] as? Int ?? 1
        let r = Float(o["w"] as? Int ?? 0) / 2
        let ns = numbers(o["d"] as? String ?? "")
        var i = 0, px: Int32 = 0, py: Int32 = 0
        func next() -> Float? {
            guard i + 1 < ns.count else { return nil }
            let zx = ns[i], zy = ns[i + 1]
            i += 2
            px = px &+ Int32(bitPattern: (zx >> 1) ^ (0 &- (zx & 1)))
            py = py &+ Int32(bitPattern: (zy >> 1) ^ (0 &- (zy & 1)))
            return 0
        }
        switch mode {
        case 2:
            while next() != nil { c.caps += [Float(px), Float(py), Float(px), Float(py), r] }
        default:
            while i < ns.count {
                let n = Int(ns[i]); i += 1
                var pts: [Float] = []
                pts.reserveCapacity(n * 2)
                for _ in 0..<n where next() != nil { pts += [Float(px), Float(py)] }
                if mode == 0 { fan(pts, into: &c.tris) } else { path(pts, r, into: &c.caps) }
            }
        }
        return c
    }

    static func path(_ p: [Float], _ r: Float, into caps: inout [Float]) {
        if p.count == 2 { caps += [p[0], p[1], p[0], p[1], r]; return }
        var k = 2
        while k + 1 < p.count {
            caps += [p[k - 2], p[k - 1], p[k], p[k + 1], r]
            k += 2
        }
    }

    // a polygon as a triangle fan, turned counter-clockwise, so the
    // stencil's winding count fills every polygon of a layer as one union
    static func fan(_ p: [Float], into tris: inout [Float]) {
        let n = p.count / 2
        guard n >= 3 else { return }
        var area: Float = 0
        for k in 0..<n {
            let j = (k + 1) % n
            area += p[2 * k] * p[2 * j + 1] - p[2 * j] * p[2 * k + 1]
        }
        for k in 1..<(n - 1) {
            let (a, b) = area >= 0 ? (k, k + 1) : (k + 1, k)
            tris += [p[0], p[1], p[2 * a], p[2 * a + 1], p[2 * b], p[2 * b + 1]]
        }
    }
}

// What the renderer draws: the chunks in paint order and which of them
// just arrived (they fade in), the box for the first view, or why there
// is nothing to draw.
struct PlotFrame {
    let key: String
    let box: [Float]
    let chunks: [PlotChunk]
    let fresh: Set<Int>
    let none: String
    let at: Date
}

@MainActor
@Observable
final class PlotStore {
    private(set) var frame: PlotFrame?
    @ObservationIgnored private var held: [PlotChunk] = []
    @ObservationIgnored private let queue = DispatchQueue(label: "plot", qos: .userInitiated)
    @ObservationIgnored private var generation = 0

    // a plot frame: JSON text beginning so (PL.Plot.prefix); every other
    // frame is CBOR, which never begins with '{'
    private static let prefix = Data("{\"t\":\"plot\"".utf8)
    static func isPlot(_ d: Data) -> Bool { d.starts(with: prefix) }

    // a new connection holds nothing
    func reset() {
        generation += 1
        held = []
        frame = nil
    }

    // decoded off the main thread, applied in order
    func receive(_ text: String) {
        let gen = generation
        queue.async {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
            let key = o["key"] as? String ?? ""
            if let why = o["none"] as? String {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard gen == self.generation else { return }
                        self.held = []
                        self.frame = PlotFrame(key: key, box: [], chunks: [], fresh: [], none: why, at: Date())
                    }
                }
                return
            }
            let refs = o["cs"] as? [Any] ?? []
            var cs: [PlotChunk?] = Array(repeating: nil, count: refs.count)
            var fresh = Set<Int>()
            // new chunks decode side by side
            let objs = refs.enumerated().compactMap { i, r in (r as? [String: Any]).map { (i, $0) } }
            let decoded = UnsafeMutableBufferPointer<PlotChunk?>.allocate(capacity: objs.count)
            decoded.initialize(repeating: nil)
            DispatchQueue.concurrentPerform(iterations: objs.count) { k in decoded[k] = PlotChunk.decode(objs[k].1) }
            for (k, (i, _)) in objs.enumerated() { cs[i] = decoded[k]; fresh.insert(i) }
            decoded.deallocate()
            let box = (o["box"] as? [NSNumber] ?? []).map { $0.floatValue }
            // the main queue keeps arrival order: each plot applies to the
            // one before it
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard gen == self.generation else { return }
                    for (i, r) in refs.enumerated() {
                        if let k = r as? Int, k < self.held.count { cs[i] = self.held[k] }
                    }
                    let all = cs.compactMap { $0 }
                    self.held = all
                    self.frame = PlotFrame(key: key, box: box, chunks: all, fresh: fresh, none: "", at: Date())
                }
            }
        }
    }
}
