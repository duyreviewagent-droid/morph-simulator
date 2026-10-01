// Parametric head, body and legs for the 97 generated animals. Ported from GenParts.swift.
// Also holds the Part base classes (Parts.swift) so parts.js and this file don't import each other.
import * as THREE from '../vendor/three.module.js'
import { V3, mix, smoothstep, clamp, RNG, Noise } from './util.js'
import { Ring, loft, mesh, loftNode, limb, sphereNode, boxNode, cylNode, coneNode, torusNode, at, rot, scl, group } from './loft.js'
import { Mat, Coats } from './mats.js'
import { Species, Zoo, def } from './species.js'

// ---- small array-vector helpers (ring centres are [x,y,z]) ----
const vs = (v, k) => [v[0] * k, v[1] * k, v[2] * k]
const va = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const vsub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const vlen2 = a => a[0] * a[0] + a[1] * a[1] + a[2] * a[2]
const vn = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l] }
const c3 = (v, k) => [v[0] * k, v[1] * k, v[2] * k]
const c3add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const UP = new THREE.Vector3(0, 1, 0)

export const wave = (phase, off) => Math.sin((phase + off) * 2 * Math.PI)
export const wavec = (phase, off) => Math.cos((phase + off) * 2 * Math.PI)
/// Euler angles in SceneKit order.
export function eul(o, x, y, z) { if (o.rotation.order !== 'YXZ') o.rotation.order = 'YXZ'; o.rotation.set(x, y, z) }
/// Points a node's +y axis along `dir` (simd_quatf(from: [0,1,0], to: dir)).
export function orient(o, dir) { o.quaternion.setFromUnitVectors(UP, new THREE.Vector3(dir[0], dir[1], dir[2]).normalize()) }

/// Frees GPU buffers of one-off (lofted) geometry under `o`. Shared primitive geometry (it has
/// `.parameters`) and materials are cached and left alone.
export function disposeTree(o) {
  o.traverse(m => { if (m.isMesh && m.geometry && !m.geometry.parameters) m.geometry.dispose() })
}

export function speciesFor(d) {
  let i = Zoo.defs.indexOf(d)
  if (i < 0) i = Math.max(0, Zoo.defs.findIndex(x => x.name === d.name))
  return Species.of(i)
}

// ---- Part base classes ----

export class Part {
  constructor(s) { this.node = group(); this.species = s }
  pose(p) {}
}

export class LegsPart extends Part {
  constructor(s) {
    super(s)
    this.footNodes = []
    this.attach = V3(0, 1, 0)
    this.radius = 0.3
    this.stride = 1.2          // metres per gait cycle
    this.footPhases = [0, 0.5]
    this.mass = 1
  }
  bob(p) { return 0 }
  pitch(p) { return 0 }
}

export class TorsoPart extends Part {
  constructor(s) {
    super(s)
    this.anchor = null
    this.neck = V3(0, 0.6, 0)
    this.neckRot = 0          // extra pitch for whatever head sits here
    this.canGrab = false
    this.hasWings = false
    this.flight = 0           // 0 none, 1 flap and glide, 2 hover
    this.carry = V3(0, 0.3, 0.4)
    this.mass = 1
    this.tilt = 0
  }
}

export class HeadPart extends Part {
  constructor(s) {
    super(s)
    this.anchor = null
    this.height = 0.35
    this.mouth = V3(0, 0.2, 0.1)
  }
}

// ---- builders ----

/// Adds fur shells to a lofted part when the animal is furry.
export function furry(n, d, scale = 1) {
  if (!Coats.isFurry(d.coat) || !n.isMesh || !n.material) return n
  const len = (d.coat === 'wool' ? 0.03 : d.coat === 'quills' ? 0.02 : 0.011) * Math.max(0.5, d.size) * scale
  Coats.furShells(n, n.material, len, d.coat === 'wool' ? 4 : 3)
  return n
}

/// A leg segment with muscle: wide and flattened at the top where it meets the body, tapering to the joint.
export function muscleLimb(len, top, mid, bottom, m, { depth = 1.3, dir = [0, -1, 0], bulgeAt = 0.3 } = {}) {
  const d = vn(dir)
  const rings = [Ring(vs(d, -top * 0.5), top * 0.55, top * 0.55 * depth),
    Ring(vs(d, len * 0.05), top, top * depth),
    Ring(vs(d, len * bulgeAt), mix(top, mid, 0.4), mix(top, mid, 0.4) * depth * 1.05),
    Ring(vs(d, len * 0.7), mid, mid * depth * 0.95),
    Ring(vs(d, len * 0.95), bottom * 1.1, bottom * 1.05),
    Ring(vs(d, len + bottom * 0.5), bottom * 0.6, bottom * 0.6)]
  return loftNode(rings, m, { seg: 16, ref: Math.abs(d[2]) > 0.9 ? [0, 1, 0] : [0, 0, 1], smooth: 3 })
}

export function chainLimb(parent, count, len, r0, r1, m, dir = [0, -1, 0]) {
  const nodes = []
  let p = parent
  const nd = vn(dir)
  for (let k = 0; k < count; k++) {
    const t0 = k / count, t1 = (k + 1) / count
    const n = group()
    if (k > 0) n.position.set(nd[0] * len, nd[1] * len, nd[2] * len)
    p.add(n)
    n.add(limb(len, mix(r0, r1, t0), mix(r0, r1, t1), m, { seg: 10, dir }))
    nodes.push(n)
    p = n
  }
  return nodes
}

/// Feet and hooves at the bottom of a leg (origin at the ankle).
export function buildFoot(parent, d, th, m) {
  const lm = Coats.limbMat(d)
  switch (d.foot) {
    case 'hoof':
      parent.add(at(coneNode(th * 1.15, th * 0.9, th * 1.4, Mat.hoof), 0, -th * 0.6, th * 0.1))
      break
    case 'pad':
      parent.add(at(cylNode(th * 1.25, th * 0.9, m, 18), 0, -th * 0.5, 0))
      for (let k = -1; k <= 1; k++) parent.add(at(sphereNode(th * 0.28, Mat.horn, 8), k * th * 0.6, -th * 0.75, th * 1.1))
      break
    case 'paw':
      parent.add(at(scl(sphereNode(th * 1.3, lm, 14), 1, 0.55, 1.3), 0, -th * 0.55, th * 0.45))
      for (let k = -1; k <= 1; k++) parent.add(at(rot(coneNode(th * 0.14, 0.001, th * 0.5, Mat.claw, 6), Math.PI / 2, 0, 0), k * th * 0.5, -th * 0.7, th * 1.9))
      break
    case 'foot':
      parent.add(loftNode([Ring([0, -th * 0.5, -th * 0.9], th * 0.5, th * 0.4), Ring([0, -th * 0.6, 0], th * 0.95, th * 0.55), Ring([0, -th * 0.75, th * 1.8], th * 1.0, th * 0.35),
        Ring([0, -th * 0.8, th * 2.4], th * 0.6, th * 0.2)], lm, { seg: 12, ref: [0, 1, 0], smooth: 3 }))
      break
    case 'webbed': case 'talon':
      for (const a of [-0.5, 0, 0.5]) {
        const toe = group(); eul(toe, 0, a, 0)
        parent.add(toe)
        toe.add(limb(th * 5, th * 0.5, th * 0.35, lm, { seg: 8, dir: [0, -0.15, 1] }))
        if (d.foot === 'talon') toe.add(at(rot(coneNode(th * 0.3, 0.001, th * 1.2, Mat.claw, 6), Math.PI / 2, 0, 0), 0, -th * 0.8, th * 5.3))
      }
      if (d.foot === 'webbed') parent.add(at(scl(sphereNode(th * 4, lm, 12), 1, 0.06, 0.8), 0, -th * 0.7, th * 2.6))
      break
  }
}

export function buildTail(parent, d, s, m, ground) {
  const root = group()
  parent.add(root)
  const lm = d.limbCol ? Coats.plain(d.limbCol) : m
  const dark = () => Coats.plain(c3add(c3(d.b, 0.8), c3(d.a, 0.2)), 0.8)
  switch (d.tail) {
    case 'none': return null
    case 'thin': root.add(limb(0.45 * s, 0.025 * s, 0.012 * s, m, { dir: [0, -0.7, -0.4] })); break
    case 'long': root.add(limb(0.8 * s, 0.03 * s, 0.01 * s, lm, { dir: [0, -0.35, -0.8] })); break
    case 'tuft':
      root.add(limb(0.55 * s, 0.025 * s, 0.015 * s, m, { dir: [0, -0.8, -0.35] }))
      root.add(at(scl(sphereNode(0.045 * s, dark(), 10), 0.9, 2.2, 0.9), 0, -0.56 * s, -0.24 * s))
      break
    case 'bushy': root.add(loftNode([Ring([0, 0, 0], 0.04 * s, 0.04 * s), Ring([0, -0.05 * s, -0.2 * s], 0.1 * s, 0.1 * s), Ring([0, -0.12 * s, -0.45 * s], 0.11 * s, 0.11 * s),
      Ring([0, -0.15 * s, -0.62 * s], 0.02 * s, 0.02 * s)], m, { seg: 14, ref: [0, 1, 0], smooth: 3 })); break
    case 'fluffy': root.add(sphereNode(0.08 * s, Coats.plain([0.93, 0.92, 0.9], 0.9), 12)); break
    case 'curly': root.add(at(rot(torusNode(0.05 * s, 0.012 * s, m), 0, 0, Math.PI / 2), 0, 0.02 * s, -0.05 * s)); break
    case 'stub': root.add(sphereNode(0.05 * s, m, 10)); break
    case 'reptile': {
      const len = Math.max(0.5, ground * 2.2)
      root.add(loftNode([Ring([0, 0, 0.05 * s], 0.1 * s, 0.1 * s), Ring([0, -ground * 0.5, -len * 0.35], 0.07 * s, 0.07 * s),
        Ring([0, -ground * 0.85, -len * 0.75], 0.035 * s, 0.03 * s), Ring([0, -ground * 0.92, -len], 0.008 * s, 0.008 * s)], m, { seg: 14, ref: [0, 1, 0], smooth: 3 }))
      break
    }
    case 'horse': root.add(loftNode([Ring([0, 0, 0], 0.05 * s, 0.05 * s), Ring([0, -0.25 * s, -0.12 * s], 0.07 * s, 0.05 * s), Ring([0, -0.6 * s, -0.12 * s], 0.06 * s, 0.04 * s),
      Ring([0, -0.75 * s, -0.1 * s], 0.01 * s, 0.01 * s)], Mat.brownHair, { seg: 12, ref: [0, 0, 1], smooth: 3 })); break
    case 'flat': root.add(at(scl(sphereNode(0.16 * s, Coats.coat('scales', [0.18, 0.15, 0.12], [0.1, 0.08, 0.07]), 16), 0.8, 0.12, 1.4), 0, -0.05 * s, -0.22 * s)); break
    case 'stinger': root.add(at(rot(coneNode(0.02 * s, 0.001, 0.08 * s, Mat.black, 8), -Math.PI / 2, 0, 0), 0, 0, -0.04 * s)); break
    case 'curl': root.add(at(rot(torusNode(0.09 * s, 0.025 * s, m), 0, 0, Math.PI / 2), 0, -0.08 * s, -0.12 * s)); break
    case 'fan': return null
  }
  return root
}

