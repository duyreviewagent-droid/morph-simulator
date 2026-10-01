// Every procedural material in the game, plus the generated animal coats.
// Ported from Mats.swift and Coats.swift. Materials build on first use and are cached.
import * as THREE from '../vendor/three.module.js'
import { RNG, Noise, smoothstep, mix, mix3 } from './util.js'
import { makePBR, makeRGBA, pbrMaterial, tiled, pbr, patchShader } from './tex.js'

const tp = 2 * Math.PI
const fmod1 = a => a % 1                                  // Swift truncatingRemainder(dividingBy: 1)
const isEven = n => ((n % 2) + 2) % 2 === 0               // Swift Int.isMultiple(of: 2), negatives too
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k]
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

// SceneKit puts image row 0 at v = 0; loft.js flips v (uv.y = 1 - v) and a DataTexture puts row 0
// at uv.y = 0. Feeding the pixel functions a flipped y keeps every texture the right way up.
const FLIP_V = true
const pbrTex = (w, h, bump, f, opts) => makePBR(w, h, bump, FLIP_V ? (x, y) => f(x, h - 1 - y) : f, opts)
const rgbaTex = (w, h, f, quality) => makeRGBA(w, h, FLIP_V ? (x, y) => f(x, h - 1 - y) : f, quality ? { quality } : undefined)

/// Swift TexSample -> makePBR sample.
const T = (c, h = 0, r = 0.8, m = 0) => ({ c, h, r, m })

/// Same material as a MeshPhysicalMaterial with a clear coat (SceneKit clearCoat).
function withClearcoat(m, cc) {
  const p = new THREE.MeshPhysicalMaterial()
  for (const k of ['map', 'normalMap', 'roughnessMap', 'metalnessMap', 'roughness', 'metalness', 'transparent', 'opacity', 'side', 'depthWrite', 'alphaTest']) p[k] = m[k]
  p.color.copy(m.color); p.normalScale.copy(m.normalScale); p.emissive.copy(m.emissive)
  p.clearcoat = cc; p.clearcoatRoughness = 0.06
  return p
}
const ccPbr = (c, rough, cc = 1, metal = 0) => withClearcoat(pbr(c, { rough, metal }), cc)

/// Lighter belly, slightly darker back (Coats.countershade). Runs after the albedo map.
/// smoothstep(0.15, -0.75, y) is written as 1 - smoothstep(-0.75, 0.15, y) (GLSL needs e0 < e1).
const COUNTERSHADE = /* glsl */`
  vec3 csN = normalize(vWorldNormalMS);
  float csBelly = 1.0 - smoothstep(-0.75, 0.15, csN.y);
  float csBack = smoothstep(0.35, 1.0, csN.y);
  diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * 1.3 + 0.06, csBelly * 0.45);
  diffuseColor.rgb *= 1.0 - csBack * 0.12;
`
const countershaded = m => patchShader(m, { fragment: COUNTERSHADE, key: 'cs' })

// ---------------------------------------------------------------------------------------------
// Pixel functions that are used more than once

/// Overlapping feather scales. `a` body colour, `b` edge lacing colour.
function feathers(a, b, lace, seed, sheen = 0) {
  const W = 512, rows = 10, cols = 7
  const p = pbrTex(W, W, 3, (x, y) => {
    const u = x / W, v = y / W
    const fy = v * rows, row = Math.floor(fy)
    let best = 9, bx = 0, bid = 0, bdy = 0
    for (const dr of [0, 1]) {
      const r = row - dr
      const off = isEven(r) ? 0 : 0.5
      const fx = u * cols - off
      const c = Math.floor(fx + 0.5)
      for (const dc of [-1, 0, 1]) {
        const cx = c + dc
        const lx = (fx - cx) / 0.62, ly = (fy - r) / 1.25
        if (!(ly > -0.15)) continue
        const d = lx * lx + ly * ly
        if (d < 1) {
          // the lower row lies on top
          const prio = d - dr * 3
          if (prio < best) { best = prio; bx = lx; bdy = ly; bid = Noise.cell(cx & 63, r & 63, seed) }
        }
      }
    }
    const d = best < 9 ? Math.min(1, bx * bx + bdy * bdy) : 1
    const barbs = Noise.streak(u, v, 90, 8, seed + 3)
    const shaft = smoothstep(0.06, 0.0, Math.abs(bx)) * smoothstep(1, 0.3, bdy)
    const edge = smoothstep(0.55, 0.95, d)
    let col = mix3(mul(a, 0.85 + bid * 0.3), b, edge * lace)
    col = mul(col, 0.9 + barbs * 0.2)
    col = mix3(col, add(mul(col, 1.35), [0.04, 0.03, 0.02]), shaft * 0.5)
    return T(col, (1 - d) * 0.8 + barbs * 0.15, 0.55 - sheen * 0.25 + barbs * 0.05)
  })
  return pbrMaterial(p, { normalScale: 0.9 })
}

function hair(c) {
  const p = pbrTex(256, 256, 2, (x, y) => {
    const u = x / 256, v = y / 256
    const s = Noise.streak(u, v, 64, 3, 51)
    return T(mul(c, 0.75 + s * 0.5), s, 0.45)
  })
  return tiled(pbrMaterial(p), 2, 2)
}

