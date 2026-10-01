import SceneKit
import simd

/// One cross-section of a lofted body part.
struct Ring {
    var c: V3          // centre
    var rx: Float      // half-width (side axis)
    var ry: Float      // half-depth (reference axis)
    var e: Float = 2   // superellipse exponent: 2 round, 3-4 boxier
    init(_ c: V3, _ rx: Float, _ ry: Float, e: Float = 2) { self.c = c; self.rx = rx; self.ry = ry; self.e = e }
}

/// Catmull-Rom resampling so a handful of control rings becomes a smooth organic surface.
func smoothRings(_ k: [Ring], per: Int = 4) -> [Ring] {
    guard k.count > 2 else { return k }
    var out: [Ring] = []
    func cr(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
    }
    for i in 0..<(k.count - 1) {
        let a = k[max(0, i - 1)], b = k[i], c = k[i + 1], d = k[min(k.count - 1, i + 2)]
        for s in 0..<per {
            let t = Float(s) / Float(per)
            let p = V3(cr(a.c.x, b.c.x, c.c.x, d.c.x, t), cr(a.c.y, b.c.y, c.c.y, d.c.y, t), cr(a.c.z, b.c.z, c.c.z, d.c.z, t))
            out.append(Ring(p, max(0.001, cr(a.rx, b.rx, c.rx, d.rx, t)), max(0.001, cr(a.ry, b.ry, c.ry, d.ry, t)), e: mixf(b.e, c.e, t)))
        }
    }
    out.append(k[k.count - 1])
    return out
}

/// Builds a closed tube through the rings (end caps fan to a point). `ref` picks each ring's depth
/// axis: the component of `ref` perpendicular to the path. UVs run around (u) and along in metres (v).
func loft(_ rings: [Ring], seg: Int = 22, ref: V3 = V3(0, 0, 1), vScale: Float = 1, uScale: Float = 1,
          displace: ((V3, V3, Float, Float) -> Float)? = nil) -> SCNGeometry {
    let n = rings.count
    let cols = seg + 1
    var pos = [V3](repeating: .zero, count: n * cols)
    var uv = [SIMD2<Float>](repeating: .zero, count: n * cols)
    var arc: Float = 0
    for i in 0..<n {
        let r = rings[i]
        let prev = rings[max(0, i - 1)].c, next = rings[min(n - 1, i + 1)].c
        var t = next - prev
        if simd_length(t) < 1e-6 { t = V3(0, 1, 0) }
        t = simd_normalize(t)
        var a = ref - simd_dot(ref, t) * t
        if simd_length(a) < 1e-4 { a = V3(1, 0, 0) - simd_dot(V3(1, 0, 0), t) * t }
        a = simd_normalize(a)
        let b = simd_cross(t, a)
        if i > 0 { arc += simd_length(r.c - rings[i - 1].c) }
        for j in 0...seg {
            let th = Float(j) / Float(seg) * 2 * .pi
            let cs = cosf(th), sn = sinf(th)
            let pe = 2 / r.e
            let sx = copysign(powf(abs(cs), pe), cs), sy = copysign(powf(abs(sn), pe), sn)
            var p = r.c + b * (sx * r.rx) + a * (sy * r.ry)
            if let d = displace {
                let outward = simd_normalize(b * sx * r.ry + a * sy * r.rx + V3(0, 0.0001, 0))
                p += outward * d(p, outward, Float(j) / Float(seg), Float(i) / Float(max(1, n - 1)))
            }
            pos[i * cols + j] = p
            uv[i * cols + j] = SIMD2(Float(j) / Float(seg) * uScale, arc * vScale)
        }
    }
    // smooth normals from the grid, flipped outward
    var nor = [V3](repeating: V3(0, 1, 0), count: n * cols)
    for i in 0..<n {
        for j in 0...seg {
            let jl = j == 0 ? seg - 1 : j - 1, jr = j == seg ? 1 : j + 1
            let il = max(0, i - 1), ir = min(n - 1, i + 1)
            let du = pos[i * cols + jr] - pos[i * cols + jl]
            let dv = pos[ir * cols + j] - pos[il * cols + j]
            var nv = simd_cross(du, dv)
            if simd_length(nv) < 1e-9 {
                nv = pos[i * cols + j] - rings[i].c
                if simd_length(nv) < 1e-9 { nv = (i == 0 ? -1 : 1) * (rings[min(n - 1, 1)].c - rings[0].c) }
            }
            nv = simd_normalize(nv)
            if simd_dot(nv, pos[i * cols + j] - rings[i].c) < 0 { nv = -nv }
            nor[i * cols + j] = nv
        }
    }
    var idx: [UInt32] = []
    idx.reserveCapacity((n - 1) * seg * 6 + seg * 6)
    for i in 0..<(n - 1) {
        for j in 0..<seg {
            let a = UInt32(i * cols + j), b = UInt32(i * cols + j + 1), c = UInt32((i + 1) * cols + j), d = UInt32((i + 1) * cols + j + 1)
            idx += [a, b, d, a, d, c]
        }
    }
    // caps
    var P = pos, N = nor, U = uv
    for end in [0, n - 1] {
        let r = rings[end]
        if max(r.rx, r.ry) < 0.002 { continue }
        let other = rings[end == 0 ? min(1, n - 1) : max(0, n - 2)].c
        var t = r.c - other
        t = simd_length(t) > 1e-6 ? simd_normalize(t) : V3(0, 1, 0)
        let ci = UInt32(P.count)
        P.append(r.c + t * min(r.rx, r.ry) * 0.35); N.append(t); U.append(SIMD2(0.5, uv[end * cols].y))
        for j in 0..<seg {
            let a = UInt32(end * cols + j), b = UInt32(end * cols + j + 1)
            idx += end == 0 ? [ci, b, a] : [ci, a, b]
        }
    }
    // pick winding so faces point outward
    if n > 1 {
        let p0 = P[Int(idx[0])], p1 = P[Int(idx[1])], p2 = P[Int(idx[2])]
        let fn = simd_cross(p1 - p0, p2 - p0)
        if simd_dot(fn, N[Int(idx[0])]) < 0 {
            for k in stride(from: 0, to: idx.count, by: 3) { idx.swapAt(k + 1, k + 2) }
        }
    }
    return meshGeometry(P, N, U, idx)
}