// ---- Legs ----

export class GenLegs extends LegsPart {
  constructor(d) {
    super(speciesFor(d))
    this.d = d
    this.s = d.size
    this.ups = []; this.los = []; this.feet = []
    this.offs = []; this.hind = []; this.sides = []
    this.tail = null
    this.base = group()
    this.chain = []; this.chainR = []
    this.tentacles = []
    this.tailPiv = group()
    this.liftY = 0
    this.R = 0.3; this.L = 0.7
    this.node.add(this.base)
    const m = Coats.coat(d)
    const lm = Coats.limbMat(d)
    const s = this.s
    this.mass = Math.max(0.15, 2.2 * s * s * s * d.girth)
    switch (d.plan) {
      case 'quad': this.buildQuad(m); break
      case 'sprawl': this.buildSprawl(m); break
      case 'bird': this.buildBird(m, lm); break
      case 'biped': this.buildBiped(m, lm); break
      case 'hopper': this.buildHopper(m, lm); break
      case 'slither': this.buildSlither(m); break
      case 'fish': this.buildFish(m); break
      case 'insect': case 'spider': this.buildBug(m, lm); break
      case 'tentacle': this.buildTentacles(m); break
    }
  }

  leg(p, up, lo, th, m, off, isHind, side, { upDir = [0, -1, 0], loDir = [0, -1, 0], foot = true } = {}) {
    const d = this.d
    const u = group(); u.position.set(p[0], p[1], p[2])
    this.base.add(u)
    const chunky = d.plan === 'quad' || d.plan === 'sprawl'
    if (chunky) {
      u.add(furry(muscleLimb(up, th * (isHind ? 1.9 : 1.6), th * 1.0, th * 0.72, m, { depth: isHind ? 1.55 : 1.3, dir: upDir, bulgeAt: isHind ? 0.25 : 0.3 }), d))
    } else {
      u.add(limb(up, th * (isHind ? 1.25 : 1.05), th * 0.8, m, { depth: isHind ? 1.3 : 1.1, bulge: 0.2, seg: 12, dir: upDir }))
    }
    const l = group(); const ud = vs(vn(upDir), up); l.position.set(ud[0], ud[1], ud[2])
    u.add(l)
    if (chunky) {
      l.add(furry(muscleLimb(lo, th * 0.75, th * 0.55, th * 0.5, m, { depth: 1.15, dir: loDir, bulgeAt: 0.12 }), d, 0.6))
    } else {
      l.add(limb(lo, th * 0.7, th * 0.55, m, { seg: 10, dir: loDir }))
    }
    const f = group(); const ld = vs(vn(loDir), lo); f.position.set(ld[0], ld[1], ld[2])
    l.add(f)
    if (foot) buildFoot(f, d, th * 0.75, m)
    this.ups.push(u); this.los.push(l); this.feet.push(f); this.offs.push(off); this.hind.push(isHind); this.sides.push(side)
    this.footNodes.push(f)
  }

  buildQuad(m) {
    const d = this.d, s = this.s
    this.R = 0.3 * s * d.girth; this.L = 0.72 * s * d.bodyLen
    const legH = 0.82 * s * d.legLen
    const R = this.R, L = this.L
    const by = legH + R * 0.5
    const slim = d.foot === 'paw' && d.girth < 1.15 ? 0.82 : 0.97
    const rings = [Ring([0, by + 0.08 * R, -L - 0.1 * s], 0.25 * R, 0.25 * R), Ring([0, by + 0.06 * R, -L * 0.92], 0.78 * R, 0.8 * R, 2.2),
      Ring([0, by + 0.02 * R, -L * 0.55], 0.95 * R, 0.95 * R), Ring([0, by - 0.02 * R, -L * 0.1], R * slim, R * slim * 0.98),
      Ring([0, by - 0.08 * R, L * 0.35], 1.02 * R, 1.12 * R), Ring([0, by - 0.02 * R, L * 0.72], R * 0.95, R * 1.08),
      Ring([0, by + 0.12 * R, L], 0.72 * R, 0.8 * R), Ring([0, by + 0.2 * R, L + 0.1 * s], 0.3 * R, 0.3 * R)]
    this.base.add(furry(loftNode(rings, m, {
      seg: 28, ref: [0, 1, 0], smooth: 4, vScale: 0.8, displace: (p, n) => {
        // shoulder blades and haunches under the skin
        let dd = 0
        for (const sx of [1, -1]) {
          const sh = vsub(p, [sx * R * 0.55, by + R * 0.5, L * 0.62])
          dd += Math.exp(-vlen2(sh) / (R * R * 0.12)) * R * 0.1
          const hp = vsub(p, [sx * R * 0.6, by + R * 0.35, -L * 0.62])
          dd += Math.exp(-vlen2(hp) / (R * R * 0.15)) * R * 0.12
        }
        dd += Math.exp(-p[0] * p[0] / (R * R * 0.02)) * Math.max(0, n[1]) * R * 0.03
        return dd
      },
    }), d))
    const th = 0.085 * s * d.legThick * Math.sqrt(d.girth)
    const hipY = by - R * 0.35
    const up = hipY * 0.5, lo = hipY * 0.5 - th * 0.9
    const wo = [0, 0.5, 0.25, 0.75]
    const spots = [[R * 0.55, -L * 0.7], [-R * 0.55, -L * 0.7], [R * 0.55, L * 0.72], [-R * 0.55, L * 0.72]]
    spots.forEach(([x, z], k) => this.leg([x, hipY, z], up, lo, th, m, wo[k], k < 2, x > 0 ? 1 : -1))
    if (d.hump) this.base.add(at(scl(sphereNode(R * 0.6, m, 16), 1, 0.8, 1.3), 0, by + R * 0.75, -0.1 * L))
    if (d.shell) {
      const sh = Coats.coat('shell', d.a, d.b)
      this.base.add(at(scl(sphereNode(R * 1.18, sh, 24), 1, 0.8, L / R * 0.95), 0, by + 0.1 * R, 0))
    }
    if (d.spikes) this.addSpikes([0, by, 0], R, L)
    this.tail = buildTail(this.base, d, s, m, by)
    if (this.tail) this.tail.position.set(0, by + R * 0.45, -L - 0.02 * s)
    this.attach = V3(0, by + R * 0.6, L * 0.8)
    this.radius = clamp(L * 0.72, 0.3, 1.05)
    this.stride = legH * 2.2 + 0.3 * s
    this.footPhases = [0, 0.25, 0.5, 0.75]
  }

  addSpikes(center, rx, rz) {
    const s = this.s
    const rr = new RNG(7)
    const q = Coats.plain(this.d.b, 0.6)
    for (let i = 0; i < 60; i++) {
      const a = rr.range(-1.2, 1.2), zt = rr.range(-0.95, 0.9)
      const dir = [Math.sin(a), Math.cos(a), 0]
      const p = va(center, [dir[0] * rx * 1.02, dir[1] * rx * 0.95, zt * rz])
      const c = coneNode(0.012 * s, 0.001, 0.12 * s, q, 5)
      c.position.set(p[0] + dir[0] * 0.04 * s, p[1] + dir[1] * 0.04 * s, p[2])
      orient(c, va(dir, [0, 0, -0.8]))
      this.base.add(c)
    }
  }

  buildSprawl(m) {
    const d = this.d, s = this.s
    this.R = 0.2 * s * d.girth; this.L = 0.5 * s * d.bodyLen
    const R = this.R, L = this.L
    const legH = 0.2 * s * d.legLen
    const by = legH + R * 0.55
    this.base.add(furry(loftNode([Ring([0, by, -L - 0.05 * s], 0.3 * R, 0.25 * R), Ring([0, by, -L * 0.6], R * 0.85, R * 0.7), Ring([0, by, 0], R, R * 0.75),
      Ring([0, by, L * 0.6], R * 0.9, R * 0.7), Ring([0, by + 0.05 * R, L + 0.05 * s], R * 0.4, R * 0.35)], m, { seg: 20, ref: [0, 1, 0], smooth: 3 }), d))
    const th = 0.05 * s * d.legThick * Math.sqrt(d.girth)
    const wo = [0, 0.5, 0.5, 0]
    const spots = [[R * 0.8, -L * 0.6], [-R * 0.8, -L * 0.6], [R * 0.8, L * 0.6], [-R * 0.8, L * 0.6]]
    spots.forEach(([x, z], k) => {
      const sd = x > 0 ? 1 : -1
      this.leg([x, by - R * 0.2, z], R * 1.1 + 0.05 * s, by - R * 0.2, th, m, wo[k], k < 2, sd, { upDir: [sd, -0.25, 0], loDir: [sd * 0.15, -1, 0] })
    })
    if (d.shell) {
      const sh = Coats.coat('shell', d.a, d.b)
      this.base.add(at(scl(sphereNode(R * 1.65, sh, 28), 1.0, 0.62, L / R * 0.72), 0, by + 0.2 * R, 0))
      this.base.add(at(scl(cylNode(R * 1.6, 0.03 * s, sh, 28), 1, 1, L / R * 0.72), 0, by + 0.05 * R, 0))
    }
    if (d.dorsal) {
      const dm = Coats.plain(d.b)
      for (let k = 0; k < 10; k++) this.base.add(at(coneNode(0.02 * s, 0.001, 0.07 * s, dm, 5), 0, by + R * 0.75 + 0.03 * s, -L + k * L * 0.2))
    }
    this.tailPiv.position.set(0, by, -L)
    this.base.add(this.tailPiv)
    this.tail = buildTail(this.tailPiv, d, s, m, by)
    this.attach = V3(0, by + R * 0.55, L * 0.8)
    this.radius = clamp(L * 0.8, 0.3, 1.0)
    this.stride = 0.6 * s + legH
    this.footPhases = [0, 0.5]
  }

