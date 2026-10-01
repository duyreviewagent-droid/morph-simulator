// Loose physics junk to knock over, Goat Simulator style. Ported from Knock.swift, with Rapier in
// place of SceneKit physics.
//
// Rapier setup (units: metres, kilograms, seconds; gravity is the game's choice, e.g. -9.81):
//   collision groups are (membership << 16) | filter, using the SceneKit category bits:
//     STATIC  = 1  terrain heightfield + every Solid (box / cylinder)      filter: everything
//     PUSHER  = 2  the player's kinematic capsule (makePusher)              filter: JUNK
//     ANIMAL  = 4  free for the game (NPC pushers)                          —
//     JUNK    = 8  knockables                                               filter: STATIC|PUSHER|ANIMAL|JUNK
import * as THREE from '../vendor/three.module.js'
import { RNG } from './util.js'
import { Ring, loftNode, limb, sphereNode, boxNode, cylNode, coneNode, torusNode } from './loft.js'
import { Mat, Coats } from './mats.js'
import { MapBuilder } from './mapbuilder.js'
import { Farm, meterBox, mergeStatic } from './world.js'

export const GROUP = { STATIC: 1, PUSHER: 2, ANIMAL: 4, JUNK: 8 }
export const groups = (member, filter) => ((member & 0xFFFF) << 16) | (filter & 0xFFFF)
const STATIC_GROUPS = groups(GROUP.STATIC, 0xFFFF)
const JUNK_GROUPS = groups(GROUP.JUNK, GROUP.STATIC | GROUP.PUSHER | GROUP.ANIMAL | GROUP.JUNK)
const PUSHER_GROUPS = groups(GROUP.PUSHER, GROUP.JUNK)

/// One piece of junk. mesh is a THREE.Group in world.knockRoot; body is a RAPIER.RigidBody (null without physics
/// or after removeKnockable).
export class Knockable {
  constructor(mesh, kind, points, explosive, group, spec) {
    this.mesh = mesh; this.kind = kind; this.points = points; this.explosive = explosive; this.group = group
    this.home = { pos: mesh.position.clone(), quat: mesh.quaternion.clone() }
    this.body = null; this.colliders = []
    this.knocked = false; this.knockedAt = 0; this.fuse = -1; this.exploded = false
    this.half = KnockKit.half(kind)
    this.spec = spec             // physics description (shapes, mass, bounce, friction)
  }
  /// Current world position (from the body if it exists, else the mesh).
  get pos() { if (this.body) { const t = this.body.translation(); return new THREE.Vector3(t.x, t.y, t.z) } return this.mesh.position.clone() }
  /// Current local up axis in world space.
  get up() { const q = this.body ? this.body.rotation() : this.mesh.quaternion; return new THREE.Vector3(0, 1, 0).applyQuaternion(new THREE.Quaternion(q.x, q.y, q.z, q.w)) }
}

// Shape helpers for specs: SceneKit shapes are centred on the node like Rapier's.
const box = (w, h, l) => ({ t: 'cuboid', a: [w / 2, h / 2, l / 2] })
const cyl = (r, h) => ({ t: 'cylinder', a: [h / 2, r] })
const cone = (r, h) => ({ t: 'cone', a: [h / 2, r] })
const ball = (r, y = 0) => ({ t: 'ball', a: [r], y })

const protos = new Map()
let _mats = null
function M() {
  if (_mats) return _mats
  _mats = {
    orange: Coats.coat('bands', [0.95, 0.4, 0.05], [0.95, 0.95, 0.93]),
    redBarrel: Coats.coat('bands', [0.75, 0.08, 0.05], [0.95, 0.8, 0.1]),
    woodBarrel: Coats.coat('bands', [0.45, 0.28, 0.14], [0.3, 0.3, 0.3]),
    pin: Coats.coat('bands', [0.95, 0.95, 0.93], [0.85, 0.08, 0.08]),
    clay: Coats.coat('skin', [0.7, 0.4, 0.22], [0.55, 0.3, 0.15]),
    melon: Coats.coat('stripes', [0.2, 0.45, 0.12], [0.1, 0.25, 0.05]),
    can: Coats.coat('bands', [0.85, 0.1, 0.1], [0.9, 0.9, 0.9]),
  }
  return _mats
}
const at = (o, x, y, z, rx, ry, rz) => { o.position.set(x, y, z); if (rx !== undefined) { o.rotation.order = 'YXZ'; o.rotation.set(rx, ry, rz) } return o }

