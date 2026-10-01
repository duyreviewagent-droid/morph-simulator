// Scenery for the nine generated maps. Ported from MapBuilder.swift.
// Everything is added through w.add() and later merged into static chunks by World.
import * as THREE from '../vendor/three.module.js'
import { RNG, Noise } from './util.js'
import { pbr } from './tex.js'
import { Ring, loft, mesh, loftNode, limb, boxNode, cylNode, sphereNode } from './loft.js'
import { Mat, Coats } from './mats.js'
import { Foliage } from './foliage.js'
import { Farm, Solid, meterBox, poly, P, S, G, Prim } from './world.js'

// Materials (lazy, like Swift static lets).
const cache = {}
const lazy = (k, f) => () => cache[k] || (cache[k] = f())
const MB = {}
const def = (k, f) => Object.defineProperty(MB, k, { get: lazy(k, f), enumerable: true })
def('rock', () => Coats.coat('skin', [0.46, 0.44, 0.41], [0.3, 0.29, 0.27]))
def('redRock', () => Coats.coat('skin', [0.62, 0.36, 0.22], [0.45, 0.25, 0.15]))
def('sandstone', () => Coats.coat('skin', [0.82, 0.68, 0.45], [0.7, 0.55, 0.35]))
def('snow', () => {
  const m = new THREE.MeshPhysicalMaterial({ roughness: 0.55, metalness: 0, clearcoat: 0.2 })
  m.color.setRGB(0.92, 0.94, 0.98, THREE.SRGBColorSpace)
  return m
})
def('ice', () => {
  const m = new THREE.MeshPhysicalMaterial({ roughness: 0.08, metalness: 0, clearcoat: 1, transparent: true, opacity: 0.85 })
  m.color.setRGB(0.7, 0.88, 0.95, THREE.SRGBColorSpace)
  return m
})
def('pineGreen', () => Coats.coat('fur', [0.08, 0.2, 0.08], [0.04, 0.12, 0.05]))
def('palmLeaf', () => Coats.coat('fur', [0.2, 0.42, 0.1], [0.12, 0.3, 0.05]))
def('deadWood', () => Coats.coat('skin', [0.28, 0.26, 0.23], [0.18, 0.17, 0.15]))
def('cactus', () => Coats.coat('fur', [0.22, 0.42, 0.18], [0.15, 0.3, 0.12]))
def('stoneBlock', () => Coats.coat('cells', [0.5, 0.5, 0.46], [0.3, 0.3, 0.28]))

// MARK: helpers

const ground = (w, x, z) => w.terrain(x, z)

/// Random spots on dry land away from the spawn. avoid = [[x, z, r], ...]. Returns [[x, z], ...].
function spots(w, n, seed, { r0 = 10, r1 = 200, dry = true, avoid = [] } = {}) {
  const rr = new RNG(seed)
  const out = []
  let tries = 0
  const sp = w.map.spawn
  while (out.length < n && tries < n * 30) {
    tries++
    const a = rr.range(0, 2 * Math.PI), d = r0 + (r1 - r0) * Math.sqrt(rr.float())
    const x = Math.cos(a) * d + sp[0], z = Math.sin(a) * d + sp[2]
    if (!(Math.abs(x) < Farm.half - 12 && Math.abs(z) < Farm.half - 12)) continue
    const lvl = w.map.waterLevel
    if (dry && lvl !== null && w.terrain(x, z) < lvl + 0.3) continue
    if (avoid.some(([ax, az, ar]) => Math.hypot(x - ax, z - az) < ar)) continue
    out.push([x, z])
  }
  return out
}

function boulder(w, x, z, s, m = MB.rock, seed = 1) {
  const rings = []
  for (let i = 0; i <= 8; i++) {
    const t = i / 8
    const r = Math.sin(Math.PI * t) * s + 0.01
    rings.push(Ring([0, (t - 0.5) * s * 1.4, 0], r, r * 0.9))
  }
  const g = loft(rings, { seg: 18, ref: [0, 0, 1], displace: p => Noise.fbm(p[0] * 1.5 / s + seed, p[1] * 1.5 / s + p[2] * 1.3 / s, 3, seed) * s * 0.35 })
  const n = P(mesh(g, m), x, ground(w, x, z) + s * 0.35, z, 0, seed % 7, 0)
  w.add(n)
  if (s > 0.6) w.solids.push(Solid.cyl(x, z, s * 0.85, s * 1.1, { base: ground(w, x, z), tag: 'rock', surface: 'concrete' }))
}

