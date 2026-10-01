// Leaf-card tree crowns, needle branches and wind. Ported from Foliage.swift.
import * as THREE from '../vendor/three.module.js'
import { RNG, mix3, smoothstep, QUALITY } from './util.js'
import { makeRGBA, patchShader } from './tex.js'
import { meshGeometry, mesh, sphereNode } from './loft.js'
import { Coats } from './mats.js'

/// Wind sway in object space (merged static scenery is baked to world space, so the phase varies across the map).
const WIND = `
float sway = sin(uTime * 1.3 + transformed.x * 0.15 + transformed.z * 0.11) * 0.5 + sin(uTime * 3.1 + transformed.y * 0.7) * 0.25;
transformed.x += sway * 0.05;
transformed.z += sway * 0.035;
`

function cardMaterial(tex, rough = 0.95) {
  const m = new THREE.MeshStandardMaterial({ map: tex, roughness: rough, metalness: 0, side: THREE.DoubleSide, alphaTest: 0.5 })
  m.envMapIntensity = 0.6          // "_surface.specular = 0": keep cards matte
  patchShader(m, { vertex: WIND, key: 'foliage-wind' })
  return m
}

const leafCache = new Map()
const k3 = v => v.map(x => x.toFixed(2)).join(',')

// tex.js DataTextures put data row 0 at the bottom of SceneKit-style UVs, so flip y to match the Swift images.
function img(W, f) { return makeRGBA(W, W, (x, y) => f(x, W - 1 - y)) }

