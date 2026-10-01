// Morph Simulator for the web. Ported from Game.swift / HUD.swift / Input.swift.
import * as THREE from '../vendor/three.module.js'
import RAPIER from '../vendor/rapier.js'
import { RNG, Noise, smoothstep, mix3, IS_TOUCH, IS_MAC_DESKTOP, QUALITY } from './util.js'
import { TIME } from './tex.js'
import { Species, Zoo } from './species.js'
import { Slot, Combo, newPose, Body } from './parts.js'
import { AddOns } from './addons.js'
import { Mat, Coats } from './mats.js'
import { World, Farm } from './world.js'
import { Maps } from './maps.js'
import { Audio } from './audio.js'
import { NPC } from './npc.js'
import { Prop } from './props.js'
import { PlayerMixin } from './player.js'
import { hitCircles } from './hitbox.js'
import { Fx } from './fx.js'

const $ = id => document.getElementById(id)
const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z)
const nextFrame = () => new Promise(r => requestAnimationFrame(() => setTimeout(r, 0)))
function loading(p, msg) { $('loadBar').style.width = Math.round(p * 100) + '%'; if (msg) $('loadMsg').textContent = msg }

// ---------------- save ----------------
const SAVE_KEY = 'morphsim.v1'
function loadSave() {
  const s = { combo: 0, musicOn: true, eggs: 0, tried: [0], combos: [0], map: 0, visited: [0], addOns: [0, 0, 0], stats: {} }
  try { Object.assign(s, JSON.parse(localStorage.getItem(SAVE_KEY) || '{}')) } catch (e) { }
  return s
}
function storeSave(s) { try { localStorage.setItem(SAVE_KEY, JSON.stringify(s)) } catch (e) { } }