export const KnockKit = {
  get orange() { return M().orange }, get redBarrel() { return M().redBarrel }, get woodBarrel() { return M().woodBarrel },
  get pin() { return M().pin }, get clay() { return M().clay }, get melon() { return M().melon }, get can() { return M().can },

  /// Builds one knockable of a kind, centred on the origin (its base sits at -half).
  /// Returns { mesh, points, explosive, spec: { shapes, mass, bounce, friction } }.
  /// The parts are merged into one mesh per material once per kind; instances share those geometries.
  make(kind) {
    let proto = protos.get(kind)
    if (!proto) {
      const raw = KnockKit.makeRaw(kind)
      const merged = new THREE.Group()
      mergeStatic(raw.mesh, merged, [], 1e9)
      proto = { parts: merged.children.map(o => ({ geometry: o.geometry, material: o.material, cast: o.castShadow })), points: raw.points, explosive: raw.explosive, spec: raw.spec }
      protos.set(kind, proto)
    }
    const n = new THREE.Group(); n.rotation.order = 'YXZ'
    for (const p of proto.parts) {
      const m = new THREE.Mesh(p.geometry, p.material)
      m.castShadow = p.cast; m.receiveShadow = true
      m.matrixAutoUpdate = false
      n.add(m)
    }
    return { mesh: n, points: proto.points, explosive: proto.explosive, spec: proto.spec }
  },

  /// The unmerged scene graph for a kind (a straight port of KnockKit.make in Swift).
  makeRaw(kind) {
    const m = M()
    const n = new THREE.Group(); n.rotation.order = 'YXZ'
    const geo = new THREE.Group()
    n.add(geo)
    let pts = 10, boom = false
    let spec
    const body = (shapes, mass, bounce = 0.2, friction = 0.7) => { spec = { shapes, mass, bounce, friction } }
    switch (kind) {
      case 'crate': {
        const b = meterBox(0.8, 0.8, 0.8, Mat.woodFresh, 1.2)
        b.add(at(boxNode(0.82, 0.08, 0.82, Mat.woodGrey), 0, 0.36, 0)); b.add(at(boxNode(0.82, 0.08, 0.82, Mat.woodGrey), 0, -0.36, 0))
        geo.add(b)
        body([box(0.8, 0.8, 0.8)], 18)
        pts = 15
        break
      }
      case 'barrel': case 'boom': {
        boom = kind === 'boom'
        geo.add(cylNode(0.3, 0.9, boom ? m.redBarrel : m.woodBarrel, 18))
        for (const y of [-0.3, 0.3]) geo.add(at(cylNode(0.305, 0.05, Mat.galv, 18), 0, y, 0))
        body([cyl(0.3, 0.9)], boom ? 20 : 28)
        pts = boom ? 50 : 20
        break
      }
      case 'cone':
        geo.add(coneNode(0.17, 0.02, 0.5, m.orange, 14))
        geo.add(at(boxNode(0.4, 0.03, 0.4, Coats.plain([0.1, 0.1, 0.1])), 0, -0.24, 0))
        body([cone(0.2, 0.5)], 2)
        pts = 5
        break
      case 'trash':
        geo.add(cylNode(0.28, 0.8, Mat.galv, 18))
        geo.add(at(cylNode(0.3, 0.05, Mat.galv, 18), 0, 0.42, 0))
        body([cyl(0.28, 0.85)], 8, 0.3)
        pts = 10
        break
      case 'hay':
        geo.add(meterBox(0.9, 0.45, 0.5, Mat.hay, 1))
        body([box(0.9, 0.45, 0.5)], 14)
        pts = 10
        break
      case 'snowman': {
        const snow = MapBuilder.snow
        geo.add(at(sphereNode(0.45, snow, 16), 0, -0.35, 0))
        geo.add(at(sphereNode(0.33, snow, 16), 0, 0.3, 0))
        geo.add(at(sphereNode(0.23, snow, 16), 0, 0.78, 0))
        geo.add(at(coneNode(0.04, 0.002, 0.2, Coats.plain([0.95, 0.45, 0.05]), 8), 0, 0.78, 0.28, Math.PI / 2, 0, 0))
        for (const sx of [-1, 1]) {
          geo.add(at(sphereNode(0.03, Mat.black, 6), sx * 0.08, 0.86, 0.2))
          geo.add(at(limb(0.45, 0.015, 0.01, Mat.bark, { seg: 5, dir: [sx, 0.4, 0] }), sx * 0.28, 0.35, 0))
        }
        geo.add(at(cylNode(0.16, 0.25, Mat.black, 14), 0, 1.05, 0))
        // + a flat-bottomed puck: Rapier has no rolling friction, and a snowman on one sphere rolls off any slope
        body([ball(0.45, -0.35), ball(0.33, 0.3), ball(0.23, 0.78), { t: 'cylinder', a: [0.04, 0.3], y: -0.76 }], 30)
        pts = 25
        break
      }
      case 'gnome': {
        geo.add(at(coneNode(0.14, 0.1, 0.3, Coats.plain([0.2, 0.35, 0.8]), 12), 0, -0.05, 0))
        geo.add(at(sphereNode(0.1, Mat.skin, 12), 0, 0.17, 0))
        geo.add(at(coneNode(0.1, 0.005, 0.25, Coats.plain([0.85, 0.1, 0.1]), 12), 0, 0.36, 0))
        const beard = at(sphereNode(0.08, Coats.plain([0.95, 0.95, 0.95]), 10), 0, 0.1, 0.07); beard.scale.set(1, 1.3, 0.6)
        geo.add(beard)
        body([cyl(0.13, 0.6)], 3)
        pts = 15
        break
      }
      case 'beachball':
        geo.add(sphereNode(0.35, Coats.coat('bands', [0.95, 0.2, 0.2], [0.2, 0.5, 0.95]), 18))
        body([ball(0.35)], 0.4, 0.85, 0.4)
        pts = 5
        break
      case 'tire':
        geo.add(torusNode(0.32, 0.12, Mat.rubber, 24, 10))
        body([cyl(0.44, 0.24)], 9, 0.5)
        pts = 10
        break
      case 'pin':
        geo.add(loftNode([Ring([0, -0.3, 0], 0.05, 0.05), Ring([0, -0.2, 0], 0.075, 0.075), Ring([0, 0.02, 0], 0.04, 0.04), Ring([0, 0.18, 0], 0.05, 0.05), Ring([0, 0.3, 0], 0.01, 0.01)],
          m.pin, { seg: 14, smooth: 3 }))
        body([cyl(0.06, 0.6)], 1.5, 0.3)
        pts = 20
        break
      case 'domino': {
        geo.add(boxNode(0.5, 1.0, 0.1, Coats.plain([0.08, 0.08, 0.08], 0.3)))
        const pip = Coats.plain([0.95, 0.95, 0.95])
        for (let k = 0; k < 3; k++) { const d = at(sphereNode(0.04, pip, 6), (k - 1) * 0.12, (k - 1) * 0.2, 0.05); d.scale.set(1, 1, 0.2); geo.add(d) }
        body([box(0.5, 1.0, 0.1)], 3, 0.2, 0.5)
        pts = 5
        break
      }
      case 'can':
        geo.add(cylNode(0.06, 0.16, m.can, 12))
        body([cyl(0.06, 0.16)], 0.3, 0.3)
        pts = 3
        break
      case 'vase':
        geo.add(loftNode([Ring([0, -0.3, 0], 0.12, 0.12), Ring([0, -0.1, 0], 0.22, 0.22), Ring([0, 0.15, 0], 0.14, 0.14), Ring([0, 0.28, 0], 0.08, 0.08), Ring([0, 0.32, 0], 0.1, 0.1)], m.clay, { seg: 16, smooth: 3 }))
        body([cyl(0.18, 0.62)], 4)
        pts = 15
        break
      case 'melon': {
        const s = sphereNode(0.22, m.melon, 16); s.scale.set(1, 0.85, 1.25)
        geo.add(s)
        body([ball(0.21)], 5, 0.2)
        pts = 10
        break
      }
      case 'barrier': {
        geo.add(at(boxNode(1.4, 0.3, 0.06, m.orange), 0, 0.3, 0))
        const white = Coats.plain([0.9, 0.9, 0.9])
        for (const sx of [-0.6, 0.6]) geo.add(at(boxNode(0.06, 1.0, 0.4, white), sx, 0, 0))
        body([box(1.4, 1.0, 0.4)], 10)
        pts = 10
        break
      }
      default:
        geo.add(boxNode(0.5, 0.5, 0.5, Mat.woodFresh))
        body([box(0.5, 0.5, 0.5)], 10)
    }
    n.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true } })
    return { mesh: n, points: pts, explosive: boom, spec }
  },

  /// Half-height of each kind (its base sits on the ground).
  half(kind) {
    switch (kind) {
      case 'crate': return 0.4
      case 'barrel': case 'boom': return 0.45
      case 'cone': return 0.25
      case 'trash': return 0.43
      case 'hay': return 0.225
      case 'snowman': return 0.8
      case 'gnome': return 0.25
      case 'beachball': return 0.35
      case 'tire': return 0.12
      case 'pin': return 0.3
      case 'domino': return 0.5
      case 'can': return 0.08
      case 'vase': return 0.31
      case 'melon': return 0.19
      case 'barrier': return 0.5
      default: return 0.25
    }
  },
}

