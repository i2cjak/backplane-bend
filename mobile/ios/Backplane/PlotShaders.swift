// The board viewer's shaders, compiled on the device the first time the
// viewer opens (so building the app needs no Metal toolchain).
//
// Each layer is drawn as coverage (R8, max blending, so overlapping copper
// never darkens), then laid over the frame in its colour and opacity.
// Tracks, outlines and dots are capsules with an analytic edge; fills go
// through the stencil (nonzero), so no polygon is triangulated beyond a
// fan. In 3D the same capsules are drawn on the board's faces: each end is
// projected, the capsule is widened in pixels by its depth, and the edge
// is measured in pixels, so layers stay sharp at any angle; the model's
// depth hides what is behind parts.
enum PlotShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct U {
    float2 size;   // drawable, pixels
    float2 off;    // 2D: where micrometre 0,0 lands, pixels
    float scale;   // 2D: pixels per micrometre
    float fade;    // coverage multiplier (a chunk fading in)
    float z;       // 3D: the face's height, micrometres
    float focal;   // 3D: pixels per unit at depth 1
    float4 color;  // the layer's colour and opacity
    float4x4 mvp;  // 3D: micrometres to clip space
    float4 light;  // 3D: towards the light
};

struct Cap { float ax, ay, bx, by, r; };

struct CapOut {
    float4 pos [[position]];
    float2 a [[flat]];
    float2 b [[flat]];
    float r [[flat]];
};

static float4 clip(float2 p, float2 size) {
    float2 c = p / size * 2.0 - 1.0;
    return float4(c.x, -c.y, 0, 1);
}

static float2 corner(uint vid, float2 A, float2 B, float R, thread float2 &dir) {
    float2 d = B - A;
    float l = length(d);
    dir = l > 0.001 ? d / l : float2(1, 0);
    float2 n = float2(-dir.y, dir.x);
    float pad = R + 1.0;
    float2 uv = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    return (uv.x < 0 ? A - dir * pad : B + dir * pad) + n * (uv.y * pad);
}

vertex CapOut cap_v(uint vid [[vertex_id]], uint iid [[instance_id]],
                    const device Cap *caps [[buffer(0)]], constant U &u [[buffer(1)]]) {
    Cap c = caps[iid];
    float2 A = float2(c.ax, c.ay) * u.scale + u.off;
    float2 B = float2(c.bx, c.by) * u.scale + u.off;
    // never thinner than a pixel (a zero-width KiCad line is a hairline)
    float R = max(c.r * u.scale, 0.5);
    float2 dir;
    float2 p = corner(vid, A, B, R, dir);
    CapOut o;
    o.pos = clip(p, u.size);
    o.a = A;
    o.b = B;
    o.r = R;
    return o;
}

// the same capsule on a face in 3D: its ends projected, its width by depth
vertex CapOut cap3_v(uint vid [[vertex_id]], uint iid [[instance_id]],
                     const device Cap *caps [[buffer(0)]], constant U &u [[buffer(1)]]) {
    Cap c = caps[iid];
    float4 ca = u.mvp * float4(c.ax, c.ay, u.z, 1);
    float4 cb = u.mvp * float4(c.bx, c.by, u.z, 1);
    ca.w = max(ca.w, 1e-3);
    cb.w = max(cb.w, 1e-3);
    float2 A = float2(ca.x / ca.w * 0.5 + 0.5, 0.5 - ca.y / ca.w * 0.5) * u.size;
    float2 B = float2(cb.x / cb.w * 0.5 + 0.5, 0.5 - cb.y / cb.w * 0.5) * u.size;
    float R = max(c.r * u.focal / max(min(ca.w, cb.w), 1e-3), 0.5);
    float2 dir;
    float2 p = corner(vid, A, B, R, dir);
    float4 e = (vid & 1) ? cb : ca;
    float2 n = p / u.size * 2.0 - 1.0;
    CapOut o;
    o.pos = float4(n.x * e.w, -n.y * e.w, e.z, e.w);
    o.a = A;
    o.b = B;
    o.r = R;
    return o;
}

// the edge is measured at the pixel itself (its position is in pixels)
fragment float4 cap_f(CapOut i [[stage_in]], constant U &u [[buffer(1)]]) {
    float2 pa = i.pos.xy - i.a, ba = i.b - i.a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    float d = length(pa - ba * h);
    return float4(clamp(i.r + 0.5 - d, 0.0, 1.0) * u.fade);
}

vertex float4 fill_v(uint vid [[vertex_id]], const device packed_float2 *pts [[buffer(0)]], constant U &u [[buffer(1)]]) {
    return clip(float2(pts[vid]) * u.scale + u.off, u.size);
}

vertex float4 fill3_v(uint vid [[vertex_id]], const device packed_float2 *pts [[buffer(0)]], constant U &u [[buffer(1)]]) {
    return u.mvp * float4(float2(pts[vid]), u.z, 1);
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

// the model: lit from the viewer (both sides of a face)
struct MV { packed_float3 p; packed_float3 n; };
struct MOut { float4 pos [[position]]; float3 c; };

vertex MOut mesh_v(uint vid [[vertex_id]], const device MV *vs [[buffer(0)]], const device uint *cs [[buffer(2)]], constant U &u [[buffer(1)]]) {
    MV v = vs[vid];
    uint c = cs[vid];
    float k = 0.35 + 0.65 * abs(dot(normalize(float3(v.n)), u.light.xyz));
    MOut o;
    o.pos = u.mvp * float4(float3(v.p), 1);
    o.c = float3((c >> 16) & 255, (c >> 8) & 255, c & 255) / 255.0 * k;
    return o;
}

fragment float4 mesh_f(MOut i [[stage_in]]) {
    return float4(i.c, 1);
}
"""#
}
