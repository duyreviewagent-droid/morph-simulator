// Things you can wear or have happen to each part. Index 0 is "none", 1 is "hurt". Ported from AddOns.swift.
import * as THREE from '../vendor/three.module.js'
import { V3 } from './util.js'
import { pbr } from './tex.js'
import { Ring, loftNode, sphereNode, boxNode, cylNode, coneNode, torusNode, tubeNode, at, rot, scl, group } from './loft.js'
import { Mat, Coats } from './mats.js'
import { disposeTree } from './genparts.js'

let _gold, _steel, _bandage, _glow, _star, _flame
const cloth = c => Coats.plain(c, 0.8)

export const AddOns = {
  head: ['None', 'Hurt', 'Top Hat', 'Crown', 'Party Hat', 'Cowboy Hat', 'Sunglasses', 'Viking Helmet', 'Clown Nose', 'Headphones', 'Halo', 'Propeller Cap'],
  body: ['None', 'Hurt', 'Superhero Cape', 'Jetpack', 'Tutu', 'Bow Tie', 'Backpack', 'Life Jacket', 'Armor', 'Balloons', 'Scarf', 'Angel Wings'],
  legs: ['None', 'Hurt', 'Roller Skates', 'Spring Shoes', 'Rocket Boots', 'Rain Boots', 'Socks', 'Flippers', 'High Heels', 'Stilts', 'Sneakers', 'Ice Skates'],
  names(s) { return [AddOns.head, AddOns.body, AddOns.legs][s] },
  blurbs: {
    'Propeller Cap': 'hold SPACE to float down', 'Superhero Cape': 'hold SPACE to glide', 'Jetpack': 'hold SPACE to fly',
    'Life Jacket': 'float and swim fast', 'Armor': 'nothing knocks you over', 'Balloons': 'floaty jumps', 'Angel Wings': 'flap and glide',
    'Roller Skates': 'zoom!', 'Spring Shoes': 'huge jumps', 'Rocket Boots': 'double jump', 'Flippers': 'swim fast', 'Stilts': 'so tall',
    'Sneakers': 'run faster', 'Ice Skates': 'slide fast', 'Rain Boots': 'splash through water', 'Hurt': 'ouch…',
  },

  get gold() { return _gold || (_gold = pbr([1, 0.78, 0.25], { rough: 0.25, metal: 1 })) },
  get steel() { return _steel || (_steel = pbr([0.7, 0.72, 0.75], { rough: 0.3, metal: 0.9 })) },
  get bandage() { return _bandage || (_bandage = Coats.coat('bands', [0.95, 0.94, 0.9], [0.85, 0.83, 0.78])) },
  get glow() { return _glow || (_glow = pbr([1, 0.95, 0.6], { rough: 0.3, emissive: [1, 0.9, 0.5] })) },
  get star() { return _star || (_star = pbr([1, 0.9, 0.2], { rough: 0.3, emissive: [1, 0.85, 0.1] })) },
  get flame() { return _flame || (_flame = pbr([1, 0.5, 0.1], { rough: 1, emissive: [1, 0.55, 0.1], opacity: 0.85 })) },

  box, buildHead, buildBody, buildFoot,
}

// ---- local-space bounding box (like SceneKit's node.boundingBox: own geometry + children, in the node's space) ----

const _gb = new THREE.Box3()
function box(n) {
  const out = new THREE.Box3()
  const visit = (o, m) => {
    if (o.isMesh && o.geometry) {
      if (!o.geometry.boundingBox) o.geometry.computeBoundingBox()
      _gb.copy(o.geometry.boundingBox)
      if (m) _gb.applyMatrix4(m)
      out.union(_gb)
    }
    for (const c of o.children) {
      if (c.matrixAutoUpdate) c.updateMatrix()
      visit(c, m ? new THREE.Matrix4().multiplyMatrices(m, c.matrix) : c.matrix.clone())
    }
  }
  visit(n, null)
  const min = out.isEmpty() ? V3() : out.min.clone(), max = out.isEmpty() ? V3() : out.max.clone()
  return { min, max, size: max.clone().sub(min), center: min.clone().add(max).multiplyScalar(0.5) }
}