// ---------------------------------------------------------------------------------------------
// MARK: Rapier bodies

const shapeVolume = s => s.t === 'cuboid' ? 8 * s.a[0] * s.a[1] * s.a[2] : s.t === 'ball' ? 4 / 3 * Math.PI * s.a[0] ** 3 :
  s.t === 'cylinder' ? Math.PI * s.a[1] ** 2 * 2 * s.a[0] : Math.PI * s.a[1] ** 2 * 2 * s.a[0] / 3

function colliderDesc(R, s) {
  switch (s.t) {
    case 'cuboid': return R.ColliderDesc.cuboid(s.a[0], s.a[1], s.a[2])
    case 'cylinder': return R.ColliderDesc.cylinder(s.a[0], s.a[1])
    case 'cone': return R.ColliderDesc.cone(s.a[0], s.a[1])
    default: return R.ColliderDesc.ball(s.a[0])
  }
}

/// Creates (or re-creates) the dynamic body for a knockable at its mesh's current transform.
function makeBody(w, k) {
  const R = w.R, pw = w.physics
  if (!R || !pw) return
  const p = k.mesh.position, q = k.mesh.quaternion, sp = k.spec
  const thin = k.half < 0.1 || k.kind === 'domino' || k.kind === 'pin'
  const bd = R.RigidBodyDesc.dynamic().setTranslation(p.x, p.y, p.z).setRotation({ x: q.x, y: q.y, z: q.z, w: q.w })
    .setLinearDamping(0.05).setAngularDamping(0.2).setCanSleep(true).setCcdEnabled(thin)
  const body = pw.createRigidBody(bd)
  const vol = sp.shapes.reduce((a, s) => a + shapeVolume(s), 0)
  k.colliders = sp.shapes.map(s => {
    let cd = colliderDesc(R, s)
      .setMass(sp.mass * shapeVolume(s) / vol)
      .setRestitution(sp.bounce).setFriction(sp.friction)
      .setRestitutionCombineRule(R.CoefficientCombineRule.Max)
      .setCollisionGroups(JUNK_GROUPS).setSolverGroups(JUNK_GROUPS)
    if (s.y) cd = cd.setTranslation(0, s.y, 0)
    const c = pw.createCollider(cd, body)
    w._knockByCollider.set(c.handle, k)
    return c
  })
  k.body = body
}

