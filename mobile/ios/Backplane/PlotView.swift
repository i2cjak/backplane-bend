import MetalKit
import SwiftUI

// The board viewer: a plot on the GPU. A plot is uploaded once; panning
// and zooming only move a transform, so every frame costs the same however
// big the board. Frames are drawn on demand: while a finger moves, a fade
// runs or a fling coasts, and never otherwise.

private struct Uniforms {
    var size: SIMD2<Float>
    var off: SIMD2<Float>
    var scale: Float
    var fade: Float
    var pad = SIMD2<Float>(0, 0)
    var color: SIMD4<Float>
}

// one layer's share of the buffers: capsules and fill vertices, the chunks
// already shown first, then those fading in
private struct LayerDraw {
    var color: SIMD4<Float>
    var caps: Range<Int>
    var freshCaps: Range<Int>
    var tris: Range<Int>
    var freshTris: Range<Int>
}

@MainActor
final class PlotRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let capPipe, fillStencilPipe, fillCoverPipe, quadPipe: MTLRenderPipelineState
    private let plain, stencilWrite, stencilCover: MTLDepthStencilState
    private var capBuf, triBuf: MTLBuffer?
    private var layers: [LayerDraw] = []
    private var cov, stencil: MTLTexture?
    var bg = SIMD4<Float>(0, 0, 0, 1)
    // view: pixels per micrometre and where 0,0 lands, in points
    var scale: Float = 0.01
    var off = SIMD2<Float>(0, 0)
    var fade: Float = 1

    private static var compiled: MTLLibrary?

    private static func library(_ d: MTLDevice) -> MTLLibrary? {
        if let l = compiled { return l }
        do {
            compiled = try d.makeLibrary(source: PlotShaders.source, options: nil)
        } catch {
            NSLog("plot shaders: %@", "\(error)")
        }
        return compiled
    }

    init?(view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue(), let lib = Self.library(d) else { return nil }
        device = d
        queue = q
        view.device = d
        view.colorPixelFormat = .bgra8Unorm
        func pipe(_ v: String, _ f: String, _ fmt: MTLPixelFormat, stencil: Bool, write: Bool = true, over: Bool = false) -> MTLRenderPipelineState? {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = lib.makeFunction(name: v)
            p.fragmentFunction = lib.makeFunction(name: f)
            let c = p.colorAttachments[0]!
            c.pixelFormat = fmt
            c.writeMask = write ? .all : []
            if write {
                c.isBlendingEnabled = true
                if over {
                    c.sourceRGBBlendFactor = .one
                    c.sourceAlphaBlendFactor = .one
                    c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                } else {
                    c.rgbBlendOperation = .max
                    c.alphaBlendOperation = .max
                    c.sourceRGBBlendFactor = .one
                    c.destinationRGBBlendFactor = .one
                    c.sourceAlphaBlendFactor = .one
                    c.destinationAlphaBlendFactor = .one
                }
            }
            if stencil { p.stencilAttachmentPixelFormat = .stencil8 }
            return try? d.makeRenderPipelineState(descriptor: p)
        }
        guard let cp = pipe("cap_v", "cap_f", .r8Unorm, stencil: true),
              let fs = pipe("fill_v", "fill_f", .r8Unorm, stencil: true, write: false),
              let fc = pipe("fill_v", "fill_f", .r8Unorm, stencil: true),
              let qp = pipe("quad_v", "quad_f", .bgra8Unorm, stencil: false, over: true) else { return nil }
        capPipe = cp
        fillStencilPipe = fs
        fillCoverPipe = fc
        quadPipe = qp
        plain = d.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())!
        // nonzero winding: counter-clockwise triangles count up, others down
        let w = MTLDepthStencilDescriptor()
        let up = MTLStencilDescriptor(), down = MTLStencilDescriptor()
        up.depthStencilPassOperation = .incrementWrap
        down.depthStencilPassOperation = .decrementWrap
        w.frontFaceStencil = up
        w.backFaceStencil = down
        stencilWrite = d.makeDepthStencilState(descriptor: w)!
        // cover where the count is not zero, and zero it again
        let c = MTLDepthStencilDescriptor(), s = MTLStencilDescriptor()
        s.stencilCompareFunction = .notEqual
        s.depthStencilPassOperation = .zero
        c.frontFaceStencil = s
        c.backFaceStencil = s
        stencilCover = d.makeDepthStencilState(descriptor: c)!
        super.init()
    }

    // a plot's chunks into two buffers, layer by layer (the hub sends them
    // in paint order)
    func load(_ chunks: [PlotChunk], fresh: Set<Int>) {
        var caps: [Float] = [], tris: [Float] = []
        caps.reserveCapacity(chunks.reduce(0) { $0 + $1.caps.count })
        tris.reserveCapacity(chunks.reduce(0) { $0 + $1.tris.count })
        var out: [LayerDraw] = []
        var i = 0
        while i < chunks.count {
            let first = chunks[i]
            var j = i
            while j < chunks.count, chunks[j].layer == first.layer { j += 1 }
            let c0 = caps.count / 5, t0 = tris.count / 2
            for k in i..<j where !fresh.contains(k) { caps += chunks[k].caps; tris += chunks[k].tris }
            let c1 = caps.count / 5, t1 = tris.count / 2
            for k in i..<j where fresh.contains(k) { caps += chunks[k].caps; tris += chunks[k].tris }
            let rgb = first.color
            out.append(LayerDraw(
                color: SIMD4(Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, first.alpha),
                caps: c0..<c1, freshCaps: c1..<(caps.count / 5), tris: t0..<t1, freshTris: t1..<(tris.count / 2)))
            i = j
        }
        capBuf = caps.isEmpty ? nil : device.makeBuffer(bytes: caps, length: caps.count * 4, options: .storageModeShared)
        triBuf = tris.isEmpty ? nil : device.makeBuffer(bytes: tris, length: tris.count * 4, options: .storageModeShared)
        layers = out
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cov = nil
    }

    private func targets(_ w: Int, _ h: Int) {
        if let c = cov, c.width == w, c.height == h { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        cov = device.makeTexture(descriptor: d)
        let s = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .stencil8, width: w, height: h, mipmapped: false)
        s.usage = .renderTarget
        s.storageMode = .memoryless
        stencil = device.makeTexture(descriptor: s)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        let w = Int(view.drawableSize.width), h = Int(view.drawableSize.height)
        guard w > 0, h > 0 else { return }
        targets(w, h)
        let k = Float(view.contentScaleFactor)
        var u = Uniforms(size: SIMD2(Float(w), Float(h)), off: off * k, scale: scale * k, fade: 1, color: .zero)
        var first = true
        for l in layers {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = cov
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            pass.stencilAttachment.texture = stencil
            pass.stencilAttachment.loadAction = .clear
            pass.stencilAttachment.storeAction = .dontCare
            guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
            e.setFrontFacing(.counterClockwise)
            e.setCullMode(.none)
            for (r, f) in [(l.tris, Float(1)), (l.freshTris, fade)] where !r.isEmpty {
                u.fade = f
                e.setVertexBuffer(triBuf, offset: r.lowerBound * 8, index: 0)
                e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                e.setRenderPipelineState(fillStencilPipe)
                e.setDepthStencilState(stencilWrite)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.count)
                e.setRenderPipelineState(fillCoverPipe)
                e.setDepthStencilState(stencilCover)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.count)
            }
            e.setRenderPipelineState(capPipe)
            e.setDepthStencilState(plain)
            for (r, f) in [(l.caps, Float(1)), (l.freshCaps, fade)] where !r.isEmpty {
                u.fade = f
                e.setVertexBuffer(capBuf, offset: r.lowerBound * 20, index: 0)
                e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: r.count)
            }
            e.endEncoding()
            let over = MTLRenderPassDescriptor()
            over.colorAttachments[0].texture = drawable.texture
            over.colorAttachments[0].loadAction = first ? .clear : .load
            over.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
            over.colorAttachments[0].storeAction = .store
            first = false
            guard let q = cb.makeRenderCommandEncoder(descriptor: over) else { return }
            u.color = l.color
            q.setRenderPipelineState(quadPipe)
            q.setFragmentTexture(cov, index: 0)
            q.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            q.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            q.endEncoding()
        }
        if first {
            let over = MTLRenderPassDescriptor()
            over.colorAttachments[0].texture = drawable.texture
            over.colorAttachments[0].loadAction = .clear
            over.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
            over.colorAttachments[0].storeAction = .store
            cb.makeRenderCommandEncoder(descriptor: over)?.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
    }
}