const named = (o, name) => { o.name = name; return o }

// ---- head ----

export function buildHead(i, n) {
  const root = named(group(), 'addon')
  const b = box(n)
  const w = Math.max(0.08, Math.min(b.size.x, b.size.z))
  const top = V3(b.center.x, b.max.y, b.center.z - b.size.z * 0.1)
  const face = V3(b.center.x, b.center.y + b.size.y * 0.15, b.min.z + b.size.z * 0.62)
  const { gold, steel } = AddOns
  switch (AddOns.head[i]) {
    case 'Hurt': {
      const bandage = AddOns.bandage
      root.add(rot(at(torusNode(w * 0.52, w * 0.07, bandage), b.center.x, b.center.y + b.size.y * 0.25, b.center.z), 0.25, 0, 0.1))
      root.add(rot(at(boxNode(w * 0.25, w * 0.25, 0.01, bandage), b.center.x + w * 0.25, b.center.y + b.size.y * 0.3, b.max.z * 0.9), 0, 0, 0.7))
      const stars = named(group(), 'spin'); stars.position.copy(top).add(V3(0, w * 0.35, 0))
      for (let k = 0; k < 4; k++) {
        const a = k / 4 * 2 * Math.PI
        stars.add(at(sphereNode(w * 0.07, AddOns.star, 8), Math.cos(a) * w * 0.6, 0, Math.sin(a) * w * 0.6))
      }
      root.add(stars)
      break
    }
    case 'Top Hat':
      root.add(at(cylNode(w * 0.62, w * 0.04, Mat.black, 24), top.x, top.y, top.z))
      root.add(at(cylNode(w * 0.4, w * 0.8, Mat.black, 24), top.x, top.y + w * 0.4, top.z))
      root.add(at(cylNode(w * 0.405, w * 0.12, cloth([0.6, 0.05, 0.05]), 24), top.x, top.y + w * 0.1, top.z))
      break
    case 'Crown': {
      root.add(at(tubeNode(w * 0.38, w * 0.42, w * 0.22, gold, 24), top.x, top.y + w * 0.08, top.z))
      const gems = [[0.8, 0.05, 0.1], [0.1, 0.3, 0.9], [0.1, 0.7, 0.2]]
      for (let k = 0; k < 6; k++) {
        const a = k / 6 * 2 * Math.PI
        root.add(at(coneNode(w * 0.07, 0.003, w * 0.22, gold, 6), top.x + Math.cos(a) * w * 0.4, top.y + w * 0.3, top.z + Math.sin(a) * w * 0.4))
        root.add(at(sphereNode(w * 0.035, Coats.glossy(gems[k % 3]), 8), top.x + Math.cos(a) * w * 0.42, top.y + w * 0.08, top.z + Math.sin(a) * w * 0.42))
      }
      break
    }
    case 'Party Hat':
      root.add(at(coneNode(w * 0.3, 0.005, w * 0.75, Coats.coat('bands', [0.95, 0.3, 0.6], [0.3, 0.7, 0.95]), 20), top.x, top.y + w * 0.35, top.z))
      root.add(at(sphereNode(w * 0.08, cloth([1, 0.9, 0.2]), 10), top.x, top.y + w * 0.75, top.z))
      break
    case 'Cowboy Hat':
      root.add(scl(at(tubeNode(w * 0.3, w * 0.85, w * 0.03, Mat.leather, 30), top.x, top.y + w * 0.02, top.z), 1, 1, 0.85))
      root.add(at(scl(sphereNode(w * 0.4, Mat.leather, 16), 1, 0.8, 1.1), top.x, top.y + w * 0.15, top.z))
      break
    case 'Sunglasses': {
      const g = group(); g.position.copy(face).add(V3(0, 0, b.size.z * 0.02))
      root.add(g)
      for (const sx of [-1, 1]) g.add(at(scl(sphereNode(w * 0.16, Coats.glossy([0.02, 0.02, 0.03]), 12), 1.2, 0.8, 0.3), sx * w * 0.24, 0, w * 0.12))
      g.add(at(boxNode(w * 0.9, w * 0.03, w * 0.03, Mat.black), 0, w * 0.06, w * 0.12))
      break
    }
    case 'Viking Helmet':
      root.add(at(scl(sphereNode(w * 0.5, steel, 20), 1, 0.75, 1.05), top.x, top.y - w * 0.05, top.z))
      for (const sx of [-1, 1]) root.add(at(rot(coneNode(w * 0.1, 0.004, w * 0.5, Mat.horn, 10), 0, 0, -sx * 0.7), top.x + sx * w * 0.5, top.y + w * 0.2, top.z))
      break
    case 'Clown Nose':
      root.add(at(sphereNode(Math.max(0.03, w * 0.12), Coats.glossy([0.9, 0.05, 0.05]), 14), b.center.x, b.center.y - b.size.y * 0.05, b.max.z))
      break
    case 'Headphones':
      root.add(at(rot(torusNode(w * 0.55, w * 0.04, Mat.black), 0, 0, Math.PI / 2), b.center.x, b.center.y + b.size.y * 0.15, b.center.z))
      for (const sx of [-1, 1]) root.add(at(rot(cylNode(w * 0.18, w * 0.12, cloth([0.9, 0.2, 0.3]), 16), 0, 0, Math.PI / 2), b.center.x + sx * w * 0.55, b.center.y, b.center.z))
      break
    case 'Halo': {
      const hn = named(torusNode(w * 0.4, w * 0.04, AddOns.glow), 'bob')
      hn.position.copy(top).add(V3(0, w * 0.35, 0))
      root.add(hn)
      break
    }
    case 'Propeller Cap': {
      root.add(at(scl(sphereNode(w * 0.45, Coats.coat('bands', [0.95, 0.8, 0.1], [0.2, 0.4, 0.95]), 16), 1, 0.55, 1), top.x, top.y, top.z))
      root.add(at(cylNode(w * 0.02, w * 0.18, Mat.black, 6), top.x, top.y + w * 0.3, top.z))
      const prop = named(group(), 'spin'); prop.position.copy(top).add(V3(0, w * 0.4, 0))
      for (let k = 0; k < 3; k++) prop.add(rot(at(boxNode(w * 0.5, w * 0.01, w * 0.1, cloth([0.9, 0.15, 0.1])), Math.cos(k * 2.094) * w * 0.25, 0, Math.sin(k * 2.094) * w * 0.25), 0, -k * 2.094, 0.2))
      root.add(prop)
      break
    }
  }
  return root
}

