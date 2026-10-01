import AppKit
import SceneKit
import simd

/// A set of physically based maps generated together from one height field.
struct PBR {
    let diffuse: CGImage
    let normal: CGImage
    let rough: CGImage
    let metal: CGImage?
    let emission: CGImage?
}

/// Per-pixel sample for PBR generation.
struct TexSample {
    var albedo = V3(0.5, 0.5, 0.5)
    var height: Float = 0
    var rough: Float = 0.8
    var metal: Float = 0
    var emit = V3.zero
}

/// Writes raw RGBA bytes into a CGImage in a given colour space.
private func imageFromBytes(_ w: Int, _ h: Int, _ bytes: [UInt8], linear: Bool) -> CGImage {
    let cs = linear ? CGColorSpace(name: CGColorSpace.linearSRGB)! : CGColorSpace(name: CGColorSpace.sRGB)!
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Generates albedo/normal/roughness(/metal/emission) maps. The height field wraps at the edges, so
/// tileable inputs give tileable normals.
func makePBR(_ w: Int, _ h: Int, bump: Float = 1, metal: Bool = false, emission: Bool = false, _ f: (Int, Int) -> TexSample) -> PBR {
    var samples = [TexSample](repeating: TexSample(), count: w * h)
    samples.withUnsafeMutableBufferPointer { buf in
        let p = buf.baseAddress!
        DispatchQueue.concurrentPerform(iterations: h) { y in
            for x in 0..<w { p[y * w + x] = f(x, y) }
        }
    }
    var dif = [UInt8](repeating: 255, count: w * h * 4)
    var nor = dif, rou = dif
    var met: [UInt8] = metal ? dif : []
    var emi: [UInt8] = emission ? dif : []
    samples.withUnsafeBufferPointer { sb in
        let s = sb.baseAddress!
        dif.withUnsafeMutableBufferPointer { db in
        nor.withUnsafeMutableBufferPointer { nb in
        rou.withUnsafeMutableBufferPointer { rb in
        met.withUnsafeMutableBufferPointer { mb in
        emi.withUnsafeMutableBufferPointer { eb in
            let d = db.baseAddress!, n = nb.baseAddress!, r = rb.baseAddress!
            let m = metal ? mb.baseAddress : nil, e = emission ? eb.baseAddress : nil
            let hasM = metal, hasE = emission
            DispatchQueue.concurrentPerform(iterations: h) { y in
                for x in 0..<w {
                    let i = y * w + x, o = i * 4
                    let t = s[i]
                    d[o] = UInt8(clampf(t.albedo.x, 0, 1) * 255); d[o + 1] = UInt8(clampf(t.albedo.y, 0, 1) * 255); d[o + 2] = UInt8(clampf(t.albedo.z, 0, 1) * 255)
                    let xl = s[y * w + (x + w - 1) % w].height, xr = s[y * w + (x + 1) % w].height
                    let yu = s[((y + h - 1) % h) * w + x].height, yd = s[((y + 1) % h) * w + x].height
                    let nv = simd_normalize(V3(-(xr - xl) * bump, (yd - yu) * bump, 1))
                    n[o] = UInt8(clampf(nv.x * 0.5 + 0.5, 0, 1) * 255); n[o + 1] = UInt8(clampf(nv.y * 0.5 + 0.5, 0, 1) * 255); n[o + 2] = UInt8(clampf(nv.z * 0.5 + 0.5, 0, 1) * 255)
                    let rv = UInt8(clampf(t.rough, 0.02, 1) * 255)
                    r[o] = rv; r[o + 1] = rv; r[o + 2] = rv
                    if hasM, let m { let mv = UInt8(clampf(t.metal, 0, 1) * 255); m[o] = mv; m[o + 1] = mv; m[o + 2] = mv }
                    if hasE, let e { e[o] = UInt8(clampf(t.emit.x, 0, 1) * 255); e[o + 1] = UInt8(clampf(t.emit.y, 0, 1) * 255); e[o + 2] = UInt8(clampf(t.emit.z, 0, 1) * 255) }
                }
            }
        }}}}}
    }
    return PBR(diffuse: imageFromBytes(w, h, dif, linear: false), normal: imageFromBytes(w, h, nor, linear: true),
               rough: imageFromBytes(w, h, rou, linear: true), metal: metal ? imageFromBytes(w, h, met, linear: true) : nil,
               emission: emission ? imageFromBytes(w, h, emi, linear: false) : nil)
}

/// A PBR material from generated maps, tiling by default.
func pbrMaterial(_ p: PBR, normalIntensity: CGFloat = 1, tile: Bool = true) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = p.diffuse
    m.normal.contents = p.normal
    m.normal.intensity = normalIntensity
    m.roughness.contents = p.rough
    if let mt = p.metal { m.metalness.contents = mt } else { m.metalness.contents = 0.0 }
    if let e = p.emission { m.emission.contents = e }
    for prop in [m.diffuse, m.normal, m.roughness, m.metalness, m.emission] {
        prop.wrapS = tile ? .repeat : .clamp
        prop.wrapT = tile ? .repeat : .clamp
        prop.mipFilter = .linear
        prop.maxAnisotropy = 8
    }
    return m
}

/// A plain physically based material.
func pbr(_ c: NSColor, rough: CGFloat = 0.7, metal: CGFloat = 0, emission: NSColor? = nil) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = c
    m.roughness.contents = rough
    m.metalness.contents = metal
    if let e = emission { m.emission.contents = e }
    return m
}