  buildBird(m, lm) {
    const d = this.d, s = this.s
    const br = 0.24 * s * d.girth
    const thigh = 0.2 * s * Math.sqrt(d.legLen), shank = 0.3 * s * d.legLen
    const hipY = thigh * Math.cos(0.5) + shank * Math.cos(0.3) + 0.03 * s
    this.base.add(loftNode([Ring([0, hipY - br * 0.7, -0.1 * s], 0.02, 0.02), Ring([0, hipY - br * 0.5, -0.08 * s], br * 0.6, br * 0.6), Ring([0, hipY, -0.05 * s], br, br),
      Ring([0, hipY + br * 0.5, -0.03 * s], br * 1.02, br), Ring([0, hipY + br * 0.95, -0.02 * s], br * 0.85, br * 0.82), Ring([0, hipY + br * 1.2, -0.02 * s], br * 0.6, br * 0.58)],
    m, { seg: 22, smooth: 3 }))
    const th = 0.024 * s * d.legThick * (d.legLen > 1.5 ? 1.6 : 1)
    ;[1, -1].forEach((sd, k) => {
      const u = group(); u.position.set(0.1 * s * d.girth * sd, hipY, 0)
      this.base.add(u)
      u.add(limb(thigh, 0.07 * s * d.girth, 0.035 * s, m, { bulge: 0.25, seg: 12 }))
      const l = group(); l.position.set(0, -thigh, 0)
      u.add(l)
      l.add(limb(shank, th, th * 0.8, lm, { seg: 10 }))
      const f = group(); f.position.set(0, -shank, 0)
      l.add(f)
      buildFoot(f, d, th * 0.6 * Math.max(1, 1 / d.legLen), m)
      this.ups.push(u); this.los.push(l); this.feet.push(f); this.offs.push(k * 0.5); this.hind.push(false); this.sides.push(sd)
      this.footNodes.push(f)
    })
    this.attach = V3(0, hipY + br * 1.05, -0.02 * s)
    this.radius = Math.max(0.25, br * 1.15)
    this.stride = (thigh + shank) * 1.4
  }

  buildBiped(m, lm) {
    const d = this.d, s = this.s
    const th = 0.075 * s * d.legThick * Math.sqrt(d.girth)
    const thigh = 0.36 * s * d.legLen, shin = 0.34 * s * d.legLen
    const hipY = thigh + shin + th * 0.9
    const w = 0.16 * s * d.girth
    this.base.add(furry(loftNode([Ring([0, hipY - 0.08 * s, -0.01], w * 0.9, w * 0.62), Ring([0, hipY, -0.015], w * 1.1, w * 0.72), Ring([0, hipY + 0.1 * s, 0], w * 1.05, w * 0.7),
      Ring([0, hipY + 0.14 * s, 0], w * 0.6, w * 0.45)], m, { seg: 20, smooth: 3 }), d))
    ;[1, -1].forEach((sd, k) => {
      const u = group(); u.position.set(w * 0.55 * sd, hipY, 0)
      this.base.add(u)
      u.add(furry(muscleLimb(thigh, th * 1.35, th * 1.0, th * 0.75, m, { depth: 1.1 }), d))
      const l = group(); l.position.set(0, -thigh, 0)
      u.add(l)
      l.add(limb(shin, th * 0.8, th * 0.6, m, { seg: 10 }))
      const f = group(); f.position.set(0, -shin, 0)
      l.add(f)
      buildFoot(f, d, th * 0.8, m)
      this.ups.push(u); this.los.push(l); this.feet.push(f); this.offs.push(k * 0.5); this.hind.push(false); this.sides.push(sd)
      this.footNodes.push(f)
    })
    this.tail = buildTail(this.base, d, s, m, hipY)
    if (this.tail) this.tail.position.set(0, hipY, -w * 0.6)
    this.attach = V3(0, hipY + 0.1 * s, 0)
    this.radius = Math.max(0.25, w * 1.6)
    this.stride = (thigh + shin) * 1.5
  }

  buildHopper(m, lm) {
    const d = this.d, s = this.s
    const th = 0.07 * s * d.legThick
    const thigh = 0.3 * s * d.legLen, shin = 0.34 * s * d.legLen, footL = 0.3 * s * d.legLen
    const hipY = thigh * Math.cos(1.0) + shin * Math.cos(0.9) + th * 0.5
    const w = 0.17 * s * d.girth
    this.base.add(loftNode([Ring([0, hipY - 0.1 * s, -0.08 * s], w * 0.5, w * 0.5), Ring([0, hipY, -0.06 * s], w * 1.15, w * 1.1), Ring([0, hipY + 0.12 * s, -0.02 * s], w * 1.05, w),
      Ring([0, hipY + 0.2 * s, 0], w * 0.6, w * 0.55)], m, { seg: 20, smooth: 3 }))
    for (const sd of [1, -1]) {
      const u = group(); u.position.set(w * 0.8 * sd, hipY, 0)
      this.base.add(u)
      u.add(at(scl(sphereNode(w * 0.7, m, 14), 0.8, 1, 1.2), 0, -w * 0.2, 0))
      u.add(limb(thigh, th * 1.3, th, m, { seg: 10 }))
      const l = group(); l.position.set(0, -thigh, 0)
      u.add(l)
      l.add(limb(shin, th * 0.8, th * 0.55, m, { seg: 10 }))
      const f = group(); f.position.set(0, -shin, 0)
      l.add(f)
      f.add(limb(footL, th * 0.6, th * 0.45, d.foot === 'webbed' ? lm : m, { seg: 8, dir: [0, -0.1, 1] }))
      if (d.foot === 'webbed') f.add(at(scl(sphereNode(footL * 0.35, lm, 10), 1.2, 0.08, 1), 0, -0.02 * s, footL * 0.9))
      this.ups.push(u); this.los.push(l); this.feet.push(f); this.offs.push(0); this.hind.push(false); this.sides.push(sd)
      this.footNodes.push(f)
    }
    this.tail = buildTail(this.base, d, s, m, hipY)
    if (this.tail) this.tail.position.set(0, hipY, -w)
    this.attach = V3(0, hipY + 0.16 * s, 0)
    this.radius = Math.max(0.25, w * 1.5)
    this.stride = footL * 3 + 0.3 * s
  }