/// Knockables start asleep so stacks, dominoes and snowmen stand exactly as placed until something touches
/// them (contacts, the pusher and applyImpulse(..., true) all wake bodies).
function settle(k) { if (k.body) k.body.sleep() }

function dropBody(w, k) {
  if (!k.body || !w.physics) return
  for (const c of k.colliders) w._knockByCollider.delete(c.handle)
  w.physics.removeRigidBody(k.body)
  k.body = null; k.colliders = []
}

/// Static physics for the ground, buildings and walls so junk can land on things.
export function buildPhysics(w) {
  const R = w.R, pw = w.physics
  // terrain: a heightfield on the same 320×320 grid as the render mesh (columns run along x, rows along z)
  const tg = w.terrainGrid
  const N = tg.N, hf = new Float32Array((N + 1) * (N + 1))
  for (let j = 0; j <= N; j++) for (let i = 0; i <= N; i++) hf[j + i * (N + 1)] = tg.heights[j * (N + 1) + i]
  const tb = pw.createRigidBody(R.RigidBodyDesc.fixed())
  pw.createCollider(R.ColliderDesc.heightfield(N, N, hf, { x: 2 * tg.H, y: 1, z: 2 * tg.H })
    .setFriction(0.8).setRestitution(0).setCollisionGroups(STATIC_GROUPS).setSolverGroups(STATIC_GROUPS), tb)
  w._bodies.push(tb)
  // every solid as a box or cylinder from its bottom up to its top at (mid x, max z), on one fixed body
  const sb = pw.createRigidBody(R.RigidBodyDesc.fixed())
  w._bodies.push(sb)
  w.staticColliders = []
  for (const s of w.solids) {
    const top = s.top((s.minX + s.maxX) / 2, s.maxZ)
    const base = Math.max(s.bottom, -20)
    const h = Math.max(0.1, top - base)
    let cd
    if (s.round) cd = R.ColliderDesc.cylinder(h / 2, s.round.r).setTranslation(s.round.cx, base + h / 2, s.round.cz)
    else cd = R.ColliderDesc.cuboid((s.maxX - s.minX) / 2, h / 2, (s.maxZ - s.minZ) / 2).setTranslation((s.minX + s.maxX) / 2, base + h / 2, (s.minZ + s.maxZ) / 2)
    cd = cd.setFriction(0.6).setRestitution(0).setCollisionGroups(STATIC_GROUPS).setSolverGroups(STATIC_GROUPS)
    w.staticColliders.push(pw.createCollider(cd, sb))
  }
}

