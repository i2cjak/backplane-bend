package dev.backplane.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.opengl.GLES30.*
import android.opengl.GLSurfaceView
import android.view.Choreographer
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

// The board viewer: a plot on the GPU (OpenGL ES 3). A plot is uploaded
// once; panning and zooming only move a transform, so every frame costs
// the same however big the board. Each layer is drawn as coverage (max
// blending: overlapping copper never darkens), then laid over the frame
// in its colour and opacity. Frames are drawn on demand: while a finger
// moves, a fade runs or a fling coasts, and never otherwise.

private const val CAP_V = """#version 300 es
layout(location = 0) in vec4 ab;
layout(location = 1) in float rr;
uniform vec2 size;
uniform vec2 off;
uniform float scale;
out vec2 p;
flat out vec2 A;
flat out vec2 B;
flat out float R;
void main() {
  vec2 a = ab.xy * scale + off;
  vec2 b = ab.zw * scale + off;
  float r = max(rr * scale, 0.5);
  vec2 d = b - a;
  float l = length(d);
  vec2 dir = l > 0.001 ? d / l : vec2(1.0, 0.0);
  vec2 n = vec2(-dir.y, dir.x);
  float pad = r + 1.0;
  vec2 uv = vec2((gl_VertexID & 1) == 1 ? 1.0 : -1.0, (gl_VertexID & 2) == 2 ? 1.0 : -1.0);
  vec2 q = (uv.x < 0.0 ? a - dir * pad : b + dir * pad) + n * (uv.y * pad);
  p = q; A = a; B = b; R = r;
  vec2 c = q / size * 2.0 - 1.0;
  gl_Position = vec4(c.x, -c.y, 0.0, 1.0);
}"""

private const val CAP_F = """#version 300 es
precision highp float;
in vec2 p;
flat in vec2 A;
flat in vec2 B;
flat in float R;
uniform float fade;
out vec4 o;
void main() {
  vec2 pa = p - A, ba = B - A;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  float d = length(pa - ba * h);
  o = vec4(clamp(R + 0.5 - d, 0.0, 1.0) * fade);
}"""

private const val FILL_V = """#version 300 es
layout(location = 0) in vec2 pt;
uniform vec2 size;
uniform vec2 off;
uniform float scale;
void main() {
  vec2 c = (pt * scale + off) / size * 2.0 - 1.0;
  gl_Position = vec4(c.x, -c.y, 0.0, 1.0);
}"""

private const val FILL_F = """#version 300 es
precision mediump float;
uniform float fade;
out vec4 o;
void main() { o = vec4(fade); }"""

private const val QUAD_V = """#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}"""

private const val QUAD_F = """#version 300 es
precision mediump float;
uniform sampler2D cov;
uniform vec4 color;
out vec4 o;
void main() {
  float a = texelFetch(cov, ivec2(gl_FragCoord.xy), 0).r * color.a;
  o = vec4(color.rgb * a, a);
}"""

private class Layer(val color: FloatArray, val caps: IntRange, val freshCaps: IntRange, val tris: IntRange, val freshTris: IntRange)

private class Program(v: String, f: String) {
    val id: Int = glCreateProgram()
    init {
        for ((kind, src) in listOf(GL_VERTEX_SHADER to v, GL_FRAGMENT_SHADER to f)) {
            val s = glCreateShader(kind)
            glShaderSource(s, src)
            glCompileShader(s)
            val ok = IntArray(1)
            glGetShaderiv(s, GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) throw IllegalStateException("plot shader: " + glGetShaderInfoLog(s))
            glAttachShader(id, s)
        }
        glLinkProgram(id)
    }
    fun at(name: String) = glGetUniformLocation(id, name)
}

