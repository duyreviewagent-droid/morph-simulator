import AppKit
import simd

// MARK: - Scalar helpers

@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}
@inline(__always) func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func clampf(_ x: Float, _ a: Float, _ b: Float) -> Float { min(max(x, a), b) }
@inline(__always) func clampd(_ x: Double, _ a: Double, _ b: Double) -> Double { min(max(x, a), b) }
@inline(__always) func mix3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func color(_ v: SIMD3<Float>) -> NSColor {
    NSColor(srgbRed: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
}

// MARK: - Deterministic RNG (splitmix64)

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed }
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func float() -> Float { Float(next() >> 40) / 16_777_216.0 }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * float() }
    mutating func chance(_ p: Float) -> Bool { float() < p }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

// MARK: - Gradient noise

enum Noise {
    @inline(__always) static func hash(_ x: Int32, _ y: Int32, _ seed: Int32) -> UInt32 {
        var h = UInt32(bitPattern: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return h ^ (h >> 16)
    }
    @inline(__always) static func grad(_ h: UInt32, _ x: Float, _ y: Float) -> Float {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x * 1.4
        case 5: return -x * 1.4
        case 6: return y * 1.4
        default: return -y * 1.4
        }
    }
    @inline(__always) static func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    /// Perlin-style gradient noise, roughly in [-1, 1].
    static func perlin(_ x: Float, _ y: Float, seed: Int32 = 1) -> Float {
        let xi = floorf(x), yi = floorf(y)
        let xf = x - xi, yf = y - yi
        let ix = Int32(xi), iy = Int32(yi)
        let u = fade(xf), v = fade(yf)
        let a = grad(hash(ix, iy, seed), xf, yf)
        let b = grad(hash(ix &+ 1, iy, seed), xf - 1, yf)
        let c = grad(hash(ix, iy &+ 1, seed), xf, yf - 1)
        let d = grad(hash(ix &+ 1, iy &+ 1, seed), xf - 1, yf - 1)
        return mixf(mixf(a, b, u), mixf(c, d, u), v) * 0.75
    }

    static func fbm(_ x: Float, _ y: Float, octaves: Int, seed: Int32 = 1) -> Float {
        var sum: Float = 0, amp: Float = 1, f: Float = 1, norm: Float = 0
        for i in 0..<octaves {
            sum += amp * perlin(x * f, y * f, seed: seed &+ Int32(i) &* 17)
            norm += amp
            amp *= 0.5
            f *= 2.03
        }
        return sum / norm
    }

    /// Ridged multifractal in roughly [0, 1]; sharp crests for mountains.
    static func ridged(_ x: Float, _ y: Float, octaves: Int, seed: Int32 = 1) -> Float {
        var sum: Float = 0, amp: Float = 0.55, f: Float = 1, weight: Float = 1
        for i in 0..<octaves {
            var n = 1 - abs(perlin(x * f, y * f, seed: seed &+ Int32(i) &* 31) * 1.3)
            n = max(n, 0)
            n *= n
            n *= weight
            weight = clampf(n * 1.8, 0, 1)
            sum += n * amp
            f *= 2.05
            amp *= 0.5
        }
        return sum
    }
}

// MARK: - Images

func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

/// Build an image from a per-pixel function (x, y from top-left) returning linear-ish RGBA 0...1.
func makePixelImage(_ w: Int, _ h: Int, _ f: (Int, Int) -> SIMD4<Float>) -> CGImage {
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBufferPointer { buf in
        let p = buf.baseAddress!
        DispatchQueue.concurrentPerform(iterations: h) { y in
            for x in 0..<w {
                let c = f(x, y)
                let a = clampf(c.w, 0, 1)
                let i = (y * w + x) * 4
                p[i] = UInt8(clampf(c.x * a, 0, 1) * 255)
                p[i + 1] = UInt8(clampf(c.y * a, 0, 1) * 255)
                p[i + 2] = UInt8(clampf(c.z * a, 0, 1) * 255)
                p[i + 3] = UInt8(a * 255)
            }
        }
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func savePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: path))
    }
}

/// Soft round sprite used by particles and clouds.
func softDotImage(size: Int = 64, hardness: Float = 0) -> CGImage {
    makePixelImage(size, size) { x, y in
        let dx = (Float(x) + 0.5) / Float(size) * 2 - 1
        let dy = (Float(y) + 0.5) / Float(size) * 2 - 1
        let d = sqrtf(dx * dx + dy * dy)
        var a = clampf(1 - d, 0, 1)
        a = powf(a, 1.6 - hardness)
        return SIMD4(1, 1, 1, a)
    }
}

// MARK: - Tileable noise (period in lattice cells, so textures wrap seamlessly)

extension Noise {
    @inline(__always) private static func wrap(_ a: Int32, _ p: Int32) -> Int32 { let m = a % p; return m < 0 ? m + p : m }

    static func tperlin(_ x: Float, _ y: Float, period: Int32, seed: Int32 = 1) -> Float {
        let xi = floorf(x), yi = floorf(y)
        let xf = x - xi, yf = y - yi
        let ix = wrap(Int32(xi), period), iy = wrap(Int32(yi), period)
        let ix1 = wrap(ix &+ 1, period), iy1 = wrap(iy &+ 1, period)
        let u = fade(xf), v = fade(yf)
        let a = grad(hash(ix, iy, seed), xf, yf)
        let b = grad(hash(ix1, iy, seed), xf - 1, yf)
        let c = grad(hash(ix, iy1, seed), xf, yf - 1)
        let d = grad(hash(ix1, iy1, seed), xf - 1, yf - 1)
        return mixf(mixf(a, b, u), mixf(c, d, u), v) * 0.75
    }

    /// Tileable fBm over u, v in 0...1.
    static func tfbm(_ u: Float, _ v: Float, freq: Int, octaves: Int, seed: Int32 = 1, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0, f = Int32(freq)
        for i in 0..<octaves {
            sum += amp * tperlin(u * Float(f), v * Float(f), period: f, seed: seed &+ Int32(i) &* 17)
            norm += amp
            amp *= gain
            f *= 2
        }
        return sum / norm
    }

    /// Cheap hash to 0...1 for per-cell variation.
    @inline(__always) static func cell(_ x: Int, _ y: Int, _ seed: Int32 = 7) -> Float {
        Float(hash(Int32(truncatingIfNeeded: x), Int32(truncatingIfNeeded: y), seed) & 0xFFFF) / 65535
    }
}

typealias V3 = SIMD3<Float>

extension RNG {
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}