export function syncKnockables(w) {
  for (const k of w.knockables) {
    const b = k.body
    if (!b || b.isSleeping()) continue
    const t = b.translation(), r = b.rotation()
    k.mesh.position.set(t.x, t.y, t.z)
    k.mesh.quaternion.set(r.x, r.y, r.z, r.w)
  }
}

/// Puts a knockable back where it started (re-adding its mesh and body if it was removed).
export function resetKnockable(w, k) {
  k.mesh.position.copy(k.home.pos)
  k.mesh.quaternion.copy(k.home.quat)
  if (!k.mesh.parent) w.knockRoot.add(k.mesh)
  if (!k.body) makeBody(w, k)
  else {
    k.body.setTranslation(k.home.pos, true)
    k.body.setRotation(k.home.quat, true)
    k.body.setLinvel({ x: 0, y: 0, z: 0 }, true)
    k.body.setAngvel({ x: 0, y: 0, z: 0 }, true)
  }
  settle(k)
  k.knocked = false
  k.fuse = -1
  k.exploded = false
}

/// Takes a knockable out of the world (explosions): body and colliders are removed, the mesh is detached.
export function removeKnockable(w, k) {
  dropBody(w, k)
  k.mesh.removeFromParent()
}

export function disposePhysics(w) {
  const pw = w.physics
  if (!pw) return
  for (const k of w.knockables) dropBody(w, k)
  for (const b of w._bodies) pw.removeRigidBody(b)
  w._bodies.length = 0
  w.staticColliders = []
}