class PlotRenderer : GLSurfaceView.Renderer {
    @Volatile var scale = 0.01f
    @Volatile var offX = 0f
    @Volatile var offY = 0f
    @Volatile var fade = 1f
    @Volatile var bg = floatArrayOf(0f, 0f, 0f)
    private lateinit var cap: Program
    private lateinit var fill: Program
    private lateinit var quad: Program
    private val bufs = IntArray(2)
    private var vao = IntArray(1)
    private var fbo = IntArray(1)
    private var tex = IntArray(1)
    private var rb = IntArray(1)
    private var w = 0
    private var h = 0
    private var layers: List<Layer> = emptyList()

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        cap = Program(CAP_V, CAP_F)
        fill = Program(FILL_V, FILL_F)
        quad = Program(QUAD_V, QUAD_F)
        glGenBuffers(2, bufs, 0)
        glGenVertexArrays(1, vao, 0)
        glGenFramebuffers(1, fbo, 0)
        glGenTextures(1, tex, 0)
        glGenRenderbuffers(1, rb, 0)
        w = 0
        h = 0
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        w = width
        h = height
        glBindTexture(GL_TEXTURE_2D, tex[0])
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, w, h, 0, GL_RED, GL_UNSIGNED_BYTE, null)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glBindRenderbuffer(GL_RENDERBUFFER, rb[0])
        glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, w, h)
        glBindFramebuffer(GL_FRAMEBUFFER, fbo[0])
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex[0], 0)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rb[0])
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
    }

    private fun put(buf: Int, data: FloatArray) {
        val b = ByteBuffer.allocateDirect(max(data.size, 1) * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        b.put(data).position(0)
        glBindBuffer(GL_ARRAY_BUFFER, buf)
        glBufferData(GL_ARRAY_BUFFER, data.size * 4, b, GL_STATIC_DRAW)
    }

    // a plot's chunks into two buffers, layer by layer (the hub sends them
    // in paint order); runs on the GL thread
    fun load(chunks: List<PlotChunk>, fresh: Set<Int>) {
        val caps = Floats()
        val tris = Floats()
        val out = ArrayList<Layer>()
        var i = 0
        while (i < chunks.size) {
            val first = chunks[i]
            var j = i
            while (j < chunks.size && chunks[j].layer == first.layer) j++
            val c0 = caps.size / 5
            val t0 = tris.size / 2
            for (k in i until j) if (k !in fresh) { caps.addAll(chunks[k].caps); tris.addAll(chunks[k].tris) }
            val c1 = caps.size / 5
            val t1 = tris.size / 2
            for (k in i until j) if (k in fresh) { caps.addAll(chunks[k].caps); tris.addAll(chunks[k].tris) }
            val rgb = first.color
            out.add(Layer(floatArrayOf(((rgb shr 16) and 255) / 255f, ((rgb shr 8) and 255) / 255f, (rgb and 255) / 255f, first.alpha),
                c0 until c1, c1 until caps.size / 5, t0 until t1, t1 until tris.size / 2))
            i = j
        }
        put(bufs[0], caps.array())
        put(bufs[1], tris.array())
        layers = out
    }

    private fun view(p: Program) {
        glUniform2f(p.at("size"), w.toFloat(), h.toFloat())
        glUniform2f(p.at("off"), offX, offY)
        glUniform1f(p.at("scale"), scale)
    }

    override fun onDrawFrame(gl: GL10?) {
        glBindVertexArray(vao[0])
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glViewport(0, 0, w, h)
        glClearColor(bg[0], bg[1], bg[2], 1f)
        glClear(GL_COLOR_BUFFER_BIT)
        glDisable(GL_CULL_FACE)
        for (l in layers) {
            glBindFramebuffer(GL_FRAMEBUFFER, fbo[0])
            glClearColor(0f, 0f, 0f, 0f)
            glClearStencil(0)
            glStencilMask(0xFF)
            glColorMask(true, true, true, true)
            glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)
            glEnable(GL_BLEND)
            glBlendEquation(GL_MAX)
            glBlendFunc(GL_ONE, GL_ONE)
            // fills: count the winding in the stencil, then cover where it is not zero
            glUseProgram(fill.id)
            view(fill)
            glBindBuffer(GL_ARRAY_BUFFER, bufs[1])
            glVertexAttribDivisor(0, 0)
            glDisableVertexAttribArray(1)
            glEnableVertexAttribArray(0)
            for ((r, f) in listOf(l.tris to 1f, l.freshTris to fade)) {
                if (r.isEmpty()) continue
                glUniform1f(fill.at("fade"), f)
                glVertexAttribPointer(0, 2, GL_FLOAT, false, 8, r.first * 8)
                glEnable(GL_STENCIL_TEST)
                glColorMask(false, false, false, false)
                glStencilFunc(GL_ALWAYS, 0, 0xFF)
                glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP)
                glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP)
                glDrawArrays(GL_TRIANGLES, 0, r.last - r.first + 1)
                glColorMask(true, true, true, true)
                glStencilFunc(GL_NOTEQUAL, 0, 0xFF)
                glStencilOp(GL_KEEP, GL_KEEP, GL_ZERO)
                glDrawArrays(GL_TRIANGLES, 0, r.last - r.first + 1)
                glDisable(GL_STENCIL_TEST)
            }
            // capsules: tracks, outlines, arcs and dots
            glUseProgram(cap.id)
            view(cap)
            glBindBuffer(GL_ARRAY_BUFFER, bufs[0])
            glEnableVertexAttribArray(0)
            glEnableVertexAttribArray(1)
            glVertexAttribDivisor(0, 1)
            glVertexAttribDivisor(1, 1)
            for ((r, f) in listOf(l.caps to 1f, l.freshCaps to fade)) {
                if (r.isEmpty()) continue
                glUniform1f(cap.at("fade"), f)
                glVertexAttribPointer(0, 4, GL_FLOAT, false, 20, r.first * 20)
                glVertexAttribPointer(1, 1, GL_FLOAT, false, 20, r.first * 20 + 16)
                glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, r.last - r.first + 1)
            }
            glVertexAttribDivisor(0, 0)
            glVertexAttribDivisor(1, 0)
            glDisableVertexAttribArray(0)
            glDisableVertexAttribArray(1)
            // the layer over the frame
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            glBlendEquation(GL_FUNC_ADD)
            glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
            glUseProgram(quad.id)
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, tex[0])
            glUniform1i(quad.at("cov"), 0)
            glUniform4f(quad.at("color"), l.color[0], l.color[1], l.color[2], l.color[3])
            glDrawArrays(GL_TRIANGLES, 0, 3)
        }
    }
}

