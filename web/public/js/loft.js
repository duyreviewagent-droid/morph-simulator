// Lofted organic shapes and small scene-graph helpers. Ported from Loft.swift.
// Coordinates match the Swift/SceneKit version exactly: y up, +z forward, metres.
import * as THREE from '../vendor/three.module.js'
import { mix } from './util.js'

/// Ring(c: [x,y,z], rx, ry, e = superellipse exponent)
export const Ring = (c, rx, ry, e = 2) => ({ c: c instanceof THREE.Vector3 ? [c.x, c.y, c.z] : c, rx, ry, e })

/// Catmull-Rom resampling of control rings.
export function smoothRings(k, per = 4) {
  if (k.length <= 2) return k
  const cr = (a, b, c, d, t) => { const t2 = t * t, t3 = t2 * t; return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3) }
  const out = []
  for (let i = 0; i < k.length - 1; i++) {
    const a = k[Math.max(0, i - 1)], b = k[i], c = k[i + 1], d = k[Math.min(k.length - 1, i + 2)]
    for (let s = 0; s < per; s++) {
      const t = s / per
      out.push({
        c: [cr(a.c[0], b.c[0], c.c[0], d.c[0], t), cr(a.c[1], b.c[1], c.c[1], d.c[1], t), cr(a.c[2], b.c[2], c.c[2], d.c[2], t)],
        rx: Math.max(0.001, cr(a.rx, b.rx, c.rx, d.rx, t)), ry: Math.max(0.001, cr(a.ry, b.ry, c.ry, d.ry, t)), e: mix(b.e, c.e, t),
      })
    }
  }
  out.push(k[k.length - 1])
  return out
}

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const scale = (a, k) => [a[0] * k, a[1] * k, a[2] * k]
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const len = a => Math.hypot(a[0], a[1], a[2])
const norm = a => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l] }