// ---------------------------------------------------------------------------------------------
// MARK: placement

function placeKnock(w, kind, x, z, { y = null, yaw = 0, group = '' } = {}) {
  const { mesh, points, explosive, spec } = KnockKit.make(kind)
  const gy = y === null ? w.ground(x, z, 100, 0.2).g : y
  mesh.position.set(x, gy + KnockKit.half(kind) + 0.01, z)
  mesh.rotation.set(0, yaw, 0)
  mesh.updateMatrix()
  w.knockRoot.add(mesh)
  const k = new Knockable(mesh, kind, points, explosive, group, spec)
  makeBody(w, k)
  settle(k)
  w.knockables.push(k)
  return k
}

function crateStack(w, x, z, yaw) {
  const dx = Math.cos(yaw), dz = -Math.sin(yaw)
  for (let row = 0; row < 3; row++) for (let k = 0; k < 3 - row; k++) {
    const off = (k - (2 - row) / 2) * 0.82
    const gy = w.terrain(x, z)
    placeKnock(w, 'crate', x + dx * off, z + dz * off, { y: gy + row * 0.81, yaw, group: 'stack' })
  }
}
function canPyramid(w, x, z, base) {
  for (let row = 0; row < 4; row++) for (let k = 0; k < 4 - row; k++) {
    placeKnock(w, 'can', x + (k - (3 - row) / 2) * 0.13, z, { y: base + row * 0.165, group: 'cans' })
  }
}
function bowling(w, x, z) {
  for (let row = 0; row < 4; row++) for (let j = 0; j <= row; j++) placeKnock(w, 'pin', x + (j - row / 2) * 0.32, z + row * 0.3, { group: 'bowling' })
}
function dominoes(w, x, z, count, yaw) {
  for (let k = 0; k < count; k++) {
    const a = yaw + k * 0.05
    const px = x + Math.sin(a) * k * 0.55 + Math.cos(a) * Math.sin(k * 0.25) * 1.5
    const pz = z + Math.cos(a) * k * 0.55 - Math.sin(a) * Math.sin(k * 0.25) * 1.5
    placeKnock(w, 'domino', px, pz, { yaw: a, group: 'dominoes' })
  }
}
function tireStack(w, x, z) {
  const gy = w.terrain(x, z)
  for (let k = 0; k < 5; k++) placeKnock(w, 'tire', x, z, { y: gy + k * 0.24, group: 'tires' })
}

const collideTest = (w, x, z, r) => w.solids.some(s => s.tag !== 'edge' && x > s.minX - r && x < s.maxX + r && z > s.minZ - r && z < s.maxZ + r)

const SETS = [
  ['crate', 'barrel', 'hay', 'hay', 'gnome', 'melon', 'barrel'],        // farm
  ['crate', 'barrel', 'tire', 'crate', 'cone'],                        // savanna
  ['snowman', 'snowman', 'crate', 'barrel', 'snowman'],                // arctic
  ['crate', 'vase', 'barrel', 'melon', 'vase'],                        // jungle
  ['vase', 'vase', 'crate', 'tire', 'barrel'],                         // desert
  ['beachball', 'beachball', 'cone', 'crate', 'melon', 'barrel'],      // beach
  ['crate', 'barrel', 'gnome', 'hay'],                                 // forest
  ['crate', 'barrel', 'cone', 'tire'],                                 // mountains
  ['barrel', 'crate', 'barrel'],                                       // swamp
  ['trash', 'cone', 'barrier', 'gnome', 'beachball', 'trash'],         // park
]

