import Foundation

// Synths run on the audio thread. The game thread writes their public parameters
// (benign single-word races); render() smooths them.

@inline(__always) func softClip(_ x: Float) -> Float {
    let c = max(-3, min(3, x))
    return c * (27 + c * c) / (27 + 9 * c * c)
}

struct Noise32 {
    var s: UInt32
    @inline(__always) mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Float(s) / 2_147_483_648.0 - 1
    }
}

@inline(__always) func midiHz(_ m: Float) -> Float { 440 * powf(2, (m - 69) / 12) }

/// Two-pole resonator (band-pass-ish). Output is roughly unity at the centre frequency.
struct Reso {
    var y1: Float = 0, y2: Float = 0
    @inline(__always) mutating func run(_ x: Float, f: Float, q: Float, sr: Float) -> Float {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let r = max(0, 1 - w / (2 * q))
        let y = x * (1 - r) * 2 * sinf(w) + 2 * r * cosf(w) * y1 - r * r * y2
        y2 = y1; y1 = y
        return y
    }
}

/// One-pole low-pass with a cutoff in Hz.
struct LP1 {
    var y: Float = 0
    @inline(__always) mutating func run(_ x: Float, f: Float, sr: Float) -> Float {
        let a = 1 - expf(-2 * Float.pi * f / sr)
        y += (x - y) * a
        return y
    }
}

@inline(__always) func equalPan(_ p: Float) -> (Float, Float) {
    let a = (max(-1, min(1, p)) + 1) * .pi / 4
    return (cosf(a) * 1.414, sinf(a) * 1.414)
}