/// Builds a closed tube through rings (caps fan to a point). `ref` picks each ring's depth axis.
/// UVs: u around (0..1), v along in metres × vScale. displace(p, outward, u, v) -> metres.
export function loft(rings, { seg = 22, ref = [0, 0, 1], vScale = 1, displace = null } = {}) {
  const n = rings.length, cols = seg + 1
  const pos = new Array(n * cols), uv = new Array(n * cols)
  let arc = 0
  for (let i = 0; i < n; i++) {
    const r = rings[i]
    const prev = rings[Math.max(0, i - 1)].c, next = rings[Math.min(n - 1, i + 1)].c
    let t = sub(next, prev)
    t = len(t) < 1e-6 ? [0, 1, 0] : norm(t)
    let a = sub(ref, scale(t, dot(ref, t)))
    if (len(a) < 1e-4) a = sub([1, 0, 0], scale(t, t[0]))
    a = norm(a)
    const b = cross(t, a)
    if (i > 0) arc += len(sub(r.c, rings[i - 1].c))
    const pe = 2 / r.e
    for (let j = 0; j <= seg; j++) {
      const th = j / seg * Math.PI * 2
      const cs = Math.cos(th), sn = Math.sin(th)
      const sx = Math.sign(cs) * Math.pow(Math.abs(cs), pe), sy = Math.sign(sn) * Math.pow(Math.abs(sn), pe)
      let p = add(r.c, add(scale(b, sx * r.rx), scale(a, sy * r.ry)))
      if (displace) {
        const out = norm(add(add(scale(b, sx * r.ry), scale(a, sy * r.rx)), [0, 0.0001, 0]))
        p = add(p, scale(out, displace(p, out, j / seg, i / Math.max(1, n - 1))))
      }
      pos[i * cols + j] = p
      uv[i * cols + j] = [j / seg, arc * vScale]
    }
  }
  const nor = new Array(n * cols)
  for (let i = 0; i < n; i++) for (let j = 0; j <= seg; j++) {
    const jl = j === 0 ? seg - 1 : j - 1, jr = j === seg ? 1 : j + 1
    const il = Math.max(0, i - 1), ir = Math.min(n - 1, i + 1)
    const du = sub(pos[i * cols + jr], pos[i * cols + jl])
    const dv = sub(pos[ir * cols + j], pos[il * cols + j])
    let nv = cross(du, dv)
    if (len(nv) < 1e-9) {
      nv = sub(pos[i * cols + j], rings[i].c)
      if (len(nv) < 1e-9) nv = scale(sub(rings[Math.min(n - 1, 1)].c, rings[0].c), i === 0 ? -1 : 1)
    }
    nv = norm(nv)
    if (dot(nv, sub(pos[i * cols + j], rings[i].c)) < 0) nv = scale(nv, -1)
    nor[i * cols + j] = nv
  }
  const idx = []
  for (let i = 0; i < n - 1; i++) for (let j = 0; j < seg; j++) {
    const a = i * cols + j, b = a + 1, c = (i + 1) * cols + j, d = c + 1
    idx.push(a, b, d, a, d, c)
  }
  const P = pos.slice(), N = nor.slice(), U = uv.slice()
  for (const end of [0, n - 1]) {
    const r = rings[end]
    if (Math.max(r.rx, r.ry) < 0.002) continue
    const other = rings[end === 0 ? Math.min(1, n - 1) : Math.max(0, n - 2)].c
    let t = sub(r.c, other); t = len(t) > 1e-6 ? norm(t) : [0, 1, 0]
    const ci = P.length
    P.push(add(r.c, scale(t, Math.min(r.rx, r.ry) * 0.35))); N.push(t); U.push([0.5, uv[end * cols][1]])
    for (let j = 0; j < seg; j++) {
      const a = end * cols + j, b = a + 1
      if (end === 0) idx.push(ci, b, a); else idx.push(ci, a, b)
    }
  }
  if (n > 1) {
    const p0 = P[idx[0]], p1 = P[idx[1]], p2 = P[idx[2]]
    if (dot(cross(sub(p1, p0), sub(p2, p0)), N[idx[0]]) < 0) for (let k = 0; k < idx.length; k += 3) { const t = idx[k + 1]; idx[k + 1] = idx[k + 2]; idx[k + 2] = t }
  }
  return meshGeometry(P, N, U, idx)
}

/// BufferGeometry from arrays of [x,y,z] positions/normals, [u,v] uvs and triangle indices.
/// UV v is flipped (1 - v) so textures read the same way as in SceneKit.
export function meshGeometry(P, N, U, I) {
  const g = new THREE.BufferGeometry()
  const pa = new Float32Array(P.length * 3), na = new Float32Array(P.length * 3), ua = new Float32Array(P.length * 2)
  for (let i = 0; i < P.length; i++) {
    pa[i * 3] = P[i][0]; pa[i * 3 + 1] = P[i][1]; pa[i * 3 + 2] = P[i][2]
    na[i * 3] = N[i][0]; na[i * 3 + 1] = N[i][1]; na[i * 3 + 2] = N[i][2]
    ua[i * 2] = U[i][0]; ua[i * 2 + 1] = 1 - U[i][1]
  }
  g.setAttribute('position', new THREE.BufferAttribute(pa, 3))
  g.setAttribute('normal', new THREE.BufferAttribute(na, 3))
  g.setAttribute('uv', new THREE.BufferAttribute(ua, 2))
  g.setIndex(P.length > 65535 ? new THREE.BufferAttribute(new Uint32Array(I), 1) : new THREE.BufferAttribute(new Uint16Array(I), 1))
  g.computeBoundingSphere()
  return g
}

export function mesh(g, m, { shadow = true } = {}) {
  const o = new THREE.Mesh(g, m)
  o.castShadow = shadow; o.receiveShadow = true
  return o
}