// ---- body ----

export function buildBody(i, n) {
  const root = named(group(), 'addon')
  const b = box(n)
  const w = Math.max(0.1, b.size.x), d = Math.max(0.1, b.size.z), h = Math.max(0.1, b.size.y)
  const c = b.center
  const back = V3(c.x, c.y + h * 0.1, b.min.z), front = V3(c.x, c.y + h * 0.25, b.max.z)
  const { gold, steel } = AddOns
  switch (AddOns.body[i]) {
    case 'Hurt': {
      const bandage = AddOns.bandage
      for (let k = 0; k < 3; k++) {
        const t = torusNode(Math.max(w, d) * 0.5, Math.max(0.015, w * 0.04), bandage)
        root.add(rot(at(scl(t, w / Math.max(w, d), 1, d / Math.max(w, d)), c.x, b.min.y + h * (0.3 + k * 0.18), c.z), 0.1 * k, 0, 0.15))
      }
      root.add(rot(at(boxNode(w * 0.12, h * 0.6, w * 0.05, cloth([0.85, 0.85, 0.9])), c.x + w * 0.2, c.y, b.max.z + 0.01), 0, 0, 0.6))
      break
    }
    case 'Superhero Cape': {
      const cape = named(group(), 'sway'); cape.position.set(c.x, b.max.y - h * 0.05, b.min.z - 0.02)
      root.add(cape)
      const len = Math.max(0.5, h * 1.3)
      cape.add(loftNode([Ring([0, 0, 0], w * 0.45, 0.01), Ring([0, -len * 0.5, -0.04], w * 0.6, 0.012), Ring([0, -len, -0.08], w * 0.75, 0.012)],
        Coats.membrane([0.8, 0.05, 0.08], 1), { seg: 8, ref: [0, 0, 1], smooth: 2 }))
      break
    }
    case 'Jetpack': {
      const j = group(); j.position.copy(back).sub(V3(0, 0, 0.08))
      root.add(j)
      for (const sx of [-1, 1]) {
        j.add(at(cylNode(w * 0.14, h * 0.55, steel, 14), sx * w * 0.16, 0, 0))
        j.add(at(coneNode(w * 0.14, w * 0.08, w * 0.15, Mat.black, 12), sx * w * 0.16, -h * 0.34, 0))
        const f = named(rot(coneNode(w * 0.09, 0.001, h * 0.35, AddOns.flame, 10), Math.PI, 0, 0), 'flame')
        f.position.set(sx * w * 0.16, -h * 0.58, 0)
        f.castShadow = false
        j.add(f)
      }
      j.add(at(boxNode(w * 0.2, h * 0.35, w * 0.1, cloth([0.8, 0.1, 0.1])), 0, 0, 0.02))
      break
    }
    case 'Tutu':
      root.add(rot(at(tubeNode(Math.max(w, d) * 0.4, Math.max(w, d) * 0.85, h * 0.08, Coats.membrane([1, 0.6, 0.8], 0.9), 30), c.x, b.min.y + h * 0.15, c.z), 0.05, 0, 0))
      break
    case 'Bow Tie':
      for (const sx of [-1, 1]) root.add(at(rot(coneNode(w * 0.12, 0.005, w * 0.2, cloth([0.85, 0.1, 0.15]), 8), 0, 0, -sx * Math.PI / 2), front.x + sx * w * 0.1, b.max.y - h * 0.12, front.z + 0.01))
      root.add(at(sphereNode(w * 0.05, cloth([0.85, 0.1, 0.15]), 8), front.x, b.max.y - h * 0.12, front.z + 0.02))
      break
    case 'Backpack':
      root.add(at(boxNode(w * 0.6, h * 0.5, Math.max(0.08, d * 0.35), cloth([0.2, 0.45, 0.2])), back.x, back.y, back.z - d * 0.12))
      root.add(at(boxNode(w * 0.5, h * 0.18, Math.max(0.03, d * 0.12), cloth([0.15, 0.35, 0.15])), back.x, back.y - h * 0.1, back.z - d * 0.32))
      break
    case 'Life Jacket':
      root.add(at(scl(sphereNode(0.5, Coats.coat('bands', [1, 0.45, 0.05], [0.95, 0.9, 0.85]), 20), w * 1.15, h * 0.75, d * 1.25), c.x, c.y + h * 0.1, c.z))
      break
    case 'Armor':
      root.add(at(scl(sphereNode(0.5, steel, 22), w * 1.12, h * 0.9, d * 1.18), c.x, c.y + h * 0.05, c.z))
      root.add(at(scl(sphereNode(w * 0.12, gold, 10), 1, 1, 0.3), front.x, front.y, front.z + d * 0.08))
      break
    case 'Balloons': {
      const bl = named(group(), 'bob'); bl.position.copy(back).add(V3(0, h * 0.4, -0.05))
      root.add(bl)
      const cols = [[0.9, 0.1, 0.1], [0.1, 0.4, 0.95], [1, 0.8, 0.1]]
      for (let k = 0; k < 3; k++) {
        const dx = (k - 1) * 0.35, hy = 1.5 + (k % 2) * 0.3
        bl.add(at(rot(cylNode(0.004, hy, Coats.plain([0.9, 0.9, 0.9]), 4), 0, 0, -dx * 0.25), dx * 0.5, hy / 2, 0))
        bl.add(at(scl(sphereNode(0.25, Coats.glossy(cols[k]), 16), 1, 1.2, 1), dx, hy + 0.25, 0))
      }
      break
    }
    case 'Scarf': {
      const sm = Coats.coat('bands', [0.9, 0.15, 0.1], [0.95, 0.9, 0.8])
      root.add(at(torusNode(Math.max(0.06, w * 0.3), Math.max(0.025, w * 0.08), sm), c.x, b.max.y - h * 0.06, c.z))
      const tail = named(group(), 'sway'); tail.position.set(c.x + w * 0.15, b.max.y - h * 0.08, b.max.z - d * 0.1)
      tail.add(at(boxNode(w * 0.15, h * 0.4, 0.02, sm), 0, -h * 0.2, 0))
      root.add(tail)
      break
    }
    case 'Angel Wings':
      for (const sx of [-1, 1]) {
        const wg = named(group(), sx < 0 ? 'wingL' : 'wingR'); wg.position.copy(back).add(V3(sx * w * 0.15, h * 0.15, -0.03))
        root.add(wg)
        wg.add(rot(at(scl(sphereNode(Math.max(0.2, h * 0.45), Mat.whiteFeather, 14), 1, 0.55, 0.12), sx * Math.max(0.2, h * 0.4), h * 0.1, 0), 0, 0, sx * 0.4))
      }
      break
  }
  return root
}

