// Small particle bursts: morph puffs, feathers, sparkles, splashes, smoke and fireballs.
import * as THREE from '../vendor/three.module.js'

function dotTexture() {
  const S = 64, d = new Uint8Array(S * S * 4)
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const dx = (x + 0.5) / S * 2 - 1, dy = (y + 0.5) / S * 2 - 1
    const a = Math.pow(Math.max(0, 1 - Math.hypot(dx, dy)), 1.6)
    const i = (y * S + x) * 4
    d[i] = d[i + 1] = d[i + 2] = 255; d[i + 3] = a * 255
  }
  const t = new THREE.DataTexture(d, S, S, THREE.RGBAFormat); t.needsUpdate = true
  return t
}

export class Fx {
  constructor(root) { this.root = root; this.bursts = []; this.tex = dotTexture() }
  clear() { for (const b of this.bursts) this.root.remove(b.points); this.bursts = [] }

  burst(pos, { n = 20, color = [1, 1, 1], size = 0.12, speed = 2, spread = 1, up = 0.3, gravity = -2, life = 1, additive = false, damping = 1.5, grow = 0 }) {
    const geo = new THREE.BufferGeometry()
    const p = new Float32Array(n * 3), v = new Float32Array(n * 3)
    for (let i = 0; i < n; i++) {
      p[i * 3] = pos.x; p[i * 3 + 1] = pos.y; p[i * 3 + 2] = pos.z
      const th = Math.random() * Math.PI * 2, ph = Math.acos(1 - Math.random() * (1 + spread))
      const s = speed * (0.4 + Math.random() * 0.8)
      v[i * 3] = Math.sin(ph) * Math.cos(th) * s; v[i * 3 + 1] = Math.cos(ph) * s + up; v[i * 3 + 2] = Math.sin(ph) * Math.sin(th) * s
    }
    geo.setAttribute('position', new THREE.BufferAttribute(p, 3))
    const mat = new THREE.PointsMaterial({ size, map: this.tex, transparent: true, depthWrite: false, sizeAttenuation: true,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending })
    mat.color.setRGB(color[0], color[1], color[2], THREE.SRGBColorSpace)
    const points = new THREE.Points(geo, mat)
    points.frustumCulled = false
    this.root.add(points)
    this.bursts.push({ points, v, n, life, age: 0, gravity, damping, size, grow })
  }

  puff(pos, color, n = 16) { this.burst(pos, { n, color, size: 0.45, speed: 1.4, gravity: 0.3, life: 0.9, grow: 1.2 }) }
  feathers(pos, n = 12) { this.burst(pos, { n, color: [0.55, 0.25, 0.1], size: 0.09, speed: 2.4, gravity: -0.8, life: 2, damping: 2 }) }
  sparkle(pos, n = 16) { this.burst(pos, { n, color: [1, 0.95, 0.7], size: 0.14, speed: 2.2, gravity: 0, life: 0.6, additive: true }) }
  splash(pos) { this.burst(pos, { n: 40, color: [0.78, 0.88, 0.95], size: 0.12, speed: 3.5, spread: 0.3, up: 1.5, gravity: -9, life: 0.9 }) }
  cloud(pos, color) { this.burst(pos, { n: 60, color, size: 0.9, speed: 1.5, gravity: 0.1, life: 2.5, grow: 1.5, damping: 2 }) }
  fireball(pos) {
    this.burst(pos, { n: 140, color: [1, 0.55, 0.15], size: 1.0, speed: 7, gravity: 0.5, life: 0.7, additive: true, damping: 3, grow: 0.8 })
    this.cloud(pos.clone().add(new THREE.Vector3(0, 1, 0)), [0.15, 0.13, 0.12])
    const light = new THREE.PointLight(0xff9a40, 60, 18, 1.5)
    light.position.copy(pos).y += 1
    this.root.add(light)
    const t0 = performance.now()
    const fade = () => { const k = (performance.now() - t0) / 500; if (k >= 1) { this.root.remove(light); return } light.intensity = 60 * (1 - k); requestAnimationFrame(fade) }
    requestAnimationFrame(fade)
  }

  update(dt) {
    for (let k = this.bursts.length - 1; k >= 0; k--) {
      const b = this.bursts[k]
      b.age += dt
      if (b.age >= b.life) { this.root.remove(b.points); b.points.geometry.dispose(); b.points.material.dispose(); this.bursts.splice(k, 1); continue }
      const p = b.points.geometry.attributes.position.array, v = b.v
      const damp = Math.max(0, 1 - b.damping * dt)
      for (let i = 0; i < b.n; i++) {
        v[i * 3 + 1] += b.gravity * dt
        v[i * 3] *= damp; v[i * 3 + 1] *= damp; v[i * 3 + 2] *= damp
        p[i * 3] += v[i * 3] * dt; p[i * 3 + 1] += v[i * 3 + 1] * dt; p[i * 3 + 2] += v[i * 3 + 2] * dt
      }
      b.points.geometry.attributes.position.needsUpdate = true
      const t = b.age / b.life
      b.points.material.opacity = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
      b.points.material.size = b.size * (1 + b.grow * t)
    }
  }
}