func meshGeometry(_ P: [V3], _ N: [V3], _ U: [SIMD2<Float>], _ idx: [UInt32]) -> SCNGeometry {
    let vs = SCNGeometrySource(vertices: P.map { SCNVector3($0.x, $0.y, $0.z) })
    let ns = SCNGeometrySource(normals: N.map { SCNVector3($0.x, $0.y, $0.z) })
    let ts = SCNGeometrySource(textureCoordinates: U.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
    let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
    return SCNGeometry(sources: [vs, ns, ts], elements: [el])
}

/// A node holding lofted geometry with one material.
func loftNode(_ rings: [Ring], _ m: SCNMaterial, seg: Int = 22, ref: V3 = V3(0, 0, 1), smooth: Int = 4, vScale: Float = 1,
              displace: ((V3, V3, Float, Float) -> Float)? = nil) -> SCNNode {
    let g = loft(smooth > 1 ? smoothRings(rings, per: smooth) : rings, seg: seg, ref: ref, vScale: vScale, displace: displace)
    g.materials = [m]
    return SCNNode(geometry: g)
}

/// A limb segment hanging from its joint (origin) straight down -y by `len`, tapering.
func limb(_ len: Float, _ r0: Float, _ r1: Float, _ m: SCNMaterial, depth: Float = 1, bulge: Float = 0.1, seg: Int = 16, dir: V3 = V3(0, -1, 0)) -> SCNNode {
    let d = simd_normalize(dir)
    let rings = [Ring(d * (-r0 * 0.6), r0 * 0.5, r0 * 0.5 * depth),
                 Ring(d * (-r0 * 0.1), r0 * 0.95, r0 * 0.95 * depth),
                 Ring(d * (len * 0.3), r0 * (1 + bulge), r0 * (1 + bulge) * depth),
                 Ring(d * (len * 0.75), mixf(r0, r1, 0.7), mixf(r0, r1, 0.7) * depth),
                 Ring(d * len, r1, r1 * depth),
                 Ring(d * (len + r1 * 0.6), r1 * 0.5, r1 * 0.5 * depth)]
    return loftNode(rings, m, seg: seg, ref: abs(d.z) > 0.9 ? V3(0, 1, 0) : V3(0, 0, 1), smooth: 3)
}

func sphereNode(_ r: CGFloat, _ m: SCNMaterial, seg: Int = 24) -> SCNNode {
    let s = SCNSphere(radius: r)
    s.segmentCount = seg
    s.materials = [m]
    return SCNNode(geometry: s)
}

func boxNode(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, chamfer: CGFloat = 0) -> SCNNode {
    let b = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
    b.materials = [m]
    return SCNNode(geometry: b)
}

func cylNode(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial, seg: Int = 24) -> SCNNode {
    let c = SCNCylinder(radius: r, height: h)
    c.radialSegmentCount = seg
    c.materials = [m]
    return SCNNode(geometry: c)
}

func coneNode(_ r0: CGFloat, _ r1: CGFloat, _ h: CGFloat, _ m: SCNMaterial, seg: Int = 20) -> SCNNode {
    let c = SCNCone(topRadius: r1, bottomRadius: r0, height: h)
    c.radialSegmentCount = seg
    c.materials = [m]
    return SCNNode(geometry: c)
}

extension SCNNode {
    func at(_ x: Float, _ y: Float, _ z: Float) -> SCNNode { simdPosition = V3(x, y, z); return self }
    func rot(_ x: Float, _ y: Float, _ z: Float) -> SCNNode { simdEulerAngles = V3(x, y, z); return self }
    func scl(_ x: Float, _ y: Float, _ z: Float) -> SCNNode { simdScale = V3(x, y, z); return self }
    @discardableResult func add(_ c: SCNNode) -> SCNNode { addChildNode(c); return c }
    func castAll(_ on: Bool) { enumerateHierarchy { n, _ in n.castsShadow = on } }
}