  buildSlither(m) {
    const d = this.d, s = this.s
    const r = 0.085 * s * d.girth
    this.liftY = (d.hood ? 0.5 : 0.22) * s
    const n = 26
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1)
      const rr = r * (1 - t * 0.75) * (t < 0.05 ? 0.85 : 1)
      const sp = sphereNode(rr, m, 14)
      this.base.add(sp)
      this.chain.push(sp); this.chainR.push(rr)
    }
    if (d.shell) {
      const sh = Coats.coat('shell', d.b, c3(d.b, 0.6))
      const shell = group(); shell.position.set(0, r * 2.2, -0.2 * s)
      this.base.add(shell)
      shell.add(scl(sphereNode(0.16 * s, sh, 20), 0.7, 1, 1))
      shell.add(at(scl(rot(torusNode(0.08 * s, 0.05 * s, sh), 0, 0, Math.PI / 2), 1.2, 1, 1), 0.02 * s, 0, 0))
    }
    this.attach = V3(0, this.liftY + r, 0.12 * s)
    this.radius = 0.3
    this.stride = 0.5 * s
    this.mass = Math.max(0.2, s * s * 1.2)
    this.R = r
  }

  buildFish(m) {
    const d = this.d, s = this.s
    const R = this.R = 0.2 * s * d.girth
    this.base.add(loftNode([Ring([0, R, 0.2 * s], R * 0.6, R * 0.7), Ring([0, R, 0], R, R), Ring([0, R * 0.95, -0.3 * s], R * 0.75, R * 0.85)], m, { seg: 20, ref: [0, 1, 0], smooth: 3 }))
    this.tailPiv.position.set(0, R * 0.95, -0.3 * s)
    this.base.add(this.tailPiv)
    const tl = 0.5 * s * d.bodyLen
    this.tailPiv.add(loftNode([Ring([0, 0, 0.02 * s], R * 0.75, R * 0.85), Ring([0, 0, -tl * 0.5], R * 0.45, R * 0.55), Ring([0, 0, -tl], R * 0.12, R * 0.15)], m, { seg: 18, ref: [0, 1, 0], smooth: 3 }))
    const fin = Coats.plain(c3add(c3(d.a, 0.8), c3(d.b, 0.2)), 0.4)
    if (d.tail === 'flat') {
      for (const sd of [1, -1]) this.tailPiv.add(rot(at(scl(sphereNode(0.2 * s, fin, 12), 1, 0.12, 0.45), sd * 0.15 * s, 0, -tl - 0.05 * s), 0, sd * 0.4, 0))
    } else {
      for (const sd of [1, -1]) this.tailPiv.add(rot(at(scl(sphereNode(0.2 * s, fin, 12), 0.12, 1, 0.45), 0, sd * 0.13 * s, -tl - 0.07 * s), sd * 0.5, 0, 0))
    }
    this.attach = V3(0, R * 1.8, 0.12 * s)
    this.radius = Math.max(0.3, R * 1.3)
    this.stride = 0.7 * s
  }

  buildBug(m, lm) {
    const d = this.d, s = this.s
    const spider = d.plan === 'spider'
    const crab = d.arms === 'pincer' && spider
    const h = (spider ? 0.2 : 0.24) * s * d.legLen
    const chit = d.coat === 'bands' || d.coat === 'spots' ? Coats.coat('chitin', d.b, d.b) : m
    this.base.add(at(scl(sphereNode(0.1 * s, chit, 16), crab ? 2.2 : 1, crab ? 0.7 : 1, crab ? 1.4 : 1.2), 0, h, 0))
    if (!crab) {
      const abL = (spider ? 0.2 : 0.22) * s * d.bodyLen
      if (d.name === 'Lobster') {
        for (let k = 0; k < 5; k++) this.base.add(at(scl(sphereNode(0.09 * s * (1 - k * 0.12), m, 14), 1.2, 0.8, 0.9), 0, h, -0.14 * s - k * 0.1 * s))
        this.base.add(at(scl(sphereNode(0.12 * s, m, 12), 1.3, 0.2, 0.8), 0, h - 0.02 * s, -0.68 * s))
      } else {
        this.base.add(at(scl(sphereNode(abL, d.bugWings === 'elytra' ? chit : m, 20), 0.8 * d.girth, 0.75 * d.girth, 1), 0, h + 0.02 * s, -abL - 0.06 * s))
        if (d.tail === 'stinger') this.base.add(at(rot(coneNode(0.02 * s, 0.001, 0.08 * s, Mat.black, 8), -Math.PI / 2, 0, 0), 0, h, -abL * 2 - 0.1 * s))
      }
    }
    const count = spider ? 4 : 3
    for (let k = 0; k < count; k++) {
      for (const sd of [1, -1]) {
        const z = (k - (count - 1) / 2) * 0.07 * s
        const off = ((k + (sd > 0 ? 0 : 1)) % 2 === 0) ? 0 : 0.5
        const spread = spider ? 0.75 : 0.5
        this.leg([sd * 0.07 * s * (crab ? 1.8 : 1), h, z], 0.16 * s * (spider ? 1.3 : 1), h * 1.25, 0.016 * s, lm, off, false, sd,
          { upDir: [sd, spread, z * 3], loDir: [sd * 0.35, -1, z * 2], foot: false })
      }
    }
    this.attach = V3(0, h + 0.08 * s, 0.06 * s)
    this.radius = Math.max(0.25, 0.25 * s * (spider ? 1.6 : 1))
    this.stride = 0.35 * s
    this.footPhases = [0, 0.5]
    this.mass = Math.max(0.1, s * s * 0.5)
  }

  buildTentacles(m) {
    const d = this.d, s = this.s
    const h = 0.3 * s
    const jelly = d.name === 'Jellyfish'
    const tm = jelly ? Coats.membrane(d.a, 0.55) : m
    this.base.add(at(scl(sphereNode(0.16 * s, tm, 20), 1.1, 0.55, 1.1), 0, h, 0))
    for (let k = 0; k < 8; k++) {
      const a = k / 8 * 2 * Math.PI
      const root = group(); root.position.set(Math.cos(a) * 0.1 * s, h - 0.04 * s, Math.sin(a) * 0.1 * s)
      eul(root, 0, -a + Math.PI / 2, 0)
      this.base.add(root)
      this.tentacles.push(chainLimb(root, 5, (jelly ? 0.12 : 0.1) * s, (jelly ? 0.012 : 0.045) * s, 0.008 * s, tm, [0, -1, 0]))
    }
    this.attach = V3(0, h + 0.06 * s, 0)
    this.radius = Math.max(0.3, 0.3 * s)
    this.stride = 0.4 * s
    this.mass = Math.max(0.2, s * s)
  }

  // ---- animation ----

  bob(p) {
    const s = this.s
    switch (this.d.plan) {
      case 'hopper': case 'fish': return Math.abs(Math.sin(p.phase * Math.PI * 2)) * 0.18 * s * p.gait * (1 - p.air)
      case 'quad': return mix(-Math.abs(wave(p.phase * 2, 0)) * 0.02, wave(p.phase, 0.3) * 0.06 * s, p.run) * p.gait * (1 - p.air)
      case 'tentacle': return Math.sin(p.t * 2) * 0.02 * s + (this.d.name === 'Jellyfish' ? 0.15 * s : 0)
      default: return -Math.abs(wave(p.phase, 0)) * 0.025 * s * p.gait * (1 - p.air) - p.lay * 0.2 * s
    }
  }
  pitch(p) { return this.d.plan === 'quad' ? (wave(p.phase, 0.1) * 0.06 * p.run * p.gait + p.kick * 0.25) : 0 }

  pose(p) {
    const g = p.gait, d = this.d, s = this.s
    const { ups, los, feet, offs, hind, sides } = this
    switch (d.plan) {
      case 'quad': {
        const gal = [0, 0.1, 0.45, 0.58]
        for (let k = 0; k < ups.length; k++) {
          const off = mix(offs[k], gal[k], p.run)
          const sw = wave(p.phase, off), c = wavec(p.phase, off)
          let u = -sw * (0.3 + 0.35 * p.run) * g
          let l = Math.max(0, c) * (0.5 + 0.7 * p.run) * g
          if (hind[k]) { u += 0.06; l = -l * 0.9 - 0.08 }
          u = mix(u, hind[k] ? 0.5 : -0.5, p.air * 0.7); l = mix(l, hind[k] ? -0.8 : 1.0, p.air * 0.7)
          if (hind[k]) u = mix(u, 1.2, p.kick)
          u = mix(u, hind[k] ? 0.9 : -0.9, p.lay); l = mix(l, hind[k] ? -2.1 : 2.2, p.lay)
          ups[k].rotation.set(u, 0, 0); los[k].rotation.set(l, 0, 0); feet[k].rotation.set(-(u + l) * 0.6, 0, 0)
        }
        const sw = Math.sin(p.t * 1.7) * 0.35
        if (this.tail) eul(this.tail, p.run * 0.8 * g + p.kick * 0.5, 0, sw)
        break
      }
      case 'sprawl':
        for (let k = 0; k < ups.length; k++) {
          const sw = wave(p.phase, offs[k])
          const c = wavec(p.phase, offs[k])
          ups[k].rotation.set(0, sw * 0.6 * g, sides[k] * Math.max(0, c) * 0.5 * g)
          los[k].rotation.set(0, 0, -sides[k] * Math.max(0, c) * 0.4 * g)
        }
        this.base.rotation.set(0, wave(p.phase, 0.25) * 0.14 * g, 0)
        this.tailPiv.rotation.set(0, -wave(p.phase, 0.1) * 0.35 * g + Math.sin(p.t * 1.1) * 0.1, 0)
        break
      case 'bird':
        for (let k = 0; k < ups.length; k++) {
          const sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
          let th = -0.5 - sw * (0.38 + 0.3 * p.run) * g
          let hk = 0.8 + Math.max(0, c) * (0.6 + 0.6 * p.run) * g
          th = mix(th, -1.0, p.air); hk = mix(hk, 1.7, p.air)
          th = mix(th, -1.25, p.lay); hk = mix(hk, 2.1, p.lay)
          ups[k].rotation.set(th, 0, 0); los[k].rotation.set(hk, 0, 0); feet[k].rotation.set(-(th + hk), 0, 0)
        }
        break
      case 'biped':
        for (let k = 0; k < ups.length; k++) {
          const sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
          let hip = -sw * (0.32 + 0.38 * p.run) * g
          let knee = (0.08 + (0.35 + 1.0 * p.run) * Math.max(0, c)) * g + 0.05
          hip = mix(hip, k === 0 ? -0.7 : -0.25, p.air); knee = mix(knee, k === 0 ? 1.1 : 0.6, p.air)
          hip = mix(hip, -1.1, p.lay); knee = mix(knee, 1.9, p.lay)
          const cs = wave(p.phase * 0.7, offs[k])
          hip = mix(hip, -0.7 - cs * 0.5, p.climb); knee = mix(knee, 1.0 + cs * 0.4, p.climb)
          ups[k].rotation.set(hip, 0, 0); los[k].rotation.set(knee, 0, 0); feet[k].rotation.set(-(hip + knee) * 0.4, 0, 0)
        }
        if (this.tail) eul(this.tail, -0.4, Math.sin(p.t * 1.3) * 0.3, 0)
        break
      case 'hopper': {
        const hop = Math.max(0, Math.sin(p.phase * Math.PI * 2)) * g
        const fold = Math.max(hop, p.air)
        for (let k = 0; k < ups.length; k++) {
          const th = mix(-1.0, -0.2, fold * 0.8)
          const kn = mix(1.9, 0.6, fold * 0.8)
          ups[k].rotation.set(th, 0, 0); los[k].rotation.set(kn, 0, 0); feet[k].rotation.set(-(th + kn), 0, 0)
        }
        if (this.tail) eul(this.tail, -0.2 + fold * 0.3, 0, 0)
        break
      }
      case 'slither': {
        const n = this.chain.length
        const len = 1.6 * s * d.bodyLen
        for (let i = 0; i < n; i++) {
          const t = i / (n - 1)
          const z = 0.12 * s - t * len
          const rise = this.liftY * (1 - smoothstep(0, 0.22, t))
          const amp = (0.05 + 0.12 * t) * s * (0.3 + g)
          const x = Math.sin(p.phase * 2 * Math.PI * 1.0 - t * 7) * amp
          this.chain[i].position.set(x, this.chainR[i] + rise, z)
        }
        break
      }
      case 'fish':
        this.tailPiv.rotation.set(0, Math.sin(p.phase * 2 * Math.PI) * 0.45 * (0.3 + g) + Math.sin(p.t * 3) * 0.08, 0)
        this.base.rotation.set(0, 0, Math.sin(p.phase * 2 * Math.PI) * 0.1 * g)
        break
      case 'insect': case 'spider':
        for (let k = 0; k < ups.length; k++) {
          const sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
          ups[k].rotation.set(0, sw * 0.4 * g, sides[k] * Math.max(0, c) * 0.35 * g)
          los[k].rotation.set(0, 0, 0)
        }
        break
      case 'tentacle':
        this.tentacles.forEach((segs, k) => {
          segs.forEach((n, j) => {
            const wv = Math.sin(p.t * 2.5 + k * 0.8 + j * 0.7) * 0.25
            const walk = Math.sin(p.phase * 2 * Math.PI + k * Math.PI / 4) * 0.3 * g
            n.rotation.set(j === 0 ? -1.0 + walk : 0.35 + wv, 0, 0)
          })
        })
        break
    }
  }
}

// ---- Bodies ----

export class GenTorso extends TorsoPart {
  constructor(d, horizontal) {
    super(speciesFor(d))
    this.d = d
    this.horizontal = horizontal
    this.s = d.size
    this.shoulders = []; this.elbows = []; this.hands = []
    this.tentArms = []
    this.wings = []; this.bugW = []
    this.pincers = []
    this.tailFan = group()
    this.body = group()
    this.node.add(this.body)
    this.anchor = this.body
    const m = Coats.coat(d)
    const s = this.s
    this.mass = Math.max(0.15, 1.8 * s * s * s * d.girth)
    if (horizontal) this.buildHorizontal(m); else this.buildUpright(m)
    if (d.bugWings !== 'none') { this.buildBugWings(); this.flight = d.bugWings === 'elytra' ? 1 : 2 }
    if (d.arms === 'wing' || d.arms === 'batWing') this.flight = Math.max(this.flight, 1)
    this.hasWings = this.flight > 0
    this.canGrab = d.arms === 'hands' && !horizontal
  }

  buildUpright(m) {
    const d = this.d, s = this.s
    const bird = d.plan === 'bird'
    const H = (bird ? 0.56 : 0.54) * s
    const w = (bird ? 0.25 : 0.2) * s * d.girth, dd = (bird ? 0.25 : 0.14) * s * d.girth
    const fz = bird ? 0.05 * s : 0.01 * s
    this.body.add(furry(loftNode([Ring([0, -0.08 * s, 0], w * 0.85, dd * 0.85), Ring([0, H * 0.12, 0], w * 0.97, dd), Ring([0, H * 0.38, fz], w * 1.04, dd * 1.06),
      Ring([0, H * 0.64, fz * 0.8], w * 0.95, dd * 0.92), Ring([0, H * 0.84, fz * 0.5], w * 0.72, dd * 0.7), Ring([0, H * 0.97, fz * 0.3], w * 0.38, dd * 0.4),
      Ring([0, H * 1.03, fz * 0.3], w * 0.3, dd * 0.32)], m, { seg: 24, smooth: 4, vScale: 0.8 }), d))
    this.neck = V3(0, H * 0.99, fz * 0.3)
    this.carry = V3(0, H * 0.5, dd + 0.25)
    // back decorations
    if (d.hump) this.body.add(at(scl(sphereNode(w * 0.7, m, 16), 1, 0.9, 0.8), 0, H * 0.6, -dd * 0.8))
    if (d.shell) {
      const sh = Coats.coat('shell', d.a, d.b)
      this.body.add(at(scl(sphereNode(w * 1.1, sh, 22), 1, 1.2, 0.55), 0, H * 0.45, -dd * 0.55))
    }
    if (d.dorsal) this.body.add(at(rot(scl(coneNode(0.12 * s, 0.01, 0.3 * s, m, 12), 0.2, 1, 1), -0.6, 0, 0), 0, H * 0.55, -dd - 0.05 * s))
    if (d.spikes) this.addBackSpikes(H, w, dd)
    if (bird) this.buildBirdTail(dd)
    this.buildArms(m, [w * 0.95, H * 0.8, 0], H)
  }