// ---- legs ----

/// One piece per foot; `sole` is the foot's lowest point in its own space.
export function buildFoot(i, sole, size) {
  const root = named(group(), 'addon')
  const s = Math.max(0.05, size)
  const y = sole
  const { steel } = AddOns
  const nm = AddOns.legs[i]
  switch (nm) {
    case 'Hurt':
      root.add(at(cylNode(s * 0.65, s * 1.6, Coats.plain([0.95, 0.95, 0.93], 0.9), 14), 0, y + s * 1.1, 0))
      break
    case 'Roller Skates': case 'Ice Skates':
      root.add(at(boxNode(s * 1.2, s * 0.35, s * 2.4, cloth(nm === 'Ice Skates' ? [0.95, 0.95, 0.95] : [0.9, 0.2, 0.5])), 0, y - s * 0.1, s * 0.3))
      if (nm === 'Ice Skates') {
        root.add(at(boxNode(s * 0.06, s * 0.3, s * 2.6, steel), 0, y - s * 0.4, s * 0.3))
      } else {
        for (const [zx, zz] of [[-0.45, -0.6], [0.45, -0.6], [-0.45, 1.2], [0.45, 1.2]]) root.add(at(rot(cylNode(s * 0.25, s * 0.18, cloth([1, 0.9, 0.2]), 12), 0, 0, Math.PI / 2), zx * s, y - s * 0.45, zz * s))
      }
      break
    case 'Spring Shoes':
      for (let k = 0; k < 4; k++) root.add(at(torusNode(s * 0.45, s * 0.07, steel), 0, y - s * (0.2 + k * 0.22), 0))
      root.add(at(cylNode(s * 0.7, s * 0.12, Mat.rubber, 14), 0, y - s * 1.05, 0))
      break
    case 'Rocket Boots': {
      root.add(at(cylNode(s * 0.7, s * 1.0, steel, 14), 0, y + s * 0.3, 0))
      const f = named(rot(coneNode(s * 0.45, 0.001, s * 1.4, AddOns.flame, 10), Math.PI, 0, 0), 'flame')
      f.position.set(0, y - s * 0.9, 0); f.visible = false; f.castShadow = false
      root.add(f)
      break
    }
    case 'Rain Boots':
      root.add(at(cylNode(s * 0.72, s * 2.0, Coats.glossy([0.95, 0.8, 0.05]), 14), 0, y + s * 0.9, 0))
      break
    case 'Socks':
      root.add(at(cylNode(s * 0.62, s * 1.8, Coats.coat('bands', [0.95, 0.95, 0.95], [0.85, 0.15, 0.2]), 14), 0, y + s * 1.0, 0))
      break
    case 'Flippers':
      root.add(at(scl(sphereNode(s * 1.6, Coats.glossy([0.1, 0.6, 0.9]), 14), 0.6, 0.08, 1), 0, y + s * 0.05, s * 1.3))
      break
    case 'High Heels': {
      const hm = Coats.glossy([0.85, 0.05, 0.15])
      root.add(at(cylNode(s * 0.12, s * 1.4, hm, 8), 0, y - s * 0.5, -s * 0.5))
      root.add(rot(at(boxNode(s * 1.0, s * 0.15, s * 2, hm), 0, y + 0.02, s * 0.3), -0.4, 0, 0))
      break
    }
    case 'Stilts':
      root.add(at(cylNode(s * 0.2, 0.8, Mat.woodFresh, 8), 0, y - 0.4, 0))
      root.add(at(boxNode(s * 1.2, 0.04, s * 1.6, Mat.woodFresh), 0, y, 0))
      break
    case 'Sneakers':
      root.add(at(boxNode(s * 1.2, s * 0.6, s * 2.2, cloth([0.95, 0.95, 0.97])), 0, y + s * 0.2, s * 0.35))
      root.add(at(boxNode(s * 1.25, s * 0.18, s * 2.25, cloth([0.1, 0.4, 0.9])), 0, y - s * 0.05, s * 0.35))
      break
  }
  return root
}