/// Vertical board-and-batten siding with worn paint over grey wood. 4 m per tile.
function siding(paint, seed, horizontal = false) {
  const W = 1024
  const p = pbrTex(W, W, 3, (x, y) => {
    const u = x / W, v = y / W
    const a = horizontal ? v : u, b = horizontal ? u : v
    const boards = horizontal ? 20 : 18
    const fb = a * boards, bi = Math.floor(fb), fr = fb - bi
    const grain = Noise.streak(horizontal ? b : a * 0.25 + bi * 0.13, horizontal ? a : b, 64, 4, seed + bi)
    const groove = horizontal ? smoothstep(0.0, 0.12, fr) : (smoothstep(0.0, 0.04, fr) * smoothstep(1.0, 0.96, fr))
    const batten = horizontal ? 0 : smoothstep(0.08, 0.03, Math.min(fr, 1 - fr))
    const wear = smoothstep(0.15, 0.45, Noise.tfbm(u, v, 6, 5, seed + 9) + grain * 0.2 + (horizontal ? 0 : (1 - v) * 0.15))
    const wood = mul([0.42, 0.38, 0.33], 0.75 + grain * 0.35)
    const pcol = mul(paint, 0.85 + Noise.tfbm(u, v, 12, 3, seed + 4) * 0.2)
    const c = mul(mix3(pcol, wood, wear * 0.8), 0.55 + 0.45 * groove)
    return T(c, groove * 0.6 + batten * 0.4 + grain * 0.12 - wear * 0.1, mix(0.6, 0.85, wear))
  })
  return pbrMaterial(p)
}

/// Alpha-tested grass card: 70 blades, y up from the base. Wind sway in the vertex shader,
/// normal forced to world up so cards light like the ground under them.
const bladeCache = new Map()
function grassBlade(lo, hi) {
  if (!lo || !hi) throw new Error('Mat.grassBlade(lo, hi) needs two colours; use Mat.grassBladeDefault')
  const key = lo.join(',') + '|' + hi.join(',')
  if (bladeCache.has(key)) return bladeCache.get(key)
  const W = 256
  const rr = new RNG(17)
  const blades = Array.from({ length: 70 }, () => [rr.range(0.04, 0.96), rr.range(0.35, 1.0), rr.range(-0.3, 0.3), rr.range(0.006, 0.016), rr.float()])
  const tex = rgbaTex(W, W, (px, py) => {
    const x = px / W, y = 1 - py / W     // y up from the base
    let a = 0, shade = 0, hue = 0
    for (const [bx, h, lean, w, tone] of blades) {
      if (!(y < h)) continue
      const s = y / h
      const cx = bx + lean * s * s
      const ww = w * (1 - s * 0.85)
      const d = Math.abs(x - cx)
      if (d < ww) {
        const aa = smoothstep(ww, ww * 0.4, d)
        if (aa > a) { a = aa; shade = 0.3 + s * 0.7; hue = tone }
      }
    }
    // transparent texels carry grass colour too, so mipmaps don't bleed black into the blades
    if (a <= 0) { const g = mul(mix3(lo, hi, 0.5), 0.75); return [g[0], g[1], g[2], 0] }
    let c = mix3(lo, hi, hue)
    if (hue > 0.9) c = [0.42, 0.4, 0.2]       // a few dry blades
    c = mul(c, shade)
    return [c[0], c[1], c[2], a]
  }, 1)
  // alpha-tested cut-outs: no sorting, no blended overdraw
  const m = new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.45, side: THREE.DoubleSide })
  m.onBeforeCompile = shader => {
    shader.fragmentShader = shader.fragmentShader.replace('#include <normal_fragment_maps>',
      '#include <normal_fragment_maps>\nnormal = normalize((viewMatrix * vec4(0.0, 1.0, 0.0, 0.0)).xyz);')
  }
  patchShader(m, {
    key: 'grass',
    vertex: /* glsl */`
      float hgt = uv.y;
      float sw = sin(uTime * 1.6 + transformed.x * 0.35 + transformed.z * 0.27) + 0.4 * sin(uTime * 3.7 + transformed.x * 1.3);
      transformed.x += sw * 0.045 * hgt;
      transformed.z += sw * 0.03 * hgt;`,
  })
  bladeCache.set(key, m)
  return m
}

// ---------------------------------------------------------------------------------------------
// Mat: lazy getters for every `static let`, plain functions for every `static func`.

export const Mat = { tp, feathers, hair, siding, grassBlade }
const lazy = (name, make) => {
  let v
  Object.defineProperty(Mat, name, { enumerable: true, get: () => (v === undefined ? (v = make()) : v) })
}

// MARK: Creatures

/// Holstein hide: big black islands on white, short hair lying along v.
lazy('hide', () => {
  const W = 1024
  const p = pbrTex(W, W, 1.6, (x, y) => {
    const u = x / W, v = y / W
    const hair = Noise.streak(u, v, 160, 14, 3)
    const n = Noise.tfbm(u, v, 3, 5, 71) + Noise.tfbm(u, v, 2, 2, 72) * 0.5
    const edge = smoothstep(0.02, 0.07, n + hair * 0.05)
    const white = mul([0.82, 0.79, 0.74], 0.9 + hair * 0.15)
    const black = mul([0.028, 0.026, 0.026], 1 + hair * 0.4)
    // dirt and a faint cream tint low down
    const dirt = smoothstep(0.3, 0.8, Noise.tfbm(u, v, 6, 3, 73)) * 0.25
    const c = add(mul(mix3(white, black, edge), 1 - dirt * (1 - edge)), mul([0.05, 0.035, 0.015], dirt * (1 - edge)))
    return T(c, hair * 0.6 + edge * 0.05, 0.62 + hair * 0.1 - edge * 0.08)
  })
  return countershaded(tiled(pbrMaterial(p, { normalScale: 0.8 }), 1, 0.9))
})

