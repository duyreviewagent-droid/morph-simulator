// The playable world: terrain, buildings, colliders, grass. Ported from World.swift.
// Coordinates match SceneKit: y up, +z forward, metres.
import * as THREE from '../vendor/three.module.js'
import { RNG, Noise, smoothstep, mix3, clamp, QUALITY } from './util.js'
import { pbr } from './tex.js'
import { Ring, meshGeometry, mesh, loftNode, limb, sphereNode, boxNode, cylNode, coneNode } from './loft.js'
import { Mat, Coats } from './mats.js'
import { Maps, FastNoise } from './maps.js'
import { Foliage } from './foliage.js'
import { MapBuilder } from './mapbuilder.js'
import { buildPhysics, buildKnockables, syncKnockables, resetKnockable, removeKnockable, disposePhysics } from './knock.js'

export { makePusher, GROUP, groups, KnockKit, Knockable } from './knock.js'

export const Surface = Object.freeze({ grass: 'grass', dirt: 'dirt', wood: 'wood', metal: 'metal', hay: 'hay', concrete: 'concrete', water: 'water' })

// ---------------------------------------------------------------------------------------------
// MARK: small helpers (shared with mapbuilder.js)

/// Position (and optionally YXZ euler, like simdEulerAngles) in one call. Returns o.
export function P(o, x, y, z, rx, ry, rz) {
  o.position.set(x, y, z)
  if (rx !== undefined) { o.rotation.order = 'YXZ'; o.rotation.set(rx, ry, rz) }
  return o
}
export function R(o, rx, ry, rz) { o.rotation.order = 'YXZ'; o.rotation.set(rx, ry, rz); return o }
export function S(o, sx, sy, sz) { o.scale.set(sx, sy, sz); return o }
export function G() { const g = new THREE.Group(); g.rotation.order = 'YXZ'; return g }

/// Uncached primitives for one-off static scenery (it is merged and the sources dropped, so caching
/// thousands of random sizes would only leak). Same conventions as loft.js.
export const Prim = {
  box: (w, h, l, m) => mesh(new THREE.BoxGeometry(w, h, l), m),
  cyl: (r, h, m, seg = 24) => mesh(new THREE.CylinderGeometry(r, r, h, seg), m),
  cone: (r0, r1, h, m, seg = 20) => mesh(new THREE.CylinderGeometry(r1, r0, h, seg), m),
  sphere: (r, m, seg = 24) => mesh(new THREE.SphereGeometry(r, seg, Math.max(6, seg >> 1)), m),
  torus: (ring, pipe, m, seg = 24, pseg = 8) => mesh(new THREE.TorusGeometry(ring, pipe, pseg, seg).rotateX(Math.PI / 2), m),
  plane: (w, h, m) => mesh(new THREE.PlaneGeometry(w, h), m),
  tube(inner, outer, h, m, seg = 32) {
    const shape = new THREE.Shape(); shape.absarc(0, 0, outer, 0, Math.PI * 2, false)
    const hole = new THREE.Path(); hole.absarc(0, 0, inner, 0, Math.PI * 2, true); shape.holes.push(hole)
    const g = new THREE.ExtrudeGeometry(shape, { depth: h, bevelEnabled: false, curveSegments: seg })
    g.rotateX(-Math.PI / 2); g.translate(0, -h / 2, 0)
    return mesh(g, m)
  },
}

/// Texture.clone() JSON-copies userData, and tex.js tiled() keeps the owning material there (circular).
export function cloneTex(t) {
  const ud = t.userData
  t.userData = {}
  const c = t.clone()
  t.userData = ud
  c.needsUpdate = true
  return c
}

/// tex.js tiled() for a cloned material, without Texture.clone()'s userData copy (see cloneTex).
export function retile(m, su, sv) {
  const done = new Map()
  for (const k of ['map', 'normalMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'emissiveMap']) {
    const t = m[k]
    if (!t) continue
    if (!done.has(t)) { const c = cloneTex(t); c.repeat.set(su, sv); c.wrapS = c.wrapT = THREE.RepeatWrapping; done.set(t, c) }
    m[k] = done.get(t)
  }
  return m
}

const blade = (lo, hi) => (lo ? Mat.grassBlade(lo, hi) : Mat.grassBladeDefault)

// ---------------------------------------------------------------------------------------------
// MARK: colliders

/// A static collider. Axis-aligned footprint (or a cylinder) with a top that can slope (roofs).
export class Solid {
  constructor({ minX, maxX, minZ, maxZ, bottom = -5, top, round = null, tag = '', surface = 'wood', walkable = true }) {
    this.minX = minX; this.maxX = maxX; this.minZ = minZ; this.maxZ = maxZ
    this.bottom = bottom; this.top = top; this.round = round
    this.tag = tag; this.surface = surface; this.walkable = walkable
  }
  static box(cx, cz, w, l, h, { base = 0, tag = '', surface = 'wood' } = {}) {
    return new Solid({ minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - l / 2, maxZ: cz + l / 2, bottom: base, top: () => base + h, tag, surface })
  }
  static cyl(cx, cz, r, h, { base = 0, tag = '', surface = 'concrete' } = {}) {
    return new Solid({ minX: cx - r, maxX: cx + r, minZ: cz - r, maxZ: cz + r, bottom: base, top: () => base + h, round: { cx, cz, r }, tag, surface })
  }
  /// Signed horizontal distance from the footprint edge (negative inside); the outward direction goes to `out` {x, z}.
  edge(x, z, out = EDGE_N) {
    const r = this.round
    if (r) {
      const dx = x - r.cx, dz = z - r.cz, l = Math.hypot(dx, dz)
      if (l > 1e-5) { out.x = dx / l; out.z = dz / l } else { out.x = 1; out.z = 0 }
      return l - r.r
    }
    const cx = (this.minX + this.maxX) / 2, cz = (this.minZ + this.maxZ) / 2
    const hx = (this.maxX - this.minX) / 2, hz = (this.maxZ - this.minZ) / 2
    const qx = Math.abs(x - cx) - hx, qz = Math.abs(z - cz) - hz
    if (qx > 0 || qz > 0) {
      const ox = Math.max(qx, 0), oz = Math.max(qz, 0)
      const l = Math.sqrt(ox * ox + oz * oz)
      const dx = ox * (x < cx ? -1 : 1), dz = oz * (z < cz ? -1 : 1)
      if (l > 1e-6) { out.x = dx / l; out.z = dz / l } else { out.x = 1; out.z = 0 }
      return l
    }
    // inside: push out through the nearest side
    if (qx > qz) { out.x = x < cx ? -1 : 1; out.z = 0; return qx }
    out.x = 0; out.z = z < cz ? -1 : 1; return qz
  }
}
const EDGE_N = { x: 0, z: 0 }

// ---------------------------------------------------------------------------------------------
// MARK: farm layout

const inRun = (x, z) => x > Farm.coopRun.minX && x < Farm.coopRun.maxX && z > Farm.coopRun.minZ && z < Farm.coopRun.maxZ
const inPasture = (x, z) => x > Farm.pasture.minX && x < Farm.pasture.maxX && z > Farm.pasture.minZ && z < Farm.pasture.maxZ
function seg(x, z, ax, az, bx, bz) {
  const abx = bx - ax, abz = bz - az
  const t = clamp(((x - ax) * abx + (z - az) * abz) / (abx * abx + abz * abz), 0, 1)
  return Math.hypot(x - (ax + abx * t), z - (az + abz * t))
}

/// Places on the farm the game logic cares about.
export const Farm = {
  barn: { x: -20, z: -12, len: 18, wid: 12, eave: 6.5, ridge: 10.5 },
  silo: { x: -7.5, z: -15.5, r: 3, h: 15 },
  coopRun: { minX: 11, maxX: 25, minZ: -21, maxZ: -8 },
  coopHouse: { x: 21.5, z: -17.5 },
  pasture: { minX: 32, maxX: 80, minZ: -26, maxZ: 36 },
  pastureGate: { z0: 1, z1: 6 },
  coopGate: { x0: 15, x1: 17.5 },
  house: { x: -4, z: 28, w: 12, d: 9, eave: 5.2, ridge: 8 },
  pond: { x: -34, z: 24, r: 9 },
  pondWater: -0.35,
  appleTree: { x: 10, z: 17 },
  pumpkinPatch: { x: 15, z: 29 },
  trough: { x: 38, z: 9 },
  tractor: { x: -7, z: 3 },
  half: 236,

  /// p is anything with x and z (THREE.Vector3 works).
  inRun: p => inRun(p.x, p.z),
  inPasture: p => inPasture(p.x, p.z),

  /// Distance to the dirt tracks that link the yard to everything.
  pathDist(x, z) {
    let d = seg(x, z, -2, 2, -4, 22)                        // yard → porch
    d = Math.min(d, seg(x, z, -2, 2, 33, 3.5))              // yard → pasture gate
    d = Math.min(d, seg(x, z, 33, 3.5, 60, 3.5) + 0.6)      // cow track into the pasture
    d = Math.min(d, seg(x, z, 4, -3, 16, -8))               // yard → coop gate
    d = Math.min(d, seg(x, z, -2, 2, -11, -12))             // yard → barn door
    d = Math.min(d, seg(x, z, -4, 22, -4, 60) + 0.5)        // lane out to the road
    return d
  },

  yardDist: (x, z) => Math.hypot(x + 3, (z + 3) * 1.3),

  /// Terrain height. Flat around the buildings, rolling beyond.
  height(x, z) {
    const far = smoothstep(40, 95, Math.hypot(x - 10, z - 5))
    let h = FastNoise.fbm(x * 0.011, z * 0.011, 4, 3) * 9 * far
    h += FastNoise.fbm(x * 0.06, z * 0.06, 3, 4) * 0.25 * (0.3 + far)
    // the pasture dips gently toward the pond side
    if (inPasture(x, z)) h += FastNoise.fbm(x * 0.03, z * 0.03, 2, 9) * 0.6
    const pd = Math.hypot(x - Farm.pond.x, z - Farm.pond.z)
    h -= 1.5 * smoothstep(Farm.pond.r + 2.5, 1, pd)
    return h
  },

  groundColor(x, z) {
    const n1 = FastNoise.fbm(x * 0.05, z * 0.05, 4, 21)
    const n2 = FastNoise.fbm(x * 0.4, z * 0.4, 3, 22)
    const dry = smoothstep(0.0, 0.5, FastNoise.fbm(x * 0.02, z * 0.02, 3, 23))
    let c = mix3([0.13, 0.24, 0.05], [0.22, 0.29, 0.08], n1 * 0.5 + 0.5)
    c = mix3(c, [0.32, 0.31, 0.13], dry * 0.45)
    const k = 0.92 + n2 * 0.12
    c = [c[0] * k, c[1] * k, c[2] * k]
    if (inPasture(x, z)) c = mix3(c, [0.14, 0.27, 0.06], 0.35)
    // tracks: two wheel ruts with grass down the middle
    const pd = Farm.pathDist(x, z)
    const dk = 0.85 + n2 * 0.2
    const dirt = [0.36 * dk, 0.28 * dk, 0.19 * dk]
    const rut = smoothstep(1.6, 1.1, pd) * (1 - smoothstep(0.35, 0.15, pd) * 0.6)
    c = mix3(c, dirt, rut * (0.8 + n2 * 0.2))
    // gravel yard
    const yd = Farm.yardDist(x, z)
    const gk = 0.8 + Noise.cell(Math.trunc(x * 12), Math.trunc(z * 12), 3) * 0.3
    c = mix3(c, [0.42 * gk, 0.39 * gk, 0.34 * gk], smoothstep(11 + n1 * 3, 8 + n1 * 3, yd))
    // bare, pecked earth in the coop run
    if (inRun(x, z)) { const rk = 0.85 + n2 * 0.25; c = mix3(c, [0.3 * rk, 0.24 * rk, 0.16 * rk], 0.75 + n2 * 0.2) }
    // mud at the pasture gate and around the trough
    const mud = Math.max(smoothstep(4, 1.5, Math.hypot(x - 33, z - 3.5)), smoothstep(4.5, 2, Math.hypot(x - Farm.trough.x, z - Farm.trough.z)))
    c = mix3(c, [0.2, 0.15, 0.1], mud * 0.85)
    // pond shore
    const pd2 = Math.hypot(x - Farm.pond.x, z - Farm.pond.z)
    c = mix3(c, [0.24, 0.2, 0.13], smoothstep(Farm.pond.r + 1.5, Farm.pond.r - 1, pd2))
    return c
  },

  isGrass(x, z) {
    return Farm.pathDist(x, z) > 1.8 && Farm.yardDist(x, z) > 11 && !inRun(x, z) && Math.hypot(x - Farm.pond.x, z - Farm.pond.z) > Farm.pond.r + 1.5
  },
}

// ---------------------------------------------------------------------------------------------
// MARK: geometry helpers

const v3sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const v3cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const v3dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const v3norm = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l] }