// ---- Body.applyAddOns / animateAddOns ----

/// Rebuilds the add-on geometry on the current parts.
export function applyAddOns(body) {
  for (const n of body.addOnNodes) { n.removeFromParent(); disposeTree(n) }
  body.addOnNodes = []
  const [h, t, l] = body.addOns
  const { head, torso, legs } = body
  if (h > 0) {
    const a = head.anchor || head.node
    const n = buildHead(h, a); a.add(n); body.addOnNodes.push(n)
  }
  if (t > 0) {
    const a = torso.anchor || torso.node
    const n = buildBody(t, a); a.add(n); body.addOnNodes.push(n)
  }
  if (l > 0) {
    const feet = legs.footNodes
    if (feet.length === 0) {
      const n = buildFoot(l, 0.02, 0.1 * Math.max(0.5, legs.radius * 2)); n.position.set(0, 0, 0)
      legs.node.add(n); body.addOnNodes.push(n)
    } else {
      for (const f of feet) {
        const b = box(f)
        const s = Math.max(0.03, Math.min(b.size.x, b.size.z) * 0.5)
        const n = buildFoot(l, b.size.y > 0.001 ? b.min.y : -0.02, s)
        f.add(n); body.addOnNodes.push(n)
      }
    }
  }
  // cache the animated pieces so update() doesn't walk the hierarchy every frame
  const anim = []
  for (const r of body.addOnNodes) r.traverse(o => { if (o.name && o.name !== 'addon') anim.push(o) })
  body._addOnAnim = anim
  const ln = AddOns.legs[l]
  body.lift = ln === 'Stilts' ? 0.8 : ln === 'Spring Shoes' ? 0.25 : ln === 'High Heels' ? 0.08 : ln === 'Roller Skates' || ln === 'Ice Skates' ? 0.12 : 0
}

export function animateAddOns(body, p, dt, boosting) {
  const list = body._addOnAnim
  if (!list) return
  for (const n of list) {
    switch (n.name) {
      case 'spin': n.rotation.y += dt * (p.glide > 0.1 ? 25 : 4); break
      case 'bob': n.position.y += Math.sin(p.t * 2) * 0.0015; break
      case 'sway': n.rotation.set(0.25 + p.gait * 0.5 + p.run * 0.4 + p.air * 0.6 + Math.sin(p.t * 3) * 0.08, 0, 0); break
      case 'flame': n.visible = !!boosting; n.scale.set(1, 0.8 + 0.4 * Math.sin(p.t * 40), 1); break
      case 'wingL': case 'wingR': {
        const sd = n.name === 'wingL' ? -1 : 1
        n.rotation.set(0, sd * 0.3, sd * (Math.max(p.glide, p.flap, p.air * 0.4) * 0.6 + Math.sin(p.t * 20) * 0.5 * p.flap))
        break
      }
    }
  }
}