export const Foliage = {
  WIND,

  /// A clump of broad leaves on a transparent card. Cached by colours (like Coats.get in Swift).
  leafMat(lo, hi, seed) {
    const key = 'leafcard|' + k3(lo) + '|' + k3(hi)
    let m = leafCache.get(key)
    if (m) return m
    const rr = new RNG(seed)
    const W = 256
    const leaves = []
    for (let i = 0; i < 70; i++) leaves.push([rr.range(0.1, 0.9), rr.range(0.1, 0.9), rr.range(0, 6.28), rr.range(0.06, 0.11), rr.float()])
    const tex = img(W, (px, py) => {
      const u = px / W, v = py / W
      let best = 0, tone = 0, rib = 0
      for (const [cx, cy, a, sz, tn] of leaves) {
        const dx = u - cx, dy = v - cy
        const ca = Math.cos(a), sa = Math.sin(a)
        const lx = (dx * ca + dy * sa) / sz, ly = (-dx * sa + dy * ca) / (sz * 0.48)
        const d = lx * lx + ly * ly
        if (d < 1) {
          const h = 1 - d
          if (h > best) { best = h; tone = tn; rib = Math.abs(ly) < 0.08 ? 1 : 0 }
        }
      }
      if (best <= 0) return [lo[0] * 0.6, lo[1] * 0.6, lo[2] * 0.6, 0]
      let c = mix3(lo, hi, tone).map(x => x * (0.7 + best * 0.45))
      c = mix3(c, [c[0] * 1.3 + 0.03, c[1] * 1.3 + 0.04, c[2] * 1.3], rib * 0.5)
      return [c[0], c[1], c[2], 1]
    })
    m = cardMaterial(tex)
    leafCache.set(key, m)
    return m
  },

  _pine: null,
  get pineMat() {
    if (this._pine) return this._pine
    const rr = new RNG(88)
    const W = 256
    const needles = []
    for (let i = 0; i < 420; i++) needles.push([rr.float(), rr.range(0.05, 0.95), rr.range(-0.5, 0.5), rr.range(0.04, 0.09), rr.float()])
    const tex = img(W, (px, py) => {
      // a branch along the middle with needles sticking out both ways
      const u = px / W, v = py / W
      const taper = 1 - v * 0.7
      if (Math.abs(u - 0.5) < 0.012 * taper) return [0.2, 0.14, 0.08, 1]
      for (const [side, y, lean, len, tn] of needles) {
        const sx = side < 0.5 ? -1 : 1
        const dx = (u - 0.5) * sx, dy = v - y - dx * lean
        if (dx > 0 && dx < len * 4 * taper && Math.abs(dy) < 0.006) {
          const c = mix3([0.05, 0.14, 0.06], [0.12, 0.26, 0.1], tn).map(x => x * (0.8 + dx * 2))
          return [c[0], c[1], c[2], 1]
        }
      }
      return [0.05, 0.12, 0.05, 0]
    })
    this._pine = cardMaterial(tex, 0.8)
    return this._pine
  },

  /// Cards scattered through an ellipsoid, facing roughly outward, with a darker core ball.
  /// center/radii are [x,y,z]. Card counts are thinned a little on tablets.
  crown(center, radii, cards, size, seed, m) {
    const rr = new RNG(seed)
    const n = Math.max(8, Math.round(cards * (0.6 + 0.4 * QUALITY)))
    const P = [], N = [], U = [], I = []
    for (let k = 0; k < n; k++) {
      const th = rr.range(0, 2 * Math.PI), ph = Math.acos(rr.range(-0.6, 1))
      const r = Math.pow(rr.float(), 0.3)
      const dir = [Math.sin(ph) * Math.cos(th), Math.cos(ph), Math.sin(ph) * Math.sin(th)]
      const p = [center[0] + dir[0] * radii[0] * r, center[1] + dir[1] * radii[1] * r, center[2] + dir[2] * radii[2] * r]
      let out = [dir[0] / radii[0], dir[1] / radii[1], dir[2] / radii[2]]
      let l = Math.hypot(...out); out = out.map(x => x / l)
      const q = [rr.range(-1, 1) + 0.001, rr.range(-1, 1), rr.range(-1, 1)]
      let t1 = [out[1] * q[2] - out[2] * q[1], out[2] * q[0] - out[0] * q[2], out[0] * q[1] - out[1] * q[0]]
      l = Math.hypot(...t1)
      t1 = l > 1e-6 ? t1.map(x => x / l) : [1, 0, 0]
      const t2 = [out[1] * t1[2] - out[2] * t1[1], out[2] * t1[0] - out[0] * t1[2], out[0] * t1[1] - out[1] * t1[0]]
      const hs = size * rr.range(0.7, 1.3) * 0.5
      const i = P.length
      const a1 = t1.map(x => x * hs), a2 = t2.map(x => x * hs)
      P.push([p[0] - a1[0] - a2[0], p[1] - a1[1] - a2[1], p[2] - a1[2] - a2[2]],
        [p[0] + a1[0] - a2[0], p[1] + a1[1] - a2[1], p[2] + a1[2] - a2[2]],
        [p[0] + a1[0] + a2[0], p[1] + a1[1] + a2[1], p[2] + a1[2] + a2[2]],
        [p[0] - a1[0] + a2[0], p[1] - a1[1] + a2[1], p[2] - a1[2] + a2[2]])
      N.push(out, out, out, out)
      U.push([0, 1], [1, 1], [1, 0], [0, 0])
      I.push(i, i + 1, i + 2, i, i + 2, i + 3)
    }
    const node = mesh(meshGeometry(P, N, U, I), m)
    // a darker core so you can't see straight through
    // (radius min*0.72 scaled by radii/min == a unit sphere scaled by radii*0.72; shares one geometry)
    const core = sphereNode(1, Coats.plain([0.05, 0.1, 0.03], 0.9), 10)
    core.position.set(center[0], center[1], center[2])
    core.scale.set(radii[0] * 0.72, radii[1] * 0.72, radii[2] * 0.72)
    node.add(core)
    return node
  },

  /// Drooping needle branches in tiers around a trunk.
  pineBranches(h, radius, tiers, seed) {
    const rr = new RNG(seed)
    const P = [], N = [], U = [], I = []
    for (let k = 0; k < tiers; k++) {
      const t = k / tiers
      const y = h * (0.22 + t * 0.72)
      const r = radius * (1 - t * 0.85) + 0.2
      const n = 9 + Math.trunc((1 - t) * 6)
      for (let j = 0; j < n; j++) {
        const a = j / n * 2 * Math.PI + rr.range(0, 0.4)
        const out = [Math.cos(a), 0, Math.sin(a)]
        const side = [-Math.sin(a), 0, Math.cos(a)]
        const w = r * 0.55
        const base = [0, y, 0], tip = [out[0] * r, y - r * 0.35, out[2] * r]
        const i = P.length
        const s3 = side.map(x => x * w * 0.3), s6 = side.map(x => x * w * 0.6)
        P.push([base[0] - s3[0], base[1], base[2] - s3[2]], [base[0] + s3[0], base[1], base[2] + s3[2]],
          [tip[0] + s6[0], tip[1], tip[2] + s6[2]], [tip[0] - s6[0], tip[1], tip[2] - s6[2]])
        let nn = [out[0] * 0.6, 1, out[2] * 0.6]; const l = Math.hypot(...nn); nn = nn.map(x => x / l)
        N.push(nn, nn, nn, nn)
        U.push([0.3, 0], [0.7, 0], [1, 1], [0, 1])
        I.push(i, i + 1, i + 2, i, i + 2, i + 3)
      }
    }
    return mesh(meshGeometry(P, N, U, I), Foliage.pineMat)
  },
}