const meterCache = new Map()
/// A box whose UVs are in metres × `uv`, so tiled materials keep their real-world scale.
export function meterBox(w, h, l, m, uv = 0.25) {
  const key = `${w}|${h}|${l}|${uv}`
  let g = meterCache.get(key)
  if (!g) {
    const Pp = [], N = [], U = [], I = []
    const hx = w / 2, hy = h / 2, hz = l / 2
    const face = (o, a, b, n, la, lb) => {
      const i = Pp.length
      Pp.push([o[0] - a[0] - b[0], o[1] - a[1] - b[1], o[2] - a[2] - b[2]], [o[0] + a[0] - b[0], o[1] + a[1] - b[1], o[2] + a[2] - b[2]],
        [o[0] + a[0] + b[0], o[1] + a[1] + b[1], o[2] + a[2] + b[2]], [o[0] - a[0] + b[0], o[1] - a[1] + b[1], o[2] - a[2] + b[2]])
      N.push(n, n, n, n)
      U.push([0, lb * uv], [la * uv, lb * uv], [la * uv, 0], [0, 0])
      I.push(i, i + 1, i + 2, i, i + 2, i + 3)
    }
    face([0, 0, hz], [hx, 0, 0], [0, hy, 0], [0, 0, 1], w, h)
    face([0, 0, -hz], [-hx, 0, 0], [0, hy, 0], [0, 0, -1], w, h)
    face([hx, 0, 0], [0, 0, -hz], [0, hy, 0], [1, 0, 0], l, h)
    face([-hx, 0, 0], [0, 0, hz], [0, hy, 0], [-1, 0, 0], l, h)
    face([0, hy, 0], [hx, 0, 0], [0, 0, -hz], [0, 1, 0], w, l)
    face([0, -hy, 0], [hx, 0, 0], [0, 0, hz], [0, -1, 0], w, l)
    g = meshGeometry(Pp, N, U, I)
    if (meterCache.size < 4000) meterCache.set(key, g)
  }
  return mesh(g, m)
}

/// A flat convex polygon (fan) with metric UVs. pts are [x,y,z].
export function poly(pts, m, uv = 0.25) {
  const n = v3norm(v3cross(v3sub(pts[1], pts[0]), v3sub(pts[2], pts[0])))
  const ax = v3norm(v3sub(pts[1], pts[0])), ay = v3cross(n, ax)
  const N = pts.map(() => n)
  const U = pts.map(p => [v3dot(v3sub(p, pts[0]), ax) * uv, -v3dot(v3sub(p, pts[0]), ay) * uv])
  const I = []
  for (let k = 1; k < pts.length - 1; k++) I.push(0, k, k + 1)
  return mesh(meshGeometry(pts, N, U, I), m)
}

// ---------------------------------------------------------------------------------------------
// MARK: static merge

const _v = new THREE.Vector3(), _n = new THREE.Vector3(), _nm = new THREE.Matrix3()

function matKey(m) {
  const plain = !m.map && !m.normalMap && !m.roughnessMap && !m.metalnessMap && !m.alphaMap && !m.emissiveMap &&
    !Object.prototype.hasOwnProperty.call(m, 'onBeforeCompile') && (m.isMeshStandardMaterial || m.isMeshLambertMaterial)
  if (!plain) return m.uuid
  return [m.type, m.color.getHexString(), m.roughness, m.metalness, m.emissive ? m.emissive.getHexString() : '', m.emissiveIntensity,
    m.opacity, m.transparent, m.side, m.clearcoat || 0, m.alphaTest].join('|')
}

/// Collapses every mesh under `src` into one mesh per (material, shadow flag, 64 m map cell) under `dst`.
/// Static scenery goes from thousands of draw calls to a few hundred, and the cells keep frustum culling useful.
export function mergeStatic(src, dst, owned, cell = 64) {
  src.updateMatrixWorld(true)
  const buckets = new Map(), canon = new Map()
  const keep = []
  src.traverse(o => {
    if (!o.isMesh || !o.visible || !o.geometry || !o.geometry.attributes.position) return
    const g = o.geometry
    if (!g.boundingSphere) g.computeBoundingSphere()
    const c = _v.copy(g.boundingSphere.center).applyMatrix4(o.matrixWorld)
    const rad = g.boundingSphere.radius * o.matrixWorld.getMaxScaleOnAxis()
    if (rad > 48 || o.userData.noMerge || Array.isArray(o.material)) { keep.push(o); return }
    const mk = matKey(o.material)
    if (!canon.has(mk)) canon.set(mk, o.material)
    const cast = o.castShadow && rad > 0.12
    const key = mk + '|' + cast + '|' + Math.floor(c.x / cell) + ',' + Math.floor(c.z / cell)
    let b = buckets.get(key)
    if (!b) { b = { mat: canon.get(mk), cast, items: [], verts: 0, idx: 0 }; buckets.set(key, b) }
    const nv = g.attributes.position.count
    b.items.push(o); b.verts += nv; b.idx += g.index ? g.index.count : nv
  })
  for (const b of buckets.values()) {
    const pos = new Float32Array(b.verts * 3), nor = new Float32Array(b.verts * 3), uvs = new Float32Array(b.verts * 2)
    const index = b.verts > 65535 ? new Uint32Array(b.idx) : new Uint16Array(b.idx)
    let vo = 0, io = 0
    for (const o of b.items) {
      const g = o.geometry, M = o.matrixWorld
      _nm.getNormalMatrix(M)
      const pa = g.attributes.position, na = g.attributes.normal, ua = g.attributes.uv
      const nv = pa.count
      for (let i = 0; i < nv; i++) {
        _v.fromBufferAttribute(pa, i).applyMatrix4(M)
        pos[(vo + i) * 3] = _v.x; pos[(vo + i) * 3 + 1] = _v.y; pos[(vo + i) * 3 + 2] = _v.z
        if (na) {
          _n.fromBufferAttribute(na, i).applyMatrix3(_nm).normalize()
          nor[(vo + i) * 3] = _n.x; nor[(vo + i) * 3 + 1] = _n.y; nor[(vo + i) * 3 + 2] = _n.z
        } else nor[(vo + i) * 3 + 1] = 1
        if (ua) { uvs[(vo + i) * 2] = ua.getX(i); uvs[(vo + i) * 2 + 1] = ua.getY(i) }
      }
      const flip = M.determinant() < 0
      if (g.index) {
        const ia = g.index.array, n = g.index.count
        for (let k = 0; k < n; k += 3) {
          index[io++] = ia[k] + vo
          index[io++] = (flip ? ia[k + 2] : ia[k + 1]) + vo
          index[io++] = (flip ? ia[k + 1] : ia[k + 2]) + vo
        }
      } else {
        for (let k = 0; k < nv; k += 3) {
          index[io++] = vo + k; index[io++] = vo + (flip ? k + 2 : k + 1); index[io++] = vo + (flip ? k + 1 : k + 2)
        }
      }
      vo += nv
    }
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    g.setAttribute('normal', new THREE.BufferAttribute(nor, 3))
    g.setAttribute('uv', new THREE.BufferAttribute(uvs, 2))
    g.setIndex(new THREE.BufferAttribute(index, 1))
    g.computeBoundingSphere()
    g.computeBoundingBox()
    owned.push(g)
    const m = new THREE.Mesh(g, b.mat)
    m.castShadow = b.cast; m.receiveShadow = true
    m.matrixAutoUpdate = false
    dst.add(m)
  }
  for (const o of keep) {
    const m = new THREE.Mesh(o.geometry, o.material)
    m.castShadow = o.castShadow; m.receiveShadow = o.receiveShadow
    m.matrixAutoUpdate = false
    m.matrix.copy(o.matrixWorld)
    dst.add(m)
  }
  return { meshes: dst.children.length, buckets: buckets.size, kept: keep.length }
}