// ---------------- input ----------------
class Input {
  constructor() {
    this.held = new Set(); this.presses = []; this.move = new THREE.Vector2(); this.running = false
    this.drag = new THREE.Vector2(); this.scroll = 0
    const keyName = e => ({ ' ': 'space', Shift: 'shift', Tab: 'tab', Escape: 'esc', Enter: 'enter', ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' }[e.key] || e.key.toLowerCase())
    addEventListener('keydown', e => {
      if (document.activeElement && document.activeElement.tagName === 'INPUT') return
      const k = keyName(e)
      if (['tab', 'space', 'up', 'down', 'left', 'right'].includes(k)) e.preventDefault()
      if (!e.repeat) this.presses.push(k)
      this.held.add(k)
    })
    addEventListener('keyup', e => this.held.delete(keyName(e)))
    addEventListener('blur', () => this.held.clear())
  }
  frame() {
    const f = { presses: this.presses, held: new Set(this.held), move: this.move.clone(), running: this.running, drag: this.drag.clone(), scroll: this.scroll }
    f.down = k => f.held.has(k)
    f.pressed = (...ks) => ks.some(k => f.presses.includes(k))
    this.presses = []; this.drag.set(0, 0); this.scroll = 0
    return f
  }
  tap(k) { this.presses.push(k) }
}
const EMPTY = { presses: [], held: new Set(), move: new THREE.Vector2(), drag: new THREE.Vector2(), scroll: 0, down: () => false, pressed: () => false, running: false }

// ---------------- game ----------------
class Game {
  constructor(renderer) {
    this.renderer = renderer
    this.scene = new THREE.Scene()
    this.camera = new THREE.PerspectiveCamera(58, innerWidth / innerHeight, 0.08, 1500)
    this.audio = Audio
    this.save = loadSave()
    this.rng = new RNG((Date.now() & 0x7fffffff) >>> 0)
    this.input = new Input()
    this.mode = 'loading'
    this.time = 0
    this.props = []; this.npcs = []
    this.propRoot = new THREE.Group(); this.npcRoot = new THREE.Group(); this.fxRoot = new THREE.Group()
    this.scene.add(this.propRoot, this.npcRoot, this.fxRoot)
    this.fx = new Fx(this.fxRoot)
    // player state
    this.pos = V(2, 0, 7); this.vel = V(); this.yaw = Math.PI
    this.grounded = true; this.groundTag = ''; this.surface = 'grass'
    this.pose = newPose(); this.phase = 0; this.flapsLeft = 3; this.gliding = false; this.glideStart = V()
    this.climbing = false; this.climbAcc = 0; this.carrying = null
    this.throwT = -1; this.shoveT = 0; this.talkT = 0; this.eatT = 0; this.kickT = 0; this.layT = -1; this.flipT = -1; this.flipAngle = 0
    this.voiceCool = 0; this.actionCool = 0; this.eatCool = 0; this.legsCool = 0
    this.inWater = false; this.swimming = false; this.lastFootPhase = 0; this.airTime = 0
    this.playerSpeech = null; this.playerSpeechT = 0; this.hintText = ''; this.hintT = 0
    this.hoverSnd = 0; this.pounceT = 0; this.flightMode = 0; this.rocketReady = true; this.boostT = 0; this.hurtT = 3
    this.hitCache = []; this.lastTackle = -9; this.lastScare = -9
    this.ball = null; this.ballKickFrom = null
    this.morphSlot = 0; this.titleMap = 0
    // camera
    this.camYaw = Math.PI; this.camPitch = 0.32; this.zoom = 1
    this.camPos = V(0, 3, 12); this.camLook = V()
    this.saveTimer = 0
    this.setupScene()
  }

  // ---------- scene ----------
  setupScene() {
    const sun = new THREE.DirectionalLight(0xffffff, 3)
    sun.castShadow = true
    const sm = IS_TOUCH ? 2048 : 4096
    sun.shadow.mapSize.set(sm, sm)
    const sc = sun.shadow.camera
    sc.left = -45; sc.right = 45; sc.top = 45; sc.bottom = -45; sc.near = 1; sc.far = 260
    sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.04
    this.sun = sun
    this.scene.add(sun, sun.target)
    this.hemi = new THREE.HemisphereLight(0xcfe0ff, 0x5a6a3a, 0.7)
    this.scene.add(this.hemi)
    this.pmrem = new THREE.PMREMGenerator(this.renderer)
  }

  applyMapLook() {
    const m = this.world.map
    const tex = makeSky(m)
    this.scene.background = tex
    if (this.envRT) this.envRT.dispose()
    this.envRT = this.pmrem.fromEquirectangular(tex)
    this.scene.environment = this.envRT.texture
    this.scene.environmentIntensity = 1.1
    this.scene.fog = new THREE.Fog(new THREE.Color().setRGB(m.fog[0], m.fog[1], m.fog[2], THREE.SRGBColorSpace), m.fogStart, m.fogEnd)
    this.sun.color.setRGB(m.sunColor[0], m.sunColor[1], m.sunColor[2], THREE.SRGBColorSpace)
    this.sun.intensity = m.sunIntensity / 800
    this.sunDir = V(m.sunDir[0], m.sunDir[1], m.sunDir[2]).normalize()
  }

  // ---------- maps ----------
  loadMap(i) {
    this.carrying = null
    for (const n of this.npcs) { this.npcRoot.remove(n.body.root); n.body.dispose && n.body.dispose() }
    this.npcs = []
    for (const p of this.props) this.propRoot.remove(p.node)
    this.props = []
    this.ball = null; this.ballKickFrom = null
    this.fx.clear()
    while (this.fxRoot.children.length) this.fxRoot.remove(this.fxRoot.children[0])
    if (this.world) { this.scene.remove(this.world.root); this.world.dispose() }
    this.world = new World(i, RAPIER, this.physics)
    this.scene.add(this.world.root)
    this.mapIndex = i; this.titleMap = i
    this.applyMapLook()
    this.spawnFor(i)
    const sp = this.world.map.spawn
    this.pos.set(sp[0], this.world.ground(sp[0], sp[2], 100, 0.3).g, sp[2])
    this.vel.set(0, 0, 0); this.grounded = true; this.climbing = false; this.gliding = false
    this.camPos.copy(this.pos).add(V(0, 3, 6)); this.camLook.copy(this.pos)
    this.save.map = i
    if (!this.save.visited.includes(i)) this.save.visited.push(i)
    storeSave(this.save)
    if (this.mode === 'play') this.toast(this.world.map.name.toUpperCase(), this.world.map.blurb)
  }

  spawnFor(i) {
    const rr = new RNG(i * 101 + 7)
    const addNPC = n => { n.host = this; this.npcs.push(n); this.npcRoot.add(n.body.root) }
    if (i === 0) {
      for (let k = 0; k < 6; k++) addNPC(new NPC('hen', V(rr.range(13, 23), 0, rr.range(-19, -10)), k * 7 + 1))
      addNPC(new NPC('rooster', V(18, 0, -13), 99))
      for (let k = 0; k < 5; k++) addNPC(new NPC('cow', V(rr.range(40, 70), 0, rr.range(-15, 28)), 200 + k))
      addNPC(new NPC('farmer', V(-4, 0, 19), 300))
      const pp = Farm.pumpkinPatch
      for (let k = 0; k < 8; k++) {
        const x = pp.x - 4 + (k % 4) * 2.6 + rr.range(-0.4, 0.4), z = pp.z - 1.8 + Math.floor(k / 4) * 3.4 + rr.range(-0.4, 0.4)
        this.addProp(new Prop('pumpkin', V(x, Farm.height(x, z) + 0.26, z)))
      }
      for (let k = 0; k < 6; k++) {
        const a = rr.range(0, 6.28), d = rr.range(1, 2.6)
        const x = Farm.appleTree.x + Math.cos(a) * d, z = Farm.appleTree.z + Math.sin(a) * d
        this.addProp(new Prop('apple', V(x, Farm.height(x, z) + 0.05, z)))
      }
      this.ball = new Prop('ball', V(4, 0.11, 9)); this.addProp(this.ball)
      for (const [x, z] of [[36.5, 5.5], [-9, -8.5], [12.5, -6.5]]) this.addProp(new Prop('bucket', V(x, Farm.height(x, z) + 0.15, z)))
      return
    }
    const m = this.world.map
    let k = 0
    const cap = IS_TOUCH ? 2 : 3
    for (const name of m.natives) {
      const id = Zoo.defs.findIndex(d => d.name === name)
      if (id < 0) continue
      const sp = Species.of(id)
      const aquatic = sp.def.plan === 'fish' || sp.def.plan === 'tentacle'
      const count = sp.def.size > 1.2 ? 1 : cap
      let placed = 0
      for (let t = 0; t < 400 && placed < count; t++) {
        const a = rr.range(0, Math.PI * 2), d = aquatic ? rr.range(8, 200) : rr.range(10, 140)
        const x = m.spawn[0] + Math.cos(a) * d, z = m.spawn[2] + Math.sin(a) * d
        if (Math.abs(x) > Farm.half - 12 || Math.abs(z) > Farm.half - 12) continue
        const lvl = this.world.waterLevel(x, z)
        if (aquatic ? (lvl === null || this.world.terrain(x, z) > lvl - 0.8) : (lvl !== null)) continue
        addNPC(new NPC('critter', V(x, this.world.terrain(x, z), z), rr.next(), sp))
        placed++
      }
      k++
    }
    const s = m.spawn
    this.ball = new Prop('ball', V(s[0] + 3, this.world.terrain(s[0] + 3, s[2] + 3) + 0.2, s[2] + 3)); this.addProp(this.ball)
    for (let j = 0; j < 4; j++) { const x = s[0] - 3 + j, z = s[2] + 4; this.addProp(new Prop('apple', V(x, this.world.terrain(x, z) + 0.1, z))) }
  }

  addProp(p) { this.props.push(p); this.propRoot.add(p.node) }
  removeProp(p) { p.dead = true; this.propRoot.remove(p.node); this.props = this.props.filter(q => q !== p); if (this.carrying === p) this.carrying = null }

  // ---------- NPC host ----------
  get playerPos() { return this.pos }
  get playerCombo() { return this.body.combo }
  get playerRadius() { return this.body.radius }
  sfx(name, p, vol, rate = 1) {
    const d = this.camPos.distanceTo(p)
    const att = Math.min(1, 6 / (d + 3)) * Math.max(0, 1 - d / 90)
    const f = this.camLook.clone().sub(this.camPos).normalize()
    const right = V(-f.z, 0, f.x)
    const dir = p.clone().sub(this.camPos).normalize()
    this.audio.play(name, { volume: vol * att * 1.6, pan: -dir.dot(right) * 0.8, rate })
  }
  farmerScared() { if (this.time - this.lastScare > 2) { this.lastScare = this.time; this.stat('Farmer scared') } }
  stat(k, n = 1) { this.save.stats[k] = (this.save.stats[k] || 0) + n }
  say(s, secs = 2.2) { this.playerSpeech = s; this.playerSpeechT = secs }
  hintOnce(s, secs = 2.5) { this.hintText = s; this.hintT = secs }

  // ---------- morph ----------
  morph(slot, s) {
    s = typeof s === 'number' ? Species.of(s) : s
    if (this.body.combo.get(slot) === s) return
    if (this.carrying && slot === 1 && s.torsoAbility !== 'grab') this.carryDrop()
    if (this.climbing && slot === 1 && s.torsoAbility !== 'grab') this.climbing = false
    this.body.set(slot, s)
    this.audio.play('morph', { volume: 0.8 }); this.audio.play('poof', { volume: 0.5 })
    const b = this.body
    const at = this.pos.clone().add(V(0, slot === 2 ? b.legs.attach.y * 0.6 : slot === 1 ? b.legs.attach.y + 0.3 : b.height - 0.2, 0))
    this.fx.puff(at, [1, 0.95, 0.9], 16)
    const coat = s.def.coat
    if (coat === 'feathers') this.fx.feathers(at, 20)
    else if (Coats.isFurry(coat)) this.fx.puff(at, [0.15, 0.14, 0.13], 14)
    else this.fx.sparkle(at, 16)
    if (slot === 0) setTimeout(() => this.audio.play(s.voiceSound, { volume: 0.55 }), 350)
    if (!this.save.tried.includes(s.id)) this.save.tried.push(s.id)
    const idx = this.body.combo.index
    if (!this.save.combos.includes(idx) && this.save.combos.length < 5000) this.save.combos.push(idx)
    this.save.combo = idx
    this.stat('Morphs')
    this.refreshHUD()
  }
  randomMorph() { for (let s = 0; s < 3; s++) this.morph(s, Species.of(this.rng.int(Species.count))) }
  cycleAddOn(slot, back) {
    const i = (this.body.addOns[slot] + (back ? 11 : 1)) % 12
    this.body.setAddOn(slot, i)
    this.save.addOns = [...this.body.addOns]
    const name = AddOns.names(slot)[i]
    this.audio.play(i === 1 ? 'oof' : 'pickup', { volume: 0.6 }); this.audio.play('poof', { volume: 0.3 })
    this.hintOnce(name === 'None' ? `${Slot.names[slot]}: no add-on` : `${Slot.names[slot]} add-on: ${name}` + (AddOns.blurbs[name] ? ' — ' + AddOns.blurbs[name] : ''), 2.2)
    if (i === 1) this.say(this.rng.pick(['Ow!', 'Ouch…', 'That hurts!']), 1.4)
    this.refreshHUD()
  }

  // ---------- modes ----------
  enter(m) {
    this.mode = m
    $('title').classList.toggle('hidden', m !== 'title')
    $('hud').classList.toggle('hidden', m === 'title' || m === 'loading')
    $('touch').classList.toggle('hidden', !(IS_TOUCH && m === 'play'))
    $('morph').classList.toggle('hidden', m !== 'morph')
    $('mapsOv').classList.toggle('hidden', m !== 'maps')
    $('statsOv').classList.toggle('hidden', m !== 'stats')
    $('pause').classList.toggle('hidden', m !== 'paused')
    this.audio.music.mood = m === 'title' ? 'menu' : 'play'
    if (m === 'morph') { this.buildMorphUI(); this.morphCursor = this.body.combo.get(this.morphSlot).id }
    if (m === 'maps') this.buildMapsUI()
    if (m === 'stats') this.buildStatsUI()
    if (m === 'title') this.updateTitle()
    if (m === 'play') this.refreshHUD()
  }

  // ---------- loop ----------
  frame(dt) {
    this.time += dt
    TIME.value = this.time
    const f = this.input.frame()
    if (f.pressed('m') && this.mode !== 'morph') this.toggleMusic()
    switch (this.mode) {
      case 'title':
        if (f.pressed('left')) this.stepTitleMap(-1)
        if (f.pressed('right')) this.stepTitleMap(1)
        if (f.pressed('enter', 'space')) this.startPlay()
        this.simulate(dt, EMPTY, false)
        break
      case 'play':
        if (f.pressed('esc')) this.enter('paused')
        else if (f.pressed('tab')) this.enter('morph')
        else if (f.pressed('b')) this.enter('maps')
        else if (f.pressed('j')) this.enter('stats')
        this.simulate(dt, f, true)
        break
      case 'morph':
        if (f.pressed('tab') || f.pressed('esc')) this.enter('play')
        for (let i = 0; i < 3; i++) if (f.pressed(String(i + 1))) { this.morphSlot = i; this.buildMorphUI() }
        for (let i = 0; i < 3; i++) if (f.pressed(String(i + 4))) { this.cycleAddOn(i, f.down('shift')); this.buildMorphUI() }
        this.simulate(dt, EMPTY, false)
        break
      case 'maps': case 'stats':
        if (f.pressed('esc') || f.pressed(this.mode === 'maps' ? 'b' : 'j')) this.enter('play')
        this.simulate(dt, EMPTY, false)
        break
      case 'paused':
        if (f.pressed('esc')) this.enter('play')
        break
    }
    this.saveTimer += dt
    if (this.saveTimer > 30 && this.mode !== 'title') {
      this.saveTimer = 0
      storeSave(this.save)
      const s = $('saved'); s.style.opacity = 1; setTimeout(() => s.style.opacity = 0, 1400)
    }
    this.renderer.render(this.scene, this.camera)
  }

  simulate(dt, f, control) {
    this.updatePlayer(dt, f, control)
    for (const n of this.npcs) {
      const d = n.pos.distanceTo(this.pos)
      // far animals update less often (and not at all very far away)
      if (d > 120) continue
      if (d > 60 && ((this.frameNo + n.seedSlot) & 3)) continue
      n.update(d > 60 ? dt * 4 : dt, this.world, this.time)
    }
    this.frameNo = (this.frameNo || 0) + 1
    this.updateProps(dt)
    this.interactions(dt)
    this.physics.timestep = Math.min(1 / 30, dt)
    this.physics.step()
    this.world.syncKnockables()
    this.updateKnockables(dt)
    this.fx.update(dt)
    this.updateCamera(dt, f, control)
    if (this.world.water && this.world.water.material.normalMap) this.world.water.material.normalMap.offset.set(this.time * 0.01, this.time * 0.013)
    this.audio.ambience.rush = Math.min(1, Math.max(0, (this.vel.length() - 3) / 9))
    this.audio.music.energy = Math.min(1, this.playerSpeed / 6)
    if (this.mode !== 'title') this.updateHUD(dt)
  }

  updateCamera(dt, f, control) {
    if (this.mode === 'title') {
      this.camYaw += dt * 0.12
      this.camPitch += (0.18 - this.camPitch) * Math.min(1, dt)
    } else if (control) {
      this.camYaw -= f.drag.x * 0.006
      this.camPitch = Math.min(1.25, Math.max(-0.25, this.camPitch + f.drag.y * 0.004))
      if (f.down('left')) this.camYaw += dt * 1.8
      if (f.down('right')) this.camYaw -= dt * 1.8
      if (f.down('up')) this.camPitch = Math.max(-0.25, this.camPitch - dt)
      if (f.down('down')) this.camPitch = Math.min(1.25, this.camPitch + dt)
      this.zoom = Math.min(2.6, Math.max(0.45, this.zoom * (1 + f.scroll * 0.0012)))
      if (f.pressed('c')) this.zoom = this.zoom > 1.5 ? 0.7 : this.zoom < 0.9 ? 1 : 1.8
    }
    const h = this.body.height
    const target = this.pos.clone().add(V(0, h * 0.78, 0))
    const dist = (2.4 + h * 1.35) * this.zoom * (this.mode === 'title' ? 1.15 : 1)
    const cp = target.clone().add(V(-Math.sin(this.camYaw) * dist * Math.cos(this.camPitch), dist * Math.sin(this.camPitch), -Math.cos(this.camYaw) * dist * Math.cos(this.camPitch)))
    const gy = this.world.terrain(cp.x, cp.z) + 0.35
    if (cp.y < gy) cp.y = gy
    this.camPos.lerp(cp, Math.min(1, dt * 10))
    this.camLook.lerp(target, Math.min(1, dt * 14))
    if (this.camLook.distanceTo(target) > 8) { this.camLook.copy(target); this.camPos.copy(cp) }
    this.camera.position.copy(this.camPos)
    this.camera.lookAt(this.camLook)
    // shadows follow the action
    this.sun.position.copy(this.pos).addScaledVector(this.sunDir, 120)
    this.sun.target.position.copy(this.pos)
  }

  // ---------- HUD ----------
  toast(a, b) {
    const t = $('toast'); t.querySelector('.t1').textContent = a; t.querySelector('.t2').textContent = b
    t.style.opacity = 1; clearTimeout(this.toastTimer); this.toastTimer = setTimeout(() => t.style.opacity = 0, 2800)
  }
  abilities() {
    const c = this.body.combo, ls = c.legs.def
    const fl = this.flightMode, rocket = AddOns.legs[this.body.addOns[2]] === 'Rocket Boots'
    let jump = c.legs.id === 0 ? 'Jump' : c.legs.id === 1 ? 'Big hop' : c.legs.id === 2 ? 'Little jump' : (ls.jump > 1.5 || ls.plan === 'hopper' ? 'Big jump' : ls.plan === 'fish' ? 'Flop' : ls.plan === 'slither' ? 'Little hop' : 'Jump')
    const extra = fl === 1 ? ' · again to flap, hold to glide' : fl === 2 ? ' · hold to fly' : fl === 3 ? ' · hold to glide' : rocket ? ' · again to rocket' : ''
    const sprint = c.legs.id === 0 ? 'Sprint' : c.legs.id === 1 ? 'Scurry' : c.legs.id === 2 ? 'Gallop!' : ls.speed > 1.6 ? 'Top speed!' : ls.foot === 'hoof' ? 'Gallop!' : ls.plan === 'slither' ? 'Slither fast' : ls.speed < 0.5 ? 'Hurry (slowly)' : 'Run'
    const ta = { grab: 'Grab / throw', flap: 'Wing buffet', shove: 'Headbutt', swipe: 'Claw swipe', pinch: 'Pinch', slap: 'Flipper slap', ink: 'Squirt ink', puff: 'Puff up!', spray: 'Stink spray', shell: 'Hide in shell' }[c.torso.torsoAbility]
    const vn = { talk: 'Talk', cluck: 'Cluck', moo: 'MOO', neigh: 'Neigh', oink: 'Oink', baa: 'Baa', bleat: 'Bleat', bray: 'Hee-haw', bark: 'Bark', meow: 'Meow', roar: 'ROAR', howl: 'Howl', yip: 'Yip', growl: 'Growl', squeak: 'Squeak', hiss: 'Hiss', quack: 'Quack', honk: 'Honk', gobble: 'Gobble', hoot: 'Hoot', caw: 'Caw', squawk: 'Squawk', tweet: 'Tweet', coo: 'Coo', trumpet: 'Trumpet', grunt: 'Grunt', bellow: 'Bellow', hoo: 'Ooh-aah', screech: 'Screech', chatter: 'Chatter', ribbit: 'Ribbit', buzz: 'Buzz', click: 'Click', whale: 'Whale song', blub: 'Blub', chirp: 'Chirp', snort: 'Snort' }[c.head.def.voice] || 'Call'
    const eat = { fruit: 'Eat apple', peck: 'Peck', graze: 'Graze', bite: 'Chomp' }[c.head.def.eat]
    const la = { backflip: 'Backflip', egg: 'Lay egg', buck: 'Buck kick', pounce: 'Pounce', leap: 'Mega leap', dash: 'Dash' }[c.legs.legAbility]
    return { jump: jump + extra, jumpShort: fl === 2 ? 'FLY' : fl ? 'JUMP / GLIDE' : 'JUMP', sprint, ta, vn, eat, la }
  }
  refreshHUD() {
    const c = this.body.combo
    $('comboName').textContent = c.name.toUpperCase()
    document.querySelectorAll('#combo .slot').forEach((row, i) => {
      const sp = c.get(i)
      const col = mix3(sp.def.a, [1, 1, 1], 0.45)
      const el = row.querySelector('.sp'); el.textContent = sp.name; el.style.color = `rgb(${col.map(v => Math.round(v * 255)).join(',')})`
      const ao = this.body.addOns[i]
      row.querySelector('.add').textContent = `${i + 4} · ${ao > 0 ? AddOns.names(i)[ao] : 'add-on'}`
    })
    const a = this.abilities()
    $('abilities').innerHTML = `<div><b>SPACE</b>${a.jump}</div><div><b>SHIFT</b>${a.sprint}</div><div><b>E</b>${a.ta}</div><div><b>F</b>${a.vn}</div><div><b>R</b>${a.eat}</div><div><b>Q</b>${a.la}</div>`
    $('bE').textContent = a.ta; $('bF').textContent = a.vn; $('bR').textContent = a.eat; $('bQ').textContent = a.la; $('bJump').textContent = a.jumpShort
  }
  updateHUD(dt) {
    if (this.hintT > 0) { this.hintT -= dt; if (this.hintT <= 0) this.hintText = '' }
    let hint = this.hintText
    if (!hint) {
      if (this.climbing) hint = IS_TOUCH ? 'Stick up/down to climb · JUMP to let go' : 'W / S to climb · SPACE to let go'
      else if (this.gliding) hint = 'Gliding!'
      else if (this.carrying) hint = `${IS_TOUCH ? 'Tap the grab button' : 'E'} to throw the ${this.carrying.kind}`
      else if (this.body.torso.canGrab && this.nearestProp(1.3)) hint = `${IS_TOUCH ? 'Tap Grab' : 'E'} to pick up the ${this.nearestProp(1.3).kind}`
    }
    if ($('hint').textContent !== hint) $('hint').textContent = hint
    if (this.flightMode !== this._lastFm) { this._lastFm = this.flightMode; this.refreshHUD() }
    // speech bubbles
    const items = []
    if (this.playerSpeech) items.push([this.pos.clone().add(V(0, this.body.height + 0.25, 0)), this.playerSpeech, true])
    for (const n of this.npcs) if (n.speech && n.pos.distanceTo(this.camPos) < 40) items.push([n.pos.clone().add(V(0, n.body.height * n.scale + 0.3, 0)), n.speech, false])
    const box = $('bubbles')
    while (box.children.length < items.length) { const d = document.createElement('div'); d.className = 'bubble'; box.appendChild(d) }
    ;[...box.children].forEach((el, i) => {
      if (i >= items.length) { el.style.display = 'none'; return }
      const [p, text, me] = items[i]
      const v = p.clone().project(this.camera)
      if (v.z > 1) { el.style.display = 'none'; return }
      el.style.display = 'block'
      el.className = 'bubble' + (me ? ' me' : '')
      if (el.textContent !== text) el.textContent = text
      el.style.left = Math.min(innerWidth - 120, Math.max(120, (v.x * 0.5 + 0.5) * innerWidth)) + 'px'
      el.style.top = Math.max(50, (-v.y * 0.5 + 0.5) * innerHeight) + 'px'
    })
  }

  // ---------- overlays ----------
  buildMorphUI() {
    const c = this.body.combo
    $('morphTitle').textContent = c.name.toUpperCase()
    document.querySelectorAll('.slotTab').forEach((t, i) => {
      t.classList.toggle('on', i === this.morphSlot)
      t.querySelector('.l2').textContent = c.get(i).name
      t.querySelector('.l3').textContent = `${i + 4} · add-on: ${AddOns.names(i)[this.body.addOns[i]]}`
    })
    const grid = $('grid')
    if (!grid.children.length) {
      for (const sp of Species.all) {
        const b = document.createElement('button')
        const col = sp.def.a.map(v => Math.round(v * 255)).join(',')
        b.innerHTML = `<span class="dot" style="background:rgb(${col})"></span>${sp.name}`
        b.dataset.id = sp.id
        b.onclick = () => { this.morph(this.morphSlot, sp); this.buildMorphUI() }
        grid.appendChild(b)
      }
    }
    const cur = c.get(this.morphSlot).id
    const q = $('search').value.trim().toLowerCase()
    const hit = q ? searchAnimal(q) : -1
    ;[...grid.children].forEach(b => {
      const id = +b.dataset.id
      b.classList.toggle('sel', id === cur)
      b.classList.toggle('hit', id === hit)
    })
  }
  buildMapsUI() {
    const box = $('maps'); box.innerHTML = ''
    Maps.all.forEach((m, i) => {
      const b = document.createElement('button')
      b.className = i === this.mapIndex ? 'here' : ''
      b.innerHTML = `<div class="mn">${m.name}${i === this.mapIndex ? ' · here' : ''}</div><div class="mb">${m.blurb}</div><div class="ma">${m.natives.length ? m.natives.slice(0, 5).join(', ') + (m.natives.length > 5 ? '…' : '') : 'Farm animals + the farmer'}</div>`
      b.onclick = () => this.travel(i)
      box.appendChild(b)
    })
  }
  buildStatsUI() {
    const st = this.save.stats, v = k => Math.round(st[k] || 0)
    const secs = Math.round(st['Time played'] || 0)
    const rows = [['Time played', `${Math.floor(secs / 3600)}h ${String(Math.floor(secs / 60) % 60).padStart(2, '0')}m`],
      ['Distance walked', ((st['Distance walked'] || 0) / 1000).toFixed(1) + ' km'], ['Distance flown / glided', v('Distance flown') + ' m'],
      ['Highest point reached', v('Highest point') + ' m'], ['Jumps', v('Jumps')], ['Morphs', v('Morphs')],
      ['Animals tried', `${this.save.tried.length} of ${Species.count}`], ['Different mixes made', this.save.combos.length],
      ['Maps visited', `${this.save.visited.length} of ${Maps.all.length}`], ['Things knocked over', v('Things knocked over')],
      ['Barrels exploded', v('Barrels exploded')], ['Eggs laid', this.save.eggs], ['Farmer scared', v('Farmer scared')],
      ['Farmer knocked over', v('Farmer knocked over')], ['Times swum', v('Swims')], ['Things thrown', v('Things thrown')], ['Things eaten', v('Things eaten')],
      ['Current look', this.body.combo.recipe]]
    $('stats').innerHTML = rows.map(r => `<tr><td>${r[0]}</td><td>${r[1]}</td></tr>`).join('')
  }
  updateTitle() {
    const m = Maps.all[this.titleMap]
    $('mapName').textContent = 'MAP: ' + m.name.toUpperCase()
    $('mapBlurb').textContent = m.blurb
  }
  stepTitleMap(d) { this.titleMap = (this.titleMap + d + Maps.all.length) % Maps.all.length; this.audio.play('click', { volume: 0.5 }); this.updateTitle() }
  async startPlay() {
    await this.audio.init()
    this.audio.play('select', { volume: 0.6, jitter: 0 })
    if (this.titleMap !== this.mapIndex) await this.travel(this.titleMap, true)
    this.enter('play')
  }
  async travel(i, fromTitle = false) {
    $('loading').classList.remove('hidden'); loading(0.5, `Travelling to the ${Maps.all[i].name}…`)
    await nextFrame()
    this.loadMap(i)
    $('loading').classList.add('hidden')
    if (!fromTitle) { this.enter('play'); this.toast(this.world.map.name.toUpperCase(), this.world.map.blurb) }
  }
  toggleMusic() { this.save.musicOn = !this.save.musicOn; this.audio.music.on = this.save.musicOn; $('musicBtn').textContent = 'Music: ' + (this.save.musicOn ? 'on' : 'off'); storeSave(this.save) }
}
Object.defineProperties(Game.prototype, Object.getOwnPropertyDescriptors(PlayerMixin))

function searchAnimal(q) {
  const names = Zoo.defs.map(d => d.name.toLowerCase())
  let i = names.indexOf(q)
  if (i < 0) i = names.findIndex(n => n.startsWith(q))
  if (i < 0) i = names.findIndex(n => n.split(' ').some(w => w.startsWith(q)))
  if (i < 0) i = names.findIndex(n => n.includes(q))
  return i
}

/// Equirectangular sky with sun glow and clouds, like Game.sky() in Swift (smaller for the web).
function makeSky(m) {
  const W = IS_TOUCH ? 768 : 1280, H = W / 2
  const data = new Uint8Array(W * H * 4)
  const sd = V(m.sunDir[0], m.sunDir[1], m.sunDir[2]).normalize()
  for (let py = 0; py < H; py++) {
    const lat = Math.PI / 2 - (py + 0.5) / H * Math.PI
    for (let px = 0; px < W; px++) {
      const lon = (px + 0.5) / W * 2 * Math.PI - Math.PI
      // three's equirect maps u=0.5 to -z like SceneKit after the flip below
      const dx = Math.sin(lon) * Math.cos(lat), dy = Math.sin(lat), dz = -Math.cos(lon) * Math.cos(lat)
      const cosSun = dx * sd.x + dy * sd.y + dz * sd.z
      const up = Math.max(0, dy)
      let c = mix3(m.horizon, m.zenith, Math.pow(up, 0.5))
      c = mix3(c, [1, 0.85, 0.62], Math.pow(Math.max(0, cosSun), 8) * 0.45 * (1 - up * 0.5))
      const s = Math.pow(Math.max(0, cosSun), 200) * 0.7
      c = [c[0] + s, c[1] + s * 0.9, c[2] + s * 0.7]
      if (cosSun > 0.9995) c = [1, 0.98, 0.92]
      if (dy > 0) {
        const cx = dx / (dy + 0.12), cz = dz / (dy + 0.12)
        const cl = Noise.fbm(cx * 1.1, cz * 1.1, 4, 5)
        const cover = smoothstep(0.1, 0.45, cl - (m.clouds - 1) * 0.12) * smoothstep(0, 0.1, dy) * (1 - smoothstep(0.4, 0.85, dy)) * Math.min(1, m.clouds)
        if (cover > 0.001) {
          const shade = Noise.fbm(cx * 1.1 + 0.08, cz * 1.1 + 0.08, 3, 5)
          const lit = mix3([0.66, 0.68, 0.74], [1, 0.97, 0.92], Math.min(1, Math.max(0, 0.55 + (cl - shade) * 5 + cosSun * 0.3)))
          c = mix3(c, lit, cover * 0.9)
        }
      } else c = mix3(mix3(m.horizon, [0, 0, 0], 0.1), mix3(m.hills, m.horizon, 0.2), smoothstep(0, 0.2, -dy))
      const i = ((H - 1 - py) * W + px) * 4
      data[i] = Math.min(255, c[0] * 255); data[i + 1] = Math.min(255, c[1] * 255); data[i + 2] = Math.min(255, c[2] * 255); data[i + 3] = 255
    }
  }
  const t = new THREE.DataTexture(data, W, H, THREE.RGBAFormat)
  t.mapping = THREE.EquirectangularReflectionMapping
  t.colorSpace = THREE.SRGBColorSpace
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearFilter
  t.needsUpdate = true
  return t
}

// ---------------- touch + mouse wiring ----------------
function wireControls(game) {
  const inp = game.input
  const canvas = $('c')
  // mouse drag to look, wheel to zoom
  let dragging = false, lx = 0, ly = 0
  canvas.addEventListener('mousedown', e => { dragging = true; lx = e.clientX; ly = e.clientY })
  addEventListener('mouseup', () => dragging = false)
  addEventListener('mousemove', e => { if (dragging) { inp.drag.x += e.clientX - lx; inp.drag.y += e.clientY - ly; lx = e.clientX; ly = e.clientY } })
  canvas.addEventListener('wheel', e => { inp.scroll += e.deltaY; e.preventDefault() }, { passive: false })
  // touch: anything that isn't a control drags the camera
  const looks = new Map()
  canvas.addEventListener('touchstart', e => { for (const t of e.changedTouches) looks.set(t.identifier, [t.clientX, t.clientY]); game.audio.init() }, { passive: true })
  canvas.addEventListener('touchmove', e => {
    for (const t of e.changedTouches) { const p = looks.get(t.identifier); if (p) { inp.drag.x += (t.clientX - p[0]) * 1.4; inp.drag.y += (t.clientY - p[1]) * 1.4; looks.set(t.identifier, [t.clientX, t.clientY]) } }
    e.preventDefault()
  }, { passive: false })
  canvas.addEventListener('touchend', e => { for (const t of e.changedTouches) looks.delete(t.identifier) })
  // joystick
  const stick = $('stick'), knob = $('knob')
  let sid = null
  const setStick = (x, y) => {
    const r = stick.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2
    let dx = (x - cx) / (r.width / 2), dy = (y - cy) / (r.height / 2)
    const l = Math.hypot(dx, dy); if (l > 1) { dx /= l; dy /= l }
    inp.move.set(dx, -dy)
    knob.style.transform = `translate(${dx * 45}px, ${dy * 45}px)`
  }
  stick.addEventListener('touchstart', e => { const t = e.changedTouches[0]; sid = t.identifier; setStick(t.clientX, t.clientY); e.preventDefault() }, { passive: false })
  stick.addEventListener('touchmove', e => { for (const t of e.changedTouches) if (t.identifier === sid) setStick(t.clientX, t.clientY); e.preventDefault() }, { passive: false })
  const endStick = e => { for (const t of e.changedTouches) if (t.identifier === sid) { sid = null; inp.move.set(0, 0); knob.style.transform = '' } }
  stick.addEventListener('touchend', endStick); stick.addEventListener('touchcancel', endStick)
  // action buttons
  const hold = (id, key) => {
    const el = $(id)
    el.addEventListener('touchstart', e => { inp.tap(key); inp.held.add(key); el.classList.add('on'); e.preventDefault() }, { passive: false })
    const up = e => { inp.held.delete(key); el.classList.remove('on'); e.preventDefault() }
    el.addEventListener('touchend', up, { passive: false }); el.addEventListener('touchcancel', up, { passive: false })
  }
  hold('bJump', 'space'); hold('bE', 'e'); hold('bF', 'f'); hold('bR', 'r'); hold('bQ', 'q')
  $('bRun').addEventListener('touchstart', e => { inp.running = !inp.running; $('bRun').classList.toggle('on', inp.running); e.preventDefault() }, { passive: false })
  // HUD buttons (work with mouse and touch)
  const click = (el, fn) => el.addEventListener('click', e => { e.stopPropagation(); game.audio.init(); fn() })
  document.querySelectorAll('#combo .slot').forEach((row, i) => {
    row.querySelectorAll('.sw').forEach(b => click(b, () => { const s = game.body.combo.get(i); game.morph(i, +b.dataset.dir > 0 ? s.next : s.prev) }))
    click(row.querySelector('.add'), () => game.cycleAddOn(i, false))
  })
  click($('bMorph'), () => game.enter('morph'))
  click($('bRandom'), () => game.randomMorph())
  click($('bMaps'), () => game.enter('maps'))
  click($('bStats'), () => game.enter('stats'))
  click($('bPause'), () => game.enter('paused'))
  click($('resume'), () => game.enter('play'))
  click($('toTitle'), () => { storeSave(game.save); game.enter('title') })
  click($('musicBtn'), () => game.toggleMusic())
  document.querySelectorAll('[data-close]').forEach(b => click(b, () => game.enter('play')))
  document.querySelectorAll('.slotTab').forEach((t, i) => click(t, () => { game.morphSlot = i; game.buildMorphUI() }))
  document.querySelectorAll('.slotTab .l3').forEach((t, i) => t.addEventListener('click', e => { e.stopPropagation(); game.cycleAddOn(i, false); game.buildMorphUI() }))
  click($('wholeBtn'), () => { const s = game.body.combo.get(game.morphSlot); for (let k = 0; k < 3; k++) game.morph(k, s); game.buildMorphUI() })
  click($('randBtn'), () => { game.randomMorph(); game.buildMorphUI() })
  const search = $('search')
  search.addEventListener('input', () => game.buildMorphUI())
  search.addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      const i = searchAnimal(search.value.trim().toLowerCase())
      if (i >= 0) { if (e.shiftKey) for (let k = 0; k < 3; k++) game.morph(k, Species.of(i)); else game.morph(game.morphSlot, Species.of(i)) }
      search.value = ''; game.buildMorphUI(); search.blur()
    } else if (e.key === 'Escape' || e.key === 'Tab') { search.blur(); e.preventDefault(); game.enter('play') }
    e.stopPropagation()
  })
  click($('mapPrev'), () => game.stepTitleMap(-1))
  click($('mapNext'), () => game.stepTitleMap(1))
  click($('play'), () => game.startPlay())
}