/// Scatters junk and set pieces around the current map.
export function buildKnockables(w) {
  w._knockByCollider = new Map()
  const rr = new RNG(w.mapIndex * 97 + 5)
  const kinds = SETS[w.mapIndex]
  const isFarm = w.mapIndex === 0
  const spawn = isFarm ? [2, 0, 7] : w.map.spawn
  let placed = 0, tries = 0
  const target = isFarm ? 90 : 80
  while (placed < target && tries < target * 20) {
    tries++
    const a = rr.range(0, 2 * Math.PI), d = rr.range(5, Farm.half * 0.55)
    const x = spawn[0] + Math.cos(a) * d, z = spawn[2] + Math.sin(a) * d
    if (!(Math.abs(x) < Farm.half - 10 && Math.abs(z) < Farm.half - 10 && w.waterLevel(x, z) === null)) continue
    if (collideTest(w, x, z, 0.6)) continue
    placeKnock(w, kinds[rr.int(kinds.length)], x, z, { yaw: rr.range(0, 6.28) })
    placed++
  }
  // explosive barrels, set pieces
  const spot = (r0, r1) => {
    for (let i = 0; i < 40; i++) {
      const a = rr.range(0, 2 * Math.PI), d = rr.range(r0, r1)
      const x = spawn[0] + Math.cos(a) * d, z = spawn[2] + Math.sin(a) * d
      if (Math.abs(x) < Farm.half - 10 && Math.abs(z) < Farm.half - 10 && w.waterLevel(x, z) === null && !collideTest(w, x, z, 2.5)) return [x, z]
    }
    return null
  }
  let s
  for (let i = 0; i < (isFarm ? 6 : 8); i++) if ((s = spot(10, Farm.half * 0.5))) placeKnock(w, 'boom', s[0], s[1])
  for (let i = 0; i < 4; i++) if ((s = spot(8, 60))) crateStack(w, s[0], s[1], rr.range(0, 3))
  if ((s = spot(8, 20))) bowling(w, s[0], s[1])
  if ((s = spot(12, 40))) dominoes(w, s[0], s[1], 24, rr.range(0, 6.28))
  for (let i = 0; i < 2; i++) if ((s = spot(10, 50))) tireStack(w, s[0], s[1])
  if (isFarm) {
    // tin cans lined up on the porch rail and a row of gnomes
    canPyramid(w, Farm.house.x + 2, Farm.house.z - Farm.house.d / 2 - 1.5, 0.68)
    for (let k = 0; k < 6; k++) placeKnock(w, 'gnome', Farm.house.x - 5 + k * 2, Farm.house.z - Farm.house.d / 2 - 4.6)
    crateStack(w, -9, -3.5, 0.2)
    for (let k = 0; k < 4; k++) placeKnock(w, 'boom', -12 + k * 0.7, -4.2)
  }
}

// ---------------------------------------------------------------------------------------------
// MARK: player pusher

/// A kinematic capsule that shoves knockables (group PUSHER, hits JUNK only).
/// setPosition takes the FEET position; the capsule is centred height/2 above it.
export function makePusher(R, pw) {
  const body = pw.createRigidBody(R.RigidBodyDesc.kinematicPositionBased().setTranslation(0, -1000, 0))
  let collider = null, radius = 0.4, height = 1.6
  const api = {
    body,
    get collider() { return collider },
    setShape(r, h) {
      radius = Math.max(0.05, r); height = Math.max(h, 2 * radius + 0.02)
      if (collider) pw.removeCollider(collider, true)
      collider = pw.createCollider(R.ColliderDesc.capsule(height / 2 - radius, radius).setFriction(0.5)
        .setCollisionGroups(PUSHER_GROUPS).setSolverGroups(PUSHER_GROUPS), body)
    },
    /// teleport = true jumps there without sweeping (no shove along the way).
    setPosition(x, y, z, teleport = false) {
      const p = { x, y: y + height / 2, z }
      if (teleport) body.setTranslation(p, true)
      body.setNextKinematicTranslation(p)
    },
    dispose() { pw.removeRigidBody(body); collider = null },
  }
  api.setShape(radius, height)
  return api
}