function pine(w, x, z, s, snowy = false) {
  const y = ground(w, x, z)
  const n = P(G(), x, y, z)
  w.add(n)
  n.add(P(Prim.cone(0.22 * s, 0.03 * s, 7.5 * s, Mat.bark, 8), 0, 3.75 * s, 0))
  n.add(P(Prim.cone(1.1 * s, 0.05, 5.5 * s, Coats.plain([0.03, 0.08, 0.03], 0.9), 10), 0, 4.3 * s, 0))
  n.add(Foliage.pineBranches(7.8 * s, 2.2 * s, 9, Math.abs(Math.trunc(x * 31 + z)) + 1))
  if (snowy) {
    for (let k = 0; k < 4; k++) {
      const r = (1.6 - k * 0.35) * s, yy = (2.2 + k * 1.4) * s
      n.add(P(Prim.cone(r, 0.02, 0.6 * s, MB.snow, 12), 0, yy + 0.2 * s, 0))
    }
  }
  w.solids.push(Solid.cyl(x, z, 0.3 * s, 7 * s, { base: y, tag: 'tree', surface: 'wood' }))
}

function oak(w, x, z, s, seed, leaves = null) {
  const rr = new RNG(seed)
  const y = ground(w, x, z)
  const n = P(G(), x, y, z)
  w.add(n)
  const th = 2.4 * s
  n.add(loftNode([Ring([0, -0.2, 0], 0.32 * s, 0.3 * s), Ring([0, 0.3, 0], 0.22 * s, 0.2 * s), Ring([0.05, th, 0.03], 0.14 * s, 0.13 * s), Ring([0.1, th + 0.8 * s, 0.05], 0.06 * s, 0.06 * s)], Mat.bark, { seg: 12, smooth: 3 }))
  const lm = leaves || Foliage.leafMat([0.06, 0.16, 0.04], [0.2, 0.34, 0.08], 3)
  for (let k = 0; k < 3; k++) {
    const a = rr.range(0, 6.28), d = rr.range(0.3, 1.1) * s
    const cy = th + 1.4 * s + rr.range(-0.3, 0.8) * s
    const rk = s * rr.range(0.85, 1.15)
    n.add(Foliage.crown([Math.cos(a) * d, cy, Math.sin(a) * d], [1.8 * rk, 1.4 * rk, 1.8 * rk], 130, 1.1 * s, rr.next(), lm))
  }
  w.solids.push(Solid.cyl(x, z, 0.35 * s, th + 3 * s, { base: y, tag: 'tree', surface: 'wood' }))
}

function palm(w, x, z, s, seed) {
  const rr = new RNG(seed)
  const y = ground(w, x, z)
  const n = P(G(), x, y, z, 0, rr.range(0, 6.28), 0)
  w.add(n)
  const lean = rr.range(0.8, 2.2) * s, h = 6 * s
  const rings = []
  for (let k = 0; k <= 8; k++) {
    const t = k / 8
    rings.push(Ring([lean * t * t, h * t, 0], 0.2 * s * (1 - t * 0.35), 0.2 * s * (1 - t * 0.35)))
  }
  n.add(loftNode(rings, Coats.coat('bands', [0.45, 0.36, 0.25], [0.35, 0.27, 0.18]), { seg: 12, smooth: 1 }))
  const top = [lean, h, 0]
  for (let k = 0; k < 9; k++) {
    const a = k / 9 * 2 * Math.PI + rr.range(0, 0.3)
    const dx = Math.cos(a), dz = Math.sin(a)
    const len = 2.6 * s
    const at = (f, dy) => [top[0] + dx * len * f, top[1] + dy, top[2] + dz * len * f]
    n.add(loftNode([Ring(top, 0.03 * s, 0.01 * s), Ring(at(0.4, 0.35 * s), 0.35 * s, 0.02 * s),
      Ring(at(0.8, -0.3 * s), 0.25 * s, 0.015 * s), Ring(at(1, -0.9 * s), 0.02 * s, 0.01 * s)],
    MB.palmLeaf, { seg: 6, ref: [0, 1, 0], smooth: 3 }))
  }
  const nut = Coats.plain([0.35, 0.25, 0.12])
  for (let k = 0; k < 4; k++) n.add(P(Prim.sphere(0.13 * s, nut, 10), top[0] + Math.cos(k * 1.6) * 0.2 * s, top[1] - 0.25 * s, Math.sin(k * 1.6) * 0.2 * s))
  w.solids.push(Solid.cyl(x, z, 0.25 * s, h, { base: y, tag: 'tree', surface: 'wood' }))
}

