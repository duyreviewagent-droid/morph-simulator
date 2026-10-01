// Loose things you can pick up, throw, kick and knock around. Ported from Props.swift.
import * as THREE from '../vendor/three.module.js'
import { Mat } from './mats.js'
import { loft, Ring, mesh, sphereNode, limb, cylNode, tubeNode, torusNode, group, at, rot, scl } from './loft.js'

export class Prop {
  constructor(kind, p) {
    this.kind = kind
    this.node = group()
    this.spin = group()
    this.pos = p.clone()
    this.home = p.clone()
    this.vel = new THREE.Vector3()
    this.held = false; this.grounded = false; this.dead = false
    this.thrownFrom = null; this.thrownBy = false; this.rest = 0; this.laid = false
    const s = this.spin
    switch (kind) {
      case 'pumpkin': {
        this.radius = 0.26; this.mass = 6
        const rings = []
        for (let i = 0; i <= 8; i++) { const t = i / 8, r = Math.sin(Math.PI * t) * 0.28 + 0.01; rings.push(Ring([0, (t - 0.5) * 0.44, 0], r, r)) }
        s.add(mesh(loft(rings, { seg: 40, displace: (p, o, u) => -0.018 * Math.pow(Math.abs(Math.cos(u * Math.PI * 10)), 0.5) }), Mat.pumpkin))
        s.add(at(limb(0.1, 0.025, 0.018, Mat.stem, { dir: [0.2, 1, 0] }), 0, 0.19, 0))
        break
      }
      case 'apple':
        this.radius = 0.045; this.mass = 0.2
        s.add(scl(sphereNode(0.045, Mat.apple, 16), 1, 0.9, 1))
        s.add(at(limb(0.025, 0.004, 0.003, Mat.stem, { dir: [0.1, 1, 0] }), 0, 0.038, 0))
        break
      case 'egg':
        this.radius = 0.05; this.mass = 0.1
        s.add(scl(sphereNode(0.05, Mat.eggBrown, 16), 0.78, 1, 0.78))
        break
      case 'ball':
        this.radius = 0.11; this.mass = 0.45
        s.add(sphereNode(0.11, Mat.ballWhite, 24))
        for (let k = 0; k < 12; k++) {
          const a = k / 12 * Math.PI * 2, e = (k % 3) * 0.8 - 0.8
          const d = scl(sphereNode(0.03, Mat.black, 8), 1, 1, 0.25)
          at(d, Math.cos(a) * Math.cos(e) * 0.105, Math.sin(e) * 0.105, Math.sin(a) * Math.cos(e) * 0.105)
          d.lookAt(d.position.clone().multiplyScalar(2))
          s.add(d)
        }
        break
      default: // bucket
        this.radius = 0.17; this.mass = 1.2
        s.add(tubeNode(0.14, 0.15, 0.3, Mat.galv, 24))
        s.add(at(cylNode(0.145, 0.01, Mat.galv, 24), 0, -0.145, 0))
        s.add(at(scl(rot(torusNode(0.15, 0.006, Mat.galv), Math.PI / 2, 0, 0), 1, 1, 0.8), 0, 0.15, 0))
    }
    this.node.add(this.spin)
    this.node.position.copy(p)
    this.node.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true } })
  }

  get impactSound() { return this.kind === 'pumpkin' ? 'bonk' : this.kind === 'bucket' ? 'clang' : this.kind === 'ball' ? 'kick' : 'thud' }

  /// Simple sphere physics against the ground and solids. Returns impact speed.
  step(dt, world) {
    if (this.held || this.dead) return 0
    let impact = 0
    this.vel.y -= 9.81 * dt
    const prevY = this.pos.y
    this.pos.addScaledVector(this.vel, dt)
    const gr = world.ground(this.pos.x, this.pos.z, prevY - this.radius, this.radius * 0.5, 0.25)
    const lvl = world.waterLevel(this.pos.x, this.pos.z)
    if (lvl !== null && this.pos.y - this.radius < lvl) {
      this.vel.multiplyScalar(1 - Math.min(1, dt * 3))
      if (this.kind !== 'egg') this.vel.y += (lvl - (this.pos.y - this.radius * 0.3)) * 25 * dt
    }
    if (this.pos.y - this.radius < gr.g) {
      const vn = -this.vel.y
      this.pos.y = gr.g + this.radius
      if (vn > 0) {
        impact = vn
        const bounce = this.kind === 'ball' ? 0.62 : this.kind === 'bucket' ? 0.25 : 0.2
        this.vel.y = vn > 1.2 ? vn * bounce : 0
      }
      this.grounded = true
      const fr = this.kind === 'ball' ? 0.6 : 2.5
      const sp = Math.hypot(this.vel.x, this.vel.z)
      if (sp > 0) {
        const ns = Math.max(0, sp - fr * dt * (gr.surf === 'grass' ? 1.5 : 1))
        this.vel.x *= ns / sp; this.vel.z *= ns / sp
      }
    } else this.grounded = false
    const p = this.pos.clone(); p.y -= this.radius
    if (world.collide(p, this.radius, this.radius * 2, 0.2)) {
      const dx = p.x - this.pos.x, dz = p.z - this.pos.z, l = Math.hypot(dx, dz)
      if (l > 1e-5) {
        const nx = dx / l, nz = dz / l
        const vn = this.vel.x * nx + this.vel.z * nz
        if (vn < 0) { this.vel.x -= nx * vn * 1.5; this.vel.z -= nz * vn * 1.5; impact = Math.max(impact, -vn) }
      }
      this.pos.x = p.x; this.pos.z = p.z
    }
    this.node.position.copy(this.pos)
    const s = Math.hypot(this.vel.x, this.vel.z)
    if (s > 0.01 && (this.grounded || this.kind === 'ball')) {
      const axis = new THREE.Vector3(this.vel.z, 0, -this.vel.x).normalize()
      this.spin.quaternion.premultiply(new THREE.Quaternion().setFromAxisAngle(axis, s * dt / this.radius))
    }
    this.rest = s < 0.05 && this.grounded ? this.rest + dt : 0
    return impact
  }
}