lazy('cowSkin', () => {
  const p = pbrTex(256, 256, 1, (x, y) => {
    const u = x / 256, v = y / 256
    const m = Noise.tfbm(u, v, 4, 4, 81)
    const freckle = smoothstep(0.25, 0.45, Noise.tfbm(u, v, 10, 3, 82))
    return T(mix3(mul([0.86, 0.58, 0.55], 0.92 + m * 0.12), [0.25, 0.18, 0.18], freckle * 0.6), Noise.tfbm(u, v, 32, 2, 83) * 0.3, 0.5)
  })
  return tiled(pbrMaterial(p), 2, 3)
})

lazy('cowNose', () => {
  const p = pbrTex(256, 256, 2.5, (x, y) => {
    const u = x / 256, v = y / 256
    const pores = Noise.tfbm(u, v, 24, 2, 91)
    const m = Noise.tfbm(u, v, 3, 3, 92)
    return T(mix3([0.55, 0.36, 0.36], [0.12, 0.09, 0.09], smoothstep(-0.1, 0.2, m)), pores * 0.6, 0.22 + pores * 0.1)
  })
  return tiled(pbrMaterial(p), 2, 2)
})

lazy('hoof', () => {
  const p = pbrTex(256, 256, 1.5, (x, y) => {
    const u = x / 256, v = y / 256
    const s = Noise.streak(v, u, 4, 40, 11)
    return T(mul([0.07, 0.06, 0.055], 1 + s * 0.6), s, 0.42)
  })
  return pbrMaterial(p)
})

lazy('horn', () => pbr([0.82, 0.76, 0.62], { rough: 0.4 }))

lazy('henBody', () => tiled(feathers([0.42, 0.16, 0.06], [0.2, 0.06, 0.02], 0.7, 5), 4, 5))
lazy('henWing', () => tiled(feathers([0.36, 0.12, 0.05], [0.08, 0.04, 0.02], 0.9, 6), 3, 5))
lazy('hackle', () => tiled(feathers([0.78, 0.45, 0.14], [0.55, 0.22, 0.05], 0.5, 7), 5, 7))
lazy('tailFeather', () => tiled(feathers([0.03, 0.045, 0.035], [0.02, 0.09, 0.06], 0.6, 8, 1), 2, 4))
lazy('whiteFeather', () => tiled(feathers([0.86, 0.84, 0.78], [0.7, 0.68, 0.62], 0.4, 9), 4, 5))

lazy('comb', () => {
  const p = pbrTex(256, 256, 3, (x, y) => {
    const u = x / 256, v = y / 256
    const bump = Noise.tfbm(u, v, 16, 3, 21)
    return T(mul([0.62, 0.035, 0.03], 0.85 + bump * 0.3), bump, 0.38)
  })
  return tiled(pbrMaterial(p), 2, 2)
})

lazy('beak', () => pbr([0.86, 0.66, 0.28], { rough: 0.35 }))

lazy('scales', () => {
  const p = pbrTex(256, 256, 3, (x, y) => {
    const u = x / 256, v = y / 256
    const row = v * 12
    const off = isEven(Math.floor(row)) ? 0 : 0.5
    const fx = fmod1(u * 6 + off) - 0.5, fy = row - Math.floor(row) - 0.5
    const d = Math.sqrt(fx * fx * 1.2 + fy * fy)
    const n = Noise.tfbm(u, v, 8, 3, 31)
    return T(mul([0.86, 0.66, 0.2], (0.85 + n * 0.2) * (1 - smoothstep(0.35, 0.5, d) * 0.35)), 1 - d * 2, 0.45)
  })
  return tiled(pbrMaterial(p), 2, 5)
})
lazy('claw', () => pbr([0.2, 0.18, 0.15], { rough: 0.35 }))

lazy('skin', () => {
  const p = pbrTex(256, 256, 0.8, (x, y) => {
    const u = x / 256, v = y / 256
    const m = Noise.tfbm(u, v, 4, 4, 41)
    const pores = Noise.tfbm(u, v, 48, 2, 42)
    return T(add(mul([0.7, 0.5, 0.42], 0.95 + m * 0.08), mul([0.03, -0.01, -0.01], Math.max(0, m))), pores * 0.3, 0.52 + pores * 0.05)
  })
  return withClearcoat(tiled(pbrMaterial(p), 2, 4), 0.08)
})
lazy('lip', () => pbr([0.62, 0.32, 0.28], { rough: 0.4 }))
lazy('mouthDark', () => pbr([0.18, 0.05, 0.05], { rough: 0.6 }))

lazy('brownHair', () => hair([0.13, 0.07, 0.035]))
lazy('greyHair', () => hair([0.45, 0.43, 0.4]))