function stepped(w, x, z, levels, base, stepH, shrink, m, tag) {
  const y0 = ground(w, x, z) - 0.3
  for (let k = 0; k < levels; k++) {
    const size = base - k * shrink
    if (!(size > 0.5)) break
    w.add(P(meterBox(size, stepH, size, m, 0.4), x, y0 + k * stepH + stepH / 2, z))
    w.solids.push(Solid.box(x, z, size, size, (k + 1) * stepH, { base: y0, tag, surface: 'concrete' }))
  }
}

function cabin(w, x, z, yaw, stilts = 0) {
  const y = ground(w, x, z) + stilts
  const n = P(G(), x, y, z, 0, yaw, 0)
  w.add(n)
  const logM = Coats.coat('bands', [0.45, 0.3, 0.17], [0.35, 0.22, 0.12])
  n.add(P(meterBox(6, 3, 5, logM, 0.5), 0, 1.5, 0))
  for (const sz of [1, -1]) n.add(P(meterBox(7, 0.15, 3.3, Mat.shingles, 0.5), 0, 3.75, sz * 1.35, sz * 0.55, 0, 0))
  n.add(poly([[-3, 3, 2.51], [3, 3, 2.51], [0, 4.6, 2.51]], logM))
  n.add(poly([[3, 3, -2.51], [-3, 3, -2.51], [0, 4.6, -2.51]], logM))
  n.add(P(boxNode(1, 2, 0.05, Mat.doorDark), 0, 1, 2.52))
  n.add(P(boxNode(0.9, 0.8, 0.05, Mat.glass), 1.9, 1.8, 2.52))
  if (stilts > 0) {
    for (const [px, pz] of [[-2.8, -2.3], [2.8, -2.3], [-2.8, 2.3], [2.8, 2.3]]) n.add(P(Prim.cyl(0.12, stilts + 1, Mat.woodGrey, 8), px, -stilts / 2 - 0.5, pz))
    n.add(P(meterBox(8, 0.15, 7, Mat.woodGrey, 1), 0, -0.05, 0.8))
  }
  w.solids.push(new Solid({ minX: x - 3.4, maxX: x + 3.4, minZ: z - 3.4, maxZ: z + 3.4, bottom: y - 0.5, top: () => y + 3.2, tag: 'cabin', surface: 'wood' }))
  if (stilts > 0) w.solids.push(Solid.box(x, z, 8.2, 8.2, 0.02, { base: y - 0.02, tag: 'deck', surface: 'wood' }))
}

// MARK: maps