// The view: gestures move the transform; a display link runs only while
// something moves by itself (a fade, a fling).
final class PlotCanvas: MTKView {
    var renderer: PlotRenderer!
    var box: [Float] = []
    var margin: Float = 0.9
    var zmin: Float = 0.5
    var zmax: Float = 0.5
    var fadeMs: Double = 220
    private var fitted = false
    private var fadeFrom: Date?
    private var fling = SIMD2<Float>(0, 0)
    private var link: CADisplayLink?
    private var lastTick = CACurrentMediaTime()

    init?(canvas frame: CGRect) {
        super.init(frame: frame, device: nil)
        guard let r = PlotRenderer(view: self) else { return nil }
        renderer = r
        delegate = r
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 120
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 2
        let twice = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        twice.numberOfTapsRequired = 2
        for g in [pinch, pan, twice] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    required init(coder: NSCoder) { fatalError() }

    // the zoom that shows the whole box, and the range around it
    private var fit: Float {
        guard box.count == 4 else { return renderer.scale }
        let w = Float(bounds.width), h = Float(bounds.height)
        return margin * min(w / max(box[2] - box[0], 1), h / max(box[3] - box[1], 1))
    }

    func refit() {
        guard box.count == 4, bounds.width > 0 else { return }
        let s = fit
        renderer.scale = s
        renderer.off = SIMD2(Float(bounds.width) / 2 - (box[0] + box[2]) / 2 * s, Float(bounds.height) / 2 - (box[1] + box[3]) / 2 * s)
        fitted = true
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !fitted { refit() }
    }

    func show(_ f: PlotFrame, bg: UInt32) {
        renderer.bg = SIMD4(Float((bg >> 16) & 255) / 255, Float((bg >> 8) & 255) / 255, Float(bg & 255) / 255, 1)
        renderer.load(f.chunks, fresh: f.fresh)
        if box.isEmpty || !fitted { box = f.box; fitted = false; setNeedsLayout() } else { box = f.box }
        fadeFrom = f.fresh.isEmpty ? nil : f.at
        renderer.fade = f.fresh.isEmpty ? 1 : 0
        run()
        setNeedsDisplay()
    }

    private func zoom(by f: Float, at p: CGPoint) {
        let s0 = renderer.scale
        let s = min(max(s0 * f, fit * zmin), max(zmax, fit))
        let k = s / s0
        let a = SIMD2(Float(p.x), Float(p.y))
        renderer.off = a - (a - renderer.off) * k
        renderer.scale = s
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        zoom(by: Float(g.scale), at: g.location(in: self))
        g.scale = 1
        setNeedsDisplay()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        renderer.off += SIMD2(Float(t.x), Float(t.y))
        g.setTranslation(.zero, in: self)
        if g.state == .began { fling = .zero }
        if g.state == .ended {
            let v = g.velocity(in: self)
            fling = SIMD2(Float(v.x), Float(v.y))
            run()
        }
        setNeedsDisplay()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let s0 = renderer.scale
        if s0 > fit * 1.5 { refit() } else { zoom(by: 3, at: g.location(in: self)) }
        setNeedsDisplay()
    }

    private func run() {
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = Float(now - lastTick)
        lastTick = now
        var busy = false
        if let t0 = fadeFrom {
            let f = Float(min(1, Date().timeIntervalSince(t0) * 1000 / fadeMs))
            renderer.fade = f
            if f >= 1 { fadeFrom = nil } else { busy = true }
        }
        if simd_length(fling) > 8 {
            renderer.off += fling * dt
            fling *= pow(0.004, dt)
            busy = true
        } else {
            fling = .zero
        }
        setNeedsDisplay()
        if !busy {
            link?.invalidate()
            link = nil
        }
    }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }
}