lazy('denim', () => {
  const W = 256
  const p = pbrTex(W, W, 2.2, (x, y) => {
    const u = x / W, v = y / W
    const tw = Math.sin((x + y) * Math.PI / 2) * 0.5 + 0.5
    const fade = Noise.tfbm(u, v, 3, 3, 61)
    const slub = Noise.streak(u, v, 3, 64, 62)
    const base = add(mul([0.08, 0.14, 0.28], 1 + fade * 0.35), mul([0.1, 0.1, 0.1], Math.max(0, slub) * 0.4))
    return T(mix3(base, [0.5, 0.52, 0.55], tw * 0.12), tw * 0.5 + slub * 0.2, 0.85)
  })
  return tiled(pbrMaterial(p), 6, 8)
})

lazy('flannel', () => {
  const W = 512
  const band = a => (fmod1(a * 2) < 0.34 ? 1 : 0)
  const line = a => (Math.abs(fmod1(a * 2) - 0.67) < 0.012 ? 1 : 0)
  const p = pbrTex(W, W, 1.4, (x, y) => {
    const u = x / W, v = y / W
    const bu = band(u), bv = band(v)
    let col = [0.5, 0.05, 0.04]
    if (bu > 0 || bv > 0) col = [0.1, 0.03, 0.03]
    if (bu > 0 && bv > 0) col = [0.03, 0.02, 0.02]
    if (line(u) + line(v) > 0) col = [0.75, 0.62, 0.3]
    const weave = Math.sin((x - y) * Math.PI / 2) * 0.5 + 0.5
    const fuzz = Noise.tfbm(u, v, 64, 2, 63)
    return T(mul(col, 0.9 + weave * 0.15 + fuzz * 0.1), weave * 0.4 + fuzz * 0.2, 0.9)
  })
  return tiled(pbrMaterial(p), 3, 3)
})

lazy('tee', () => {
  const p = pbrTex(128, 128, 1, (x, y) => {
    const w = Math.sin((x + y) * Math.PI / 2) * 0.5 + 0.5
    return T(mul([0.85, 0.84, 0.8], 0.95 + w * 0.05), w * 0.3, 0.9)
  })
  return tiled(pbrMaterial(p), 8, 8)
})

lazy('leather', () => {
  const p = pbrTex(256, 256, 2, (x, y) => {
    const u = x / 256, v = y / 256
    const g = Noise.tfbm(u, v, 24, 3, 71)
    const scuff = smoothstep(0.2, 0.5, Noise.tfbm(u, v, 5, 3, 72))
    return T(mix3(mul([0.22, 0.12, 0.06], 0.9 + g * 0.2), [0.35, 0.25, 0.16], scuff * 0.5), g * 0.5, 0.45 + scuff * 0.3)
  })
  return tiled(pbrMaterial(p), 2, 2)
})

lazy('straw', () => {
  const W = 256
  const p = pbrTex(W, W, 3, (x, y) => {
    const u = x / W, v = y / W
    // over-under weave of flat straw strips
    const cu = Math.floor(u * 16), cv = Math.floor(v * 16)
    const over = (cu + cv) % 2 === 0
    const s = over ? Noise.streak(u, v, 16, 2, 81) : Noise.streak(v, u, 16, 2, 82)
    const fu = fmod1(u * 16), fv = fmod1(v * 16)
    const edge = over ? Math.min(fv, 1 - fv) : Math.min(fu, 1 - fu)
    const e = smoothstep(0, 0.2, edge)
    return T(mul([0.78, 0.62, 0.32], (0.8 + s * 0.3) * (0.75 + e * 0.25)), (over ? 0.6 : 0.3) + e * 0.4, 0.8)
  })
  return tiled(pbrMaterial(p), 6, 4)
})

lazy('eyeWhite', () => pbr([0.9, 0.88, 0.84], { rough: 0.12 }))
lazy('eyeBlack', () => ccPbr([0.01, 0.01, 0.01], 0.05))
lazy('irisBrown', () => pbr([0.3, 0.17, 0.07], { rough: 0.1 }))
lazy('irisBlue', () => pbr([0.2, 0.36, 0.52], { rough: 0.1 }))
lazy('irisOrange', () => ccPbr([0.85, 0.45, 0.08], 0.08))
lazy('cowEye', () => ccPbr([0.06, 0.035, 0.02], 0.04))
lazy('lash', () => pbr([0.02, 0.02, 0.02], { rough: 0.7 }))

// MARK: World

lazy('grassDetail', () => {
  // Tiled at 3 m. Multiplies the macro colour map; carries blade-scale normals.
  const W = 512
  const p = pbrTex(W, W, 2.5, (x, y) => {
    const u = x / W, v = y / W
    const blades = Noise.streak(u, v, 120, 30, 91) + Noise.streak(v, u, 110, 26, 92) * 0.7
    const clump = Noise.tfbm(u, v, 8, 3, 93)
    const g = 0.8 + blades * 0.25 + clump * 0.2
    return T([g, g, g * 0.95], blades * 0.7 + clump * 0.4, 0.9)
  })
  return pbrMaterial(p)
})

lazy('grassBladeDefault', () => grassBlade([0.1, 0.2, 0.035], [0.26, 0.36, 0.08]))

lazy('flower', () => {
  const tex = rgbaTex(128, 128, (px, py) => {
    const x = px / 64 - 1, y = py / 64 - 1
    const r = Math.sqrt(x * x + y * y), th = Math.atan2(y, x)
    const petal = 0.55 + 0.35 * Math.abs(Math.cos(th * 2.5))
    if (r < 0.18) return [0.9, 0.7, 0.1, 1]
    if (r < petal) return [0.96, 0.95, 0.9, smoothstep(petal, petal - 0.08, r)]
    return [0, 0, 0, 0]
  })
  return new THREE.MeshStandardMaterial({ map: tex, roughness: 0.7, metalness: 0, side: THREE.DoubleSide, alphaTest: 0.4 })
})