function savanna(w) {
  const rr = new RNG(11)
  const am = Foliage.leafMat([0.12, 0.2, 0.05], [0.3, 0.36, 0.1], 5)
  for (const [x, z] of spots(w, 78, 12, { avoid: [[22, 18, 14]] })) {
    const s = rr.range(0.9, 1.4)
    const y = ground(w, x, z)
    const n = P(G(), x, y, z)
    w.add(n)
    n.add(P(limb(3.5 * s, 0.25 * s, 0.15 * s, Mat.bark, { seg: 10, dir: [0.25, 1, 0] }), 0, 0, 0))
    n.add(P(limb(1.8 * s, 0.12 * s, 0.07 * s, Mat.bark, { seg: 8, dir: [-0.8, 1, 0.3] }), 0.6 * s, 2.5 * s, 0))
    for (let k = 0; k < 3; k++) {
      const a = k * 2.1 + rr.range(0, 0.6)
      n.add(Foliage.crown([0.8 * s + Math.cos(a) * 1.3 * s, 4.0 * s + rr.range(0, 0.4), Math.sin(a) * 1.3 * s], [2.3 * s, 0.45 * s, 2.3 * s], 110, 0.9 * s, rr.next(), am))
    }
    w.solids.push(Solid.cyl(x, z, 0.3 * s, 4 * s, { base: y, tag: 'tree', surface: 'wood' }))
  }
  spots(w, 30, 13, { avoid: [[22, 18, 14]] }).forEach(([x, z], i) => {
    const h = rr.range(1.5, 3.2)
    w.add(P(Prim.cone(h * 0.45, 0.08, h, MB.redRock, 12), x, ground(w, x, z) + h / 2 - 0.1, z))
    w.solids.push(Solid.cyl(x, z, h * 0.35, h * 0.8, { base: ground(w, x, z), tag: 'mound', surface: 'dirt' }))
    if (i % 3 === 0) boulder(w, x + 4, z + 2, rr.range(0.8, 2), MB.redRock, i)
  })
  // a big kopje of rocks to climb
  for (let k = 0; k < 7; k++) boulder(w, -30 + (k % 3) * 2.5, -25 + Math.trunc(k / 3) * 2.2, 1.5 + (k % 2), MB.rock, 40 + k)
}

function arctic(w) {
  const rr = new RNG(21)
  for (const [x, z] of spots(w, 90, 22, { r0: 20, avoid: [[-28, -22, 26]] })) pine(w, x, z, rr.range(0.8, 1.3), true)
  // ice floes on the lake and icebergs
  for (let k = 0; k < 14; k++) {
    const a = rr.range(0, 6.28), d = rr.range(2, 15)
    const x = -28 + Math.cos(a) * d, z = -22 + Math.sin(a) * d
    const s = rr.range(1, 2.6)
    w.add(P(Prim.box(s, 0.3, s * rr.range(0.6, 1.2), MB.snow), x, -0.55, z, 0, rr.range(0, 3), 0))
    w.solids.push(Solid.cyl(x, z, s * 0.4, 0.3, { base: -0.7, tag: 'floe', surface: 'concrete' }))
    if (k < 3) {
      w.add(S(P(Prim.sphere(rr.range(2, 3.5), MB.ice, 12), x + 4, 0.8, z + 3), 1, 1.4, 0.8))
      w.solids.push(Solid.cyl(x + 4, z + 3, 2.2, 4, { base: -1, tag: 'iceberg', surface: 'concrete' }))
    }
  }
  // igloo
  const ix = 14, iz = 10
  const iy = ground(w, ix, iz)
  w.add(P(sphereNode(2.6, Coats.coat('cells', [0.92, 0.94, 0.98], [0.78, 0.84, 0.92]), 24), ix, iy, iz))
  w.add(P(cylNode(0.9, 1.8, MB.snow, 16), ix, iy + 0.6, iz + 2.8, Math.PI / 2, 0, 0))
  w.add(P(boxNode(1.1, 1.2, 0.1, Mat.doorDark), ix, iy + 0.55, iz + 3.72))
  w.solids.push(new Solid({
    minX: ix - 2.6, maxX: ix + 2.6, minZ: iz - 2.6, maxZ: iz + 2.6, bottom: iy - 1,
    top: (x, z) => iy + Math.sqrt(Math.max(0, 6.76 - (x - ix) * (x - ix) - (z - iz) * (z - iz))), round: { cx: ix, cz: iz, r: 2.6 }, tag: 'igloo', surface: 'concrete',
  }))
  for (let k = 0; k < 12; k++) boulder(w, rr.range(-180, 180), rr.range(-180, 180), rr.range(0.5, 1.6), MB.snow, k + 60)
}