extension PlotCanvas: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

struct PlotCanvasView: UIViewRepresentable {
    let frame: PlotFrame?
    let viewer: Viewer

    func makeUIView(context: Context) -> UIView {
        guard let c = PlotCanvas(canvas: .zero) else {
            let l = UILabel()
            l.text = "This device has no Metal."
            l.textAlignment = .center
            return l
        }
        return c
    }

    func updateUIView(_ v: UIView, context: Context) {
        guard let c = v as? PlotCanvas else { return }
        c.margin = viewer.margin
        c.zmin = viewer.zmin
        c.zmax = viewer.zmax
        c.fadeMs = Double(viewer.fade)
        if let f = frame, f.at != context.coordinator.shown {
            context.coordinator.shown = f.at
            c.show(f, bg: viewer.bg)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var shown: Date? }
}

// The viewer over the thread: the plot of the screen's source, the source
// choices, and a way back.
struct PlotScreen: View {
    let model: AppModel
    let viewer: Viewer

    var body: some View {
        // a plot for any other source is stale (a switch in flight)
        let f = model.plots.frame.flatMap { $0.key == viewer.key ? $0 : nil }
        ZStack(alignment: .top) {
            Color(rgb: viewer.bg).ignoresSafeArea()
            PlotCanvasView(frame: f?.none.isEmpty == true ? f : nil, viewer: viewer).ignoresSafeArea()
            if f == nil {
                ProgressView().tint(.white).frame(maxHeight: .infinity)
            } else if let why = f?.none, !why.isEmpty {
                Text(why).foregroundStyle(.secondary).frame(maxHeight: .infinity)
            }
            HStack {
                Picker("Source", selection: Binding(get: { viewer.open }, set: { model.act("view", $0) })) {
                    ForEach(viewer.choices, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                Spacer()
                Button { model.act("view", "") } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
