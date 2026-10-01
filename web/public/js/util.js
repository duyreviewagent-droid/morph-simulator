// Shared math, deterministic random numbers and noise. Ported from Util.swift / Mats.swift.
import * as THREE from '../vendor/three.module.js'

export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z)
export const clamp = (x, a, b) => Math.min(Math.max(x, a), b)
export const mix = (a, b, t) => a + (b - a) * t
export const smoothstep = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t) }
export const mix3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
export const mul3 = (a, k) => [a[0] * k, a[1] * k, a[2] * k]
export const add3 = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const TAU = Math.PI * 2

/// True on phones and tablets (iPad reports itself as a Mac, so also check for touch).
const NAV = typeof navigator !== 'undefined' ? navigator : { maxTouchPoints: 0, userAgent: '' }
export const IS_TOUCH = (NAV.maxTouchPoints || 0) > 1 || (typeof window !== 'undefined' && 'ontouchstart' in window)
export const IS_MAC_DESKTOP = /Macintosh/.test(NAV.userAgent) && !IS_TOUCH
/// Quality knob: textures and grass are scaled down on tablets.
export const QUALITY = IS_TOUCH ? 0.5 : 1

/// splitmix64-style RNG on two 32-bit halves (deterministic, seedable).
export class RNG {
  constructor(seed) { this.s = (seed >>> 0) || 0x9E3779B9; this.t = ((seed / 4294967296) >>> 0) ^ 0x85EBCA6B }
  nextU32() {
    // xorshift128-ish mix, fast and good enough for scenery
    let s = this.s, t = this.t
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5
    t = (t + 0x6D2B79F5) | 0
    let z = Math.imul(t ^ (t >>> 15), 1 | t)
    z ^= z + Math.imul(z ^ (z >>> 7), 61 | z)
    this.s = s >>> 0; this.t = t >>> 0
    return ((z ^ (z >>> 14)) ^ s) >>> 0
  }
  next() { return this.nextU32() }
  float() { return this.nextU32() / 4294967296 }
  range(a, b) { return a + (b - a) * this.float() }
  chance(p) { return this.float() < p }
  int(n) { return Math.floor(this.float() * n) % n }
  pick(arr) { return arr[this.int(arr.length)] }
}

// ---- gradient noise (same lattice hash as the Swift version) ----
function hash(x, y, seed) {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 1442695041)) | 0
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  return (h ^ (h >>> 16)) >>> 0
}
function grad(h, x, y) {
  switch (h & 7) {
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
const fade = t => t * t * t * (t * (t * 6 - 15) + 10)
const wrap = (a, p) => { const m = a % p; return m < 0 ? m + p : m }

export const Noise = {
  hash,
  perlin(x, y, seed = 1) {
    const xi = Math.floor(x), yi = Math.floor(y)
    const xf = x - xi, yf = y - yi
    const u = fade(xf), v = fade(yf)
    const a = grad(hash(xi, yi, seed), xf, yf)
    const b = grad(hash(xi + 1, yi, seed), xf - 1, yf)
    const c = grad(hash(xi, yi + 1, seed), xf, yf - 1)
    const d = grad(hash(xi + 1, yi + 1, seed), xf - 1, yf - 1)
    return mix(mix(a, b, u), mix(c, d, u), v) * 0.75
  },
  fbm(x, y, octaves, seed = 1) {
    let sum = 0, amp = 1, f = 1, norm = 0
    for (let i = 0; i < octaves; i++) {
      sum += amp * Noise.perlin(x * f, y * f, seed + i * 17)
      norm += amp; amp *= 0.5; f *= 2.03
    }
    return sum / norm
  },
  ridged(x, y, octaves, seed = 1) {
    let sum = 0, amp = 0.55, f = 1, weight = 1
    for (let i = 0; i < octaves; i++) {
      let n = 1 - Math.abs(Noise.perlin(x * f, y * f, seed + i * 31) * 1.3)
      n = Math.max(n, 0); n *= n; n *= weight
      weight = clamp(n * 1.8, 0, 1)
      sum += n * amp; f *= 2.05; amp *= 0.5
    }
    return sum
  },
  tperlin(x, y, period, seed = 1) { return Noise.tperlin2(x, y, period, period, seed) },
  tperlin2(x, y, px, py, seed = 1) {
    const xi = Math.floor(x), yi = Math.floor(y)
    const xf = x - xi, yf = y - yi
    const ix = wrap(xi, px), iy = wrap(yi, py), ix1 = wrap(ix + 1, px), iy1 = wrap(iy + 1, py)
    const u = fade(xf), v = fade(yf)
    const a = grad(hash(ix, iy, seed), xf, yf)
    const b = grad(hash(ix1, iy, seed), xf - 1, yf)
    const c = grad(hash(ix, iy1, seed), xf, yf - 1)
    const d = grad(hash(ix1, iy1, seed), xf - 1, yf - 1)
    return mix(mix(a, b, u), mix(c, d, u), v) * 0.75
  },
  /// Tileable fBm over u, v in 0..1.
  tfbm(u, v, freq, octaves, seed = 1, gain = 0.5) {
    let sum = 0, amp = 1, norm = 0, f = freq
    for (let i = 0; i < octaves; i++) {
      sum += amp * Noise.tperlin(u * f, v * f, f, seed + i * 17)
      norm += amp; amp *= gain; f *= 2
    }
    return sum / norm
  },
  /// Stretched streaks over a 0..1 tile: fu cells across, fv along.
  streak(u, v, fu, fv, seed) {
    return Noise.tperlin2(u * fu, v * fv, fu, fv, seed) * 0.65 + Noise.tperlin2(u * fu * 2, v * fv * 2, fu * 2, fv * 2, seed + 5) * 0.35
  },
  /// Cheap hash to 0..1 for per-cell variation.
  cell(x, y, seed = 7) { return (hash(x, y, seed) & 0xFFFF) / 65535 },
}

export function color3(r, g, b) { return new THREE.Color().setRGB(r, g, b, THREE.SRGBColorSpace) }