function jungle(w) {
  const rr = new RNG(31)
  const vine = Coats.plain([0.12, 0.25, 0.06], 0.8)
  const jm = Foliage.leafMat([0.03, 0.12, 0.03], [0.12, 0.3, 0.06], 7)
  for (const [x, z] of spots(w, 165, 32, { r0: 8 })) {
    if (Math.abs(z - Math.sin(x * 0.035) * 18 - 8) < 9) continue
    const s = rr.range(1.1, 1.8)
    const y = ground(w, x, z)
    const n = P(G(), x, y, z)
    w.add(n)
    const h = 11 * s
    n.add(loftNode([Ring([0, -0.3, 0], 0.8 * s, 0.8 * s, 3), Ring([0, 1, 0], 0.4 * s, 0.4 * s), Ring([0, h * 0.6, 0], 0.3 * s, 0.3 * s), Ring([0, h, 0], 0.2 * s, 0.2 * s)], Mat.bark, { seg: 12, smooth: 3 }))
    for (let k = 0; k < 3; k++) {
      const a = rr.range(0, 6.28), d = rr.range(0.5, 2.0) * s
      n.add(Foliage.crown([Math.cos(a) * d, h + rr.range(-0.5, 1.2) * s, Math.sin(a) * d], [3.2 * s, 1.6 * s, 3.2 * s], 120, 1.5 * s, rr.next(), jm))
    }
    for (let k = 0; k < 4; k++) {
      const a = rr.range(0, 6.28), d = rr.range(1, 3) * s, l = rr.range(3, 8) * s
      n.add(P(Prim.cyl(0.03, l, vine, 4), Math.cos(a) * d, h - l / 2, Math.sin(a) * d))
    }
    w.solids.push(Solid.cyl(x, z, 0.6 * s, h, { base: y, tag: 'tree', surface: 'wood' }))
  }
  for (const [x, z] of spots(w, 270, 33, { r0: 4 })) {
    if (Math.abs(z - Math.sin(x * 0.035) * 18 - 8) < 7) continue
    w.add(S(P(Prim.sphere(rr.range(0.5, 1.1), Mat.leaves, 10), x, ground(w, x, z) + 0.2, z), 1.3, 0.6, 1.3))
  }
  // an overgrown temple to climb
  stepped(w, -30, -35, 9, 18, 0.9, 1.8, MB.stoneBlock, 'temple')
  const ty = ground(w, -30, -35) - 0.3 + 8.1
  w.add(P(meterBox(2.5, 2.2, 2.5, MB.stoneBlock), -30, ty + 1.1, -35))
  w.solids.push(Solid.box(-30, -35, 2.5, 2.5, 2.2, { base: ty, tag: 'shrine', surface: 'concrete' }))
}

function desert(w) {
  const rr = new RNG(41)
  const avoid = [[30, -20, 12], [-35, 30, 20]]
  const cac = MB.cactus
  for (const [x, z] of spots(w, 120, 42, { avoid })) {
    const s = rr.range(0.8, 1.5)
    const y = ground(w, x, z)
    const n = P(G(), x, y, z)
    w.add(n)
    n.add(P(Prim.cyl(0.28 * s, 4 * s, cac, 12), 0, 2 * s, 0))
    n.add(P(Prim.sphere(0.28 * s, cac, 12), 0, 4 * s, 0))
    for (const sd of [1, -1]) {
      if (!rr.chance(0.8)) continue
      const hy = rr.range(1.4, 2.6) * s
      n.add(P(Prim.cyl(0.18 * s, 0.8 * s, cac, 10), sd * 0.5 * s, hy, 0, 0, 0, Math.PI / 2))
      n.add(P(Prim.cyl(0.18 * s, 1.3 * s, cac, 10), sd * 0.9 * s, hy + 0.6 * s, 0))
      n.add(P(Prim.sphere(0.18 * s, cac, 10), sd * 0.9 * s, hy + 1.25 * s, 0))
    }
    w.solids.push(Solid.cyl(x, z, 0.35 * s, 4.2 * s, { base: y, tag: 'cactus', surface: 'wood' }))
  }
  spots(w, 42, 43, { r0: 30, avoid }).forEach(([x, z], i) => boulder(w, x, z, rr.range(1, 3), MB.redRock, i + 70))
  for (let k = 0; k < 7; k++) {
    const a = k / 7 * 2 * Math.PI
    palm(w, 30 + Math.cos(a) * rr.range(8, 11), -20 + Math.sin(a) * rr.range(8, 11), rr.range(0.9, 1.2), k + 44)
  }
  // the pyramid: climb it, glide off it
  stepped(w, -35, 30, 16, 30, 1.0, 1.85, MB.sandstone, 'pyramid')
}