@SuppressLint("ViewConstructor")
class PlotSurface(context: Context) : GLSurfaceView(context) {
    val renderer = PlotRenderer()
    var box = FloatArray(0)
    var margin = 0.9f
    var zmin = 0.5f
    var zmax = 0.5f
    var fadeMs = 220f
    private var fitted = false
    private var fadeFrom = 0L
    private var flingX = 0f
    private var flingY = 0f
    private var last = 0L
    private var ticking = false
    private var shown: PlotFrame? = null

    init {
        setEGLContextClientVersion(3)
        setEGLConfigChooser(8, 8, 8, 8, 0, 0)
        preserveEGLContextOnPause = true
        setRenderer(renderer)
        renderMode = RENDERMODE_WHEN_DIRTY
    }

    // the zoom that shows the whole box, and the range around it (pixels)
    private val fit: Float
        get() = if (box.size < 4 || width == 0) renderer.scale
        else margin * min(width / max(box[2] - box[0], 1f), height / max(box[3] - box[1], 1f))

    fun refit() {
        if (box.size < 4 || width == 0) return
        val s = fit
        renderer.scale = s
        renderer.offX = width / 2f - (box[0] + box[2]) / 2 * s
        renderer.offY = height / 2f - (box[1] + box[3]) / 2 * s
        fitted = true
        requestRender()
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        if (!fitted) refit()
    }

    fun show(f: PlotFrame, bg: Int) {
        if (f === shown) return
        shown = f
        renderer.bg = floatArrayOf(((bg shr 16) and 255) / 255f, ((bg shr 8) and 255) / 255f, (bg and 255) / 255f)
        queueEvent { renderer.load(f.chunks, f.fresh) }
        val first = box.isEmpty() || !fitted
        box = f.box
        if (first) { fitted = false; refit() }
        fadeFrom = if (f.fresh.isEmpty()) 0 else f.at
        renderer.fade = if (f.fresh.isEmpty()) 1f else 0f
        run()
        requestRender()
    }

    private fun zoom(by: Float, x: Float, y: Float) {
        val s0 = renderer.scale
        val s = min(max(s0 * by, fit * zmin), max(zmax, fit))
        val k = s / s0
        renderer.offX = x - (x - renderer.offX) * k
        renderer.offY = y - (y - renderer.offY) * k
        renderer.scale = s
    }

    private val scaler = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean {
            zoom(d.scaleFactor, d.focusX, d.focusY)
            requestRender()
            return true
        }
    })

    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean {
            flingX = 0f
            flingY = 0f
            return true
        }

        override fun onScroll(a: MotionEvent?, b: MotionEvent, dx: Float, dy: Float): Boolean {
            renderer.offX -= dx
            renderer.offY -= dy
            requestRender()
            return true
        }

        override fun onFling(a: MotionEvent?, b: MotionEvent, vx: Float, vy: Float): Boolean {
            flingX = vx
            flingY = vy
            run()
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            if (renderer.scale > fit * 1.5f) refit() else zoom(3f, e.x, e.y)
            requestRender()
            return true
        }
    })

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        gestures.onTouchEvent(e)
        return true
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(now: Long) {
            val dt = if (last == 0L) 0f else (now - last) / 1e9f
            last = now
            var busy = false
            if (fadeFrom != 0L) {
                val f = min(1f, (System.currentTimeMillis() - fadeFrom) / fadeMs)
                renderer.fade = f
                if (f >= 1f) fadeFrom = 0 else busy = true
            }
            if (hypot(flingX, flingY) > 8f) {
                renderer.offX += flingX * dt
                renderer.offY += flingY * dt
                val k = exp(-5.5f * dt)
                flingX *= k
                flingY *= k
                busy = true
            } else {
                flingX = 0f
                flingY = 0f
            }
            requestRender()
            if (busy) Choreographer.getInstance().postFrameCallback(this) else ticking = false
        }
    }

    // frames by themselves only while a fade or a fling runs
    private fun run() {
        if (ticking) return
        ticking = true
        last = 0L
        Choreographer.getInstance().postFrameCallback(frame)
    }
}