lazy('barnRed', () => siding([0.45, 0.07, 0.05], 101))
lazy('whiteTrim', () => pbr([0.85, 0.84, 0.8], { rough: 0.6 }))
lazy('clapboard', () => siding([0.86, 0.85, 0.8], 111, true))

lazy('roofMetal', () => {
  const W = 512
  const p = pbrTex(W, W, 5, (x, y) => {
    const u = x / W, v = y / W
    const rib = 0.5 + 0.5 * Math.cos(u * 16 * tp)
    const rust = smoothstep(0.25, 0.6, Noise.tfbm(u, v, 5, 5, 121) + v * 0.25 - 0.1)
    const streakv = Noise.streak(u, v, 32, 2, 122)
    return T(mix3(mul([0.55, 0.56, 0.56], 0.85 + streakv * 0.2), [0.35, 0.16, 0.07], rust), rib * 0.8, mix(0.4, 0.85, rust), 0.8 * (1 - rust))
  }, { metal: true })
  return pbrMaterial(p)
})

lazy('shingles', () => {
  const W = 512
  const p = pbrTex(W, W, 3, (x, y) => {
    const u = x / W, v = y / W
    const row = v * 16, ri = Math.floor(row), fr = row - ri
    const off = isEven(ri) ? 0 : 0.5
    const col = u * 12 + off, ci = Math.floor(col), fc = col - ci
    const tone = Noise.cell(ci & 31, ri & 31, 5)
    const grit = Noise.cell(x, y, 6)
    return T(mul([0.2, 0.19, 0.18], 0.75 + tone * 0.4 + grit * 0.15), fr * 0.6 - (fc < 0.03 ? 0.3 : 0), 0.9)
  })
  return pbrMaterial(p)
})

lazy('woodGrey', () => {
  const p = pbrTex(512, 512, 3, (x, y) => {
    const u = x / 512, v = y / 512
    const g = Noise.streak(u, v, 24, 2, 131)
    const crack = smoothstep(0.02, 0, Math.abs(Noise.streak(u, v, 6, 1, 132))) * 0.6
    return T(mul([0.4, 0.36, 0.3], (0.75 + g * 0.35) * (1 - crack * 0.5)), g * 0.5 - crack, 0.85)
  })
  return pbrMaterial(p)
})

lazy('woodFresh', () => {
  const p = pbrTex(512, 512, 2, (x, y) => {
    const u = x / 512, v = y / 512
    const g = Noise.streak(u, v, 20, 2, 141)
    const ring = Math.sin((u * 30 + Noise.tfbm(u, v, 2, 3, 142) * 6) * tp) * 0.5 + 0.5
    return T(mul([0.55, 0.4, 0.25], 0.8 + g * 0.2 + ring * 0.1), g * 0.3 + ring * 0.2, 0.7)
  })
  return pbrMaterial(p)
})

lazy('hay', () => {
  const W = 512
  const p = pbrTex(W, W, 4, (x, y) => {
    const u = x / W, v = y / W
    const a = Noise.streak(u, v, 96, 6, 151)
    const b = Noise.streak(v, u, 80, 5, 152)
    const top = Math.max(a, b * 0.9)
    const tone = Noise.tfbm(u, v, 4, 3, 153)
    return T(mul(mix3([0.62, 0.5, 0.25], [0.78, 0.68, 0.38], tone * 0.5 + 0.5), 0.7 + top * 0.45), top, 0.9)
  })
  return pbrMaterial(p)
})

lazy('concrete', () => {
  const W = 512
  const p = pbrTex(W, W, 2, (x, y) => {
    const u = x / W, v = y / W
    const n = Noise.tfbm(u, v, 16, 4, 161)
    const stave = smoothstep(0.02, 0, Math.abs(fmod1(v * 8) - 0.5) - 0.48)
    const streaks = smoothstep(0.1, 0.5, Noise.streak(u, v, 20, 1, 162)) * 0.25
    return T(mul([0.62, 0.6, 0.56], (0.85 + n * 0.15) * (1 - streaks) * (1 - stave * 0.3)), n * 0.3 - stave * 0.4, 0.88)
  })
  return pbrMaterial(p)
})

lazy('wire', () => {
  const W = 256
  const tex = rgbaTex(W, W, (px, py) => {
    // hexagonal chicken wire, 5 cm cells
    const x = px / W * 8, y = py / W * 8
    const row = Math.floor(y * 1.5)
    const off = isEven(row) ? 0 : 0.5
    const fx = fmod1(x + off) - 0.5, fy = fmod1(y * 1.5) - 0.5
    const d = Math.max(Math.abs(fx) * 1.0 + Math.abs(fy) * 0.58, Math.abs(fy) * 1.15)
    return [0.42, 0.43, 0.42, smoothstep(0.43, 0.47, d) * 0.7]
  })
  // holes are cut away (alphaTest); the wire itself blends at 70 % like the Swift .aOne mode
  return new THREE.MeshStandardMaterial({ map: tex, metalness: 0.7, roughness: 0.5, side: THREE.DoubleSide, transparent: true, alphaTest: 0.2 })
})