// ---------------------------------------------------------------------------------------------
// MARK: World

/// Rows r0..r1 of the macro colour map for a map (pure function of the map; also runs inside workers).
/// DataTexture row r sits at uv.y = (r + 0.5) / W and the terrain's uv.y = 1 - (z + H) / 2H.
export function macroRows(mapIndex, W, H, r0, r1) {
  const color = mapIndex === 0 ? Farm.groundColor : Maps.all[mapIndex].color
  const data = new Uint8Array((r1 - r0) * W * 4)
  let p = 0
  for (let r = r0; r < r1; r++) {
    const z = H - (r + 0.5) / W * 2 * H
    for (let px = 0; px < W; px++) {
      const c = color(-H + (px + 0.5) / W * 2 * H, z)
      data[p] = clamp(c[0], 0, 1) * 255 + 0.5; data[p + 1] = clamp(c[1], 0, 1) * 255 + 0.5; data[p + 2] = clamp(c[2], 0, 1) * 255 + 0.5; data[p + 3] = 255
      p += 4
    }
  }
  return data
}

function macroTexture(data, W) {
  const t = new THREE.DataTexture(data, W, W, THREE.RGBAFormat)
  t.colorSpace = THREE.SRGBColorSpace
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter
  t.generateMipmaps = true; t.anisotropy = 8
  t.needsUpdate = true
  return t
}

// When this file runs as a module worker it only computes macro-map rows.
if (typeof WorkerGlobalScope !== 'undefined' && typeof self !== 'undefined' && self instanceof WorkerGlobalScope) {
  self.onmessage = e => {
    const d = e.data
    if (!d || !d.macro) return
    const data = macroRows(d.mapIndex, d.W, d.H, d.r0, d.r1)
    self.postMessage({ r0: d.r0, data: data.buffer }, [data.buffer])
  }
}

const GRID_CELL = 8, GRID_MARGIN = 3

export class World {
  /// Builds everything synchronously. RAPIER/physicsWorld may be null (no physics bodies are made).
  constructor(mapIndex = 0, RAPIER = null, physicsWorld = null) {
    this.root = new THREE.Group(); this.root.name = 'world'
    this.solids = []
    this.ladders = []
    this.water = null
    this.cornPiles = []
    this.static_ = new THREE.Group()           // build-time scene graph; merged into staticRoot
    this.staticRoot = new THREE.Group(); this.staticRoot.name = 'static'; this.staticRoot.matrixAutoUpdate = false
    this.grassRoot = new THREE.Group(); this.grassRoot.name = 'grass'
    this.knockRoot = new THREE.Group(); this.knockRoot.name = 'knockables'
    this.knockables = []
    this.terrainNode = null
    this.mapIndex = mapIndex
    this.map = Maps.all[mapIndex]
    this.R = RAPIER; this.physics = physicsWorld
    this._bodies = []
    this._owned = []                           // geometries/textures to free on dispose
    this._grid = null; this._gridCount = -1
    this.stats = {}

    const t0 = now()
    this.buildTerrain()
    const t1 = now()
    if (mapIndex !== 0) {
      MapBuilder.build(this)
      this.buildWater()
    } else {
      this.buildBarn(); this.buildSilo(); this.buildHayStairs(); this.buildCoop(); this.buildPasture()
      this.buildHouse(); this.buildPond(); this.buildTractor(); this.buildTrees(); this.buildMisc()
    }
    this.buildGrass()
    this.buildHills()
    this.addEdges()
    const t2 = now()
    this.finish()
    this.stats.ms = { terrain: Math.round(t1 - t0), scenery: Math.round(t2 - t1), finish: Math.round(now() - t2) }
  }

  get isFarm() { return this.mapIndex === 0 }

  finish() {
    this.stats.merge = mergeStatic(this.static_, this.staticRoot, this._owned)
    this.static_ = null
    this.root.add(this.staticRoot)
    this.root.add(this.knockRoot)
    this.buildGrid()
    if (this.R && this.physics) buildPhysics(this)
    buildKnockables(this)
  }

  addEdges() {
    // invisible boundary. Swift used a fixed 60 m wall (top at y = 40); the Mountains' border peaks reach ~54 m,
    // so the wall is raised to clear the highest terrain along the edge.
    const H = Farm.half
    let top = 40
    for (let t = -H - 2; t <= H + 2; t += 2) for (const [x, z] of [[t, -H - 1], [t, H + 1], [-H - 1, t], [H + 1, t]]) top = Math.max(top, this.terrain(x, z) + 30)
    for (const [cx, cz, w, l] of [[0, -H - 1, 2 * H + 4, 2], [0, H + 1, 2 * H + 4, 2], [-H - 1, 0, 2, 2 * H + 4], [H + 1, 0, 2, 2 * H + 4]]) {
      const s = Solid.box(cx, cz, w, l, top + 20, { base: -20, tag: 'edge' })
      s.walkable = false
      this.solids.push(s)
    }
  }

  add(n) { this.static_.add(n); return n }

  // MARK: queries

  terrain(x, z) { return this.mapIndex === 0 ? Farm.height(x, z) : this.map.height(x, z) }
  groundColor(x, z) { return this.mapIndex === 0 ? Farm.groundColor(x, z) : this.map.color(x, z) }
  isGrass(x, z) {
    if (this.mapIndex === 0) return Farm.isGrass(x, z)
    const w = this.map.waterLevel
    if (w !== null && this.terrain(x, z) < w + 0.1) return false
    return this.map.grass(x, z)
  }
  /// Water surface height here, if (x, z) is under water; otherwise null.
  waterLevel(x, z) {
    if (this.mapIndex === 0) {
      return Math.hypot(x - Farm.pond.x, z - Farm.pond.z) < Farm.pond.r + 1 && Farm.height(x, z) < Farm.pondWater ? Farm.pondWater : null
    }
    const w = this.map.waterLevel
    if (w !== null && this.terrain(x, z) < w) return w
    return null
  }

  /// Spatial hash of solids (8 m cells) so ground/collide don't scan every tree on the map.
  buildGrid() {
    const H = Farm.half + 12, n = Math.ceil(2 * H / GRID_CELL)
    const cells = new Array(n * n)
    for (let i = 0; i < cells.length; i++) cells[i] = []
    this.solids.forEach((s, idx) => {
      const x0 = Math.max(0, Math.floor((s.minX - GRID_MARGIN + H) / GRID_CELL)), x1 = Math.min(n - 1, Math.floor((s.maxX + GRID_MARGIN + H) / GRID_CELL))
      const z0 = Math.max(0, Math.floor((s.minZ - GRID_MARGIN + H) / GRID_CELL)), z1 = Math.min(n - 1, Math.floor((s.maxZ + GRID_MARGIN + H) / GRID_CELL))
      for (let j = z0; j <= z1; j++) for (let i = x0; i <= x1; i++) cells[j * n + i].push(idx)
    })
    this._grid = { H, n, cells }
    this._gridCount = this.solids.length
  }
  /// Solids that might touch a circle of radius r at (x, z), in insertion order.
  candidates(x, z, r) {
    if (this._gridCount !== this.solids.length) this.buildGrid()
    const g = this._grid
    const i = Math.floor((x + g.H) / GRID_CELL), j = Math.floor((z + g.H) / GRID_CELL)
    if (r > GRID_MARGIN || i < 0 || j < 0 || i >= g.n || j >= g.n) return null
    return g.cells[j * g.n + i]
  }

  /// Highest standing surface under (x, z) that's no more than `step` above `y`. Returns { g, surf, tag }.
  ground(x, z, y, r, step = 0.5) {
    let g = this.terrain(x, z)
    let surf
    if (this.mapIndex === 0) surf = Farm.isGrass(x, z) ? 'grass' : 'dirt'
    else if (this.isGrass(x, z)) surf = 'grass'
    else { const s = this.map.surface(x, z); surf = s === 'grass' ? 'dirt' : s }
    let tag = ''
    if (this.waterLevel(x, z) !== null) surf = 'water'
    const list = this.candidates(x, z, r), solids = this.solids
    const n = list ? list.length : solids.length
    for (let k = 0; k < n; k++) {
      const s = list ? solids[list[k]] : solids[k]
      if (!s.walkable) continue
      if (!(x > s.minX - r && x < s.maxX + r && z > s.minZ - r && z < s.maxZ + r)) continue
      const d = s.edge(x, z)
      if (!(d < r * 0.4)) continue
      const t = s.top(clamp(x, s.minX, s.maxX), clamp(z, s.minZ, s.maxZ))
      if (t <= y + step && t > g) { g = t; surf = s.surface; tag = s.tag }
    }
    return { g, surf, tag }
  }

  /// Pushes a cylinder (feet at p.y, height h) out of every solid it is inside of. p is mutated. Returns true on a hit.
  collide(p, r, h, step = 0.5) {
    let hit = false
    const list = this.candidates(p.x, p.z, r), solids = this.solids
    const n = list ? list.length : solids.length
    for (let k = 0; k < n; k++) {
      const s = list ? solids[list[k]] : solids[k]
      if (!(p.x > s.minX - r && p.x < s.maxX + r && p.z > s.minZ - r && p.z < s.maxZ + r)) continue
      const d = s.edge(p.x, p.z, EDGE_N)
      if (!(d < r)) continue
      const t = s.top(clamp(p.x, s.minX, s.maxX), clamp(p.z, s.minZ, s.maxZ))
      if (p.y >= t - (s.walkable ? step : 0)) continue
      if (p.y + h < s.bottom) continue
      const push = r - d
      p.x += EDGE_N.x * push; p.z += EDGE_N.z * push
      hit = true
    }
    return hit
  }

