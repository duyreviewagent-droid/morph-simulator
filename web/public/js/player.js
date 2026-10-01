// The player: movement, abilities, props, junk. Ported from Player.swift, Abilities.swift, Chaos.swift.
// Installed onto Game.prototype by main.js so it can use the game's state directly.
import * as THREE from '../vendor/three.module.js'
import { Species, LegStats } from './species.js'
import { AddOns } from './addons.js'
import { Prop } from './props.js'
import { Farm } from './world.js'
import { hitCircles } from './hitbox.js'
import { Mat } from './mats.js'
import { sphereNode, cylNode } from './loft.js'

export const GRAVITY = 14
const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z)
const SP = { human: () => Species.of(0), chicken: () => Species.of(1), cow: () => Species.of(2) }

export const PlayerMixin = {
  get forward() { return V(Math.sin(this.yaw), 0, Math.cos(this.yaw)) },
  get playerSpeed() { return Math.hypot(this.vel.x, this.vel.z) },

  // ---------- hitboxes ----------
  bodyCircles() {
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw)
    return this.hitCache.map(c => ({ c: V(this.pos.x + fx * c.z, this.pos.y, this.pos.z + fz * c.z), r: c.r }))
  },
  get frontReach() { return this.hitCache.length ? Math.max(...this.hitCache.map(c => c.z + c.r)) : this.body.radius },
  get backReach() { return this.hitCache.length ? Math.max(...this.hitCache.map(c => -c.z + c.r)) : this.body.radius },
  nearestCircle(p) {
    let best = { c: this.pos.clone(), r: this.body.radius }, bd = 1e9
    for (const h of this.bodyCircles()) {
      const d = Math.hypot(p.x - h.c.x, p.z - h.c.z) - h.r
      if (d < bd) { bd = d; best = h }
    }
    return best
  },
  collideBody(step) {
    for (let pass = 0; pass < 2; pass++) {
      let moved = false
      for (const h of this.bodyCircles()) {
        const p = V(h.c.x, this.pos.y, h.c.z)
        if (this.world.collide(p, h.r, this.body.height * 0.8, step)) { this.pos.x += p.x - h.c.x; this.pos.z += p.z - h.c.z; moved = true }
      }
      if (!moved) break
    }
  },
  nearestProp(reach) {
    const hand = this.pos.clone().addScaledVector(this.forward, this.frontReach * 0.8 + 0.35)
    let best = null, bd = 99
    for (const p of this.props) {
      if (p.held || p.dead) continue
      const d = Math.hypot(p.pos.x - hand.x, p.pos.z - hand.z)
      if (d < reach && Math.abs(p.pos.y - this.pos.y) < 1.6 && d < bd) { bd = d; best = p }
    }
    return best
  },
  inFront(p, range, cone = 0.3, behind = false) {
    const dx = p.x - this.pos.x, dz = p.z - this.pos.z, l = Math.hypot(dx, dz)
    if (!(l < range + (behind ? this.backReach : this.frontReach) && l > 0.01 && Math.abs(p.y - this.pos.y) < 2.5)) return false
    const s = behind ? -1 : 1
    return (dx / l) * Math.sin(this.yaw) * s + (dz / l) * Math.cos(this.yaw) * s > cone
  },

  // ---------- the main update ----------
  updatePlayer(dt, inp, control) {
    const c = this.body.combo, body = this.body
    const ls = { ...LegStats.of(c.legs) }
    const hA = AddOns.head[body.addOns[0]], bA = AddOns.body[body.addOns[1]], lA = AddOns.legs[body.addOns[2]]
    switch (lA) {
      case 'Hurt': ls.sprint *= 0.45; ls.walk *= 0.6; ls.jump *= 0.6; break
      case 'Roller Skates': ls.sprint *= 1.55; ls.walk *= 1.3; ls.accel *= 0.5; break
      case 'Ice Skates': ls.sprint *= 1.6; ls.walk *= 1.3; ls.accel *= 0.35; break
      case 'Spring Shoes': ls.jump = Math.min(12, ls.jump * 1.55); break
      case 'Sneakers': ls.sprint *= 1.2; ls.walk *= 1.1; break
      case 'Stilts': ls.walk *= 1.2; ls.sprint *= 1.15; ls.step += 0.3; break
      case 'High Heels': ls.sprint *= 0.85; break
    }
    if (bA === 'Hurt') ls.sprint *= 0.8
    if (hA === 'Hurt') ls.sprint *= 0.9
    let fm = body.torso.flight
    if (bA === 'Jetpack') fm = 2; else if (bA === 'Angel Wings') fm = Math.max(fm, 1); else if (fm === 0 && (bA === 'Superhero Cape' || hA === 'Propeller Cap')) fm = 3
    this.flightMode = fm
    const grav = bA === 'Balloons' ? GRAVITY * 0.38 : GRAVITY
    const swimmerAdd = bA === 'Life Jacket' || lA === 'Flippers'
    if (this.grounded) this.rocketReady = true
    this.boostT = Math.max(0, this.boostT - dt)
    body.boosting = this.boostT > 0
    if (hA === 'Hurt' || bA === 'Hurt' || lA === 'Hurt') {
      this.hurtT -= dt * (this.playerSpeed > 1 ? 1 : 0.2)
      if (this.hurtT < 0) { this.hurtT = 3 + Math.random() * 4; this.audio.play('oof', { volume: 0.5, rate: 1.1 }); if (Math.random() < 0.4) this.say(this.rng.pick(['Ow…', 'Ouch!', 'It hurts…', 'Need a doctor!']), 1.4) }
    }
    this.voiceCool -= dt; this.actionCool -= dt; this.eatCool -= dt; this.legsCool -= dt
    if (this.playerSpeechT > 0) { this.playerSpeechT -= dt; if (this.playerSpeechT <= 0) this.playerSpeech = null }

    if (control) {
      for (let i = 0; i < 3; i++) if (inp.pressed(String(i + 1))) this.morph(i, inp.down('shift') ? c.get(i).prev : c.get(i).next)
      if (inp.pressed('z')) this.randomMorph()
      for (let i = 0; i < 3; i++) if (inp.pressed(String(i + 4))) this.cycleAddOn(i, inp.down('shift'))
    }

    // input direction relative to the camera
    let mx = 0, my = 0
    if (control) {
      if (inp.down('w')) my += 1
      if (inp.down('s')) my -= 1
      if (inp.down('a')) mx -= 1
      if (inp.down('d')) mx += 1
      mx += inp.move.x; my += inp.move.y
    }
    const F = V(Math.sin(this.camYaw), 0, Math.cos(this.camYaw))
    const R = V(-F.z, 0, F.x).multiplyScalar(-1)   // cross(F, up)
    const wish = F.clone().multiplyScalar(my).addScaledVector(R, mx)
    if (wish.length() > 1) wish.normalize()
    const sprint = control && (inp.down('shift') || inp.running || inp.move.length() > 0.92)
    let speed = sprint ? ls.sprint : ls.walk
    if (this.carrying && this.carrying.kind === 'pumpkin') speed *= 0.8
    if (this.inWater) {
      const lg = c.legs.def
      const swimmer = swimmerAdd || lg.plan === 'fish' || lg.plan === 'tentacle' || lg.foot === 'webbed' || lg.name === 'Otter' || lg.name === 'Beaver'
      speed *= this.swimming ? (swimmer ? 2.4 : 0.65) : (swimmer || lA === 'Rain Boots' ? 1.4 : 0.5)
    }
    if (this.layT >= 0 || (this.eatT > 0 && c.head.def.eat === 'graze')) speed = 0

    // ladder
    const lad = this.world.ladder(this.pos, body.radius)
    if (this.climbing && lad) {
      const out = lad.outward
      this.yaw = Math.atan2(-out[0], -out[1])
      this.pos.x = lad.x; this.pos.z = lad.z
      this.vel.set(0, my * 2.6, 0)
      this.pos.y += this.vel.y * dt
      this.climbAcc += Math.abs(this.vel.y) * dt
      if (this.climbAcc > 0.3) { this.climbAcc = 0; this.audio.play('climb', { volume: 0.35 }) }
      this.phase += Math.abs(this.vel.y) * dt * 1.2
      if (this.pos.y >= lad.top - 0.05) { this.climbing = false; this.pos.set(lad.topStep[0], lad.top, lad.topStep[1]); this.vel.set(0, 0, 0); this.audio.play('step_metal', { volume: 0.5 }) }
      const g = this.world.terrain(this.pos.x, this.pos.z)
      if (this.pos.y <= g && my < 0) { this.pos.y = g; this.climbing = false }
      if (control && inp.pressed('space')) { this.climbing = false; this.vel.set(out[0] * 3, 3.5, out[1] * 3); this.pos.x += out[0] * 0.3; this.pos.z += out[1] * 0.3 }
      this.grounded = false
    } else {
      this.climbing = false
      if (lad && wish.length() > 0.1 && -(wish.x * lad.outward[0] + wish.z * lad.outward[1]) > 0.5 && this.pos.y < lad.top - 0.5) {
        if (body.torso.canGrab) { this.climbing = true; this.vel.set(0, 0, 0); this.carryDrop() } else this.hintOnce('You need human arms to climb ladders!')
      }
    }

    if (!this.climbing) {
      let hx = this.vel.x, hz = this.vel.z
      const wx = wish.x * speed, wz = wish.z * speed
      if (this.gliding) {
        let dx = wx, dz = wz
        const l = Math.hypot(dx, dz)
        if (l > 0.1) { dx /= l; dz /= l } else { dx = Math.sin(this.yaw); dz = Math.cos(this.yaw) }
        hx += (dx * 6.5 - hx) * Math.min(1, dt * 1.6); hz += (dz * 6.5 - hz) * Math.min(1, dt * 1.6)
      } else {
        const acc = this.grounded ? ls.accel : ls.accel * 0.3
        hx += (wx - hx) * Math.min(1, dt * acc); hz += (wz - hz) * Math.min(1, dt * acc)
      }
      this.vel.x = hx; this.vel.z = hz
      const hs = Math.hypot(hx, hz)
      if (hs > 0.3 && this.shoveT <= 0) {
        let d = Math.atan2(hx, hz) - this.yaw
        while (d > Math.PI) d -= Math.PI * 2
        while (d < -Math.PI) d += Math.PI * 2
        this.yaw += d * Math.min(1, dt * ls.turn)
      }
      // jump, flap, glide
      if (control && inp.pressed('space')) {
        if (this.grounded && this.layT < 0) {
          this.vel.y = ls.jump * (this.inWater ? 0.6 : 1)
          this.grounded = false
          this.stat('Jumps')
          this.audio.play('jump', { volume: 0.35 })
          if (c.legs.def.foot === 'hoof') this.audio.play('step_hoof', { volume: 0.6 })
        } else if (!this.grounded && lA === 'Rocket Boots' && this.rocketReady) {
          this.rocketReady = false
          this.vel.y = Math.max(this.vel.y, ls.jump * 1.2)
          this.boostT = 0.6
          this.audio.play('whoosh', { volume: 0.6, rate: 0.7 })
          this.fx.puff(this.pos, [0.55, 0.48, 0.38], 10)
        } else if (!this.grounded && this.flightMode === 1 && this.flapsLeft > 0) {
          this.flapsLeft--
          this.vel.y = Math.max(this.vel.y, Math.max(1.6, 5.2 - Math.max(0, body.mass - 1.2) * 0.8))
          this.pose.flap = 1
          this.audio.play('flap', { volume: 0.6 })
          this.fx.feathers(this.pos.clone().add(V(0, body.legs.attach.y + 0.3, 0)), 6)
        }
      }
      const hover = this.flightMode === 2 && control && inp.down('space') && !this.grounded
      if (hover) {
        const ceiling = this.world.terrain(this.pos.x, this.pos.z) + (bA === 'Jetpack' ? 40 : 14)
        this.vel.y = this.pos.y < ceiling ? Math.min(this.vel.y + 20 * dt, 2.2) : Math.min(this.vel.y, 0)
        this.pose.flap = 1
        if (bA === 'Jetpack') this.boostT = 0.15
        this.hoverSnd -= dt
        if (this.hoverSnd < 0) { this.hoverSnd = 0.5; this.audio.play(bA === 'Jetpack' ? 'whoosh' : c.torso.def.name === 'Hummingbird' ? 'flap' : 'buzzwing', { volume: 0.35, rate: bA === 'Jetpack' ? 0.5 : 1.6 }) }
      }
      const wantGlide = control && inp.down('space') && !this.grounded && (this.flightMode === 1 || this.flightMode === 3) && this.vel.y < 0
      if (wantGlide && !this.gliding) { this.gliding = true; this.glideStart = this.pos.clone(); this.audio.play('flap', { volume: 0.4, rate: 0.8 }) }
      if (!wantGlide && this.gliding) this.endGlide()
      if (this.gliding) this.vel.y = Math.max(this.vel.y - GRAVITY * dt, -(1.3 + Math.max(0, body.mass - 1.2) * 0.55))
      else if (!hover) this.vel.y -= grav * dt

      const prevY = this.pos.y
      this.pos.addScaledVector(this.vel, dt)
      this.hitCache = hitCircles(body)
      this.collideBody(ls.step)
      const wasSwimming = this.swimming
      let gr = this.world.ground(this.pos.x, this.pos.z, prevY, body.radius, ls.step)
      let g = gr.g, surf = gr.surf
      const lvl = this.world.waterLevel(this.pos.x, this.pos.z)
      const floatY = (lvl === null ? -99 : lvl) - body.height * 0.55
      this.swimming = lvl !== null && floatY > g + 0.05
      if (this.swimming) { g = floatY; surf = 'water'; if (!wasSwimming) this.stat('Swims') }
      if (this.pos.y <= g || (this.grounded && this.pos.y - g < ls.step && this.vel.y <= 0)) {
        if (!this.grounded) {
          const impact = -this.vel.y
          if (impact > 9) this.blast(this.pos, null, 1.5 + body.radius + impact * 0.15, impact * 0.5 * Math.min(3, body.mass))
          if (impact > 3) {
            this.audio.play('land', { volume: Math.min(1, impact / 12) * (body.mass > 3 ? 1 : 0.6), rate: body.mass > 3 ? 0.8 : 1.1 })
            if (impact > 7) this.fx.puff(this.pos, [0.55, 0.48, 0.38], 14)
          }
          if (this.flipT >= 0) { if (this.flipAngle > 5.6) this.say('Nailed it!', 1.5); this.flipT = -1; this.flipAngle = 0 }
          if (this.gliding) this.endGlide()
        }
        this.pos.y = g; this.vel.y = 0
        this.grounded = true; this.flapsLeft = 3
        this.surface = surf; this.groundTag = gr.tag; this.airTime = 0
      } else { this.grounded = false; this.airTime += dt }
      const wasWater = this.inWater
      this.inWater = lvl !== null && this.pos.y < lvl - 0.15
      if (this.inWater && !wasWater) { this.audio.play('splash', { volume: 0.8 }); this.fx.splash(V(this.pos.x, lvl, this.pos.z)) }
      if (this.pos.y < -20 || !isFinite(this.pos.x)) { const sp = this.world.map.spawn; this.pos.set(sp[0], this.world.terrain(sp[0], sp[2]) + 1, sp[2]); this.vel.set(0, 0, 0) }
    }

    if (this.flipT >= 0) { this.flipT += dt; this.flipAngle = Math.min(Math.PI * 2, this.flipT / 0.8 * Math.PI * 2) }
    body.flip = this.flipAngle

    if (control) {
      if (inp.pressed('e')) this.torsoAction()
      if (inp.pressed('f')) this.voiceAction()
      if (inp.pressed('r')) this.eatAction()
      if (inp.pressed('q')) this.legsAction()
    }
    // throw release
    if (this.throwT >= 0) {
      const before = this.throwT
      this.throwT += dt / 0.55
      if (before < 0.4 && this.throwT >= 0.4 && this.carrying) {
        const p = this.carrying, pumpkin = p.kind === 'pumpkin'
        p.held = false
        p.vel.copy(this.forward).multiplyScalar(pumpkin ? 8.5 : 12).add(V(this.vel.x * 0.5, pumpkin ? 5 : 4, this.vel.z * 0.5))
        p.thrownFrom = this.pos.clone(); p.thrownBy = true
        p.pos.copy(this.pos).add(V(0, body.legs.attach.y + 0.5, 0)).addScaledVector(this.forward, this.frontReach + 0.2)
        this.carrying = null
        this.audio.play('throw', { volume: 0.6 })
        this.stat('Things thrown')
      }
      if (this.throwT >= 1) this.throwT = -1
    }
    if (this.layT >= 0) {
      const before = this.layT
      this.layT += dt
      if (before < 0.55 && this.layT >= 0.55) {
        const back = this.pos.clone().addScaledVector(this.forward, -(this.backReach + 0.1)).add(V(0, Math.max(0.12, body.legs.attach.y * 0.45), 0))
        const egg = new Prop('egg', back)
        egg.vel.copy(this.forward).multiplyScalar(-0.6); egg.laid = true
        this.addProp(egg)
        this.audio.play('plop', { volume: 0.6 })
        this.save.eggs++
        const eggs = this.props.filter(p => p.kind === 'egg' && !p.held)
        if (eggs.length > 14) this.removeProp(eggs[0])
      }
      if (this.layT > 1.1) this.layT = -1
    }
    this.shoveT = Math.max(0, this.shoveT - dt * 2.5)
    this.kickT = Math.max(0, this.kickT - dt * 2.2)
    this.talkT = Math.max(0, this.talkT - dt)
    this.eatT = Math.max(0, this.eatT - dt)

    if (this.carrying) {
      body.root.updateMatrixWorld(true)
      const wp = body.carryPoint().clone().applyMatrix4(body.root.matrixWorld)
      const p = this.carrying
      p.pos.copy(wp).add(V(0, p.radius * 0.3, 0)); p.vel.set(0, 0, 0); p.node.position.copy(p.pos)
    }

    this.stat('Time played', dt)
    if (control) {
      const step = this.playerSpeed * dt
      if (this.grounded) this.stat('Distance walked', step); else if (this.gliding || this.flightMode === 2) this.stat('Distance flown', step)
      if (this.pos.y > (this.save.stats['Highest point'] || 0)) this.save.stats['Highest point'] = this.pos.y
    }

    // pose
    const hs = this.playerSpeed
    const pose = this.pose
    this.phase += (this.climbing ? 0 : hs / body.legs.stride) * dt
    pose.t = this.time; pose.phase = this.phase
    pose.gait += (Math.min(1, hs / 0.6) - pose.gait) * Math.min(1, dt * 8)
    pose.run += ((hs > LegStats.of(c.legs).sprint * 0.62 ? 1 : 0) - pose.run) * Math.min(1, dt * 5)
    pose.air += ((((!this.grounded && !this.climbing && this.airTime > 0.08) || this.flipT >= 0) ? 1 : 0) - pose.air) * Math.min(1, dt * 10)
    pose.glide += ((this.gliding ? 1 : 0) - pose.glide) * Math.min(1, dt * 8)
    pose.flap = Math.max(0, pose.flap - dt * 2.2)
    pose.carry += ((this.carrying && this.throwT < 0 ? 1 : 0) - pose.carry) * Math.min(1, dt * 10)
    pose.throwT = this.throwT
    pose.shove = this.shoveT > 0 ? Math.sin(Math.min(1, this.shoveT) * Math.PI) : 0
    pose.talk = this.talkT > 0 ? Math.min(1, this.talkT * 3) : 0
    pose.eat += ((this.eatT > 0 ? 1 : 0) - pose.eat) * Math.min(1, dt * 10)
    pose.kick = this.kickT > 0 ? Math.sin(this.kickT * Math.PI) : 0
    pose.lay = this.layT >= 0 ? Math.sin(Math.min(1, this.layT / 1.1) * Math.PI) : 0
    pose.climb += ((this.climbing ? 1 : 0) - pose.climb) * Math.min(1, dt * 10)
    if (this.climbing) pose.phase = this.pos.y * 1.4
    body.root.position.copy(this.pos)
    body.root.rotation.y = this.yaw
    body.update(pose, dt)

    // footsteps
    if (this.grounded && !this.climbing && hs > 0.3) {
      const cur = this.phase - Math.floor(this.phase), last = this.lastFootPhase
      for (const p of body.legs.footPhases) {
        const crossed = last <= cur ? (last < p && cur >= p) : (last < p || cur >= p)
        if (crossed) this.footstep(c.legs)
      }
      this.lastFootPhase = cur
    } else this.lastFootPhase = this.phase - Math.floor(this.phase)
  },

  endGlide() {
    this.gliding = false
    const d = Math.hypot(this.pos.x - this.glideStart.x, this.pos.z - this.glideStart.z)
    if (d > 4) this.hintOnce(`Glided ${Math.round(d)} m`, 1.8)
  },

  footstep(legs) {
    let [name, vol, rate] = legs.stepSound
    if (legs.id === 0) { name = 'step_shoe'; vol = 0.45; rate = 1 }
    if (legs.id === 1) { name = 'step_claw'; vol = 0.4; rate = 1 }
    if (legs.id === 2) { name = 'step_hoof'; vol = 0.7; rate = 0.9 }
    if (['step_shoe', 'step_hoof', 'step_claw'].includes(name)) {
      if (this.surface === 'wood') name = 'step_wood'
      else if (this.surface === 'hay') name = 'step_hay'
      else if ((this.surface === 'metal' || this.surface === 'concrete') && name !== 'step_hoof') { name = 'step_metal'; vol *= 0.4 }
    }
    if (this.inWater || this.surface === 'water') name = 'step_splash'
    this.audio.play(name, { volume: vol, rate })
  },

  carryDrop() { if (this.carrying) { this.carrying.held = false; this.carrying.vel.copy(this.vel); this.carrying = null } },

  // ---------- E: body ability ----------
  torsoAction() {
    if (this.actionCool >= 0 || this.climbing) return
    const c = this.body.combo, body = this.body
    const power = Math.min(2.2, 0.6 + body.torso.mass * 0.5)
    const ab = c.torso.torsoAbility
    const fw = this.forward
    switch (ab) {
      case 'grab': {
        if (body.addOns[1] === 1) { this.say('Ow, my arms hurt too much!', 1.6); this.audio.play('oof', { volume: 0.5 }); this.actionCool = 0.6; return }
        if (this.carrying) { if (this.throwT < 0) this.throwT = 0; this.actionCool = 0.4; return }
        const p = this.nearestProp(1.3)
        if (p) { p.held = true; p.vel.set(0, 0, 0); this.carrying = p; this.audio.play('pickup', { volume: 0.5 }); if (p === this.ball) this.ballKickFrom = null; this.actionCool = 0.3; return }
        this.shoveT = 1; this.actionCool = 0.5
        this.audio.play('whoosh', { volume: 0.3, rate: 1.4 })
        for (const n of this.npcs) if (this.inFront(n.pos, 1)) { if (n.kind === 'farmer') n.say('Hey! Watch it, pal.', 2); else n.flee(this.pos, 1.2) }
        for (const p2 of this.props) if (this.inFront(p2.pos, 1)) p2.vel.addScaledVector(fw, 3).y += 1
        this.blast(this.pos, fw, 1.2 + this.frontReach, 3)
        break
      }
      case 'flap':
        this.shoveT = 0.8; this.pose.flap = 1; this.actionCool = 0.45
        this.audio.play('flap', { volume: 0.6, rate: 1.1 })
        this.fx.feathers(this.pos.clone().add(V(0, body.legs.attach.y + 0.3, 0)), 6)
        if (!this.grounded && this.flapsLeft > 0) this.vel.y = Math.max(this.vel.y, 2.5)
        for (const p of this.props) if (this.inFront(p.pos, 1.6, 0)) { p.vel.addScaledVector(fw, 3.5); p.vel.y += 1.5 }
        this.blast(this.pos, fw, 2.2 + this.frontReach, 4, 0)
        for (const n of this.npcs) if (n.kind !== 'farmer' && n.kind !== 'cow' && this.inFront(n.pos, 2, 0)) n.flee(this.pos)
        break
      case 'shove': case 'swipe': case 'pinch': case 'slap': {
        const big = ab === 'shove'
        this.shoveT = 1; this.actionCool = big ? 0.7 : 0.45
        const range = big ? 2 : 1.4
        let hit = false
        for (const p of this.props) if (this.inFront(p.pos, range, 0.2)) {
          p.vel.addScaledVector(fw, (big ? 9 : 5) * power); p.vel.y += big ? 3.5 : 2; hit = true
          if (p === this.ball) this.ballKickFrom = p.pos.clone()
          if (p.kind === 'egg') this.smashEgg(p)
        }
        for (const n of this.npcs) if (this.inFront(n.pos, range, 0.2)) {
          hit = true
          if (big || body.mass > 2.5) { n.knock(Math.sin(this.yaw), Math.cos(this.yaw), 4); if (n.kind === 'farmer') this.tackled() }
          else if (n.kind === 'farmer') { n.say(ab === 'pinch' ? 'OW! It PINCHED me!' : 'Hey! Cut that out!', 2); n.flee(this.pos) }
          else n.flee(this.pos)
        }
        if (this.blast(this.pos.clone().add(V(0, 0.3, 0)), fw, range + this.frontReach, (big ? 9 : 5) * power)) hit = true
        const snd = ab === 'pinch' ? 'peck' : ab === 'slap' ? 'splat' : 'shove'
        this.audio.play(hit ? snd : 'whoosh', { volume: hit ? 0.8 : 0.4, rate: hit ? 1 : 0.9 })
        break
      }
      case 'ink': case 'spray': {
        this.shoveT = 1; this.actionCool = 2
        const ink = ab === 'ink'
        this.blast(this.pos, null, 3, 3)
        this.audio.play(ink ? 'splat' : 'whoosh', { volume: 0.8, rate: ink ? 0.7 : 0.6 })
        this.fx.cloud(this.pos.clone().addScaledVector(fw, ink ? 0.8 : -0.8).add(V(0, 0.5, 0)), ink ? [0.05, 0.03, 0.08] : [0.45, 0.6, 0.2])
        for (const n of this.npcs) if (n.pos.distanceTo(this.pos) < 5) {
          n.flee(this.pos, 3)
          if (n.kind === 'farmer') { n.say(ink ? 'Ack! INK?!' : "PEE-YEW! What's that SMELL?!", 2.5); n.state = 'scared'; n.timer = 3 }
        }
        break
      }
      case 'puff':
        this.shoveT = 3; this.actionCool = 3.2
        this.blast(this.pos, null, 2 + body.radius * 2, 8)
        this.audio.play('poof', { volume: 0.8, rate: 0.6 })
        for (const n of this.npcs) if (n.pos.distanceTo(this.pos) < 3) n.flee(this.pos)
        for (const p of this.props) if (p.pos.distanceTo(this.pos) < 1.6) p.vel.add(p.pos.clone().sub(this.pos).add(V(0, 0.3, 0)).normalize().multiplyScalar(5))
        break
      case 'shell':
        this.shoveT = 2; this.actionCool = 2.2
        this.audio.play('thud', { volume: 0.6, rate: 0.7 })
        this.say('*hides in shell*', 1.5)
        for (const n of this.npcs) if (n.kind === 'farmer' && n.pos.distanceTo(this.pos) < 8) n.say("Huh. Where'd it go?", 2)
        break
    }
  },

  // ---------- F: voice ----------
  voiceAction() {
    if (this.voiceCool >= 0) return
    const c = this.body.combo, d = c.head.def
    const HUMAN = SP.human(), CHICKEN = SP.chicken(), COW = SP.cow()
    this.talkT = c.head === COW ? 1.6 : c.head === CHICKEN ? 0.5 : 1.2
    const farmer = this.npcs.find(n => n.kind === 'farmer')
    if (c.head === HUMAN) {
      this.voiceCool = 1.2
      this.audio.play('talk', { volume: 0.8 })
      if (farmer && farmer.pos.distanceTo(this.pos) < 6 && farmer.state !== 'fallen') {
        if (c.isPure) {
          const lines = [['Nice farm you\'ve got!', 'Why thank ya kindly! Been in the family 80 years.'],
            ['Seen anything weird lately?', "Funny you ask... folks say there's a critter that's 100 animals at once."],
            ['Can I pet the cows?', 'Sure thing. Bessie likes a scratch behind the ears.'],
            ["What's for dinner?", "Not chicken, I'll tell ya that much."]]
          const l = this.rng.pick(lines)
          this.say(l[0], 2.2)
          setTimeout(() => { farmer.say(l[1], 3.2); this.sfx('talk', farmer.pos, 0.9, 0.85) }, 1400)
          farmer.state = 'talk'; farmer.timer = 4
        } else {
          this.say(this.rng.pick(['Hello, sir!', 'Howdy!', "Don't be scared!"]), 1.8)
          setTimeout(() => farmer.say('IT TALKS!', 2), 1000)
        }
      } else {
        const lines = c.isPure ? ['What a lovely day.', 'I should get some chores done.', 'Hmm, I wonder what morphing feels like.']
          : ['I feel funny.', "Something's not right with me.", `Is this what a ${c.torso.name.toLowerCase()} feels like?`, `These ${c.legs.name.toLowerCase()} legs are weird.`, 'Hello? Anyone?']
        this.say(this.rng.pick(lines), 2.2)
      }
    } else if (c.head === CHICKEN) {
      this.voiceCool = 0.5
      this.audio.play('cluck', { volume: 0.8, rate: c.isPure ? 0.9 : 0.8 })
      const asChicken = c.torso === CHICKEN
      for (const n of this.npcs) n.heardCluck(this.pos, asChicken)
      if (!asChicken) this.hintOnce('The hens want someone who looks more like a chicken (chicken body too)', 2.5)
      if (Math.random() < 0.3) this.say(this.rng.pick(['Bawk!', 'Buk buk!', 'Bagawk?']), 1.2)
    } else {
      this.voiceCool = ['moo', 'whale', 'trumpet'].includes(d.voice) ? 1.8 : 1
      const pitch = c.head === COW ? (this.body.mass > 3 ? 0.9 : 1.08) : 1
      this.audio.play(c.head.voiceSound, { volume: 1, rate: pitch })
      if (d.voice === 'moo') for (const n of this.npcs) n.heardMoo(this.pos)
      for (const n of this.npcs) if (n.kind !== 'farmer' && n.kind !== 'cow' && n.pos.distanceTo(this.pos) < (c.head.loud ? 9 : 4)) n.flee(this.pos)
      if (farmer && farmer.pos.distanceTo(this.pos) < 12 && farmer.state !== 'fallen') {
        if (c.head.loud && !c.isPure) {
          farmer.say(d.voice === 'roar' ? 'Was that a... ROAR?!' : 'What in the world was THAT noise?', 2.2)
          if (d.voice === 'roar' || d.voice === 'growl') { farmer.state = 'scared'; farmer.timer = 3; this.farmerScared() }
        } else if (d.voice === 'moo' && !c.isPure && !(c.torso === COW && c.legs === COW)) farmer.say('Did that thing just MOO at me?', 2)
      }
    }
  },

  // ---------- R: eat ----------
  eatAction() {
    if (this.eatCool >= 0) return
    const c = this.body.combo, eat = c.head.def.eat
    if (eat === 'fruit' || eat === 'bite') {
      let food = this.carrying && (this.carrying.kind === 'apple' || (this.carrying.kind === 'pumpkin' && eat === 'bite')) ? this.carrying : null
      if (!food) food = this.props.find(p => (p.kind === 'apple' || (eat === 'bite' && (p.kind === 'pumpkin' || p.kind === 'egg'))) && !p.held && p.pos.distanceTo(this.pos) < this.frontReach + 1.2)
      if (food) {
        this.eatT = 1.2; this.eatCool = 1.3
        this.audio.play('crunch', { volume: 0.8 })
        setTimeout(() => this.audio.play('munch', { volume: 0.5 }), 400)
        const wasApple = food.kind === 'apple', wasPumpkin = food.kind === 'pumpkin', home = food.home.clone()
        this.removeProp(food)
        this.stat('Things eaten')
        this.say(this.rng.pick(['Mmm, crunchy.', 'Delicious!', 'Nom nom.', 'Chomp!']), 1.6)
        if (wasApple && this.world.isFarm) {
          const a = this.rng.range(0, 6.28), d = this.rng.range(1, 2.5)
          this.addProp(new Prop('apple', V(Farm.appleTree.x + Math.cos(a) * d, 4, Farm.appleTree.z + Math.sin(a) * d)))
        } else if (wasPumpkin) setTimeout(() => this.addProp(new Prop('pumpkin', home.clone().add(V(0, 0.5, 0)))), 20000)
      } else if (eat === 'bite') {
        this.eatT = 0.5; this.eatCool = 0.6
        this.audio.play('peck', { volume: 0.6, rate: 0.6 })
        for (const n of this.npcs) if (this.inFront(n.pos, 1.2)) {
          if (n.kind === 'farmer') { n.say('YOW! It BIT me!', 2); n.state = 'scared'; n.timer = 3; this.farmerScared() } else n.flee(this.pos)
        }
      } else { this.hintOnce('Find an apple to eat'); this.eatCool = 0.5 }
    } else if (eat === 'peck') {
      this.eatT = 0.7; this.eatCool = 0.6
      this.audio.play('peck', { volume: 0.7 })
      const mouth = this.pos.clone().addScaledVector(this.forward, this.frontReach + 0.4)
      const pile = this.world.cornPiles.find(p => p.left > 0 && Math.hypot(p.pos.x - mouth.x, p.pos.z - mouth.z) < 1.4)
      if (pile) {
        pile.left--
        let k = 0
        for (const ch of pile.node.children) if (ch.visible && k < 2) { ch.visible = false; k++ }
        if (pile.left === 0) setTimeout(() => { pile.left = 20; for (const ch of pile.node.children) ch.visible = true }, 40000)
        this.stat('Things eaten')
      } else this.hintOnce(this.world.isFarm ? 'Peck at the corn in the chicken run' : 'Nothing to peck here', 1.8)
    } else {
      if (this.surface === 'grass' && this.grounded) {
        this.eatT = 1.6; this.eatCool = 1.7
        this.audio.play('rip', { volume: 0.6 })
        setTimeout(() => this.audio.play('munch', { volume: 0.6, rate: 0.85 }), 500)
        this.stat('Things eaten')
      } else { this.hintOnce('Find some grass to graze on', 1.8); this.eatCool = 0.5 }
    }
  },

  // ---------- Q: legs ability ----------
  legsAction() {
    if (this.legsCool >= 0 || this.climbing) return
    const c = this.body.combo, fw = this.forward
    switch (c.legs.legAbility) {
      case 'backflip':
        if (!this.grounded) return
        this.vel.y = 7.2; this.grounded = false; this.flipT = 0; this.flipAngle = 0; this.legsCool = 1.1
        this.audio.play('jump', { volume: 0.4 }); this.audio.play('whoosh', { volume: 0.5, rate: 1.3 })
        this.carryDrop()
        break
      case 'egg':
        if (!this.grounded || this.layT >= 0) return
        this.layT = 0; this.legsCool = 2.2
        this.audio.play(c.head.id === 1 || c.head.def.plan === 'bird' ? 'bawk' : 'hmph', { volume: 0.9, rate: c.head.id === 1 ? 1 : 0.85 })
        break
      case 'buck': {
        this.kickT = 1; this.legsCool = 1
        let hit = false
        for (const p of this.props) if (this.inFront(p.pos, 2.4, 0.2, true)) { p.vel.addScaledVector(fw, -11); p.vel.y += 5; hit = true; if (p === this.ball) this.ballKickFrom = p.pos.clone(); if (p.kind === 'egg') this.smashEgg(p) }
        for (const n of this.npcs) if (this.inFront(n.pos, 2.4, 0.2, true)) { n.knock(-Math.sin(this.yaw), -Math.cos(this.yaw), 5); hit = true; if (n.kind === 'farmer') this.tackled() }
        if (this.blast(this.pos.clone().add(V(0, 0.3, 0)), fw.clone().negate(), 2.6 + this.backReach, 12)) hit = true
        this.audio.play(hit ? 'kick' : 'whoosh', { volume: hit ? 0.9 : 0.5, rate: hit ? 0.8 : 1 })
        break
      }
      case 'pounce': case 'leap': {
        if (!this.grounded) return
        const leap = c.legs.legAbility === 'leap'
        this.vel.y = leap ? 8.5 : 5.5
        this.vel.x += fw.x * (leap ? 5 : 7); this.vel.z += fw.z * (leap ? 5 : 7)
        this.grounded = false; this.legsCool = 1
        this.audio.play('jump', { volume: 0.5 }); this.audio.play('whoosh', { volume: 0.5, rate: leap ? 0.9 : 1.2 })
        if (!leap) this.pounceT = 0.8
        break
      }
      default:
        this.vel.x += fw.x * 8; this.vel.z += fw.z * 8; this.legsCool = 0.9
        this.blast(this.pos, fw, 2 + this.frontReach, 6)
        this.audio.play('whoosh', { volume: 0.45, rate: 1.6 })
    }
  },

  tackled() { if (this.time - this.lastTackle > 1.5) { this.lastTackle = this.time; this.stat('Farmer knocked over') } },

  smashEgg(p) {
    if (p.dead) return
    this.audio.play('splat', { volume: 0.7 })
    this.fx.puff(p.pos, [0.98, 0.72, 0.1], 18)
    const gy = this.world.ground(p.pos.x, p.pos.z, p.pos.y + 0.2, 0.05).g
    const splat = cylNode(0.12, 0.005, Mat.eggYolk, 16)
    splat.position.set(p.pos.x, gy + 0.004, p.pos.z); splat.scale.set(1, 1, 0.8); splat.castShadow = false
    this.fxRoot.add(splat)
    setTimeout(() => this.fxRoot.remove(splat), 14000)
    this.removeProp(p)
  },

  // ---------- props and contacts ----------
  updateProps(dt) {
    for (const p of [...this.props]) {
      const wasAir = !p.grounded
      const impact = p.step(dt, this.world)
      if (impact > 1.2 && wasAir) {
        if (p.kind === 'egg' && impact > (p.laid && impact < 4 ? 99 : 3.2)) { this.smashEgg(p); continue }
        this.sfx(p.impactSound, p.pos, Math.min(1, impact / 8), p.kind === 'apple' ? 1.6 : 1)
        if (p.thrownFrom) { const d = Math.hypot(p.pos.x - p.thrownFrom.x, p.pos.z - p.thrownFrom.z); if (d > 3) this.hintOnce(`Thrown ${d.toFixed(1)} m`, 1.5); p.thrownFrom = null }
      }
      if (p.pos.y < -10 || Math.abs(p.pos.x) > Farm.half + 5 || Math.abs(p.pos.z) > Farm.half + 5) { p.pos.copy(p.home); p.vel.set(0, 0, 0) }
      if (p === this.ball && this.ballKickFrom && p.rest > 0.3) {
        const d = Math.hypot(p.pos.x - this.ballKickFrom.x, p.pos.z - this.ballKickFrom.z)
        if (d > 4) this.hintOnce(`Kicked ${Math.round(d)} m`, 1.5)
        this.ballKickFrom = null
      }
      const sp = p.vel.length()
      if (sp > 5 && p.thrownBy) {
        for (const n of this.npcs) {
          if (n.pos.clone().add(V(0, 0.8 * n.scale, 0)).distanceTo(p.pos) < n.radius + p.radius + 0.4) {
            const l = Math.hypot(p.vel.x, p.vel.z) || 1
            if (n.kind === 'farmer' && p.mass > 1) { n.knock(p.vel.x / l, p.vel.z / l, 3); this.tackled() }
            else if (n.kind === 'farmer') n.say("Hey! Quit throwin' stuff!", 2)
            else n.flee(p.pos)
            if (p.kind === 'egg') this.smashEgg(p)
            p.vel.multiplyScalar(-0.3); p.thrownBy = false
            break
          }
        }
      }
      if (sp < 1) p.thrownBy = false
    }
  },

  interactions(dt) {
    this.hitCache = hitCircles(this.body)
    const hx = this.vel.x, hz = this.vel.z, hs = Math.hypot(hx, hz)
    for (const p of this.props) {
      if (p.held || p.dead) continue
      const nc = this.nearestCircle(p.pos)
      const dx = p.pos.x - nc.c.x, dz = p.pos.z - nc.c.z, l = Math.hypot(dx, dz)
      const minD = nc.r + p.radius
      if (!(l < minD && l > 0.001 && p.pos.y < this.pos.y + this.body.height * 0.6)) continue
      const nx = dx / l, nz = dz / l
      p.pos.x = nc.c.x + nx * minD; p.pos.z = nc.c.z + nz * minD
      const into = hx * nx + hz * nz
      if (into > 0) {
        const kick = p.kind === 'ball' ? 1.8 : p.kind === 'pumpkin' ? 0.9 : 1.2
        p.vel.x += nx * into * kick; p.vel.z += nz * into * kick
        if (p.kind === 'ball' && into > 2.5) { p.vel.y += into * 0.35; this.ballKickFrom = p.pos.clone(); this.audio.play('kick', { volume: Math.min(1, into / 6) }) }
        if (p.kind === 'egg' && into > 3) this.smashEgg(p)
        if (this.body.mass > 3 && hs > 5) p.vel.y += 3
      }
    }
    for (const n of this.npcs) {
      let best = 1e9, dx = 1, dz = 0, minD = 0
      for (const h of n.worldCircles()) {
        const mine = this.nearestCircle(h.c)
        const ddx = h.c.x - mine.c.x, ddz = h.c.z - mine.c.z
        const gap = Math.hypot(ddx, ddz) - mine.r - h.r
        if (gap < best) { best = gap; dx = ddx; dz = ddz; minD = mine.r + h.r }
      }
      const l = Math.hypot(dx, dz)
      if (!(best < 0 && l > 0.001 && Math.abs(n.pos.y + n.y - this.pos.y) < 1.5)) continue
      const nx = dx / l, nz = dz / l, push = minD - l
      const heavy = this.body.mass, theirs = n.kind === 'cow' ? 4 : n.kind === 'farmer' ? 1.2 : Math.max(0.2, n.body.mass * 0.6)
      const share = heavy / (heavy + theirs)
      n.pos.x += nx * push * share; n.pos.z += nz * push * share
      this.pos.x -= nx * push * (1 - share); this.pos.z -= nz * push * (1 - share)
      if (this.body.mass > 2.5 && hs > 5.5) { n.knock(nx, nz, hs * 0.6); if (n.kind === 'farmer') this.tackled() }
    }
    if (this.pounceT > 0) {
      this.pounceT -= dt
      for (const n of this.npcs) {
        const nc = this.nearestCircle(n.pos)
        if (Math.hypot(n.pos.x - nc.c.x, n.pos.z - nc.c.z) < nc.r + n.radius + 0.6) {
          if (n.kind === 'farmer') { n.knock(Math.sin(this.yaw), Math.cos(this.yaw), 3); this.tackled() } else n.flee(this.pos)
          this.pounceT = 0; this.audio.play('shove', { volume: 0.7 })
          break
        }
      }
    }
  },

  // ---------- junk (Rapier) ----------
  /// Pushes junk in a cone (or all around when dir is null). Returns true if anything was hit.
  blast(c, dir, range, strength, cone = 0.2, up = 0.4) {
    let hit = false
    for (const k of this.world.knockables) {
      if (k.exploded || !k.body) continue
      const t = k.body.translation()
      const dx = t.x - c.x, dy = t.y - c.y, dz = t.z - c.z, l = Math.hypot(dx, dy, dz)
      if (!(l < range && l > 0.01)) continue
      const hl = Math.hypot(dx, dz) || 1
      if (dir && (dx / hl) * dir.x + (dz / hl) * dir.z < cone) continue
      const n = V(dx / hl, up, dz / hl).normalize()
      const m = k.body.mass()
      const s = strength * m * (0.4 + (1 - l / range))
      k.body.applyImpulse({ x: n.x * s, y: n.y * s, z: n.z * s }, true)
      k.body.applyTorqueImpulse({ x: (Math.random() - 0.5) * s * 0.08, y: s * 0.04, z: (Math.random() - 0.5) * s * 0.08 }, true)
      hit = true
    }
    return hit
  },

  updateKnockables(dt) {
    const w = this.world
    if (this.pusher) {
      const h = Math.max(0.4, this.body.height)
      const key = this.hitCache.map(c => c.z.toFixed(2) + c.r.toFixed(2)).join() + h.toFixed(1)
      if (key !== this.pusherKey) { this.pusherKey = key; this.pusher.setShape(this.hitCache, h) }
      this.pusher.setPose(this.pos.x, this.pos.y + h / 2, this.pos.z, this.yaw)
    }
    const hs = this.playerSpeed
    const heavy = Math.min(3, Math.max(0.6, this.body.mass / 2))
    for (const k of w.knockables) {
      if (k.exploded || !k.body) continue
      k.cool = (k.cool || 0) - dt
      if (k.cool > 0) continue
      const t = k.body.translation()
      const nc = this.nearestCircle(t)
      const dx = t.x - nc.c.x, dz = t.z - nc.c.z, l = Math.hypot(dx, dz)
      if (!(l < nc.r + 0.55 && t.y < this.pos.y + this.body.height + 0.3 && t.y > this.pos.y - 0.8 && hs > 1.2)) continue
      let nx = dx / (l || 1) + this.vel.x * 0.1, nz = dz / (l || 1) + this.vel.z * 0.1
      const nl = Math.hypot(nx, nz) || 1; nx /= nl; nz /= nl
      const m = k.body.mass() * heavy * 0.6
      k.body.applyImpulse({ x: nx * hs * 0.9 * m, y: hs * 0.35 * m, z: nz * hs * 0.9 * m }, true)
      k.cool = 0.35
      if (k.explosive && hs > 3 && k.fuse < 0) k.fuse = 0.3
    }
    for (const k of w.knockables) {
      if (k.exploded) continue
      if (k.fuse >= 0) { k.fuse -= dt; if (k.fuse < 0) { this.explode(k); continue } }
      if (!k.knocked && k.body) {
        const t = k.body.translation(), q = k.body.rotation()
        const upY = 1 - 2 * (q.x * q.x + q.z * q.z)
        const moved = Math.hypot(t.x - k.home.pos.x, t.y - k.home.pos.y, t.z - k.home.pos.z)
        if (upY < 0.55 || moved > 1.2) {
          k.knocked = true; k.knockedAt = this.time
          this.stat('Things knocked over')
          if (k.explosive) { const v = k.body.linvel(); if (Math.hypot(v.x, v.y, v.z) > 2.5) k.fuse = 0.4 }
          const snd = k.kind === 'trash' || k.kind === 'can' ? 'clang' : k.kind === 'beachball' ? 'kick' : k.kind === 'snowman' || k.kind === 'hay' ? 'thud' : k.kind === 'vase' ? 'splat' : 'bonk'
          this.sfx(snd, V(t.x, t.y, t.z), 0.6, k.kind === 'can' ? 1.8 : k.kind === 'pin' ? 1.5 : 1)
        }
      } else if (k.knocked && this.time - k.knockedAt > 50 && k.body && this.pos.distanceTo(k.body.translation()) > 30) {
        w.resetKnockable(k); k.knocked = false; k.fuse = -1
      }
    }
  },

  explode(k) {
    if (k.exploded) return
    const t = k.body.translation(), c = V(t.x, t.y, t.z)
    this.world.removeKnockable(k)
    k.exploded = true; k.knocked = true; k.knockedAt = this.time
    this.sfx('boom', c, 1.4, 0.9 + Math.random() * 0.2)
    this.fx.fireball(c)
    this.blast(c, null, 8, 11, 0.2, 0.8)
    for (const o of this.world.knockables) if (o.explosive && !o.exploded && o !== k && o.body && c.distanceTo(o.body.translation()) < 5) o.fuse = 0.15 + Math.random() * 0.3
    for (const n of this.npcs) {
      if (n.pos.distanceTo(c) >= 9) continue
      const dx = n.pos.x - c.x, dz = n.pos.z - c.z, l = Math.hypot(dx, dz) || 1
      n.knock(dx / l, dz / l, 6)
      if (n.kind === 'farmer') { n.say(this.rng.pick(['WHAT IN TARNATION WAS THAT?!', 'My eyebrows!', "Who keeps leavin' these barrels around?!"]), 3); this.tackled() }
    }
    const pl = this.pos.distanceTo(c)
    if (pl < 7 && AddOns.body[this.body.addOns[1]] !== 'Armor') {
      const ax = this.pos.x - c.x, az = this.pos.z - c.z, al = Math.hypot(ax, az) || 1
      this.vel.add(V(ax / al * (9 - pl), 11 - pl, az / al * (9 - pl)))
      this.grounded = false; this.flipT = 0; this.flipAngle = 0
      this.say(this.rng.pick(['WHEEE!', 'AAAAH!', 'Worth it!']), 1.6)
    }
    this.stat('Barrels exploded')
    // put it back later, somewhere out of sight
    setTimeout(() => { if (this.world.knockables.includes(k) && this.pos.distanceTo(k.home.pos) > 25) { this.world.resetKnockable(k); k.exploded = false; k.knocked = false; k.fuse = -1 } }, 50000)
  },
}