/// A mesh lofted through rings with one material.
export function loftNode(rings, m, { seg = 22, ref = [0, 0, 1], smooth = 4, vScale = 1, displace = null } = {}) {
  return mesh(loft(smooth > 1 ? smoothRings(rings, smooth) : rings, { seg, ref, vScale, displace }), m)
}

/// A limb hanging from its joint (origin) along `dir` (default straight down) by `len`, tapering.
export function limb(len_, r0, r1, m, { depth = 1, bulge = 0.1, seg = 16, dir = [0, -1, 0] } = {}) {
  const d = norm(dir)
  const rings = [Ring(scale(d, -r0 * 0.6), r0 * 0.5, r0 * 0.5 * depth),
    Ring(scale(d, -r0 * 0.1), r0 * 0.95, r0 * 0.95 * depth),
    Ring(scale(d, len_ * 0.3), r0 * (1 + bulge), r0 * (1 + bulge) * depth),
    Ring(scale(d, len_ * 0.75), mix(r0, r1, 0.7), mix(r0, r1, 0.7) * depth),
    Ring(scale(d, len_), r1, r1 * depth),
    Ring(scale(d, len_ + r1 * 0.6), r1 * 0.5, r1 * 0.5 * depth)]
  return loftNode(rings, m, { seg, ref: Math.abs(d[2]) > 0.9 ? [0, 1, 0] : [0, 0, 1], smooth: 3 })
}

const geoCache = new Map()
function cached(key, make) { let g = geoCache.get(key); if (!g) { g = make(); geoCache.set(key, g) } return g }

export const sphereNode = (r, m, seg = 24) => mesh(cached(`s${r}|${seg}`, () => new THREE.SphereGeometry(r, seg, Math.max(6, seg >> 1))), m)
export const boxNode = (w, h, l, m) => mesh(cached(`b${w}|${h}|${l}`, () => new THREE.BoxGeometry(w, h, l)), m)
export const cylNode = (r, h, m, seg = 24) => mesh(cached(`c${r}|${h}|${seg}`, () => new THREE.CylinderGeometry(r, r, h, seg)), m)
/// coneNode(bottomRadius, topRadius, height, m)
export const coneNode = (r0, r1, h, m, seg = 20) => mesh(cached(`k${r0}|${r1}|${h}|${seg}`, () => new THREE.CylinderGeometry(r1, r0, h, seg)), m)
export const torusNode = (ring, pipe, m, seg = 24, pseg = 8) => mesh(cached(`t${ring}|${pipe}|${seg}`, () => new THREE.TorusGeometry(ring, pipe, pseg, seg).rotateX(Math.PI / 2)), m)
/// SCNTube equivalent: a ring with thickness, axis along y.
export function tubeNode(inner, outer, h, m, seg = 32) {
  const g = cached(`u${inner}|${outer}|${h}|${seg}`, () => {
    const shape = new THREE.Shape(); shape.absarc(0, 0, outer, 0, Math.PI * 2, false)
    const hole = new THREE.Path(); hole.absarc(0, 0, inner, 0, Math.PI * 2, true); shape.holes.push(hole)
    const eg = new THREE.ExtrudeGeometry(shape, { depth: h, bevelEnabled: false, curveSegments: seg })
    eg.rotateX(-Math.PI / 2); eg.translate(0, -h / 2, 0)
    return eg
  })
  return mesh(g, m)
}

/// Group helpers mirroring the Swift .at() .rot() .scl() chain. Rotation order matches SceneKit (YXZ).
export function at(o, x, y, z) { o.position.set(x, y, z); return o }
export function rot(o, x, y, z) { o.rotation.order = 'YXZ'; o.rotation.set(x, y, z); return o }
export function scl(o, x, y, z) { o.scale.set(x, y, z); return o }
export function group() { const g = new THREE.Group(); g.rotation.order = 'YXZ'; return g }
export function setEuler(o, x, y, z) { o.rotation.order = 'YXZ'; o.rotation.set(x, y, z) }