function beach(w) {
  const rr = new RNG(51)
  for (const [x, z] of spots(w, 78, 52, { r0: 6, r1: 140 })) {
    if (z > -120 && z < 12 + Math.sin(x * 0.04) * 6) palm(w, x, z, rr.range(0.9, 1.3), Math.abs(Math.trunc(x * 13 + z)) + 1)
  }
  spots(w, 66, 53, { r0: 10, r1: 180, dry: false }).forEach(([x, z], i) => { if (z > 10) boulder(w, x, z, rr.range(0.6, 2.2), MB.rock, i + 80) })
  // pier out into the sea
  const px = -12
  const sz = 18 + Math.sin(px * 0.04) * 6 - 6
  w.add(P(meterBox(3, 0.2, 40, Mat.woodGrey, 1), px, 1.2, sz + 20))
  for (let k = 0; k < 11; k++) for (const sd of [1, -1]) w.add(P(cylNode(0.15, 8, Mat.woodGrey, 8), px + sd * 1.3, -2.8, sz + k * 4))
  w.solids.push(Solid.box(px, sz + 20, 3, 40, 1.3, { base: -8, tag: 'pier', surface: 'wood' }))
  // lifeguard tower, umbrellas, a sandcastle
  const lx = 16, lz = 12
  const ly = ground(w, lx, lz)
  const white = Coats.plain([0.9, 0.9, 0.9])
  for (const [ox, oz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) w.add(P(cylNode(0.08, 3, white, 8), lx + ox, ly + 1.5, lz + oz))
  w.add(P(meterBox(2.6, 0.15, 2.6, Mat.woodFresh, 1), lx, ly + 3, lz))
  w.add(P(meterBox(2.6, 1.6, 2.6, Coats.plain([0.9, 0.2, 0.15]), 1), lx, ly + 4, lz))
  w.solids.push(Solid.box(lx, lz, 2.8, 2.8, 4.8, { base: ly, tag: 'tower', surface: 'wood' }))
  for (let k = 0; k < 5; k++) {
    const x = -25 + k * 9 + rr.range(-2, 2), z = 6 + rr.range(-3, 3)
    const y = ground(w, x, z)
    w.add(P(cylNode(0.04, 2.2, white, 6), x, y + 1.1, z))
    w.add(P(Prim.cone(1.3, 0.05, 0.5, Coats.coat('bands', [[0.9, 0.2, 0.2], [0.2, 0.5, 0.9], [0.95, 0.8, 0.2]][k % 3], [0.95, 0.95, 0.95]), 16), x, y + 2.2, z))
    w.add(P(boxNode(0.9, 0.01, 1.8, Coats.plain([[0.2, 0.6, 0.9], [0.9, 0.4, 0.6]][k % 2])), x + 1, y + 0.01, z + 1, 0, rr.range(0, 3), 0))
  }
  const cx = 4, cz = 10, cy = ground(w, cx, cz)
  for (const [ox, oz] of [[-0.6, -0.6], [0.6, -0.6], [-0.6, 0.6], [0.6, 0.6]]) w.add(P(cylNode(0.25, 0.8, MB.sandstone, 10), cx + ox, cy + 0.4, cz + oz))
  w.add(P(meterBox(1.4, 0.5, 1.4, MB.sandstone), cx, cy + 0.25, cz))
}

function forest(w) {
  const rr = new RNG(61)
  for (const [x, z] of spots(w, 210, 62, { r0: 7, avoid: [[-20, 22, 13], [18, -14, 6]] })) {
    if (rr.chance(0.55)) pine(w, x, z, rr.range(1, 1.6))
    else oak(w, x, z, rr.range(1, 1.5), Math.abs(Math.trunc(x * 7 + z)) + 1)
  }
  const cap = Coats.coat('spots', [0.8, 0.1, 0.08], [0.95, 0.93, 0.88])
  const stem = Coats.plain([0.9, 0.88, 0.8])
  for (const [x, z] of spots(w, 120, 63, { r0: 4, r1: 120 })) {
    const y = ground(w, x, z), s = rr.range(0.1, 0.3)
    w.add(P(Prim.cyl(s * 0.3, s * 1.2, stem, 8), x, y + s * 0.6, z))
    w.add(S(P(Prim.sphere(s, cap, 12), x, y + s * 1.2, z), 1, 0.5, 1))
  }
  spots(w, 36, 64, { r0: 8, r1: 160 }).forEach(([x, z], i) => {
    const l = rr.range(3, 6), a = rr.range(0, 3)
    w.add(P(Prim.cyl(rr.range(0.3, 0.5), l, Mat.bark, 12), x, ground(w, x, z) + 0.35, z, 0, a, Math.PI / 2))
    if (i % 2 === 0) boulder(w, x + 3, z - 2, rr.range(0.6, 1.4), MB.rock, i + 90)
  })
  cabin(w, 18, -14, 0.4)
}

function mountains(w) {
  const rr = new RNG(71)
  for (const [x, z] of spots(w, 135, 72, { r0: 15, r1: 150, avoid: [[-10, -30, 16]] })) {
    const h = w.terrain(x, z)
    if (h < 22) pine(w, x, z, rr.range(0.9, 1.4), h > 10)
  }
  spots(w, 78, 73, { r0: 8, r1: 180 }).forEach(([x, z], i) => boulder(w, x, z, rr.range(0.7, 2.6), MB.rock, i + 100))
  cabin(w, 20, 16, -0.6)
}

function swamp(w) {
  const rr = new RNG(81)
  const moss = Coats.plain([0.35, 0.38, 0.25], 0.9)
  for (const [x, z] of spots(w, 135, 82, { r0: 8 })) {
    const y = ground(w, x, z)
    const s = rr.range(0.8, 1.4)
    const n = P(G(), x, y, z)
    w.add(n)
    n.add(limb(6 * s, 0.3 * s, 0.1 * s, MB.deadWood, { seg: 8, dir: [rr.range(-0.2, 0.2), 1, rr.range(-0.2, 0.2)] }))
    for (let k = 0; k < 4; k++) n.add(P(limb(2.2 * s, 0.1 * s, 0.03 * s, MB.deadWood, { seg: 6, dir: [Math.cos(k * 1.7), 0.7, Math.sin(k * 1.7)] }), 0, (2.5 + k * 0.8) * s, 0))
    for (let k = 0; k < 3; k++) n.add(P(Prim.cyl(0.04, 1.5 * s, moss, 4), Math.cos(k * 2) * 1.2 * s, 3.8 * s, Math.sin(k * 2) * 1.2 * s))
    w.solids.push(Solid.cyl(x, z, 0.35 * s, 6 * s, { base: y, tag: 'tree', surface: 'wood' }))
  }
  const pad = Coats.plain([0.18, 0.4, 0.12], 0.5)
  const bloom = Coats.plain([0.95, 0.7, 0.85])
  for (const [x, z] of spots(w, 480, 83, { r0: 3, r1: 100, dry: false })) {
    if (w.waterLevel(x, z) === null) continue
    const r = rr.range(0.2, 0.45)
    const p = P(Prim.cyl(r, 0.02, pad, 12), x, 0.01, z); p.castShadow = false
    w.add(p)
    if (rr.chance(0.15)) w.add(P(sphereNode(0.07, bloom, 8), x, 0.08, z))
  }
  cabin(w, 0, 0, 0.3, 1.6)
}

function park(w) {
  const rr = new RNG(91)
  for (const [x, z] of spots(w, 120, 92, { r0: 10, r1: 175, avoid: [[20, 14, 13], [0, 0, 17]] })) {
    const path = Math.min(Math.abs(x - Math.sin(z * 0.05) * 6), Math.abs(z + 20 + Math.sin(x * 0.04) * 5))
    if (path > 4) oak(w, x, z, rr.range(1, 1.5), Math.abs(Math.trunc(x * 5 + z)) + 1)
  }
  // fountain in the middle of the loop path
  const fy = ground(w, 0, 0)
  w.add(P(Prim.tube(3.6, 4, 0.7, Mat.concrete, 40), 0, fy + 0.35, 0))
  w.add(P(cylNode(3.6, 0.02, Mat.water, 40), 0, fy + 0.5, 0))
  w.add(P(cylNode(0.35, 2.2, Mat.concrete, 16), 0, fy + 1.1, 0))
  w.add(P(cylNode(1.4, 0.25, Mat.concrete, 24), 0, fy + 2.2, 0))
  w.add(P(cylNode(1.3, 0.02, Mat.water, 24), 0, fy + 2.33, 0))
  w.solids.push(Solid.cyl(0, 0, 4, 0.7, { base: fy, tag: 'fountain', surface: 'concrete' }))
  // benches and lamps around the loop
  const bench = Mat.woodFresh
  const lampM = pbr([1, 0.95, 0.8], { rough: 0.3, emissive: [1, 0.9, 0.6] })
  for (let k = 0; k < 10; k++) {
    const a = k / 10 * 2 * Math.PI
    const r = 16.5
    const x = Math.cos(a) * r, z = Math.sin(a) * r
    const y = ground(w, x, z)
    const b = P(G(), x, y, z, 0, -a - Math.PI / 2, 0)
    w.add(b)
    b.add(P(boxNode(1.8, 0.06, 0.5, bench), 0, 0.45, 0))
    b.add(P(boxNode(1.8, 0.4, 0.05, bench), 0, 0.75, -0.24))
    for (const sx of [-0.8, 0.8]) b.add(P(boxNode(0.06, 0.45, 0.5, Mat.black), sx, 0.22, 0))
    if (k % 2 === 0) {
      const lx = Math.cos(a + 0.3) * (r - 1.5), lz = Math.sin(a + 0.3) * (r - 1.5)
      w.add(P(cylNode(0.06, 3.5, Mat.black, 8), lx, y + 1.75, lz))
      w.add(P(sphereNode(0.2, lampM, 10), lx, y + 3.6, lz))
    }
  }
  // hedges and the skyline
  for (let k = 0; k < 50; k++) {
    const x = rr.range(-170, 170), z = rr.range(-170, 170)
    if (Math.hypot(x, z) < 20) continue
    w.add(P(meterBox(rr.range(3, 7), 1.2, 1, Mat.leaves, 0.5), x, ground(w, x, z) + 0.6, z, 0, rr.range(0, 3), 0))
  }
  const windows = Coats.coat('cells', [0.55, 0.6, 0.66], [0.2, 0.22, 0.26])
  for (let k = 0; k < 90; k++) {
    const a = k / 90 * 2 * Math.PI, r = rr.range(196, 230)
    const hgt = rr.range(20, 70)
    w.add(P(meterBox(rr.range(10, 18), hgt, rr.range(10, 18), windows, 0.08), Math.cos(a) * r, hgt / 2 - 1, Math.sin(a) * r, 0, -a, 0))
  }
}

export const MapBuilder = {
  get rock() { return MB.rock }, get redRock() { return MB.redRock }, get sandstone() { return MB.sandstone },
  get snow() { return MB.snow }, get ice() { return MB.ice }, get pineGreen() { return MB.pineGreen },
  get palmLeaf() { return MB.palmLeaf }, get deadWood() { return MB.deadWood }, get cactus() { return MB.cactus },
  get stoneBlock() { return MB.stoneBlock },

  build(w) {
    switch (w.mapIndex) {
      case 1: savanna(w); break
      case 2: arctic(w); break
      case 3: jungle(w); break
      case 4: desert(w); break
      case 5: beach(w); break
      case 6: forest(w); break
      case 7: mountains(w); break
      case 8: swamp(w); break
      case 9: park(w); break
      default: break
    }
  },
  spots, boulder, pine, oak, palm, stepped, cabin,
}