// ---------------- boot ----------------
async function boot() {
  if (IS_TOUCH) document.body.classList.add('touch')
  const renderer = new THREE.WebGLRenderer({ canvas: $('c'), antialias: !IS_TOUCH, powerPreference: 'high-performance' })
  renderer.setPixelRatio(Math.min(devicePixelRatio, IS_TOUCH ? 1.5 : 2))
  renderer.setSize(innerWidth, innerHeight)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.12
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  loading(0.05, 'Starting physics…')
  await RAPIER.init()
  await nextFrame()
  const game = new Game(renderer)
  window.game = game
  game.physics = new RAPIER.World({ x: 0, y: -9.81, z: 0 })
  game.pusher = makePusher(game.physics)
  loading(0.2, 'Growing the grass…')
  await nextFrame()
  const save = game.save
  game.loadMap(Math.min(Maps.all.length - 1, Math.max(0, save.map || 0)))
  loading(0.75, 'Waking up the animals…')
  await nextFrame()
  game.body = new Body(Combo.fromIndex(save.combo || 0))
  game.body.addOns = [...(save.addOns || [0, 0, 0])]
  game.body.applyAddOns()
  game.scene.add(game.body.root)
  game.hitCache = hitCircles(game.body)
  game.audio.music.on = save.musicOn !== false
  $('musicBtn').textContent = 'Music: ' + (save.musicOn !== false ? 'on' : 'off')
  wireControls(game)
  $('titleKeys').textContent = IS_TOUCH ? 'Left stick to move · drag to look · buttons on the right for moves' : '◀ ▶ map · ENTER start · WASD move · drag to look · 1 2 3 morph · 4 5 6 add-ons · TAB all 100 animals · Z random · B maps · J stats · M music'
  if (IS_MAC_DESKTOP) $('macRow').classList.remove('hidden')
  loading(1, 'Ready!')
  await nextFrame()
  $('loading').classList.add('hidden')
  game.enter('title')
  addEventListener('resize', () => { renderer.setSize(innerWidth, innerHeight); game.camera.aspect = innerWidth / innerHeight; game.camera.updateProjectionMatrix() })
  addEventListener('keydown', () => game.audio.init(), { once: true })
  addEventListener('pagehide', () => storeSave(game.save))
  document.addEventListener('visibilitychange', () => { if (document.hidden) storeSave(game.save) })
  let last = performance.now()
  const tick = now => {
    const dt = Math.min(1 / 20, Math.max(1 / 240, (now - last) / 1000))
    last = now
    game.frame(dt)
    requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
  Coats.prewarm && Coats.prewarm(Zoo.defs)
}

/// The player's invisible kinematic body: one capsule per hitbox circle, so it shoves junk realistically.
function makePusher(world) {
  const body = world.createRigidBody(RAPIER.RigidBodyDesc.kinematicPositionBased())
  let colliders = []
  return {
    setShape(circles, h) {
      for (const c of colliders) world.removeCollider(c, false)
      colliders = circles.map(c => {
        const half = Math.max(0.05, h / 2 - c.r)
        const d = RAPIER.ColliderDesc.capsule(half, c.r * 0.92).setTranslation(0, 0, c.z)
        if (PUSHER_GROUPS !== null) d.setCollisionGroups(PUSHER_GROUPS)
        return world.createCollider(d, body)
      })
    },
    setPose(x, y, z, yaw) {
      body.setNextKinematicTranslation({ x, y, z })
      body.setNextKinematicRotation({ x: 0, y: Math.sin(yaw / 2), z: 0, w: Math.cos(yaw / 2) })
    },
  }
}
// collision groups for the pusher (set after the world module tells us its groups)
let PUSHER_GROUPS = (0x0002 << 16) | 0x0008

boot().catch(e => { console.error(e); $('loadMsg').textContent = 'Something went wrong: ' + e.message })