  buildHorizontal(m) {
    const d = this.d, s = this.s
    switch (d.plan) {
      case 'fish': {
        const R = 0.2 * s * d.girth
        // attach is above the fish body: continue the body forward to the head
        this.body.add(loftNode([Ring([0, -R * 0.85, -0.1 * s], R * 0.62, R * 0.72), Ring([0, -R * 0.85, 0.1 * s], R * 0.55, R * 0.62), Ring([0, -R * 0.9, 0.22 * s], R * 0.3, R * 0.35)],
          m, { seg: 18, ref: [0, 1, 0], smooth: 3 }))
        this.neck = V3(0, -R * 0.9, 0.18 * s); this.neckRot = 1.5
        if (d.dorsal) this.body.add(at(rot(scl(coneNode(0.12 * s, 0.01, 0.3 * s, m, 12), 0.2, 1, 1), -0.5, 0, 0), 0, 0.02 * s, -0.12 * s))
        if (d.spikes) this.addBackSpikes(0, R, R)
        for (const sd of [1, -1]) this.body.add(rot(at(scl(sphereNode(0.1 * s, m, 10), 0.15, 0.5, 1), sd * R * 0.9, -R * 1.2, 0.05 * s), 0, 0, sd * 0.8))
        break
      }
      case 'insect': case 'spider':
        this.neck = V3(0, -0.06 * s, 0.07 * s); this.neckRot = 1.35
        if (d.arms === 'pincer') this.buildArms(m, [0.1 * s, -0.08 * s, 0.05 * s], 0.3 * s)
        break
      case 'slither':
        this.neck = V3(0, -0.02 * s, 0.02 * s); this.neckRot = 0.95
        if (d.hood) this.body.add(at(scl(sphereNode(0.14 * s, m, 16), 1.3, 1.1, 0.12), 0, 0.1 * s, -0.02 * s))
        break
      case 'tentacle':
        this.neck = V3(0, 0, 0)
        break
      default: {
        // quad, sprawl, hopper: continue the barrel into chest and neck
        const quad = d.plan === 'quad'
        const R = (quad ? 0.3 : d.plan === 'sprawl' ? 0.2 : 0.17) * s * d.girth
        const dy = quad ? -R * 0.6 : -R * 0.55
        this.body.add(furry(loftNode([Ring([0, dy, -0.15 * s], R, R * (quad ? 1 : 0.75)), Ring([0, dy + R * 0.1, 0.12 * s], R * 0.88, R * 0.8), Ring([0, dy + R * 0.35, 0.28 * s], R * 0.62, R * 0.6),
          Ring([0, dy + R * 0.55, 0.38 * s], R * 0.45, R * 0.45), Ring([0, dy + R * 0.65, 0.44 * s], R * 0.35, R * 0.35)], m, { seg: 22, ref: [0, 1, 0], smooth: 3, vScale: 0.8 }), d))
        this.neck = V3(0, dy + R * 0.6, 0.4 * s)
        this.neckRot = d.plan === 'sprawl' ? 1.3 : d.neck > 0.7 ? 0.2 : 0.4
        if (d.plan === 'hopper') {
          // little front paws reaching the ground
          for (const sd of [1, -1]) {
            const sh = group(); sh.position.set(sd * R * 0.6, dy, 0.25 * s)
            this.body.add(sh)
            const len = Math.max(0.05, -dy + 0.3 * s * d.legLen * 0.9)
            sh.add(limb(len, 0.035 * s, 0.025 * s, m, { seg: 8 }))
            this.shoulders.push(sh)
          }
        }
        if (d.hump) this.body.add(at(scl(sphereNode(R * 0.55, m, 16), 1, 0.9, 1.1), 0, dy + R * 1.05, 0.02 * s))
        if (d.mane && quad) this.body.add(loftNode([Ring([0, dy + R * 0.9, -0.05 * s], 0.04 * s, 0.02 * s), Ring([0, dy + R * 1.0, 0.2 * s], 0.05 * s, 0.03 * s), Ring([0, dy + R * 0.95, 0.42 * s], 0.02 * s, 0.02 * s)], Coats.plain(d.b, 0.9), { seg: 10, ref: [0, 1, 0], smooth: 3 }))
      }
    }
  }

  addBackSpikes(H, w, dd) {
    const s = this.s
    const rr = new RNG(9)
    const q = Coats.plain(this.d.b, 0.6)
    for (let i = 0; i < 40; i++) {
      const a = rr.range(-1.3, 1.3), y = rr.range(0.1, 0.9)
      const dir = [Math.sin(a) * 0.8, 0.3, -Math.cos(a)]
      const c = coneNode(0.012 * s, 0.001, 0.12 * s, q, 5)
      c.position.set(Math.sin(a) * w, H * y, -Math.cos(a) * dd)
      orient(c, dir)
      this.body.add(c)
    }
  }

  buildBirdTail(dd) {
    const d = this.d, s = this.s
    this.tailFan.position.set(0, 0.08 * s, -dd * 0.8)
    this.body.add(this.tailFan)
    const fm = Coats.plain(d.b, 0.4)
    switch (d.tail) {
      case 'fan': {
        const big = d.name === 'Peacock'
        const n = big ? 15 : 9
        for (let k = 0; k < n; k++) {
          const a = (k / (n - 1) - 0.5) * (big ? 2.6 : 1.8)
          const f = group(); eul(f, 0, 0, a)
          this.tailFan.add(f)
          const len = (big ? 1.0 : 0.4) * s
          f.add(loftNode([Ring([0, 0, 0], 0.02 * s, 0.006 * s), Ring([0, len * 0.5, -len * 0.25], 0.05 * s, 0.008 * s), Ring([0, len, -len * 0.3], 0.04 * s, 0.006 * s),
            Ring([0, len * 1.05, -len * 0.3], 0.005, 0.003)], fm, { seg: 8, ref: [0, 0, 1], smooth: 2 }))
          if (big) f.add(at(scl(sphereNode(0.045 * s, Coats.plain([0.1, 0.5, 0.35], 0.3), 8), 1, 1, 0.2), 0, len * 0.93, -len * 0.3 + 0.006))
        }
        break
      }
      case 'long':
        for (let k = 0; k < 3; k++) this.tailFan.add(scl(limb(0.5 * s, 0.03 * s, 0.01 * s, fm, { seg: 6, dir: [(k - 1) * 0.1, -0.5, -1] }), 1, 1, 0.3))
        break
      case 'fluffy':
        this.tailFan.add(scl(sphereNode(0.14 * s, Coats.plain([0.92, 0.9, 0.88], 0.9), 12), 1, 0.8, 1.2))
        break
      default:
        this.tailFan.add(scl(sphereNode(0.09 * s, Coats.coat(d), 10), 1, 0.5, 1.2))
    }
  }

  buildBugWings() {
    const d = this.d, s = this.s
    let wm
    switch (d.bugWings) {
      case 'big': wm = Coats.membrane(d.wingCol || d.b, 0.95); break
      case 'elytra': wm = Coats.coat(d); break
      default: wm = Coats.membrane([0.85, 0.9, 0.95], 0.35)
    }
    const y = this.horizontal ? 0.02 * s : 0.4 * s, z = this.horizontal ? -0.05 * s : -0.12 * s * d.girth
    for (const sd of [1, -1]) {
      const w = group(); w.position.set(sd * 0.05 * s, y, z)
      this.body.add(w)
      switch (d.bugWings) {
        case 'big':
          w.add(at(scl(sphereNode(0.3 * s, wm, 14), 1, 0.03, 0.8), sd * 0.28 * s, 0, 0.08 * s))
          w.add(at(scl(sphereNode(0.22 * s, wm, 14), 1, 0.03, 0.8), sd * 0.2 * s, -0.01, -0.2 * s))
          break
        case 'elytra':
          w.add(at(scl(sphereNode(0.15 * s * d.girth, wm, 16), 0.55, 0.55, 1.1), sd * 0.05 * s, 0.02 * s, -0.12 * s))
          break
        default:
          w.add(at(scl(sphereNode(0.16 * s, wm, 12), 1, 0.03, 0.4), sd * 0.15 * s, 0, 0))
      }
      this.bugW.push(w)
    }
  }

