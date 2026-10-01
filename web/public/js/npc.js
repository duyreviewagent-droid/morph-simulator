// Farm animals, the farmer and wild critters. Ported from Animals.swift.
import * as THREE from '../vendor/three.module.js'
import { RNG, clamp } from './util.js'
import { Species, LegStats } from './species.js'
import { Body, Combo, newPose, Outfit } from './parts.js'
import { Farm } from './world.js'
import { hitCircles } from './hitbox.js'

const FARMER_ROUTE = [[-4, 19.5], [3, 0], [15.5, -6.5], [-9.5, -8], [-10, -12], [26, 3.5], [31, 3.5], [8, 24], [-4, 19.5]]

export class NPC {
  /// kind: 'hen' | 'rooster' | 'cow' | 'farmer' | 'critter'
  constructor(kind, p, seed, species = null) {
    this.kind = kind
    this.rng = new RNG(seed)
    const C = s => new Combo(s, s, s)
    if (kind === 'critter') {
      this.species = species
      this.body = new Body(C(species))
      this.scale = 1
      this.aquatic = species.def.plan === 'fish' || species.def.plan === 'tentacle'
    } else {
      this.species = kind === 'cow' ? Species.of(2) : kind === 'farmer' ? Species.of(0) : Species.of(1)
      this.body = kind === 'farmer' ? new Body(C(Species.of(0)), { outfit: Outfit.farmer })
        : new Body(C(this.species), { white: kind === 'hen' && seed % 3 === 0 })
      this.scale = kind === 'hen' ? 0.3 : kind === 'rooster' ? 0.36 : kind === 'cow' ? this.rng.range(0.92, 1.05) : 1
      this.aquatic = false
    }
    this.body.root.scale.setScalar(this.scale)
    this.pos = p.clone(); this.home = p.clone()
    this.yaw = this.rng.range(-3, 3)
    this.vel = new THREE.Vector2()
    this.y = 0; this.vy = 0; this.phase = 0
    this.state = 'idle'; this.timer = this.rng.range(0.5, 4)
    this.target = new THREE.Vector3()
    this.pose = newPose(); this.pose.phase = this.rng.range(0, 1)
    this.followT = 0; this.voiceT = kind === 'critter' ? this.rng.range(3, 20) : this.rng.range(2, 12)
    this.replyT = -1; this.stepAcc = 0
    this.speech = null; this.speechT = 0
    this.waypoint = 0; this.greetCool = 0; this.scareCool = 0; this.fallDir = 1; this.flapT = 0; this.waveT = 0
    this.circles = null
    this.seedSlot = seed & 3
  }