lazy('bark', () => {
  const p = pbrTex(512, 512, 5, (x, y) => {
    const u = x / 512, v = y / 512
    const r = Noise.streak(u, v, 10, 2, 171)
    const fis = smoothstep(0.1, -0.2, r)
    return T(mul([0.25, 0.2, 0.15], (0.8 + r * 0.3) * (1 - fis * 0.5)), r, 0.9)
  })
  return tiled(pbrMaterial(p), 2, 1)
})

lazy('leaves', () => {
  const W = 512
  const rr = new RNG(181)
  const lv = Array.from({ length: 260 }, () => { const cx = rr.float(), cy = rr.float(), a = rr.range(0, 6.28), s = rr.range(0.03, 0.055), tn = rr.float(); return [cx, cy, Math.cos(a), Math.sin(a), s, tn] })
  const p = pbrTex(W, W, 4, (x, y) => {
    const u = x / W, v = y / W
    let h = 0, tone = 0.5
    for (const [cx, cy, ca, sa, s, tn] of lv) {
      let dx = u - cx, dy = v - cy
      dx -= Math.round(dx); dy -= Math.round(dy)
      if (dx * dx + dy * dy >= s * s) continue          // outside the leaf's bounding circle
      const lx = (dx * ca + dy * sa) / s, ly = (-dx * sa + dy * ca) / (s * 0.5)
      const d = lx * lx + ly * ly
      if (d < 1) { const hh = (1 - d) + (1 - Math.abs(ly)) * 0.2; if (hh > h) { h = hh; tone = tn } }
    }
    const c = mix3([0.08, 0.16, 0.04], [0.2, 0.3, 0.07], tone)
    return T(h > 0 ? mul(c, 0.7 + h * 0.4) : [0.03, 0.06, 0.02], h, 0.6)
  })
  return tiled(pbrMaterial(p), 2, 2)
})

lazy('dirt', () => {
  const p = pbrTex(512, 512, 3, (x, y) => {
    const u = x / 512, v = y / 512
    const n = Noise.tfbm(u, v, 8, 5, 191)
    const pebble = Noise.cell(Math.floor(x / 3), Math.floor(y / 3), 192) > 0.96
    return T(add(mul([0.33, 0.25, 0.17], 0.8 + n * 0.3), pebble ? [0.1, 0.1, 0.1] : [0, 0, 0]), n * 0.5 + (pebble ? 0.5 : 0), 0.95)
  })
  return pbrMaterial(p)
})

/// Pond water. The game loop scrolls m.normalMap.offset for ripples.
lazy('water', () => {
  const p = pbrTex(512, 512, 1.2, (x, y) => T([0.05, 0.09, 0.08], Noise.tfbm(x / 512, y / 512, 6, 5, 201), 0.05))
  const m = pbrMaterial(p)
  m.roughnessMap = null; m.roughness = 0.04
  m.metalnessMap = null; m.metalness = 0
  m.transparent = true; m.opacity = 0.82; m.depthWrite = false
  return tiled(m, 18, 18)
})

lazy('pumpkin', () => pbr([0.85, 0.38, 0.05], { rough: 0.45 }))
lazy('stem', () => pbr([0.3, 0.3, 0.12], { rough: 0.8 }))
lazy('eggBrown', () => pbr([0.72, 0.5, 0.32], { rough: 0.5 }))
lazy('eggYolk', () => pbr([0.95, 0.65, 0.05], { rough: 0.2 }))
lazy('eggWhite', () => pbr([0.95, 0.95, 0.9], { rough: 0.1, opacity: 0.85 }))
lazy('galv', () => pbr([0.62, 0.63, 0.64], { rough: 0.35, metal: 0.9 }))
lazy('rubber', () => pbr([0.03, 0.03, 0.03], { rough: 0.8 }))
lazy('tractorGreen', () => pbr([0.05, 0.3, 0.1], { rough: 0.35 }))
lazy('tractorYellow', () => pbr([0.9, 0.7, 0.05], { rough: 0.35 }))
lazy('glass', () => pbr([0.15, 0.2, 0.22], { rough: 0.05, metal: 0.4 }))
lazy('apple', () => pbr([0.7, 0.06, 0.05], { rough: 0.3 }))
lazy('ballWhite', () => pbr([0.92, 0.92, 0.9], { rough: 0.35 }))
lazy('black', () => pbr([0.03, 0.03, 0.03], { rough: 0.6 }))
lazy('doorDark', () => pbr([0.07, 0.05, 0.04], { rough: 0.9 }))

// ---------------------------------------------------------------------------------------------
// Coats: procedural coats for the generated animals, cached by pattern and colours.

const cache = new Map()
const shellCache = new Map()
const FURRY = new Set(['fur', 'spots', 'rosettes', 'patches', 'stripes', 'wool', 'cells', 'bands', 'holstein', 'quills'])

/// Voronoi-ish lookup over a g x g tileable grid: nearest (and second nearest) jittered point.
function cells(u, v, g, s1, s2, jit) {
  const cx = Math.floor(u * g), cy = Math.floor(v * g)
  let d1 = 9, d2 = 9
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) {
    const ix = cx + dx, iy = cy + dy
    const wx = (ix + g) % g, wy = (iy + g) % g
    const [px, py] = jit(ix, iy, Noise.cell(wx, wy, s1), Noise.cell(wx, wy, s2))
    const d = Math.hypot(u - px / g, v - py / g) * g
    if (d < d1) { d2 = d1; d1 = d } else if (d < d2) d2 = d
  }
  return [d1, d2]
}