  buildArms(m, sh, H) {
    const d = this.d, s = this.s
    const lm = Coats.limbMat(d)
    const th = 0.05 * s * Math.sqrt(d.girth)
    for (const sd of [1, -1]) {
      const sn = group(); sn.position.set(sh[0] * sd, sh[1], sh[2])
      this.body.add(sn)
      const e = group(), hnd = group()
      switch (d.arms) {
        case 'hands': case 'paw': case 'hoof': {
          const ape = d.plan === 'biped' && d.arms === 'hands' ? (d.name === 'Monkey' || d.name === 'Meerkat' ? 1.2 : 1.6) : 1
          const up = 0.28 * s * ape, lo = 0.26 * s * ape
          sn.add(sphereNode(th * 1.1, m, 12))
          sn.add(furry(muscleLimb(up, th * (d.arms === 'hoof' ? 1.6 : 1.3), th * 1.0, th * 0.8, m, { depth: 1.1 }), d))
          e.position.set(0, -up, 0); sn.add(e)
          e.add(limb(lo, th * 0.85, th * 0.65, m, { seg: 10 }))
          hnd.position.set(0, -lo, 0); e.add(hnd)
          if (d.arms === 'hands') {
            hnd.add(loftNode([Ring([0, 0, 0], th * 0.6, th * 0.4), Ring([0, -0.04 * s, 0.005], th * 0.85, th * 0.35, 2.6), Ring([0, -0.1 * s, 0.01], th * 0.75, th * 0.3, 2.4),
              Ring([0, -0.12 * s, 0.012], th * 0.2, th * 0.15)], lm, { seg: 12, smooth: 3 }))
          } else if (d.arms === 'hoof') {
            hnd.add(at(coneNode(th * 1.0, th * 0.8, th * 1.3, Mat.hoof), 0, -th * 0.6, 0.005))
          } else {
            hnd.add(at(scl(sphereNode(th * 1.2, m, 12), 1, 0.7, 1.2), 0, -th * 0.5, th * 0.2))
            for (let k = -1; k <= 1; k++) hnd.add(at(rot(coneNode(th * 0.12, 0.001, th * 0.5, Mat.claw, 6), Math.PI / 2, 0, 0), k * th * 0.45, -th * 0.8, th * 1.3))
          }
          break
        }
        case 'wing': {
          const big = d.name === 'Eagle' ? 1.5 : 1
          const wm = Coats.coat(d)
          sn.add(loftNode([Ring([0, 0.04 * s, 0.02 * s], 0.03 * s, 0.07 * s), Ring([0, -0.06 * s, 0], 0.05 * s, 0.13 * s * big), Ring([0, -0.2 * s * big, -0.05 * s], 0.045 * s, 0.14 * s * big),
            Ring([0, -0.34 * s * big, -0.1 * s], 0.03 * s, 0.1 * s * big), Ring([0, -0.44 * s * big, -0.15 * s], 0.012 * s, 0.04 * s)], wm, { seg: 16, smooth: 3 }))
          this.wings.push(sn)
          break
        }
        case 'batWing': {
          const mem = Coats.membrane(d.wingCol || d.b, 0.92)
          sn.add(limb(0.25 * s, th * 0.6, th * 0.4, m, { seg: 8 }))
          sn.add(at(scl(sphereNode(0.3 * s, mem, 14), 0.04, 1, 0.9), 0, -0.25 * s, -0.08 * s))
          this.wings.push(sn)
          break
        }
        case 'fin':
          sn.add(at(scl(sphereNode(0.16 * s, m, 12), 0.18, 1, 0.45), 0, -0.13 * s, 0))
          break
        case 'pincer': {
          const chit = Coats.coat(d)
          sn.add(limb(0.18 * s, th * 0.8, th * 0.7, chit, { seg: 8, dir: [sd * 0.4, -0.5, 1] }))
          const hp = vs(vn([sd * 0.4, -0.5, 1]), 0.18 * s)
          hnd.position.set(hp[0], hp[1], hp[2])
          sn.add(hnd)
          hnd.add(at(scl(sphereNode(0.08 * s, chit, 12), 0.8, 0.6, 1.2), 0, 0, 0.05 * s))
          hnd.add(at(rot(coneNode(0.035 * s, 0.004, 0.12 * s, chit, 8), Math.PI / 2, 0, 0), 0, 0.02 * s, 0.15 * s))
          const jaw = group(); jaw.position.set(0, -0.02 * s, 0.1 * s)
          hnd.add(jaw)
          jaw.add(at(rot(coneNode(0.025 * s, 0.004, 0.1 * s, chit, 8), Math.PI / 2, 0, 0), 0, 0, 0.05 * s))
          this.pincers.push(jaw)
          break
        }
        case 'tentacles':
          this.tentArms.push(chainLimb(sn, 5, 0.09 * s, 0.035 * s, 0.008 * s, m))
          break
        case 'insect': {
          sn.add(limb(0.14 * s, 0.014 * s, 0.01 * s, lm, { seg: 6, dir: [sd, 0.2, 0.3] }))
          const ep = vs(vn([sd, 0.2, 0.3]), 0.14 * s)
          e.position.set(ep[0], ep[1], ep[2]); sn.add(e)
          e.add(limb(0.16 * s, 0.01 * s, 0.007 * s, lm, { seg: 6 }))
          break
        }
      }
      this.shoulders.push(sn); this.elbows.push(e); this.hands.push(hnd)
    }
  }

  pose(p) {
    const g = p.gait, d = this.d
    if (d.special === 'puff') {
      const pf = p.shove > 0 ? 1 + p.shove * 0.8 : 1
      this.body.scale.set(pf, pf, pf)
    }
    if (this.horizontal) {
      if (d.plan === 'hopper') {
        this.shoulders.forEach((sh, i) => sh.rotation.set(wave(p.phase, i * 0.1) * 0.4 * g, 0, 0))
      }
      this.bugW.forEach((w, i) => {
        const sd = i === 0 ? 1 : -1
        const fly = Math.max(p.flap, p.glide, p.air)
        w.rotation.set(0, 0, sd * (d.bugWings === 'elytra' ? fly * 0.8 : Math.sin(p.t * 60) * 0.5 * fly + 0.1))
      })
      return
    }
    for (let i = 0; i < this.shoulders.length; i++) {
      const side = i === 0 ? 1 : -1
      const sw = wave(p.phase, i === 0 ? 0.5 : 0)
      const sh = this.shoulders[i]
      switch (d.arms) {
        case 'hands': case 'paw': case 'hoof': case 'insect': {
          let sx = -sw * (0.28 + 0.5 * p.run) * g
          let sz = side * 0.08
          let ex = -(0.12 + 0.8 * p.run * g)
          sz = mix(sz, side * 0.55, p.air * 0.7)
          sx = mix(sx, -1.15, p.carry); sz = mix(sz, -side * 0.28, p.carry); ex = mix(ex, -0.55, p.carry)
          sx = mix(sx, -1.5, p.shove); ex = mix(ex, -0.1, p.shove)
          const cs = wave(p.phase * 0.7, i === 0 ? 0.5 : 0)
          sx = mix(sx, -2.6 - cs * 0.35, p.climb); ex = mix(ex, -0.4 + cs * 0.3, p.climb)
          if (p.throwT >= 0 && i === 1) {
            const t = p.throwT
            sx = mix(mix(sx, -2.7, smoothstep(0, 0.35, t)), -0.7, smoothstep(0.35, 0.6, t))
          }
          if (p.talk > 0 && i === 1) sx -= 0.35 * p.talk
          sh.rotation.set(sx, 0, sz)
          this.elbows[i].rotation.set(ex, 0, 0)
          break
        }
        case 'wing': case 'batWing': {
          const spread = Math.max(p.glide, Math.min(1, p.flap * 1.5), p.air * 0.25, p.shove)
          const beat = Math.sin(p.t * 22) * 0.75 * Math.max(p.flap, p.shove)
          sh.rotation.set(0.15 - spread * 0.1, side * spread * 0.2, side * (spread * 1.45 + beat))
          sh.scale.set(1 + spread * 0.3, 1 + spread * 0.55, 1 + spread * 0.35)
          break
        }
        case 'fin':
          sh.rotation.set(sw * 0.3 * g, 0, side * (0.3 + Math.max(p.shove, p.air) * 0.8 + Math.sin(p.t * 3) * 0.05))
          break
        case 'pincer':
          sh.rotation.set(-p.shove * 0.6 + sw * 0.1 * g, side * 0.2, 0)
          if (i < this.pincers.length) this.pincers[i].rotation.set(0.1 + (0.5 + 0.5 * Math.sin(p.t * 8)) * 0.5 * Math.max(p.shove, p.talk), 0, 0)
          break
        case 'tentacles':
          this.tentArms[i].forEach((n, j) => n.rotation.set(Math.sin(p.t * 3 + j + i) * 0.3 - p.shove * 0.3, 0, side * 0.2))
          break
      }
    }
    this.bugW.forEach((w, i) => {
      const sd = i === 0 ? 1 : -1
      const fly = Math.max(p.flap, p.glide, p.air)
      w.rotation.set(0.2, 0, sd * (d.bugWings === 'elytra' ? fly * 0.8 : Math.sin(p.t * 60) * 0.5 * fly + 0.2))
    })
    this.tailFan.rotation.set(-0.25 - p.glide * 0.3 - (d.name === 'Peacock' ? 0.6 : 0), 0, Math.sin(p.t * 2) * 0.04)
  }
}

// ---- Heads ----

