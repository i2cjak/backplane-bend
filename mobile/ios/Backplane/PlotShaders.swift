// The board viewer's shaders, compiled on the device the first time the
// viewer opens (so building the app needs no Metal toolchain).
enum PlotShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// The board viewer's shaders. Each layer is drawn as coverage (R8, max
// blending, so overlapping copper never darkens), then laid over the
// frame in its colour and opacity. Tracks, outlines and dots are capsules
// with an analytic edge; fills go through the stencil (nonzero), so no
// polygon is ever triangulated beyond a fan.

struct U {
    float2 size;   // drawable, pixels
    float2 off;    // where micrometre 0,0 lands, pixels
    float scale;   // pixels per micrometre
    float fade;    // coverage multiplier (a chunk fading in)
    float2 pad;
    float4 color;  // the layer's colour and opacity
};

struct Cap { float ax, ay, bx, by, r; };

struct CapOut {
    float4 pos [[position]];
    float2 p;
    float2 a [[flat]];
    float2 b [[flat]];
    float r [[flat]];
};

static float4 clip(float2 p, float2 size) {
    float2 c = p / size * 2.0 - 1.0;
    return float4(c.x, -c.y, 0, 1);
}

vertex CapOut cap_v(uint vid [[vertex_id]], uint iid [[instance_id]],
                    const device Cap *caps [[buffer(0)]], constant U &u [[buffer(1)]]) {
    Cap c = caps[iid];
    float2 A = float2(c.ax, c.ay) * u.scale + u.off;
    float2 B = float2(c.bx, c.by) * u.scale + u.off;
    // never thinner than a pixel (a zero-width KiCad line is a hairline)
    float R = max(c.r * u.scale, 0.5);
    float2 d = B - A;
    float l = length(d);
    float2 dir = l > 0.001 ? d / l : float2(1, 0);
    float2 n = float2(-dir.y, dir.x);
    float pad = R + 1.0;
    float2 uv = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    float2 p = (uv.x < 0 ? A - dir * pad : B + dir * pad) + n * (uv.y * pad);
    CapOut o;
    o.pos = clip(p, u.size);
    o.p = p;
    o.a = A;
    o.b = B;
    o.r = R;
    return o;
}

fragment float4 cap_f(CapOut i [[stage_in]], constant U &u [[buffer(1)]]) {
    float2 pa = i.p - i.a, ba = i.b - i.a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    float d = length(pa - ba * h);
    return float4(clamp(i.r + 0.5 - d, 0.0, 1.0) * u.fade);
}

vertex float4 fill_v(uint vid [[vertex_id]], const device packed_float2 *pts [[buffer(0)]], constant U &u [[buffer(1)]]) {
    return clip(float2(pts[vid]) * u.scale + u.off, u.size);
}

fragment float4 fill_f(constant U &u [[buffer(1)]]) {
    return float4(u.fade);
}

struct QOut { float4 pos [[position]]; };

vertex QOut quad_v(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    QOut o;
    o.pos = float4(p * 2.0 - 1.0, 0, 1);
    return o;
}

fragment float4 quad_f(QOut i [[stage_in]], texture2d<float> cov [[texture(0)]], constant U &u [[buffer(1)]]) {
    float a = cov.read(uint2(i.pos.xy)).r * u.color.a;
    return float4(u.color.rgb * a, a);
}
"""#
}