  get radius() { return this.body.radius * this.scale }
  get isChicken() { return this.kind === 'hen' || this.kind === 'rooster' }
  worldCircles() {
    if (!this.circles) this.circles = hitCircles(this.body)
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw)
    return this.circles.map(c => ({ c: new THREE.Vector3(this.pos.x + fx * c.z * this.scale, this.pos.y, this.pos.z + fz * c.z * this.scale), r: c.r * this.scale }))
  }

  bounds() {
    if (this.isChicken) { const r = Farm.coopRun; return [r.minX + 0.6, r.maxX - 0.6, r.minZ + 0.6, r.maxZ - 0.6] }
    if (this.kind === 'cow') { const p = Farm.pasture; return [p.minX + 2, p.maxX - 2, p.minZ + 2, p.maxZ - 2] }
    return [-Farm.half, Farm.half, -Farm.half, Farm.half]
  }
  randomTarget() {
    const [a, b, c, d] = this.bounds(), r = this.rng
    if (this.kind === 'cow' && r.chance(0.25)) return new THREE.Vector3(Farm.trough.x + r.range(-1, 1), 0, Farm.trough.z + r.range(-3, 3))
    return new THREE.Vector3(r.range(a, b), 0, r.range(c, d))
  }
  say(s, secs = 2.5) { this.speech = s; this.speechT = secs }

  heardCluck(p, playerIsChicken) {
    if (!this.isChicken || this.state === 'fallen') return
    const d = Math.hypot(p.x - this.pos.x, p.z - this.pos.z)
    if (d >= 14) return
    if (playerIsChicken) { this.state = 'follow'; this.followT = 18; if (this.rng.chance(0.5)) this.voiceT = this.rng.range(0.2, 0.8) }
    else if (d < 6) this.flee(p)
  }
  heardMoo(p) {
    if (this.kind !== 'cow' || this.state === 'fallen') return
    if (Math.hypot(p.x - this.pos.x, p.z - this.pos.z) >= 28) return
    this.replyT = this.rng.range(0.6, 1.8); this.target.copy(p); this.state = 'idle'; this.timer = 2.5
  }
  flee(p, secs = 1.6) {
    if (this.state === 'fallen') return
    let ax = this.pos.x - p.x, az = this.pos.z - p.z
    const l = Math.hypot(ax, az) || 1; ax /= l; az /= l
    this.target.set(this.pos.x + ax * 8, 0, this.pos.z + az * 8)
    if (this.state !== 'flee' && this.isChicken) { this.host.sfx('cluck', this.pos, 0.55, 1.35); this.flapT = 0.8 }
    this.state = 'flee'; this.timer = secs
  }
  knock(dx, dz, strength) {
    const r = this.rng
    if (this.kind === 'farmer') {
      if (this.state === 'fallen') return
      this.state = 'fallen'; this.timer = 3.2
      this.vel.set(dx * strength, dz * strength)
      this.fallDir = r.chance(0.5) ? 1 : -1
      this.host.sfx('oof', this.pos, 0.9, 1)
      this.say(r.pick(['OOF!', 'Dagnabbit!', 'My back!', 'Ow! Why I oughta...']), 2.5)
    } else if (this.kind === 'cow') {
      this.vel.set(dx * strength * 0.3, dz * strength * 0.3)
      this.flee(new THREE.Vector3(this.pos.x - dx, 0, this.pos.z - dz), 2.5)
      this.host.sfx('moo', this.pos, 0.8, r.range(1, 1.15))
    } else {
      const k = this.kind === 'critter' ? Math.min(1, 1.5 / Math.max(0.3, this.body.mass)) : 1
      this.vel.set(dx * strength * k, dz * strength * k)
      if (this.kind !== 'critter' || this.body.mass < 1) this.vy = 3
      this.flapT = 1.2
      this.flee(new THREE.Vector3(this.pos.x - dx, 0, this.pos.z - dz), 2)
      if (this.kind === 'critter') this.host.sfx(this.species.voiceSound, this.pos, 0.8, 1.1)
    }
  }

  update(dt, world, t) {
    const host = this.host, r = this.rng, pose = this.pose
    const pp = host.playerPos, pc = host.playerCombo
    const tpx = pp.x - this.pos.x, tpz = pp.z - this.pos.z
    const dP = Math.hypot(tpx, tpz)
    this.timer -= dt; this.voiceT -= dt; this.greetCool -= dt; this.scareCool -= dt
    this.flapT = Math.max(0, this.flapT - dt)
    if (this.speechT > 0) { this.speechT -= dt; if (this.speechT <= 0) this.speech = null }
    let wx = 0, wz = 0, speed = 0
    pose.eat = Math.max(0, pose.eat - dt * 3); pose.talk = Math.max(0, pose.talk - dt * 2)
    pose.scared = Math.max(0, pose.scared - dt * 2); pose.wave = Math.max(0, pose.wave - dt * 1.5); pose.shove = 0
    const go = (tx, tz, sp, arrive = 0.4) => {
      const dx = tx - this.pos.x, dz = tz - this.pos.z, l = Math.hypot(dx, dz)
      if (l < arrive) return true
      wx = dx / l; wz = dz / l; speed = sp * Math.min(1, l / 1.2 + 0.3)
      return false
    }
    const HUMAN = Species.of(0), CHICKEN = Species.of(1), COW = Species.of(2)

    if (this.isChicken) {
      const playerChicken = pc.head === CHICKEN && pc.torso === CHICKEN
      const scary = !playerChicken || host.playerSpeed > 3.5
      if (this.state !== 'flee' && this.state !== 'fallen' && scary && dP < 1.4 + host.playerRadius * 1.5 && (host.playerSpeed > 0.8 || dP < 1)) this.flee(pp)
      switch (this.state) {
        case 'flee': go(this.target.x, this.target.z, 2.6, 0.3); if (this.timer < 0) { this.state = this.followT > 0 ? 'follow' : 'idle'; this.timer = 1 } break
        case 'follow':
          this.followT -= dt
          if (dP > 2.2) go(pp.x, pp.z, dP > 5 ? 2.4 : 1.2, 2); else if (r.chance(dt * 0.5)) pose.eat = 1
          if (this.followT < 0) this.state = 'goHome'
          break
        case 'goHome': { const c = Farm.coopRun; if (go((c.minX + c.maxX) / 2, (c.minZ + c.maxZ) / 2, 1.1, 3)) this.state = 'idle'; break }
        case 'eat': pose.eat = 1; if (this.timer < 0) { this.state = 'idle'; this.timer = r.range(0.3, 2) } break
        case 'wander': if (go(this.target.x, this.target.z, 0.5) || this.timer < 0) { this.state = r.chance(0.6) ? 'eat' : 'idle'; this.timer = r.range(1, 4) } break
        default:
          if (this.timer < 0) { if (r.chance(0.55)) { this.state = 'wander'; this.target = this.randomTarget(); this.timer = 8 } else { this.state = 'eat'; this.timer = r.range(1, 3.5) } }
      }
      if (this.voiceT < 0) {
        if (this.kind === 'rooster' && r.chance(0.35)) { host.sfx('crow', this.pos, 1, 1); this.voiceT = r.range(30, 70); pose.talk = 1.5 }
        else { host.sfx('cluck', this.pos, 0.5, this.kind === 'rooster' ? 1 : r.range(1.2, 1.45)); this.voiceT = r.range(3, 12); pose.talk = 0.6 }
      }
    } else if (this.kind === 'cow') {
      const herd = pc.isPure && pc.head === COW && Farm.inPasture(pp) && dP < 26
      if (this.replyT > 0) {
        this.replyT -= dt
        if (dP > 0) { wx = tpx / dP; wz = tpz / dP } speed = 0.01
        if (this.replyT <= 0) { host.sfx('moo', this.pos, 1, r.range(0.9, 1.1)); pose.talk = 1.6; this.state = 'moo'; this.timer = 1.6 }
      }
      switch (this.state) {
        case 'flee': go(this.target.x, this.target.z, 3.2); if (this.timer < 0) { this.state = 'idle'; this.timer = 2 } break
        case 'moo': pose.talk = 1; if (this.timer < 0) { this.state = 'idle'; this.timer = r.range(1, 3) } break
        case 'eat': pose.eat = 1; if (this.timer < 0) { this.state = 'idle'; this.timer = r.range(1, 3) } if (herd && dP > 7) this.state = 'herd'; break
        case 'wander': if (go(this.target.x, this.target.z, 0.85, 1) || this.timer < 0) { this.state = 'eat'; this.timer = r.range(6, 16) } break
        case 'herd': if (!herd) { this.state = 'idle'; this.timer = 1 } else if (go(pp.x, pp.z, 1.1, 3.5 + r.int(3))) { this.state = 'eat'; this.timer = r.range(3, 6) } break
        default:
          if (this.timer < 0) {
            if (herd) this.state = 'herd'
            else if (r.chance(0.4)) { this.state = 'wander'; this.target = this.randomTarget(); this.timer = 25 } else { this.state = 'eat'; this.timer = r.range(8, 20) }
          }
      }
      if (this.voiceT < 0 && this.state !== 'moo') { host.sfx('moo', this.pos, 0.9, r.range(0.85, 1.1)); pose.talk = 1.6; this.state = 'moo'; this.timer = 1.7; this.voiceT = r.range(18, 45) }
    } else if (this.kind === 'critter') {
      const sp = this.species, d = sp.def, ls = LegStats.of(sp)
      const same = pc.isPure && pc.head === sp
      if (!same && this.state !== 'flee' && dP < 2.5 + host.playerRadius * 1.5 && (host.playerSpeed > 2.2 || dP < 1.2)) this.flee(pp, 2)
      const pick = () => {
        for (let i = 0; i < 12; i++) {
          const a = r.range(0, 6.28), rr = r.range(3, 22)
          const x = this.home.x + Math.cos(a) * rr, z = this.home.z + Math.sin(a) * rr
          const wet = world.waterLevel(x, z) !== null
          if (Math.abs(x) < Farm.half - 12 && Math.abs(z) < Farm.half - 12 && wet === this.aquatic) return new THREE.Vector3(x, 0, z)
        }
        return this.home.clone()
      }
      switch (this.state) {
        case 'flee': go(this.target.x, this.target.z, ls.sprint * 0.75); if (this.timer < 0) { this.state = 'idle'; this.timer = 1 } break
        case 'eat': pose.eat = 1; if (this.timer < 0) { this.state = 'idle'; this.timer = r.range(0.5, 2) } break
        case 'wander': if (go(this.target.x, this.target.z, ls.walk * 0.7, 0.8) || this.timer < 0) { this.state = r.chance(0.5) ? 'eat' : 'idle'; this.timer = r.range(2, 6) } break
        case 'herd': if (!same || dP > 30) { this.state = 'idle'; this.timer = 1 } else if (go(pp.x, pp.z, ls.walk, 2.5 + this.body.radius * 2)) { this.state = 'eat'; this.timer = r.range(2, 4) } break
        default:
          if (this.timer < 0) {
            if (same && dP < 20) this.state = 'herd'
            else if (r.chance(0.6)) { this.state = 'wander'; this.target = pick(); this.timer = 20 } else { this.state = 'eat'; this.timer = r.range(2, 6) }
          }
      }
      if (this.voiceT < 0) { if (dP < 45) host.sfx(sp.voiceSound, this.pos, 0.8, r.range(0.92, 1.08)); pose.talk = 1.2; this.voiceT = r.range(10, 30) }
      if (this.state === 'flee' && d.plan === 'bird' && d.arms === 'wing') this.flapT = 0.5
    } else {
      // the farmer
      const human = pc.head === HUMAN && pc.torso === HUMAN && pc.legs === HUMAN
      const sees = dP < 4 || (dP < 15 && (tpx / Math.max(0.01, dP)) * Math.sin(this.yaw) + (tpz / Math.max(0.01, dP)) * Math.cos(this.yaw) > 0.1)
      if (this.state !== 'fallen' && this.state !== 'scared' && sees) {
        if (human) {
          if (this.greetCool < 0 && dP < 9) {
            this.greetCool = 25; this.state = 'talk'; this.timer = 2.8; this.waveT = 1.8
            this.say(r.pick(['Howdy there, stranger!', "Mornin'! Fine day for it.", "Well hello! You new round here?"]), 3)
            host.sfx('talk', this.pos, 0.9, 0.85)
          }
        } else if (pc.isPure) {
          if (this.greetCool < 0 && dP < 10) {
            this.greetCool = 20
            const n = pc.head.name.toLowerCase(), a = 'aeiou'.includes(n[0]) ? 'an' : 'a'
            const line = pc.head === COW ? "Bessie? How'd you get out of the pasture?" : pc.head === CHICKEN ? 'Now THAT is one big chicken...'
              : r.pick([`Well I'll be. ${a[0].toUpperCase() + a.slice(1)} ${n} on my farm?`, `Where in tarnation did ${a} ${n} come from?`, `Shoo, you ${n}! Shoo!`])
            this.say(line, 3)
            host.sfx('talk', this.pos, 0.8, 0.85)
          }
        } else if (this.scareCool < 0 && dP < 12) {
          this.state = 'scared'; this.timer = 4.5; this.scareCool = 9
          this.say(r.pick(['WHAT IN TARNATION?!', 'AAAH! A MONSTER!', 'Somebody call the sheriff!', 'Lord have mercy, what ARE you?!', 'Nope. Nope nope nope.']), 3)
          host.sfx('scream', this.pos, 1, r.range(0.95, 1.05))
          host.farmerScared()
        }
      }
      switch (this.state) {
        case 'fallen':
          pose.fallen = Math.min(1, pose.fallen + dt * 5)
          this.vel.multiplyScalar(1 - Math.min(1, dt * 3))
          if (this.timer < 0) { this.state = 'idle'; this.timer = 1.5; host.sfx('hmph', this.pos, 0.8, 1) }
          break
        case 'scared':
          pose.scared = 1
          if (dP <= 16) { wx = -tpx / Math.max(0.01, dP); wz = -tpz / Math.max(0.01, dP) }
          speed = 4.2
          if (this.timer < 0) { this.state = 'idle'; this.timer = 2 }
          break
        case 'talk':
          wx = tpx / Math.max(0.01, dP); wz = tpz / Math.max(0.01, dP); speed = 0.01
          this.waveT -= dt
          if (this.waveT > 0) pose.wave = 1
          pose.talk = this.timer > 1 ? 1 : 0
          if (this.timer < 0) { this.state = 'idle'; this.timer = 0.5 }
          break
        case 'chore': pose.eat = 0.6; if (this.timer < 0) { this.state = 'idle'; this.timer = 0.2 } break
        default: {
          pose.fallen = Math.max(0, pose.fallen - dt * 2)
          if (pose.fallen > 0) break
          if (!human && !pc.isPure && dP < 6 && this.scareCool > 0) { wx = -tpx / Math.max(0.01, dP); wz = -tpz / Math.max(0.01, dP); speed = 2.5; break }
          const wp = FARMER_ROUTE[this.waypoint]
          if (go(wp[0], wp[1], 1.35, 0.6)) {
            this.waypoint = (this.waypoint + 1) % FARMER_ROUTE.length
            if (r.chance(0.6)) { this.state = 'chore'; this.timer = r.range(2.5, 5) }
          }
        }
      }
      if (this.state === 'fallen') pose.fallen = Math.min(1, pose.fallen + dt * 5)
    }

    // steering and integration
    const accel = this.kind === 'cow' ? 2 : 6
    this.vel.x += (wx * speed - this.vel.x) * Math.min(1, dt * accel)
    this.vel.y += (wz * speed - this.vel.y) * Math.min(1, dt * accel)
    if (this.state === 'fallen') this.vel.multiplyScalar(1 - Math.min(1, dt * 2))
    const hs = this.vel.length()
    if (Math.hypot(wx, wz) > 0.1 && speed > 0) {
      let dy = Math.atan2(wx, wz) - this.yaw
      while (dy > Math.PI) dy -= Math.PI * 2
      while (dy < -Math.PI) dy += Math.PI * 2
      this.yaw += dy * Math.min(1, dt * (this.kind === 'cow' ? 2 : 7))
    }
    const np = new THREE.Vector3(this.pos.x + this.vel.x * dt, this.pos.y, this.pos.z + this.vel.y * dt)
    if (this.isChicken && this.y <= 0.001 && Farm.inRun(np) !== Farm.inRun(this.pos) && !(np.z > Farm.coopRun.maxZ - 1 && np.x > Farm.coopGate.x0 && np.x < Farm.coopGate.x1)) { this.vy = 4.2; this.flapT = 0.9 }
    if (this.kind === 'cow' || (this.isChicken && ['idle', 'wander', 'eat'].includes(this.state) && Farm.inRun(this.pos))) {
      const [a, b, c, d] = this.bounds()
      np.x = clamp(np.x, a, b); np.z = clamp(np.z, c, d)
    }
    if (this.kind === 'farmer' || this.kind === 'critter') world.collide(np, this.radius, 1.8)
    if (this.kind === 'critter') {
      const lvl = world.waterLevel(np.x, np.z)
      const deep = lvl !== null && world.terrain(np.x, np.z) < lvl - 0.6
      if (this.aquatic ? lvl === null : deep) { np.copy(this.pos); this.vel.set(0, 0); this.state = 'idle'; this.timer = 0.5 }
    }
    this.pos.copy(np)
    if (this.vy !== 0 || this.y > 0) { this.vy -= 14 * dt; this.y += this.vy * dt; if (this.y <= 0) { this.y = 0; this.vy = 0 } }
    let g = world.ground(this.pos.x, this.pos.z, this.pos.y + 0.3, this.radius, this.kind === 'farmer' || this.kind === 'critter' ? 0.5 : 0.3).g
    if (this.aquatic) { const lvl = world.waterLevel(this.pos.x, this.pos.z); if (lvl !== null) g = Math.max(g, lvl - this.body.height * 0.55) }
    this.pos.y = g
    // gait
    this.phase += hs / Math.max(0.05, this.body.legs.stride * this.scale) * dt
    pose.t = t; pose.phase = this.phase
    pose.gait += (Math.min(1, hs / (0.25 * this.scale + 0.05)) - pose.gait) * Math.min(1, dt * 6)
    const runAt = this.kind === 'cow' ? 2.5 : this.kind === 'farmer' ? 2.8 : this.kind === 'critter' ? LegStats.of(this.species).sprint * 0.5 : 1.4
    pose.run += ((hs > runAt ? 1 : 0) - pose.run) * Math.min(1, dt * 4)
    pose.air = this.y > 0.05 ? 1 : 0
    pose.flap = this.flapT > 0 ? 1 : 0
    pose.glide = this.y > 0.05 ? 0.8 : 0
    this.body.roll += ((this.state === 'fallen' ? this.fallDir * 1.45 : 0) - this.body.roll) * Math.min(1, dt * (this.state === 'fallen' ? 6 : 2))
    this.body.root.position.set(this.pos.x, this.pos.y + this.y, this.pos.z)
    this.body.root.rotation.y = this.yaw
    this.body.update(pose, dt)
    // footsteps for the big ones
    if (this.kind === 'critter' && this.species.def.size > 0.9 && !this.aquatic) {
      this.stepAcc += hs * dt
      if (this.stepAcc > this.body.legs.stride * 0.5) { this.stepAcc = 0; const [n, v, rr] = this.species.stepSound; if (dP < 16) host.sfx(n, this.pos, v * 0.7, rr) }
    }
    if (this.kind === 'cow' || this.kind === 'farmer') {
      this.stepAcc += hs * dt
      if (this.stepAcc > (this.kind === 'cow' ? 0.55 : 0.7)) { this.stepAcc = 0; if (dP < 18) host.sfx(this.kind === 'cow' ? 'step_hoof' : 'step_shoe', this.pos, this.kind === 'cow' ? 0.5 : 0.35, this.kind === 'cow' ? 0.85 : 1) }
    }
  }
}