export class GenHead extends HeadPart {
  constructor(d) {
    super(speciesFor(d))
    this.d = d
    this.s = d.size
    this.neckNode = group(); this.skull = group(); this.jaw = group()
    this.ears = []; this.trunk = []; this.ants = []
    this.earT = 2
    const s = this.s
    const { neckNode, skull, jaw } = this
    const m = Coats.coat(d)
    const bug = d.plan === 'insect' || d.plan === 'spider'
    const fish = d.plan === 'fish' || d.plan === 'tentacle'
    const bird = d.plan === 'bird'
    this.node.add(neckNode)
    this.anchor = skull
    const nl = d.neck * s
    const nr = (bird ? 0.05 : d.plan === 'quad' ? 0.12 : 0.09) * s * Math.sqrt(d.girth) * (bug ? 0.45 : 1) * (d.neck > 1.2 ? 0.65 : 1)
    const tilt = 0.3
    const tip = [0, nl * Math.cos(tilt), nl * Math.sin(tilt) + 0.02 * s]
    if (nl > 0.02 && !fish) {
      const nm = d.mane && d.plan !== 'quad' ? Coats.coat(d) : m
      neckNode.add(furry(loftNode([Ring([0, -0.1 * s, -0.03 * s], nr * 1.45, nr * 1.8), Ring(vs(tip, 0.45), nr * 1.0, nr * 1.35), Ring(vs(tip, 0.9), nr * 0.85, nr * 1.05), Ring(va(tip, [0, 0, 0.02 * s]), nr * 0.7, nr * 0.8)], nm, { seg: 18, ref: [0, 0, 1], smooth: 3, vScale: 0.8 }), d))
    }
    skull.position.set(tip[0], tip[1], tip[2])
    eul(skull, bird || bug || d.eyeFront ? 0.05 : 0.15, 0, 0)
    neckNode.add(skull)
    const cr = (bug ? 0.07 : fish ? 0.15 : bird ? 0.07 : 0.12) * s * d.headW
    const rawSnout = d.snout * s
    const sl = d.mouth === 'flat' ? 0.05 * s : (bird || bug ? 0.02 * s : rawSnout * (d.snout < 0.3 && d.mouth === 'snout' ? 0.5 : 0.72))
    const tz = sl + cr * 0.55
    this.height = tip[1] + cr * 1.6
    this.mouth = V3(0, tip[1], tip[2] + tz)
    // skull: a round cranium, a forehead "stop", then the muzzle blending out of the cheeks
    const catLike = sl < 0.3 * s && !bird && !bug && d.mouth === 'snout'
    const snoutW = d.mouth === 'croc' ? 0.55 : d.mouth === 'hippo' ? 1.0 : d.mouth === 'needle' ? 0.25 : catLike ? 0.72 : 0.58
    const snoutH = d.mouth === 'croc' ? 0.3 : d.mouth === 'hippo' ? 0.8 : d.mouth === 'needle' ? 0.25 : catLike ? 0.58 : 0.52
    const rings = [Ring([0, 0.05 * cr, -cr * 0.95], cr * 0.25, cr * 0.25), Ring([0, 0.06 * cr, -cr * 0.7], cr * 0.82, cr * 0.85),
      Ring([0, 0.04 * cr, -cr * 0.25], cr * 1.0, cr * 1.0), Ring([0, 0, cr * 0.2], cr * 0.96, cr * 0.92),
      Ring([0, -0.08 * cr, cr * 0.55], cr * 0.82, cr * 0.76)]
    if (sl > 0.04 * s) {
      rings.push(Ring([0, -0.2 * cr, cr * 0.55 + sl * 0.3], cr * mix(0.8, snoutW, 0.5), cr * mix(0.72, snoutH, 0.6)))
      rings.push(Ring([0, -0.26 * cr, cr * 0.5 + sl * 0.75], cr * snoutW * 1.02, cr * snoutH))
      rings.push(Ring([0, -0.24 * cr, tz], cr * snoutW * 0.92, cr * snoutH * 0.88))
      rings.push(Ring([0, -0.22 * cr, tz + cr * 0.12], cr * snoutW * 0.45, cr * snoutH * 0.45))
    } else {
      rings.push(Ring([0, -0.1 * cr, cr * 0.9], cr * 0.6, cr * 0.58))
      rings.push(Ring([0, -0.1 * cr, cr * 1.03], cr * 0.22, cr * 0.2))
    }
    const eyeZ = d.eyeFront ? cr * 0.82 : cr * (bug ? 0.45 : 0.35)
    skull.add(furry(loftNode(rings, m, {
      seg: 26, ref: [0, 1, 0], smooth: 4, vScale: 0.8, displace: p => {
        let dd = 0
        // brow ridge over each eye, cheekbones, and sockets for the eyes to sit in
        for (const sx of [1, -1]) {
          const e = [sx * cr * (d.eyeFront ? 0.42 : 0.75), cr * 0.3, eyeZ]
          dd -= Math.exp(-vlen2(vsub(p, e)) / (cr * cr * 0.03)) * cr * 0.12
          const brow = vsub(p, va(e, [0, cr * 0.2, -cr * 0.05]))
          dd += Math.exp(-vlen2(brow) / (cr * cr * 0.04)) * cr * 0.08
          const cheek = vsub(p, [sx * cr * 0.7, -cr * 0.2, cr * 0.4])
          dd += Math.exp(-vlen2(cheek) / (cr * cr * 0.08)) * cr * (catLike ? 0.14 : 0.07)
        }
        return dd
      },
    }), d))
    const nose = Coats.glossy(d.noseCol)
    const beakM = Coats.plain(d.beakCol, 0.35)
    jaw.position.set(0, -0.45 * cr, cr * 0.1)
    skull.add(jaw)
    switch (d.mouth) {
      case 'snout': case 'needle': case 'croc': case 'hippo': {
        if (d.mouth === 'snout') skull.add(at(scl(sphereNode(cr * 0.3, nose, 12), 1.2, 0.8, 0.6), 0, -0.12 * cr, tz + cr * 0.02))
        const jl = tz - cr * 0.1
        jaw.add(loftNode([Ring([0, 0, -cr * 0.2], cr * snoutW * 0.8, cr * 0.2), Ring([0, -0.02 * cr, jl * 0.8], cr * snoutW * 0.8, cr * 0.18), Ring([0, 0, jl], cr * snoutW * 0.4, cr * 0.1)],
          m, { seg: 12, ref: [0, 1, 0], smooth: 2 }))
        if (d.mouth === 'croc' || d.name === 'Shark') {
          for (let k = 0; k < 10; k++) {
            const z = cr * 0.4 + k * (tz - cr * 0.4) / 10
            for (const sd of [1, -1]) skull.add(at(rot(coneNode(0.008 * s, 0.001, 0.025 * s, Mat.horn, 5), Math.PI, 0, 0), sd * cr * snoutW * 0.85, -0.45 * cr, z))
          }
        }
        if (d.mouth === 'hippo') for (const sd of [1, -1]) skull.add(at(sphereNode(cr * 0.2, nose, 8), sd * cr * 0.3, cr * 0.25, tz))
        break
      }
      case 'pig':
        skull.add(at(rot(cylNode(cr * 0.38, cr * 0.2, Coats.plain(d.noseCol, 0.4), 18), Math.PI / 2, 0, 0), 0, -0.15 * cr, tz))
        for (const sd of [1, -1]) skull.add(at(sphereNode(cr * 0.08, Mat.black, 8), sd * cr * 0.13, -0.15 * cr, tz + cr * 0.1))
        jaw.add(loftNode([Ring([0, 0, 0], cr * 0.4, cr * 0.15), Ring([0, 0, tz * 0.9], cr * 0.3, cr * 0.1)], m, { seg: 10, ref: [0, 1, 0], smooth: 1 }))
        break
      case 'beak': case 'hooked': case 'bigBeak': case 'pouch': case 'bill': {
        let bl, bw, bh, droop
        switch (d.mouth) {
          case 'hooked': bl = cr * 1.0; bw = cr * 0.35; bh = cr * 0.4; droop = cr * 0.35; break
          case 'bigBeak': bl = cr * 2.4; bw = cr * 0.4; bh = cr * 0.6; droop = cr * 0.2; break
          case 'pouch': bl = cr * 3.0; bw = cr * 0.3; bh = cr * 0.2; droop = cr * 0.1; break
          case 'bill': bl = cr * 1.4; bw = cr * 0.5; bh = cr * 0.14; droop = 0; break
          default: bl = cr * 0.9; bw = cr * 0.28; bh = cr * 0.24; droop = cr * 0.15
        }
        const z0 = cr * 0.8
        skull.add(loftNode([Ring([0, 0, z0], bw, bh), Ring([0, -droop * 0.3, z0 + bl * 0.5], bw * 0.8, bh * 0.7), Ring([0, -droop, z0 + bl], bw * (d.mouth === 'bill' ? 0.8 : 0.15), bh * 0.2)],
          beakM, { seg: 12, ref: [0, 1, 0], smooth: 3 }))
        jaw.position.set(0, -bh * 0.7, z0)
        jaw.add(loftNode([Ring([0, 0, 0], bw * 0.8, bh * 0.4), Ring([0, 0, bl * 0.85], bw * (d.mouth === 'bill' ? 0.7 : 0.1), bh * 0.15)], beakM, { seg: 10, ref: [0, 1, 0], smooth: 1 }))
        if (d.mouth === 'pouch') jaw.add(at(scl(sphereNode(bl * 0.3, Coats.plain(c3(d.beakCol, 0.9), 0.5), 12), 0.6, 0.6, 1.6), 0, -bl * 0.12, bl * 0.45))
        this.mouth = V3(0, tip[1], tip[2] + z0 + bl)
        break
      }
      case 'trunk': {
        let p = skull
        const segs = 9
        for (let k = 0; k < segs; k++) {
          const n = group()
          if (k === 0) n.position.set(0, -0.2 * cr, tz); else n.position.set(0, 0, 0.11 * s)
          p.add(n)
          const r0 = cr * (0.35 - k * 0.025)
          n.add(limb(0.12 * s, r0, r0 * 0.9, m, { seg: 12, dir: [0, 0, 1] }))
          this.trunk.push(n)
          p = n
        }
        break
      }
      case 'flat':
        skull.add(at(scl(sphereNode(cr * 0.62, Coats.limbMat(d), 16), 1.05, 0.95, 0.5), 0, -0.1 * cr, cr * 0.72))
        skull.add(at(scl(sphereNode(cr * 0.14, nose, 10), 1.3, 0.8, 0.8), 0, -0.12 * cr, cr * 1.05))
        jaw.add(at(scl(sphereNode(cr * 0.4, Coats.limbMat(d), 12), 1, 0.5, 0.6), 0, 0, cr * 0.75))
        break
      case 'fish':
        skull.add(at(rot(torusNode(cr * 0.18, cr * 0.06, Coats.plain(c3(d.a, 0.8), 0.4)), Math.PI / 2, 0, 0), 0, -0.15 * cr, cr * 1.0))
        break
      case 'mandibles':
        for (const sd of [1, -1]) {
          const mnd = coneNode(cr * 0.15, 0.002, cr * 0.7, Coats.plain(c3(d.b, 0.5)), 6)
          mnd.position.set(sd * cr * 0.25, -0.35 * cr, cr * 1.1)
          eul(mnd, Math.PI / 2, 0, sd * 0.4)
          jaw.add(mnd)
        }
        break
    }
    // eyes
    if (d.eyeSize > 0) {
      const er = (bug ? 0.03 : 0.022) * s * d.eyeSize * (fish ? 1.2 : 1)
      const eyeM = Coats.glossy(d.eyeCol)
      for (const sd of [1, -1]) {
        const pos = d.eyeFront ? [sd * cr * 0.42, cr * 0.3, cr * 0.8] : [sd * cr * 0.72, cr * 0.3, cr * (bug ? 0.45 : 0.35)]
        skull.add(at(sphereNode(er, eyeM, 16), pos[0], pos[1], pos[2]))
        if (!bug && !fish) {
          const ln = torusNode(er * 0.95, er * 0.22, Coats.plain(c3(d.a, 0.35), 0.8))
          ln.position.set(pos[0], pos[1], pos[2])
          orient(ln, d.eyeFront ? [0, 0, 1] : [sd, 0, 0.35])
          skull.add(ln)
        }
        if (d.eyeFront || d.eyeSize > 1.4) {
          const pupil = scl(sphereNode(er * 0.5, Mat.eyeBlack, 10), 1, 1, 0.4)
          const pp = va(pos, d.eyeFront ? [0, 0, er * 0.85] : [sd * er * 0.85, 0, 0])
          pupil.position.set(pp[0], pp[1], pp[2])
          if (!d.eyeFront) pupil.scale.set(0.4, 1, 1)
          skull.add(pupil)
        }
      }
    }
    // ears
    const earM = m
    for (const sd of [1, -1]) {
      const e = group(); e.position.set(sd * cr * 0.7, cr * 0.72, -cr * 0.25)
      skull.add(e)
      switch (d.ears) {
        case 'round':
          e.add(scl(sphereNode(cr * 0.36, earM, 14), 1, 1, 0.35))
          e.add(at(scl(sphereNode(cr * 0.27, Coats.plain(c3add(c3(d.a, 0.45), [0.2, 0.12, 0.12]), 0.8), 12), 1, 1, 0.2), 0, 0.01 * cr, cr * 0.07))
          break
        case 'pointy':
          e.add(rot(at(scl(coneNode(cr * 0.28, 0.003, cr * 0.75, earM, 12), 1, 1, 0.45), 0, cr * 0.3, 0), 0, 0, -sd * 0.35))
          e.add(rot(at(scl(coneNode(cr * 0.2, 0.002, cr * 0.55, Coats.plain(c3add(c3(d.a, 0.45), [0.22, 0.14, 0.14]), 0.8), 10), 1, 1, 0.3), -sd * cr * 0.02, cr * 0.28, cr * 0.06), 0, 0, -sd * 0.35))
          break
        case 'long':
          e.add(loftNode([Ring([0, 0, 0], cr * 0.18, cr * 0.1), Ring([sd * 0.1 * cr, cr * 1.0, -0.1 * cr], cr * 0.28, cr * 0.1), Ring([sd * 0.15 * cr, cr * 2.2, -0.2 * cr], cr * 0.05, cr * 0.03)], earM, { seg: 10, smooth: 3 }))
          break
        case 'floppy': e.add(rot(at(scl(sphereNode(cr * 0.5, earM, 12), 0.25, 1, 0.6), sd * cr * 0.25, -cr * 0.4, 0), 0, 0, sd * 0.3)); break
        case 'big': e.add(rot(at(scl(sphereNode(cr * 1.4, earM, 16), 0.12, 1, 0.9), sd * cr * 0.3, -cr * 0.5, -cr * 0.6), 0, sd * 0.4, sd * 0.2)); break
        case 'tufts': e.add(rot(at(coneNode(cr * 0.2, 0.003, cr * 0.6, earM, 8), 0, cr * 0.3, 0), 0, 0, -sd * 0.4)); break
      }
      this.ears.push(e)
    }
    // horns
    const hm = Mat.horn
    for (const sd of [1, -1]) {
      const hp = [sd * cr * 0.4, cr * 0.85, -cr * 0.1]
      switch (d.horns) {
        case 'short': skull.add(rot(at(coneNode(cr * 0.14, 0.004, cr * 0.6, hm, 8), hp[0], hp[1] + cr * 0.2, hp[2]), 0, 0, -sd * 0.5)); break
        case 'ram':
          skull.add(at(rot(torusNode(cr * 0.45, cr * 0.12, hm), 0, 0, Math.PI / 2), hp[0] * 1.4, hp[1] - cr * 0.2, hp[2] - cr * 0.2))
          break
        case 'long': skull.add(rot(at(coneNode(cr * 0.1, 0.003, cr * 2.2, hm, 8), hp[0], hp[1] + cr * 0.9, hp[2] - cr * 0.6), -0.5, 0, -sd * 0.15)); break
        case 'wide':
          skull.add(loftNode([Ring(hp, cr * 0.18, cr * 0.18), Ring(va(hp, [sd * cr * 1.2, -cr * 0.1, -cr * 0.2]), cr * 0.13, cr * 0.13), Ring(va(hp, [sd * cr * 1.8, cr * 0.5, -cr * 0.1]), cr * 0.02, cr * 0.02)], hm, { seg: 10, smooth: 3 }))
          break
        case 'antlers': case 'palmate': {
          const ant = group(); ant.position.set(hp[0], hp[1], hp[2])
          eul(ant, -0.3, 0, -sd * 0.5)
          skull.add(ant)
          const am = Coats.plain([0.55, 0.45, 0.32], 0.7)
          ant.add(limb(0.35 * s, 0.018 * s, 0.01 * s, am, { seg: 6, dir: [sd * 0.3, 1, -0.3] }))
          if (d.horns === 'palmate') {
            ant.add(rot(at(scl(sphereNode(0.2 * s, am, 12), 1, 0.15, 0.7), sd * 0.15 * s, 0.3 * s, -0.08 * s), 0, 0, sd * 0.4))
          } else {
            for (let k = 0; k < 3; k++) ant.add(at(limb(0.15 * s, 0.01 * s, 0.005 * s, am, { seg: 5, dir: [sd * 0.2, 0.8, 0.6] }), sd * 0.03 * s * k, 0.1 * s + k * 0.08 * s, -0.03 * s * k))
          }
          break
        }
        case 'rhino':
          if (sd > 0) {
            skull.add(at(rot(coneNode(cr * 0.3, 0.004, cr * 1.1, hm, 10), -0.4, 0, 0), 0, cr * 0.1, tz - cr * 0.05))
            skull.add(at(rot(coneNode(cr * 0.2, 0.004, cr * 0.5, hm, 10), -0.3, 0, 0), 0, cr * 0.35, tz - cr * 0.6))
          }
          break
        case 'ossicones':
          skull.add(at(cylNode(cr * 0.08, cr * 0.5, m, 8), hp[0] * 0.6, hp[1] + cr * 0.2, hp[2]))
          skull.add(at(sphereNode(cr * 0.12, Mat.brownHair, 8), hp[0] * 0.6, hp[1] + cr * 0.47, hp[2]))
          break
      }
    }
    // extras
    if (d.mane) {
      const mm = Coats.plain(d.plan === 'sprawl' ? d.b : c3add(c3(d.b, 0.9), c3(d.a, 0.1)), 0.95)
      if (d.plan === 'sprawl') {
        for (const sd of [1, -1]) for (let k = 0; k < 3; k++) skull.add(at(limb(cr * 0.9, cr * 0.1, cr * 0.04, mm, { seg: 6, dir: [sd, 0.6 - k * 0.4, -0.5] }), sd * cr * 0.7, 0, -cr * 0.4))
      } else if (d.ears === 'round') {
        const maneM = Coats.coat('fur', c3add(c3(d.b, 0.8), c3(d.a, 0.2)), c3(d.b, 0.5))
        const mr = []
        for (let i = 0; i <= 10; i++) {
          const t = i / 10
          const r = Math.sin(Math.PI * t) * cr * 1.55 + 0.01
          mr.push(Ring([0, 0, (t - 0.5) * cr * 1.6], r, r * 1.05))
        }
        const g = loft(mr, {
          seg: 30, ref: [0, 1, 0], displace: (p, n, u, v) => {
            // big shaggy clumps
            const clump = Noise.fbm(u * 9, v * 5, 3, 17) * cr * 0.45
            return clump + Math.abs(Math.sin(u * 2 * Math.PI * 11)) * cr * 0.08
          },
        })
        const mane = mesh(g, maneM)
        mane.position.set(0, -0.05 * cr, -cr * 0.35)
        skull.add(furry(mane, def('mane', 'quad', d.size, 'fur', d.b, d.b), 2.5))
      } else {
        neckNode.add(loftNode([Ring([0, 0, -nr * 0.9], 0.02 * s, 0.03 * s), Ring(va(vs(tip, 0.5), [0, 0, -nr * 0.9]), 0.03 * s, 0.05 * s), Ring(va(tip, [0, cr * 0.5, -cr * 0.5]), 0.02 * s, 0.03 * s)], mm, { seg: 8, smooth: 3 }))
      }
    }
    if (d.whiskers) {
      const wm = Coats.plain([0.9, 0.9, 0.88])
      for (const sd of [1, -1]) for (let k = 0; k < 3; k++) skull.add(at(rot(cylNode(0.002 * s, cr * 1.3, wm, 3), 0, 0, Math.PI / 2 + (k - 1) * 0.15), sd * cr * 0.6, -0.15 * cr, tz - cr * 0.1))
    }
    if (d.antennae) {
      for (const sd of [1, -1]) {
        const a = group(); a.position.set(sd * cr * 0.3, cr * 0.8, cr * 0.4)
        skull.add(a)
        const len = (d.plan === 'slither' ? 0.18 : 0.22) * s
        a.add(limb(len, 0.006 * s, 0.004 * s, Coats.limbMat(d), { seg: 5, dir: [sd * 0.4, 1, 0.5] }))
        a.add(at(sphereNode(0.012 * s, d.plan === 'slither' ? Coats.glossy([0.05, 0.05, 0.05]) : Coats.limbMat(d), 8), sd * 0.4 * len * 0.6, len * 0.8, 0.5 * len * 0.6))
        this.ants.push(a)
      }
    }
    if (d.comb) {
      for (let k = 0; k < 4; k++) skull.add(at(scl(sphereNode(cr * 0.3, Mat.comb, 10), 0.3, 1, 0.6), 0, cr * 0.9, -cr * 0.3 + k * cr * 0.25))
      skull.add(at(scl(sphereNode(cr * 0.3, Mat.comb, 10), 0.5, 1.2, 0.6), 0, -cr * 0.8, cr * 0.7))
    }
    if (d.tusks) {
      for (const sd of [1, -1]) {
        skull.add(loftNode([Ring([sd * cr * 0.35, -0.3 * cr, tz - cr * 0.4], cr * 0.1, cr * 0.1), Ring([sd * cr * 0.45, -cr * 1.1, tz + cr * 0.3], cr * 0.08, cr * 0.08),
          Ring([sd * cr * 0.4, -cr * 1.2, tz + cr * 1.0], cr * 0.01, cr * 0.01)], Mat.horn, { seg: 8, smooth: 3 }))
      }
    }
  }