  ladder(p, r) {
    for (const l of this.ladders) if (Math.hypot(p.x - l.x, p.z - l.z) < r + 0.45 && p.y < l.top + 0.3) return l
    return null
  }

  // MARK: knockables (physics lives in knock.js)

  syncKnockables() { syncKnockables(this) }
  resetKnockable(k) { resetKnockable(this, k) }
  removeKnockable(k) { removeKnockable(this, k) }
  /// The knockable owning a Rapier collider handle (for contact events), or undefined.
  knockableFromCollider(handle) { return this._knockByCollider ? this._knockByCollider.get(handle) : undefined }

  dispose() {
    this._disposed = true
    if (this._workers) { this._workers.forEach(w => w.terminate()); this._workers = null }
    disposePhysics(this)
    this.root.removeFromParent()
    for (const o of this._owned) o.dispose()
    this._owned.length = 0
  }

  // MARK: terrain

  buildTerrain() {
    const H = Farm.half + 4
    const N = 320
    const step = 2 * H / N
    const nv = (N + 1) * (N + 1)
    const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2)
    const heights = new Float32Array(nv)        // row j (z) major, for the physics heightfield
    const e = 0.5
    for (let j = 0; j <= N; j++) {
      for (let i = 0; i <= N; i++) {
        const x = -H + i * step, z = -H + j * step
        const k = j * (N + 1) + i
        const y = this.terrain(x, z)
        heights[k] = y
        pos[k * 3] = x; pos[k * 3 + 1] = y; pos[k * 3 + 2] = z
        const dx = this.terrain(x + e, z) - this.terrain(x - e, z), dz = this.terrain(x, z + e) - this.terrain(x, z - e)
        const l = Math.hypot(dx, 2 * e, dz)
        nor[k * 3] = -dx / l; nor[k * 3 + 1] = 2 * e / l; nor[k * 3 + 2] = -dz / l
        uv[k * 2] = (x + H) / (2 * H); uv[k * 2 + 1] = 1 - (z + H) / (2 * H)    // v flipped like meshGeometry
      }
    }
    const idx = new Uint32Array(N * N * 6)
    let o = 0
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const a = j * (N + 1) + i, b = a + 1, c = a + N + 1, d = c + 1
      idx[o++] = a; idx[o++] = c; idx[o++] = b; idx[o++] = b; idx[o++] = c; idx[o++] = d
    }
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    g.setAttribute('normal', new THREE.BufferAttribute(nor, 3))
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2))
    g.setIndex(new THREE.BufferAttribute(idx, 1))
    g.computeBoundingSphere()
    this._owned.push(g)
    this.terrainGrid = { H, N, step, heights }

    // the big macro colour map: one texel ≈ 15 cm on desktop (3072²), half that resolution on tablets.
    // In a browser the build stays synchronous with a quarter-res map, and module workers (this same file)
    // compute the full map in parallel, like Swift's concurrentPerform; it swaps in when done (`this.ready`).
    const W = QUALITY >= 1 ? 3072 : Math.round(3072 * Math.max(QUALITY, 0.5))
    const async = typeof window !== 'undefined' && typeof Worker !== 'undefined' && !World.syncTextures
    const W0 = async ? W / 4 : W
    const macro = macroTexture(macroRows(this.mapIndex, W0, H, 0, W0), W0)
    this._owned.push(macro)
    this.terrainTexture = { size: W0, full: W0 === W }
    this.ready = async ? this.refineMacro(W, H) : Promise.resolve(this)

    const det = Mat.grassDetail
    const rep = 2 * H / 3
    const m = new THREE.MeshStandardMaterial({ map: macro, roughness: this.map.groundRough, metalness: 0 })
    if (det.normalMap) {
      m.normalMap = cloneTex(det.normalMap)
      m.normalMap.wrapS = m.normalMap.wrapT = THREE.RepeatWrapping
      m.normalMap.repeat.set(rep, rep); m.normalMap.anisotropy = 8
      m.normalScale.set(0.8, 0.8)
      this._owned.push(m.normalMap)
    }
    // SceneKit `multiply`: the 3 m grass detail texture darkens/lightens the macro colour
    const detailK = this.mapIndex === 2 ? 0.35 : 1
    if (det.map) {
      const uniforms = { uDetail: { value: det.map }, uDetailRep: { value: rep }, uDetailK: { value: detailK } }
      m.defines = { USE_UV: '' }
      m.onBeforeCompile = sh => {
        Object.assign(sh.uniforms, uniforms)
        sh.fragmentShader = sh.fragmentShader
          .replace('#include <common>', '#include <common>\nuniform sampler2D uDetail;\nuniform float uDetailRep;\nuniform float uDetailK;')
          .replace('#include <map_fragment>', '#include <map_fragment>\ndiffuseColor.rgb *= mix(vec3(1.0), texture2D(uDetail, vUv * uDetailRep).rgb, uDetailK);')
      }
      m.customProgramCacheKey = () => 'terrain-detail'
    }
    this._owned.push(m)
    const t = new THREE.Mesh(g, m)
    t.castShadow = false; t.receiveShadow = true
    t.name = 'terrain'
    this.root.add(t)
    this.terrainNode = t
  }

  /// Computes the full-resolution macro map off the main thread and swaps it into the terrain material.
  refineMacro(W, H) {
    return new Promise(resolve => {
      const data = new Uint8Array(W * W * 4)
      const finish = () => {
        if (this._disposed) return resolve(this)
        const m = this.terrainNode.material, old = m.map
        m.map = macroTexture(data, W)
        this._owned = this._owned.filter(o => o !== old); old.dispose()
        this._owned.push(m.map)
        this.terrainTexture = { size: W, full: true }
        this._workers = null
        resolve(this)
      }
      // fallback: compute on the main thread in ~25 ms slices
      const slices = () => {
        let r = 0
        const step = () => {
          if (this._disposed) return resolve(this)
          const t = now()
          while (r < W && now() - t < 25) { const n = Math.min(16, W - r); data.set(macroRows(this.mapIndex, W, H, r, r + n), r * W * 4); r += n }
          if (r < W) setTimeout(step, 0); else finish()
        }
        step()
      }
      let workers
      try {
        const nw = Math.max(2, Math.min(6, ((typeof navigator !== 'undefined' && navigator.hardwareConcurrency) || 4) - 1))
        workers = Array.from({ length: nw }, () => new Worker(new URL('./world.js', import.meta.url), { type: 'module' }))
      } catch (e) { return slices() }
      this._workers = workers
      const band = Math.ceil(W / (workers.length * 4))
      let next = 0, pending = 0, failed = false
      const feed = wk => {
        if (next >= W) return
        const r0 = next, r1 = Math.min(W, next + band); next = r1; pending++
        wk.postMessage({ macro: true, mapIndex: this.mapIndex, W, H, r0, r1 })
      }
      for (const wk of workers) {
        wk.onmessage = e => {
          data.set(new Uint8Array(e.data.data), e.data.r0 * W * 4); pending--
          feed(wk)
          if (next >= W && pending === 0) { workers.forEach(w => w.terminate()); finish() }
        }
        wk.onerror = () => {
          if (failed) return
          failed = true; workers.forEach(w => w.terminate()); this._workers = null
          slices()
        }
        feed(wk); feed(wk)
      }
    })
  }

  buildHills() {
    // a ring of rolling hills and forest out to the horizon
    const segs = 96, rings = 10, mi = this.mapIndex
    const Pp = [], U = [], I = []
    for (let j = 0; j <= rings; j++) {
      const r = Farm.half * 1.15 + j * j * 14
      for (let i = 0; i <= segs; i++) {
        const a = i / segs * 2 * Math.PI
        const x = Math.cos(a) * r, z = Math.sin(a) * r
        const rise = j / rings
        const y = Noise.fbm(x * 0.004, z * 0.004, 4, 7) * (mi === 7 ? 120 : 45) * rise + rise * (mi === 7 ? 80 : 30) - 2 + this.terrain(x, z) * (1 - rise)
        Pp.push([x, y, z]); U.push([i / 4, j / 2])
      }
    }
    for (let j = 0; j < rings; j++) for (let i = 0; i < segs; i++) {
      const a = j * (segs + 1) + i, b = a + 1, c = a + segs + 1, d = c + 1
      I.push(a, b, c, b, d, c)
    }
    // recompute normals
    const nn = Pp.map(() => [0, 0, 0])
    for (let k = 0; k < I.length; k += 3) {
      const a = I[k], b = I[k + 1], c = I[k + 2]
      const f = v3cross(v3sub(Pp[b], Pp[a]), v3sub(Pp[c], Pp[a]))
      for (const q of [a, b, c]) { nn[q][0] += f[0]; nn[q][1] += f[1]; nn[q][2] += f[2] }
    }
    const N = nn.map(v => { const l = Math.hypot(v[0], v[1], v[2]); if (!(l > 0)) return [0, 1, 0]; const s = v[1] < 0 ? -1 : 1; return [v[0] / l * s, v[1] / l * s, v[2] / l * s] })
    const g = meshGeometry(Pp, N, U, I)
    this._owned.push(g)
    const m = pbr(this.map.hills, { rough: 1 })
    const src = [2, 4].includes(mi) ? Mat.dirt : Mat.leaves
    if (src.map) { m.map = cloneTex(src.map); m.map.wrapS = m.map.wrapT = THREE.RepeatWrapping; m.map.repeat.set(6, 6); this._owned.push(m.map) }
    m.side = THREE.DoubleSide
    const n = mesh(g, m, { shadow: false })
    this.add(n)
    // forest bumps along the first ridge
    const rr = new RNG(44)
    const bumps = [0, 3, 6, 9].includes(mi) ? 260 : mi === 1 ? 60 : mi === 7 ? 120 : 0
    const fm = mi === 2 || mi === 7 ? Foliage.pineMat : Foliage.leafMat([0.06, 0.16, 0.04], [0.2, 0.34, 0.08], 3)
    for (let k = 0; k < bumps; k++) {
      const a = rr.range(0, 2 * Math.PI), r = Farm.half * rr.range(1.02, 1.35)
      const x = Math.cos(a) * r, z = Math.sin(a) * r
      const s = rr.range(3, 6)
      const t = Foliage.crown([x, this.terrain(x, z) + s * 1.1, z], [s, s * rr.range(1.1, 1.5), s], 45, s * 0.9, rr.next(), fm)
      t.traverse(o => { o.castShadow = false })
      this.add(t)
    }
  }

  // MARK: buildings

  buildBarn() {
    const b = Farm.barn
    const n = P(G(), b.x, 0, b.z)
    this.add(n)
    const hl = b.len / 2, hw = b.wid / 2
    const red = Mat.barnRed
    // long walls
    for (const sz of [1, -1]) n.add(P(meterBox(b.len, b.eave, 0.2, red), 0, b.eave / 2, sz * hw))
    // gable ends with a door
    for (const sx of [1, -1]) {
      const x = sx * hl
      n.add(P(meterBox(0.2, b.eave, b.wid, red), x, b.eave / 2, 0))
      const tri = [[x + sx * 0.11, b.eave, sx > 0 ? -hw : hw], [x + sx * 0.11, b.eave, sx > 0 ? hw : -hw], [x + sx * 0.11, b.ridge, 0]]
      n.add(poly(tri, red))
      // trim: corner boards and an X-braced sliding door
      for (const zz of [-hw, hw]) n.add(P(boxNode(0.25, b.eave, 0.25, Mat.whiteTrim), x, b.eave / 2, zz))
      if (sx > 0) {
        n.add(P(boxNode(0.05, 4.2, 4.4, Mat.doorDark), x + 0.12, 2.1, 0))
        for (const dz of [-1.1, 1.1]) {
          const d = P(G(), x + 0.16, 2.1, dz)
          n.add(d)
          d.add(meterBox(0.06, 4.1, 2.15, red))
          for (const [h, yy] of [[0.18, 2.0], [0.18, -2.0], [0.18, 0]]) d.add(P(boxNode(0.08, h, 2.2, Mat.whiteTrim), 0.02, yy, 0))
          for (const zz of [-1.05, 1.05]) d.add(P(boxNode(0.08, 4.1, 0.18, Mat.whiteTrim), 0.02, 0, zz))
          for (const s of [1, -1]) d.add(P(boxNode(0.07, 4.4, 0.16, Mat.whiteTrim), 0.03, 0, 0, s * 0.48, 0, 0))
        }
        n.add(P(boxNode(0.15, 0.12, 5.2, Mat.galv), x + 0.2, 4.3, 0))
        // hay loft door, open, bales peeking out
        n.add(P(boxNode(0.05, 1.8, 1.8, Mat.doorDark), x + 0.13, 7.6, 0))
        n.add(P(boxNode(0.12, 0.15, 2.1, Mat.whiteTrim), x + 0.16, 8.5, 0))
        n.add(P(boxNode(0.12, 0.15, 2.1, Mat.whiteTrim), x + 0.16, 6.7, 0))
        n.add(P(meterBox(0.6, 0.6, 1.4, Mat.hay, 1), x - 0.1, 7.0, 0))
        n.add(P(boxNode(0.4, 0.3, 0.3, Mat.galv), x + 0.6, 9.3, 0))
      }
    }
    // roof: corrugated metal, two slopes with overhang
    const slopeLen = Math.sqrt(hw * hw + (b.ridge - b.eave) * (b.ridge - b.eave)) + 0.7
    const ang = Math.atan2(b.ridge - b.eave, hw)
    for (const sz of [1, -1]) {
      n.add(P(meterBox(b.len + 1.0, 0.08, slopeLen, Mat.roofMetal, 0.33), 0, (b.eave + b.ridge) / 2 + 0.06 - 0.22, sz * (hw / 2 + 0.3), sz * ang, 0, 0))
    }
    n.add(P(Prim.cyl(0.08, b.len + 1, Mat.galv), 0, b.ridge + 0.02, 0, 0, 0, Math.PI / 2))
    // weathervane rooster on the ridge
    const vane = P(G(), hl - 2, b.ridge, 0)
    n.add(vane)
    vane.add(P(cylNode(0.03, 1.4, Mat.black), 0, 0.7, 0))
    vane.add(P(boxNode(0.5, 0.35, 0.02, Mat.black), 0, 1.45, 0))
    vane.add(P(boxNode(0.9, 0.02, 0.02, Mat.black), 0, 1.1, 0))
    vane.add(P(boxNode(0.02, 0.02, 0.9, Mat.black), 0, 1.1, 0))
    // foundation
    n.add(P(meterBox(b.len + 0.3, 0.5, b.wid + 0.3, Mat.concrete), 0, 0.1, 0))
    const e = b.eave, rg = b.ridge
    this.solids.push(new Solid({
      minX: b.x - hl - 0.5, maxX: b.x + hl + 0.5, minZ: b.z - hw - 0.7, maxZ: b.z + hw + 0.7, bottom: -1,
      top: (_, z) => e - 0.3 + (rg - e + 0.2) * Math.max(0, 1 - Math.abs(z - b.z) / (hw + 0.7)), tag: 'barnRoof', surface: 'metal',
    }))
  }

  buildSilo() {
    const s = Farm.silo
    const n = P(G(), s.x, 0, s.z)
    this.add(n)
    const m = retile(Mat.concrete.clone(), 5, 4)
    n.add(P(Prim.cyl(s.r, s.h, m, 48), 0, s.h / 2, 0))
    for (let k = 0; k < 14; k++) n.add(P(Prim.torus(s.r + 0.02, 0.03, Mat.galv, 48, 6), 0, 0.8 + k * 1.02, 0))
    // flat cap with a railing
    n.add(P(Prim.cyl(s.r + 0.15, 0.2, Mat.concrete, 48), 0, s.h + 0.1, 0))
    n.add(P(Prim.cone(s.r * 0.35, 0.25, 0.7, Mat.galv, 24), 0, s.h + 0.55, 0))
    for (let k = 0; k < 16; k++) {
      const a = k / 16 * 2 * Math.PI
      n.add(P(cylNode(0.025, 1.0, Mat.galv, 6), Math.cos(a) * (s.r - 0.05), s.h + 0.7, Math.sin(a) * (s.r - 0.05)))
    }
    n.add(P(Prim.torus(s.r - 0.05, 0.03, Mat.galv, 48, 6), 0, s.h + 1.2, 0))
    // ladder up the side facing the yard (+x), with a gap in the railing
    const lx = s.r + 0.25
    for (const dz of [-0.25, 0.25]) n.add(P(Prim.cyl(0.025, s.h + 1.2, Mat.galv, 8), lx, (s.h + 1.2) / 2, dz))
    for (let k = 0; k < Math.trunc(s.h / 0.3); k++) n.add(P(cylNode(0.018, 0.5, Mat.galv, 6), lx, 0.3 + k * 0.3, 0, Math.PI / 2, 0, 0))
    for (let k = 0; k < 10; k++) n.add(P(Prim.torus(0.38, 0.02, Mat.galv, 24, 6), lx + 0.2, 3 + k * 1.3, 0))
    this.solids.push(Solid.cyl(s.x, s.z, s.r + 0.15, s.h + 0.2, { tag: 'silo', surface: 'concrete' }))
    this.ladders.push({ x: s.x + lx + 0.25, z: s.z, top: s.h + 0.2, outward: [1, 0], topStep: [s.x + s.r - 0.9, s.z] })
  }

  buildHayStairs() {
    // big square bales stacked into a staircase up to the barn eave
    const b = Farm.barn
    const z0 = b.z + b.wid / 2 + 0.7 + 0.75
    const twine = pbr([0.1, 0.25, 0.6], { rough: 0.6 })
    for (let i = 0; i < 7; i++) {
      const x = b.x - 6 + i * 1.3
      const h = (i + 1) * 0.9
      for (let k = 0; k <= i; k++) {
        this.add(P(meterBox(1.25, 0.88, 1.5, Mat.hay, 0.8), x, k * 0.9 + 0.44, z0, 0, (k % 2) * 0.03 - 0.015, 0))
        for (const dz of [-0.4, 0.4]) this.add(P(boxNode(1.27, 0.01, 0.02, twine), x, k * 0.9 + 0.885, z0 + dz))
      }
      this.solids.push(Solid.box(x, z0, 1.3, 1.5, h, { tag: 'hay', surface: 'hay' }))
    }
    // loose round bales out in the field
    const rr = new RNG(9)
    for (const [x, z] of [[-30, 4], [-26, 8], [-38, -2], [8, -30], [14, -34]]) {
      const a = rr.range(0, 3)
      this.add(P(cylNode(0.8, 1.2, Mat.hay, 28), x, Farm.height(x, z) + 0.8, z, 0, a, Math.PI / 2))
      this.solids.push(Solid.cyl(x, z, 0.85, 1.6, { base: Farm.height(x, z), tag: 'roundbale', surface: 'hay' }))
    }
  }

  buildCoop() {
    const r = Farm.coopRun
    const wire = Mat.wire
    // posts and wire around the run, gate gap on the yard side
    const fenceLine = (a, b) => {
      const dx = b[0] - a[0], dz = b[1] - a[1], len = Math.hypot(dx, dz)
      const n = Math.ceil(len / 2.4)
      for (let k = 0; k <= n; k++) {
        const px = a[0] + dx * (k / n), pz = a[1] + dz * (k / n)
        this.add(P(meterBox(0.1, 1.4, 0.1, Mat.woodGrey, 1), px, Farm.height(px, pz) + 0.6, pz))
      }
      const mx = (a[0] + b[0]) / 2, mz = (a[1] + b[1]) / 2
      const w = retile(wire.clone(), len / 0.4, 3)
      const pn = P(Prim.plane(len, 1.2, w), mx, Farm.height(mx, mz) + 0.6, mz, 0, -Math.atan2(dz, dx), 0)
      pn.castShadow = false
      this.add(pn)
      this.add(P(meterBox(len, 0.06, 0.06, Mat.woodGrey, 1), mx, Farm.height(mx, mz) + 1.25, mz, 0, -Math.atan2(dz, dx), 0))
      const s = Solid.box(mx, mz, Math.abs(dx) + 0.12, Math.abs(dz) + 0.12, 1.25, { tag: 'fence', surface: 'wood' })
      s.walkable = false
      this.solids.push(s)
    }
    fenceLine([r.minX, r.minZ], [r.maxX, r.minZ])
    fenceLine([r.maxX, r.minZ], [r.maxX, r.maxZ])
    fenceLine([r.minX, r.minZ], [r.minX, r.maxZ])
    fenceLine([r.minX, r.maxZ], [Farm.coopGate.x0, r.maxZ])
    fenceLine([Farm.coopGate.x1, r.maxZ], [r.maxX, r.maxZ])
    // an open gate swung inward
    const gate = P(G(), Farm.coopGate.x1, 0.65, r.maxZ, 0, 1.9, 0)
    this.add(gate)
    gate.add(P(meterBox(2.4, 0.06, 0.06, Mat.woodGrey), 1.2, 0.55, 0))
    gate.add(P(meterBox(2.4, 0.06, 0.06, Mat.woodGrey), 1.2, -0.55, 0))
    gate.add(P(Prim.plane(2.4, 1.1, retile(wire.clone(), 6, 2.75)), 1.2, 0, 0))
    // the henhouse on legs, with a ramp
    const c = Farm.coopHouse
    const h = P(G(), c.x, 0, c.z)
    this.add(h)
    const wood = Mat.siding([0.72, 0.62, 0.45], 301)
    for (const [x, z] of [[-1.4, -1.1], [1.4, -1.1], [-1.4, 1.1], [1.4, 1.1]]) h.add(P(meterBox(0.12, 0.6, 0.12, Mat.woodGrey, 1), x, 0.3, z))
    h.add(P(meterBox(3.0, 1.8, 2.4, wood), 0, 1.5, 0))
    h.add(poly([[-1.5, 2.4, 1.21], [1.5, 2.4, 1.21], [0, 3.1, 1.21]], wood))
    h.add(poly([[1.5, 2.4, -1.21], [-1.5, 2.4, -1.21], [0, 3.1, -1.21]], wood))
    const rl = Math.sqrt(1.5 * 1.5 + 0.7 * 0.7) + 0.3
    for (const s of [1, -1]) h.add(P(meterBox(rl, 0.05, 2.8, Mat.roofMetal, 0.33), s * 0.78, 2.78, 0, 0, 0, -s * Math.atan2(0.7, 1.5)))
    // pop door and ramp on the yard side
    h.add(P(boxNode(0.5, 0.6, 0.04, Mat.doorDark), 0.6, 0.95, 1.22))
    h.add(P(boxNode(0.7, 0.05, 1.8, Mat.woodGrey), 0.6, 0.35, 1.95, 0.35, 0, 0))
    for (let k = 0; k < 5; k++) h.add(P(boxNode(0.7, 0.03, 0.03, Mat.woodGrey), 0.6, 0.18 + k * 0.12, 2.6 - k * 0.3, 0.35, 0, 0))
    // nest boxes bumped out on the side
    h.add(P(meterBox(0.6, 0.6, 1.8, wood), -1.8, 1.1, 0))
    h.add(P(boxNode(0.8, 0.04, 2.0, Mat.roofMetal), -1.85, 1.45, 0, 0, 0, 0.35))
    // a wired window
    h.add(P(boxNode(0.03, 0.5, 0.7, Mat.doorDark), 1.51, 1.8, 0))
    this.solids.push(Solid.box(c.x - 0.25, c.z, 3.6, 2.5, 3.0, { tag: 'coop', surface: 'metal' }))
    // corn scattered on the ground (kept as separate meshes: the game hides kernels as they're eaten)
    const rr = new RNG(55)
    const corn = pbr([0.95, 0.72, 0.15], { rough: 0.5 })
    for (const [x, z] of [[14, -11], [19, -12], [15.5, -17]]) {
      const pile = P(G(), x, Farm.height(x, z), z)
      this.root.add(pile)
      for (let k = 0; k < 40; k++) {
        const a = rr.range(0, 6.28), d = Math.pow(rr.float(), 0.7) * 0.45
        const kernel = S(P(sphereNode(0.012, corn, 6), Math.cos(a) * d, 0.008, Math.sin(a) * d, 0, a, 0), 1, 0.7, 1.3)
        kernel.castShadow = false
        pile.add(kernel)
      }
      this.cornPiles.push({ pos: pile.position.clone(), node: pile, left: 20 })
    }
    // feeder and a water fount
    const fy = Farm.height(18, -14)
    this.add(P(cylNode(0.2, 0.5, Mat.galv, 20), 18, fy + 0.25, -14))
    this.add(P(coneNode(0.3, 0.05, 0.25, Mat.galv, 20), 18, fy + 0.6, -14))
    this.add(P(cylNode(0.35, 0.05, Mat.galv, 24), 18, fy + 0.03, -14))
  }

  buildPasture() {
    const p = Farm.pasture
    const postM = Mat.woodGrey
    const rail = (a, b) => {
      const dx = b[0] - a[0], dz = b[1] - a[1], len = Math.hypot(dx, dz)
      if (!(len > 0.1)) return
      const n = Math.ceil(len / 3)
      const ang = -Math.atan2(dz, dx)
      for (let k = 0; k <= n; k++) {
        const qx = a[0] + dx * (k / n), qz = a[1] + dz * (k / n)
        this.add(P(meterBox(0.14, 1.55, 0.14, postM, 1), qx, Farm.height(qx, qz) + 0.72, qz, 0, k * 0.4, 0))
      }
      for (let k = 0; k < n; k++) {
        const q0x = a[0] + dx * (k / n), q0z = a[1] + dz * (k / n), q1x = a[0] + dx * ((k + 1) / n), q1z = a[1] + dz * ((k + 1) / n)
        const mx = (q0x + q1x) / 2, mz = (q0z + q1z) / 2
        const y0 = Farm.height(q0x, q0z), y1 = Farm.height(q1x, q1z)
        const seglen = Math.hypot(q1x - q0x, q1z - q0z)
        const tilt = Math.atan2(y1 - y0, seglen)
        for (const hgt of [0.45, 0.85, 1.25]) this.add(P(meterBox(seglen + 0.1, 0.12, 0.05, postM, 0.5), mx, (y0 + y1) / 2 + hgt, mz, 0, ang, tilt))
      }
      const s = Solid.box((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.abs(dx) + 0.16, Math.abs(dz) + 0.16, 1.35, { base: -2, tag: 'fence' })
      s.walkable = false
      this.solids.push(s)
    }
    rail([p.minX, p.minZ], [p.maxX, p.minZ])
    rail([p.maxX, p.minZ], [p.maxX, p.maxZ])
    rail([p.minX, p.maxZ], [p.maxX, p.maxZ])
    rail([p.minX, p.minZ], [p.minX, Farm.pastureGate.z0])
    rail([p.minX, Farm.pastureGate.z1], [p.minX, p.maxZ])
    // trough
    const t = Farm.trough
    const ty = Farm.height(t.x, t.z)
    const tn = P(G(), t.x, ty, t.z)
    this.add(tn)
    tn.add(P(boxNode(0.9, 0.04, 2.5, Mat.galv), 0, 0.12, 0))
    for (const sx of [1, -1]) tn.add(P(boxNode(0.03, 0.55, 2.5, Mat.galv), sx * 0.45, 0.38, 0))
    for (const sz of [1, -1]) tn.add(P(boxNode(0.93, 0.55, 0.03, Mat.galv), 0, 0.38, sz * 1.25))
    for (const sx of [1, -1]) tn.add(P(cylNode(0.02, 2.52, Mat.galv, 8), sx * 0.46, 0.66, 0, Math.PI / 2, 0, 0))
    for (const [x, z] of [[0.38, 1.1], [-0.38, 1.1], [0.38, -1.1], [-0.38, -1.1]]) tn.add(P(boxNode(0.06, 0.12, 0.06, Mat.woodGrey), x, 0.06, z))
    tn.add(P(Prim.plane(0.86, 2.46, Mat.water), 0, 0.55, 0, -Math.PI / 2, 0, 0))
    this.solids.push(Solid.box(t.x, t.z, 0.95, 2.6, 0.7, { base: ty, tag: 'trough', surface: 'metal' }))
    // a salt lick in the pasture
    this.add(P(boxNode(0.25, 0.2, 0.25, pbr([0.75, 0.7, 0.68], { rough: 0.6 })), 44, Farm.height(44, 14) + 0.1, 14))
  }

  buildHouse() {
    const h = Farm.house
    const n = P(G(), h.x, 0, h.z)
    this.add(n)
    const hw = h.w / 2, hd = h.d / 2
    const wall = Mat.clapboard
    n.add(P(meterBox(h.w, h.eave, h.d, wall), 0, h.eave / 2 + 0.4, 0))
    n.add(P(meterBox(h.w + 0.3, 0.5, h.d + 0.3, Mat.concrete), 0, 0.2, 0))
    for (const sx of [1, -1]) {
      const x = sx * (hw + 0.005)
      n.add(poly([[x, h.eave + 0.4, sx > 0 ? hd : -hd], [x, h.eave + 0.4, sx > 0 ? -hd : hd], [x, h.ridge + 0.4, 0]], wall))
    }
    const slope = Math.sqrt(hd * hd + (h.ridge - h.eave) * (h.ridge - h.eave)) + 0.8
    const ang = Math.atan2(h.ridge - h.eave, hd)
    for (const sz of [1, -1]) n.add(P(meterBox(h.w + 1.0, 0.14, slope, Mat.shingles, 0.5), 0, (h.eave + h.ridge) / 2 + 0.4 - 0.25, sz * (hd / 2 + 0.35), sz * ang, 0, 0))
    // chimney
    n.add(P(meterBox(0.9, 3.2, 0.9, Mat.siding([0.45, 0.2, 0.15], 401, true), 0.6), -hw + 1.8, h.ridge + 0.2, 1.0))
    // windows and door on the porch side (-z)
    const shutter = pbr([0.12, 0.2, 0.14], { rough: 0.6 })
    const window = (x, y, z, facingZ) => {
      const w = P(G(), x, y, z, 0, facingZ > 0 ? 0 : Math.PI, 0)
      n.add(w)
      w.add(P(boxNode(1.0, 1.4, 0.04, Mat.glass), 0, 0, 0.02))
      for (const [bw, bh, bx, by] of [[1.2, 0.1, 0, 0.75], [1.2, 0.1, 0, -0.75], [0.1, 1.5, 0.6, 0], [0.1, 1.5, -0.6, 0], [1.0, 0.05, 0, 0], [0.05, 1.4, 0, 0]]) {
        w.add(P(boxNode(bw, bh, 0.07, Mat.whiteTrim), bx, by, 0.05))
      }
      w.add(P(boxNode(0.4, 1.5, 0.04, shutter), 0.85, 0, 0.03))
      w.add(P(boxNode(0.4, 1.5, 0.04, shutter), -0.85, 0, 0.03))
    }
    for (const x of [-3.8, 3.8]) { window(x, 2.6, -hd, -1); window(x, 2.6, hd, 1) }
    window(0, 2.6, hd, 1)
    n.add(P(boxNode(1.1, 2.2, 0.06, pbr([0.35, 0.12, 0.08], { rough: 0.5 })), 0, 1.5, -hd - 0.02))
    n.add(P(cylNode(0.035, 0.05, Mat.galv, 8), 0.4, 1.5, -hd - 0.07, Math.PI / 2, 0, 0))
    // porch
    const pd = 2.6
    n.add(P(meterBox(h.w - 1, 0.18, pd, Mat.woodFresh, 0.8), 0, 0.5, -hd - pd / 2))
    const stp = (h.w - 1.4) / 4
    for (let x = -hw + 0.7; x <= hw - 0.7 + 1e-4; x += stp) n.add(P(boxNode(0.16, 2.5, 0.16, Mat.whiteTrim), x, 1.8, -hd - pd + 0.15))
    n.add(P(meterBox(h.w - 0.6, 0.1, pd + 0.4, Mat.shingles, 0.5), 0, 3.15, -hd - pd / 2, -0.18, 0, 0))
    for (let k = 0; k < 3; k++) n.add(P(meterBox(1.6, 0.16, 0.35, Mat.woodFresh), 0, 0.08 + k * 0.16, -hd - pd - 0.9 + k * 0.3))
    for (let x = -hw + 0.8; x <= hw - 0.8 + 1e-4; x += 0.25) {
      if (Math.abs(x) > 1.0) n.add(P(boxNode(0.04, 0.8, 0.04, Mat.whiteTrim), x, 1.0, -hd - pd + 0.15))
    }
    n.add(P(boxNode(h.w - 1.4, 0.07, 0.08, Mat.whiteTrim), 0, 1.42, -hd - pd + 0.15))
    // rocking chair
    const chair = P(G(), 3, 0.6, -hd - 1.1, 0, 2.8, 0)
    n.add(chair)
    chair.add(P(boxNode(0.5, 0.05, 0.5, Mat.woodFresh), 0, 0.4, 0))
    chair.add(P(boxNode(0.5, 0.7, 0.05, Mat.woodFresh), 0, 0.8, -0.24))
    for (const s of [1, -1]) chair.add(P(boxNode(0.04, 0.05, 0.8, Mat.woodFresh), s * 0.23, 0.02, 0))
    const e = h.eave + 0.4, rg = h.ridge + 0.4
    this.solids.push(new Solid({
      minX: h.x - hw - 0.5, maxX: h.x + hw + 0.5, minZ: h.z - hd - 0.6, maxZ: h.z + hd + 0.6, bottom: -1,
      top: (_, z) => e - 0.3 + (rg - e) * Math.max(0, 1 - Math.abs(z - h.z) / (hd + 0.6)), tag: 'houseRoof', surface: 'wood',
    }))
    this.solids.push(Solid.box(h.x, h.z - hd - pd / 2, h.w - 1, pd, 0.6, { tag: 'porch', surface: 'wood' }))
    this.solids.push(Solid.box(h.x, h.z - hd - pd - 0.6, 1.6, 0.6, 0.3, { tag: 'steps', surface: 'wood' }))
  }

  buildWater() {
    const lvl = this.map.waterLevel
    if (lvl === null) return
    // Swift used a 260 m plane; it is sized to the whole map here so the beach's ocean reaches the edge.
    const size = 2 * (Farm.half + 4)
    const m = Mat.water.clone()
    m.map = null
    m.color.setRGB(this.map.waterCol[0], this.map.waterCol[1], this.map.waterCol[2], THREE.SRGBColorSpace)
    if (m.normalMap) { m.normalMap = cloneTex(m.normalMap); m.normalMap.repeat.set(18 * size / 260, 18 * size / 260); this._owned.push(m.normalMap) }
    if (this.mapIndex === 2) { m.transparent = true; m.opacity = 0.9 }
    this._owned.push(m)
    const g = new THREE.PlaneGeometry(size, size)
    this._owned.push(g)
    const w = P(mesh(g, m, { shadow: false }), 0, lvl, 0, -Math.PI / 2, 0, 0)
    w.name = 'water'
    this.water = w
    this.root.add(w)
  }

  buildPond() {
    const p = Farm.pond
    const disc = P(Prim.cyl(p.r + 1.2, 0.02, Mat.water, 64), p.x, Farm.pondWater, p.z)
    disc.castShadow = false
    disc.name = 'water'
    this._owned.push(disc.geometry)
    this.water = disc
    this.root.add(disc)
    // reeds and cattails round the edge
    const rr = new RNG(66)
    const reed = pbr([0.3, 0.38, 0.12], { rough: 0.7 })
    const cat = pbr([0.3, 0.18, 0.08], { rough: 0.9 })
    for (let k = 0; k < 70; k++) {
      const a = rr.range(0, 6.28), d = p.r + rr.range(-1.2, 0.8)
      const x = p.x + Math.cos(a) * d, z = p.z + Math.sin(a) * d
      const hgt = rr.range(0.7, 1.5)
      const r = P(Prim.cyl(0.01, hgt, reed, 5), x, Farm.height(x, z) + hgt / 2, z, rr.range(-0.15, 0.15), 0, rr.range(-0.15, 0.15))
      this.add(r)
      if (rr.chance(0.4)) r.add(P(cylNode(0.025, 0.18, cat, 8), 0, hgt / 2 - 0.1, 0))
    }
    // a small dock
    const dx = p.x + p.r - 1.5, dz = p.z - 2
    this.add(P(meterBox(3.5, 0.12, 1.4, Mat.woodGrey, 1), dx - 1, 0.25, dz))
    for (const [ox, oz] of [[-2.5, -0.6], [-2.5, 0.6], [0.5, -0.6], [0.5, 0.6]]) this.add(P(cylNode(0.07, 1.4, Mat.woodGrey, 8), dx + ox, -0.4, dz + oz))
    this.solids.push(Solid.box(dx - 1, dz, 3.5, 1.4, 0.31, { base: -1.5, tag: 'dock', surface: 'wood' }))
  }

  buildTractor() {
    const t = Farm.tractor
    const n = P(G(), t.x, Farm.height(t.x, t.z), t.z, 0, 0.5, 0)
    this.add(n)
    // body
    n.add(P(boxNode(0.9, 0.7, 2.2, Mat.tractorGreen), 0, 1.05, 0.5))
    n.add(P(boxNode(0.8, 0.5, 1.4, Mat.tractorGreen), 0, 1.55, 0.85))
    n.add(P(boxNode(0.82, 0.3, 0.05, Mat.galv), 0, 1.2, 1.62))
    for (let k = 0; k < 5; k++) n.add(P(boxNode(0.7, 0.02, 0.02, Mat.black), 0, 1.08 + k * 0.05, 1.64))
    n.add(P(cylNode(0.05, 1.0, Mat.black, 10), 0.25, 2.1, 1.2))
    n.add(P(boxNode(1.6, 0.1, 1.2, Mat.tractorGreen), 0, 1.5, -0.7))
    // seat and wheel
    n.add(P(boxNode(0.5, 0.1, 0.45, Mat.black), 0, 1.75, -0.7))
    n.add(P(boxNode(0.5, 0.5, 0.08, Mat.black), 0, 2.0, -0.95))
    n.add(P(cylNode(0.02, 0.6, Mat.black), 0, 1.9, -0.25, -0.6, 0, 0))
    n.add(P(Prim.torus(0.18, 0.02, Mat.black, 24, 6), 0, 2.18, -0.1, -0.9, 0, 0))
    // roll bar
    for (const s of [1, -1]) n.add(P(cylNode(0.04, 1.6, Mat.black, 10), s * 0.7, 2.3, -1.15))
    n.add(P(cylNode(0.04, 1.4, Mat.black, 10), 0, 3.1, -1.15, 0, 0, Math.PI / 2))
    // wheels
    const wheel = (x, y, z, r, w) => {
      const wn = P(Prim.tube(r * 0.6, r, w, Mat.rubber, 36), x, y, z, 0, 0, Math.PI / 2)
      n.add(wn)
      wn.add(Prim.cyl(r * 0.62, w * 0.7, Mat.tractorYellow, 24))
      for (let k = 0; k < 20; k++) {
        const a = k / 20 * 2 * Math.PI
        wn.add(P(Prim.box(0.07, w * 0.9, r * 0.22, Mat.rubber), Math.cos(a) * r, 0, Math.sin(a) * r, 0, -a, 0))
      }
    }
    for (const s of [1, -1]) {
      wheel(s * 0.95, 0.8, -0.7, 0.8, 0.45)
      wheel(s * 0.62, 0.45, 1.3, 0.45, 0.25)
    }
    const ty = Farm.height(t.x, t.z) + 1.6
    this.solids.push(new Solid({ minX: t.x - 1.4, maxX: t.x + 1.4, minZ: t.z - 1.6, maxZ: t.z + 1.9, bottom: -1, top: () => ty, tag: 'tractor', surface: 'metal' }))
  }

  buildTrees() {
    const rr = new RNG(77)
    const lm = Foliage.leafMat([0.06, 0.16, 0.04], [0.2, 0.34, 0.08], 3)
    const tree = (x, z, s, apples = false) => {
      const y = Farm.height(x, z)
      const n = P(G(), x, y, z, 0, rr.range(0, 6), 0)
      this.add(n)
      const th = 2.2 * s
      n.add(loftNode([Ring([0, -0.2, 0], 0.3 * s, 0.28 * s), Ring([0, 0.2, 0], 0.22 * s, 0.2 * s), Ring([0.05, th * 0.6, 0.03], 0.16 * s, 0.15 * s),
        Ring([0.1, th, 0.05], 0.12 * s, 0.11 * s), Ring([0.1, th + 0.8 * s, 0.05], 0.06 * s, 0.06 * s)], Mat.bark, { seg: 14, smooth: 3 }))
      // branches
      for (let k = 0; k < 4; k++) {
        const a = k * 1.6 + rr.range(0, 0.5)
        n.add(P(limb(1.4 * s, 0.07 * s, 0.03 * s, Mat.bark, { seg: 8, dir: [Math.cos(a), 0.9, Math.sin(a)] }), 0.1, th * 0.8, 0.05))
      }
      for (let k = 0; k < 3; k++) {
        const a = k * 2.1 + rr.range(0, 0.6), d = rr.range(0.5, 1.2) * s
        const cc = [Math.cos(a) * d, th + 1.4 * s + rr.range(-0.2, 0.9) * s, Math.sin(a) * d]
        const rk = s * rr.range(0.85, 1.15)
        const rad = [1.9 * rk, 1.5 * rk, 1.9 * rk]
        n.add(Foliage.crown(cc, rad, 150, 1.1 * s, rr.next(), lm))
        if (apples) {
          for (let q = 0; q < 14; q++) {
            const b = rr.range(0, 6.28), e = rr.range(-0.6, 0.5)
            n.add(P(sphereNode(0.045, Mat.apple, 8), cc[0] + Math.cos(b) * Math.cos(e) * rad[0] * 0.8, cc[1] + Math.sin(e) * rad[1] * 0.8, cc[2] + Math.sin(b) * Math.cos(e) * rad[2] * 0.8))
          }
        }
      }
      this.solids.push(Solid.cyl(x, z, 0.35 * s, th + 3 * s, { base: y, tag: 'tree', surface: 'wood' }))
    }
    tree(Farm.appleTree.x, Farm.appleTree.z, 1.1, true)
    tree(-18, 34, 1.5); tree(8, 38, 1.3); tree(-26, 14, 1.2); tree(52, 20, 1.6); tree(28, -30, 1.2); tree(-45, -20, 1.4)
    tree(-12, 44, 1.2); tree(-30, 40, 1.4)
    let placed = 0
    while (placed < 260) {
      const x = rr.range(-Farm.half + 5, Farm.half - 5), z = rr.range(-Farm.half + 5, Farm.half - 5)
      if (!(Math.hypot(x, z) > 60)) continue
      if (inPasture(x, z) || Farm.pathDist(x, z) < 4) continue
      tree(x, z, rr.range(1.1, 1.8))
      placed++
    }
  }

  buildMisc() {
    // pumpkin patch vines, a mailbox by the lane, a well, a woodpile by the barn
    const pp = Farm.pumpkinPatch
    const vine = pbr([0.15, 0.3, 0.07], { rough: 0.7 })
    const rr = new RNG(88)
    for (let k = 0; k < 60; k++) {
      const x = pp.x + rr.range(-5, 5), z = pp.z + rr.range(-3.5, 3.5)
      this.add(S(P(Prim.sphere(rr.range(0.15, 0.3), vine, 8), x, Farm.height(x, z) + 0.05, z), 1, 0.25, 1))
    }
    this.add(P(meterBox(10.5, 0.02, 7.5, Mat.dirt, 0.5), pp.x, Farm.height(pp.x, pp.z) + 0.005, pp.z))
    // mailbox
    this.add(P(boxNode(0.1, 1.1, 0.1, Mat.woodGrey), -6, Farm.height(-6, 45) + 0.55, 45))
    this.add(P(cylNode(0.12, 0.45, Mat.galv, 16), -6, Farm.height(-6, 45) + 1.15, 45, Math.PI / 2, 0, 0))
    // stone well near the house
    const wx = 8, wz = 26
    const wy = Farm.height(wx, wz)
    this.add(P(Prim.tube(0.55, 0.75, 0.8, Mat.concrete, 24), wx, wy + 0.4, wz))
    this.add(P(cylNode(0.56, 0.02, Mat.water, 24), wx, wy + 0.5, wz))
    for (const s of [1, -1]) this.add(P(boxNode(0.1, 1.6, 0.1, Mat.woodGrey), wx + s * 0.65, wy + 1.1, wz))
    this.add(P(boxNode(1.6, 0.08, 1.2, Mat.shingles), wx, wy + 2.0, wz))
    this.add(P(cylNode(0.05, 1.3, Mat.woodGrey), wx, wy + 1.4, wz, 0, 0, Math.PI / 2))
    this.solids.push(Solid.cyl(wx, wz, 0.78, 0.8, { base: wy, tag: 'well', surface: 'concrete' }))
    // woodpile against the barn
    for (let k = 0; k < 18; k++) {
      const x = -11 + (k % 6) * 0.3 - 0.8, y = Math.trunc(k / 6) * 0.26 + 0.13
      this.add(P(cylNode(0.13, 1.0, Mat.woodFresh, 10), x - 12, y, -4.9, Math.PI / 2, 0, 0))
    }
  }

  // MARK: grass

  buildGrass() {
    const rr = new RNG(99)
    const chunk = 32                       // Swift used 24 m; slightly larger chunks halve the draw calls
    const buckets = new Map()
    const flowers = { p: [], i: [] }
    const lim = Farm.half * 0.85
    const isFarm = this.mapIndex === 0, mi = this.mapIndex
    const target = Math.round((isFarm ? 80000 : this.map.grassCount * 2) * QUALITY)
    if (this._gridCount !== this.solids.length) this.buildGrid()
    let count = 0, tries = 0
    while (count < target && tries < target * 12) {
      tries++
      const x = rr.range(-lim, lim), z = rr.range(-lim, lim)
      if (!this.isGrass(x, z)) continue
      // denser near the middle of the map, thin at the edges
      const r = Math.hypot(x, z)
      if (r > 70 && rr.float() > 70 / r * 0.85) continue
      const cand = this.candidates(x, z, 0.3) || this.solids.map((_, i) => i)
      let blocked = false
      for (const si of cand) {
        const s = this.solids[si]
        if (s.tag !== 'fence' && s.tag !== 'edge' && x > s.minX - 0.3 && x < s.maxX + 0.3 && z > s.minZ - 0.3 && z < s.maxZ + 0.3) { blocked = true; break }
      }
      if (blocked) continue
      const y = this.terrain(x, z)
      const key = Math.floor((x + lim) / chunk) * 100 + Math.floor((z + lim) / chunk)
      let b = buckets.get(key)
      if (!b) { b = { p: [], i: [] }; buckets.set(key, b) }
      const hgt = rr.range(0.16, 0.42) * (isFarm && inPasture(x, z) ? 0.8 : mi === 1 ? 1.8 : mi === 3 ? 1.6 : 1)
      const w = rr.range(0.3, 0.55)
      const a0 = rr.range(0, Math.PI)
      for (let k = 0; k < 2; k++) {
        const a = a0 + k * Math.PI / 2
        const dx = Math.cos(a) * w / 2, dz = Math.sin(a) * w / 2
        const i = b.p.length / 3
        const lx = rr.range(-0.06, 0.06), lz = rr.range(-0.06, 0.06)
        b.p.push(x - dx, y - 0.02, z - dz, x + dx, y - 0.02, z + dz, x + dx + lx, y + hgt, z + dz + lz, x - dx + lx, y + hgt, z - dz + lz)
        b.i.push(i, i + 1, i + 2, i, i + 2, i + 3)
      }
      if (rr.chance(0.04)) {
        const fy = y + hgt * rr.range(0.5, 0.9), s = 0.05
        const i = flowers.p.length / 3
        flowers.p.push(x - s, fy, z - s, x + s, fy, z - s, x + s, fy, z + s, x - s, fy, z + s)
        flowers.i.push(i, i + 1, i + 2, i, i + 2, i + 3)
      }
      count++
    }
    // uv per quad (Swift (0,1),(1,1),(1,0),(0,0) with v flipped like meshGeometry)
    const build = (b, quadUV) => {
      const nv = b.p.length / 3
      const nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2)
      for (let v = 0; v < nv; v++) { nor[v * 3 + 1] = 1; uv[v * 2] = quadUV[(v % 4) * 2]; uv[v * 2 + 1] = quadUV[(v % 4) * 2 + 1] }
      const g = new THREE.BufferGeometry()
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(b.p), 3))
      g.setAttribute('normal', new THREE.BufferAttribute(nor, 3))
      g.setAttribute('uv', new THREE.BufferAttribute(uv, 2))
      g.setIndex(new THREE.BufferAttribute(nv > 65535 ? new Uint32Array(b.i) : new Uint16Array(b.i), 1))
      g.computeBoundingSphere()
      this._owned.push(g)
      return g
    }
    const bm = isFarm ? blade() : blade(this.map.grassLow, this.map.grassHigh)
    for (const b of buckets.values()) {
      const n = new THREE.Mesh(build(b, [0, 0, 1, 0, 1, 1, 0, 1]), bm)
      n.castShadow = false; n.receiveShadow = true
      n.matrixAutoUpdate = false
      this.grassRoot.add(n)
    }
    this.root.add(this.grassRoot)
    if (flowers.p.length) {
      const n = new THREE.Mesh(build(flowers, [0, 1, 1, 1, 1, 0, 0, 0]), Mat.flower)
      n.castShadow = false; n.receiveShadow = true
      n.matrixAutoUpdate = false
      this.root.add(n)
    }
    this.stats.grass = { blades: count, chunks: buckets.size }
  }
}

/// Set true to always build the full-resolution terrain colour map synchronously (tests, screenshots).
World.syncTextures = false
World.meterBox = meterBox
World.poly = poly

function now() { return typeof performance !== 'undefined' ? performance.now() : Date.now() }