function makeCoat(c, a, b) {
  if (c === 'feathers') return tiled(feathers(a, b, 0.6, 5), 4, 5)
  const W = 512
  let gloss = 0, bump = 2, rep = [2, 2]
  switch (c) {
    case 'slick': gloss = 0.7; bump = 0.8; break
    case 'chitin': gloss = 0.85; bump = 1; break
    case 'scales': gloss = 0.3; bump = 3; rep = [4, 6]; break
    case 'shell': bump = 4; rep = [2, 2]; break
    case 'wool': bump = 5; rep = [4, 5]; break
    case 'quills': bump = 4; rep = [6, 3]; break
    case 'stripes': rep = [1, 1.4]; break
    case 'bands': rep = [1, 3]; break
    case 'fur': bump = 1.6; break
  }
  const p = pbrTex(W, W, bump, (x, y) => {
    const u = x / W, v = y / W
    const hair = Noise.streak(u, v, 128, 12, 3)
    const big = Noise.tfbm(u, v, 3, 4, 11)
    let col = a, h = hair * 0.5, rough = 0.7
    switch (c) {
      case 'fur':
        col = mul(mix3(a, b, smoothstep(0.1, 0.6, big) * 0.35), 0.85 + hair * 0.25)
        break
      case 'spots': {
        const [best] = cells(u, v, 9, 21, 22, (ix, iy, jx, jy) => [ix + 0.2 + jx * 0.6, iy + 0.2 + jy * 0.6])
        const s = smoothstep(0.3, 0.22, best + big * 0.05)
        col = mix3(mul(a, 0.9 + hair * 0.2), b, s)
        break
      }
      case 'rosettes': {
        const [best] = cells(u, v, 7, 31, 32, (ix, iy, jx, jy) => [ix + 0.25 + jx * 0.5, iy + 0.25 + jy * 0.5])
        const ring = smoothstep(0.42, 0.36, best + big * 0.06) * smoothstep(0.18, 0.26, best + Noise.tfbm(u, v, 24, 2, 33) * 0.1)
        const inner = smoothstep(0.3, 0.2, best)
        col = mul(mix3(mix3(a, mul(a, 0.8), inner), b, ring), 0.9 + hair * 0.2)
        break
      }
      case 'cells': {
        const [d1, d2] = cells(u, v, 6, 41, 42, (ix, iy, jx, jy) => [ix + jx, iy + jy])
        const line = smoothstep(0.06, 0.12, d2 - d1 + big * 0.03)
        col = mul(mix3(a, mul(b, 0.9 + big * 0.2), line), 0.9 + hair * 0.15)
        break
      }
      case 'patches': {
        const n = big + Noise.tfbm(u, v, 2, 2, 12) * 0.5
        col = mul(mix3(a, b, smoothstep(0.05, 0.1, n + hair * 0.04)), 0.9 + hair * 0.2)
        break
      }
      case 'stripes': {
        const w = Noise.tfbm(u, v, 4, 3, 51) * 2.2
        const s = Math.sin((v * 9 + w + u * 0.5) * tp)
        const m = smoothstep(0.25, 0.45, s + Noise.tfbm(u, v, 8, 2, 52) * 0.3)
        col = mul(mix3(a, b, m), 0.9 + hair * 0.2)
        break
      }
      case 'bands': {
        const s = Math.sin(v * 6 * tp + big * 0.6)
        col = mul(mix3(a, b, smoothstep(-0.1, 0.1, s)), 0.92 + hair * 0.15)
        break
      }
      case 'scales': {
        const row = v * 16
        const off = isEven(Math.floor(row)) ? 0 : 0.5
        const fx = fmod1(u * 10 + off) - 0.5, fy = row - Math.floor(row) - 0.5
        const d = Math.sqrt(fx * fx * 1.3 + fy * fy)
        col = mul(mix3(a, b, smoothstep(0.1, 0.5, big) * 0.6), 1 - smoothstep(0.32, 0.5, d) * 0.4)
        h = 1 - d * 2; rough = 0.5
        break
      }
      case 'skin': {
        const wr = Noise.streak(u, v, 40, 6, 61) + Noise.streak(v, u, 36, 5, 62) * 0.6
        col = mul(mix3(a, b, smoothstep(0.0, 0.6, big) * 0.4), 0.9 + wr * 0.1)
        h = -Math.abs(wr) * 0.8 + Noise.tfbm(u, v, 40, 2, 63) * 0.2; rough = 0.75
        break
      }
      case 'slick':
        col = mix3(a, b, smoothstep(0.0, 0.5, big) * 0.35)
        h = Noise.tfbm(u, v, 24, 2, 71) * 0.2; rough = 0.28
        break
      case 'shell': {
        const [d1, d2] = cells(u, v, 4, 81, 82, (ix, iy, jx, jy) => [ix + 0.3 + jx * 0.4, iy + 0.3 + jy * 0.4])
        const edge = smoothstep(0.02, 0.15, d2 - d1)
        const rings = Math.sin(d1 * 30) * 0.5 + 0.5
        col = mix3(b, mul(a, 0.85 + rings * 0.2), edge)
        h = edge * 0.8 - d1 * 0.3; rough = 0.55
        break
      }
      case 'chitin':
        col = mix3(a, b, smoothstep(0.2, 0.7, big) * 0.3)
        h = Noise.tfbm(u, v, 32, 2, 91) * 0.15; rough = 0.2
        break
      case 'wool': {
        const cu = Noise.tfbm(u, v, 24, 3, 101)
        const curl = Math.sin(u * 60 + cu * 8) * Math.sin(v * 60 + cu * 8)
        col = mul(a, 0.8 + cu * 0.2 + curl * 0.08)
        h = cu + curl * 0.3; rough = 0.95
        break
      }
      case 'quills': {
        const q = Noise.streak(u, v, 64, 4, 111)
        col = mix3(a, b, smoothstep(0.0, 0.3, q))
        h = q; rough = 0.6
        break
      }
    }
    return T(col, h, rough - gloss * 0.45)
  })
  let m = tiled(pbrMaterial(p, { normalScale: 0.9 }), rep[0], rep[1])
  if (gloss > 0.5) m = withClearcoat(m, 0.4)
  return countershaded(m)
}