  pose(p) {
    const d = this.d
    const bird = d.plan === 'bird'
    let bob = 0
    if (bird) {
      const saw = p.phase * 2 - Math.floor(p.phase * 2)
      bob = (saw < 0.75 ? -saw / 0.75 : (saw - 0.75) / 0.25 - 1) * 0.04 * d.size * p.gait * (1 - p.air)
    }
    const peck = bird ? p.eat * Math.max(0, Math.sin(p.t * 14)) * 0.9 + p.eat * 0.4 : p.eat * 0.9
    this.neckNode.rotation.set(peck - p.talk * 0.25 + p.shove * 0.4, 0, 0)
    this.neckNode.position.set(0, 0, bob)
    this.skull.rotation.set((bird || d.eyeFront ? 0.05 : 0.15) - p.talk * 0.25 + p.eat * 0.3, Math.sin(p.t * 0.33) * 0.2 * (1 - p.gait), 0)
    const open = p.talk * (0.5 + 0.5 * Math.abs(Math.sin(p.t * 14))) + p.eat * Math.abs(Math.sin(p.t * 7)) * 0.5
    this.jaw.rotation.set(open * 0.4, 0, 0)
    this.trunk.forEach((n, k) => {
      const curl = 0.18 + Math.sin(p.t * 1.3 + k * 0.4) * 0.05 - p.talk * 0.35 - p.eat * 0.1
      n.rotation.set(k === 0 ? 1.1 - p.talk * 1.8 : curl, Math.sin(p.t * 0.9 + k * 0.3) * 0.06, 0)
    })
    this.ants.forEach((a, i) => a.rotation.set(Math.sin(p.t * 5 + i) * 0.2, 0, 0))
    this.earT -= 1 / 60
    let flick = 0
    if (this.earT < 0.15) flick = Math.sin(this.earT / 0.15 * Math.PI)
    if (this.earT < 0) this.earT = 1.5 + Math.random() * 3.5
    this.ears.forEach((e, i) => e.rotation.set(0, (i === 0 ? 1 : -1) * flick * 0.4, 0))
  }
}