/// Fur shell fragment: countershade, then cut most texels away and darken toward the root.
const SHELL_FRAG = COUNTERSHADE + /* glsl */`
  vec2 furCell = floor(vUvMS * vec2(260.0 * uRepU, 260.0 * uRepV));
  float furH = fract(sin(dot(furCell, vec2(12.9898, 78.233))) * 43758.5453);
  if (furH < uCut) discard;
  diffuseColor.rgb *= uShade;
`

export const Coats = {
  get(key, make) {
    let m = cache.get(key)
    if (!m) { m = make(); cache.set(key, m) }
    return m
  },

  key(v) { return `${v[0].toFixed(2)},${v[1].toFixed(2)},${v[2].toFixed(2)}` },

  /// coat(def) with def.coat / def.a / def.b, or coat(coatName, a, b).
  coat(c, a, b) {
    if (typeof c !== 'string') { a = c.a; b = c.b; c = c.coat }
    if (c === 'holstein') return Mat.hide
    return Coats.get(`${c}|${Coats.key(a)}|${Coats.key(b)}`, () => makeCoat(c, a, b))
  },

  /// Lighter belly, slightly darker back (GLSL for patchShader: uses diffuseColor, vWorldNormalMS).
  countershade: COUNTERSHADE,

  /// Shell layers for furry coats: copies of the mesh pushed out along the normal, with most
  /// texels cut away, so the surface reads as short hair instead of painted plastic.
  furShells(mesh, base, length, layers = 3) {
    if (!mesh || !mesh.geometry) return
    for (let k = 1; k <= layers; k++) {
      const sn = new THREE.Mesh(mesh.geometry, Coats.shellMat(base, k, layers, length))
      sn.castShadow = false
      sn.receiveShadow = mesh.receiveShadow
      sn.name = 'furShell'
      mesh.add(sn)
    }
  },

  shellMat(base, k, n, len) {
    const key = `${base.uuid}|${k}|${n}|${Math.round(len * 1000)}`
    let m = shellCache.get(key)
    if (m) return m
    const t = k / n
    m = base.clone()
    m.onBeforeCompile = () => {}; m.userData = {}; m.defines = Object.assign({}, m.defines)
    const rep = base.map ? base.map.repeat : { x: 1, y: 1 }
    patchShader(m, {
      key: 'furshell',
      vertex: 'transformed += normal * furLen;',
      fragment: SHELL_FRAG,
      uniforms: {
        furLen: { value: len * t }, uCut: { value: 0.35 + t * 0.45 }, uShade: { value: 0.82 + t * 0.2 },
        uRepU: { value: rep.x }, uRepV: { value: rep.y },
      },
    })
    shellCache.set(key, m)
    return m
  },

  isFurry(c) { return FURRY.has(c) },

  plain(v, rough = 0.6, metal = 0) {
    return Coats.get(`plain|${Coats.key(v)}|${rough}|${metal}`, () => pbr(v, { rough, metal }))
  },

  glossy(v) {
    return Coats.get(`gloss|${Coats.key(v)}`, () => ccPbr(v, 0.08, 1))
  },

  membrane(v, alpha) {
    return Coats.get(`mem|${Coats.key(v)}|${alpha}`, () => {
      let m = pbr(v, { rough: alpha < 0.5 ? 0.1 : 0.6 })
      if (alpha < 0.5) m = withClearcoat(m, 1)
      m.transparent = true; m.opacity = alpha
      m.side = THREE.DoubleSide
      m.depthWrite = alpha > 0.7
      return m
    })
  },

  limbMat(d) { return d.limbCol ? Coats.plain(d.limbCol, 0.5) : Coats.coat(d) },

  /// Warm the cache a coat per idle slice so the first morph into each animal doesn't hitch.
  /// Resolves when every non-custom def has its coat built.
  prewarm(defs) {
    const todo = (defs || []).filter(d => !d.custom)
    const idle = typeof requestIdleCallback === 'function' ? cb => requestIdleCallback(cb, { timeout: 500 }) : cb => setTimeout(cb, 0)
    return new Promise(resolve => {
      const step = () => {
        const d = todo.shift()
        if (!d) return resolve()
        try { Coats.coat(d) } catch (e) { console.warn('coat prewarm failed', d && d.name, e) }
        idle(step)
      }
      idle(step)
    })
  },
}
