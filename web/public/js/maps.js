// The ten playable places. Ported from Maps.swift.
// The farm is hand-built in world.js; the other nine are generated from these numbers (scenery in mapbuilder.js).
import { Noise, smoothstep, mix, mix3 } from './util.js'

const HALF = 236   // Farm.half (kept local so this module has no import cycle)

const norm3 = v => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l] }
const mul = (v, k) => [v[0] * k, v[1] * k, v[2] * k]

// Bit-identical to util.js Noise.perlin/fbm/ridged, but inlined (about 2x faster). Terrain and colour functions
// run millions of times while a map builds, and the game queries terrain() every frame.
function grad(h, x, y) {
  switch (h & 7) { case 0: return x + y; case 1: return -x + y; case 2: return x - y; case 3: return -x - y; case 4: return x * 1.4; case 5: return -x * 1.4; case 6: return y * 1.4; default: return -y * 1.4 }
}
function perlin(x, y, seed) {
  const xi = Math.floor(x), yi = Math.floor(y)
  const xf = x - xi, yf = y - yi
  const u = xf * xf * xf * (xf * (xf * 6 - 15) + 10), v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
  const ax = Math.imul(xi, 374761393), bx = Math.imul(xi + 1, 374761393)
  const ay = Math.imul(yi, 668265263), by = Math.imul(yi + 1, 668265263), s = Math.imul(seed, 1442695041)
  let h
  h = (ax + ay + s) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); const a = grad(h ^ (h >>> 16), xf, yf)
  h = (bx + ay + s) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); const b = grad(h ^ (h >>> 16), xf - 1, yf)
  h = (ax + by + s) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); const c = grad(h ^ (h >>> 16), xf, yf - 1)
  h = (bx + by + s) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); const d = grad(h ^ (h >>> 16), xf - 1, yf - 1)
  const ab = a + (b - a) * u, cd = c + (d - c) * u
  return (ab + (cd - ab) * v) * 0.75
}
function nfbm(x, y, octaves, seed = 1) {
  let sum = 0, amp = 1, f = 1, norm = 0
  for (let i = 0; i < octaves; i++) { sum += amp * perlin(x * f, y * f, seed + i * 17); norm += amp; amp *= 0.5; f *= 2.03 }
  return sum / norm
}
function ridged(x, y, octaves, seed = 1) {
  let sum = 0, amp = 0.55, f = 1, weight = 1
  for (let i = 0; i < octaves; i++) {
    let n = 1 - Math.abs(perlin(x * f, y * f, seed + i * 31) * 1.3)
    n = Math.max(n, 0); n *= n; n *= weight
    weight = Math.min(Math.max(n * 1.8, 0), 1)
    sum += n * amp; f *= 2.05; amp *= 0.5
  }
  return sum
}
export const FastNoise = { perlin, fbm: nfbm, ridged, cell: Noise.cell }

const fbm = (x, z, f, o, s) => nfbm(x * f, z * f, o, s)
const dist = (x, z, cx, cz) => Math.hypot(x - cx, z - cz)
const edgeRise = (x, z) => smoothstep(HALF * 0.75, HALF, Math.max(Math.abs(x), Math.abs(z))) * 10

/// MapDef defaults (Swift struct defaults). Surfaces are Surface.* strings.
function MapDef(name, blurb) {
  return {
    name, blurb,
    zenith: [0.2, 0.4, 0.78], horizon: [0.82, 0.86, 0.88], fog: [0.78, 0.83, 0.86],
    fogStart: 70, fogEnd: 520,
    sunColor: [1, 0.93, 0.82], sunIntensity: 2400,
    sunDir: norm3([0.5, 0.62, 0.45]),
    clouds: 1,
    grassLow: [0.1, 0.2, 0.035], grassHigh: [0.26, 0.36, 0.08],
    grassCount: 40000,
    hills: [0.18, 0.26, 0.09],
    waterLevel: null,
    waterCol: [0.05, 0.09, 0.08],
    natives: [],
    spawn: [2, 0, 7],
    groundRough: 0.95,
    height: () => 0,
    color: () => [0.2, 0.3, 0.1],
    grass: () => true,
    surface: () => 'grass',
  }
}

const all = [
  MapDef('Farm', 'Barn, silo, coop, pasture and a very nervous farmer'),

  (() => {
    const m = MapDef('Savanna', 'Golden grass, acacia trees and a busy watering hole')
    m.zenith = [0.3, 0.48, 0.8]; m.horizon = [0.95, 0.85, 0.66]; m.fog = [0.9, 0.82, 0.66]
    m.sunColor = [1, 0.85, 0.62]; m.sunIntensity = 2700; m.sunDir = norm3([0.6, 0.45, 0.4])
    m.grassLow = [0.36, 0.28, 0.1]; m.grassHigh = [0.72, 0.58, 0.28]; m.hills = [0.5, 0.4, 0.2]
    m.waterLevel = -0.45; m.waterCol = [0.12, 0.11, 0.06]
    m.natives = ['Lion', 'Zebra', 'Giraffe', 'Elephant', 'Rhino', 'Cheetah', 'Meerkat', 'Hippo', 'Ostrich']
    m.height = (x, z) => fbm(x, z, 0.012, 4, 31) * 3 + edgeRise(x, z) - 1.8 * smoothstep(12, 3, dist(x, z, 22, 18))
    m.color = (x, z) => {
      const n = fbm(x, z, 0.05, 4, 32), d = smoothstep(0.1, 0.5, fbm(x, z, 0.02, 3, 33))
      let c = mix3([0.55, 0.45, 0.22], [0.42, 0.36, 0.16], n * 0.5 + 0.5)
      c = mix3(c, [0.58, 0.36, 0.2], d * 0.45)
      return mix3(c, [0.3, 0.22, 0.14], smoothstep(14, 9, dist(x, z, 22, 18)))
    }
    m.grass = (x, z) => dist(x, z, 22, 18) > 13
    return m
  })(),

  (() => {
    const m = MapDef('Arctic', 'Snowfields, ice floes and a freezing lake')
    m.zenith = [0.35, 0.5, 0.75]; m.horizon = [0.88, 0.92, 0.96]; m.fog = [0.86, 0.9, 0.95]
    m.fogStart = 40; m.fogEnd = 380
    m.sunColor = [1, 0.96, 0.9]; m.sunIntensity = 2100; m.sunDir = norm3([0.5, 0.3, 0.5])
    m.grassCount = 0; m.hills = [0.88, 0.9, 0.95]
    m.waterLevel = -0.6; m.waterCol = [0.04, 0.1, 0.14]
    m.natives = ['Polar Bear', 'Penguin', 'Seal', 'Walrus', 'Reindeer', 'Wolf', 'Orca']
    m.groundRough = 0.7
    m.height = (x, z) => fbm(x, z, 0.015, 4, 41) * 4 + edgeRise(x, z) * 2 - 3 * smoothstep(24, 10, dist(x, z, -28, -22))
    m.color = (x, z) => {
      const n = fbm(x, z, 0.08, 3, 42)
      const c = mul([0.86, 0.9, 0.95], 0.92 + n * 0.08)
      return mix3(c, [0.62, 0.72, 0.8], smoothstep(22, 14, dist(x, z, -28, -22)) * 0.6)
    }
    m.grass = () => false
    m.surface = () => 'concrete'
    return m
  })(),

  (() => {
    const m = MapDef('Jungle', 'Towering trees, hanging vines and a muddy river')
    m.zenith = [0.3, 0.45, 0.62]; m.horizon = [0.7, 0.78, 0.72]; m.fog = [0.55, 0.65, 0.55]
    m.fogStart = 20; m.fogEnd = 220
    m.sunColor = [1, 0.95, 0.8]; m.sunIntensity = 1900
    m.grassLow = [0.04, 0.14, 0.03]; m.grassHigh = [0.14, 0.32, 0.06]; m.grassCount = 60000; m.hills = [0.08, 0.2, 0.05]
    m.waterLevel = -0.7; m.waterCol = [0.14, 0.12, 0.06]
    m.natives = ['Monkey', 'Gorilla', 'Chimpanzee', 'Orangutan', 'Toucan', 'Parrot', 'Tiger', 'Sloth', 'Frog', 'Snake', 'Chameleon', 'Leopard']
    m.spawn = [2, 0, -14]
    m.height = (x, z) => {
      const river = Math.abs(z - Math.sin(x * 0.035) * 18 - 8)
      return fbm(x, z, 0.02, 4, 51) * 4 + edgeRise(x, z) - 2.2 * smoothstep(9, 3, river)
    }
    m.color = (x, z) => {
      const n = fbm(x, z, 0.06, 4, 52)
      const river = Math.abs(z - Math.sin(x * 0.035) * 18 - 8)
      const c = mix3([0.1, 0.18, 0.05], [0.22, 0.2, 0.1], smoothstep(-0.2, 0.4, n))
      return mix3(c, [0.25, 0.2, 0.12], smoothstep(10, 6, river))
    }
    m.grass = (x, z) => Math.abs(z - Math.sin(x * 0.035) * 18 - 8) > 8
    return m
  })(),

  (() => {
    const m = MapDef('Desert', 'Rolling dunes, cactus and a palm oasis by the pyramid')
    m.zenith = [0.25, 0.45, 0.82]; m.horizon = [0.95, 0.86, 0.72]; m.fog = [0.93, 0.84, 0.7]
    m.sunColor = [1, 0.9, 0.74]; m.sunIntensity = 3000; m.sunDir = norm3([0.3, 0.8, 0.3]); m.clouds = 0.2
    m.grassCount = 0; m.hills = [0.8, 0.62, 0.4]
    m.waterLevel = -0.4; m.waterCol = [0.05, 0.15, 0.15]
    m.natives = ['Camel', 'Lizard', 'Snake', 'Cobra', 'Spider', 'Ostrich', 'Komodo Dragon', 'Meerkat']
    m.groundRough = 0.9
    m.height = (x, z) => {
      const dune = ridged(x * 0.02 + z * 0.006, z * 0.012, 3, 61) * 9 * smoothstep(25, 70, dist(x, z, 0, 0))
      return dune + fbm(x, z, 0.03, 3, 62) * 0.8 + edgeRise(x, z) - 1.6 * smoothstep(10, 4, dist(x, z, 30, -20))
    }
    m.color = (x, z) => {
      const n = fbm(x, z, 0.1, 3, 63)
      const c = mul([0.82, 0.66, 0.44], 0.92 + n * 0.1)
      return mix3(c, [0.35, 0.3, 0.18], smoothstep(11, 7, dist(x, z, 30, -20)))
    }
    m.grass = (x, z) => dist(x, z, 30, -20) < 14 && dist(x, z, 30, -20) > 7
    m.grassLow = [0.1, 0.22, 0.05]; m.grassHigh = [0.3, 0.4, 0.1]
    m.surface = (x, z) => dist(x, z, 30, -20) < 14 ? 'grass' : 'dirt'
    return m
  })(),

  (() => {
    const m = MapDef('Beach', 'Sand, palms, a pier and a whole ocean to swim in')
    m.zenith = [0.15, 0.42, 0.85]; m.horizon = [0.78, 0.88, 0.95]; m.fog = [0.75, 0.86, 0.94]
    m.sunIntensity = 2700
    m.grassLow = [0.2, 0.3, 0.08]; m.grassHigh = [0.4, 0.45, 0.15]; m.grassCount = 12000; m.hills = [0.3, 0.45, 0.2]
    m.waterLevel = 0; m.waterCol = [0.03, 0.18, 0.24]
    m.natives = ['Crab', 'Seal', 'Turtle', 'Pelican', 'Dolphin', 'Shark', 'Octopus', 'Jellyfish', 'Goldfish', 'Lobster', 'Whale']
    m.spawn = [0, 0, -8]
    m.height = (x, z) => {
      const land = 1.4 + fbm(x, z, 0.02, 4, 71) * 2.5 + smoothstep(-20, -160, z) * 10
      const shore = 18 + Math.sin(x * 0.04) * 6
      return mix(land, -7, smoothstep(shore - 8, shore + 26, z)) + edgeRise(x, Math.min(z, 0))
    }
    m.color = (x, z) => {
      const shore = 18 + Math.sin(x * 0.04) * 6
      const n = fbm(x, z, 0.08, 3, 72)
      const sand = mul([0.86, 0.78, 0.6], 0.93 + n * 0.08)
      const wet = [0.6, 0.52, 0.38]
      let c = mix3([0.25, 0.35, 0.12], sand, smoothstep(-30, -18, z - shore + 20))
      c = mix3(c, wet, smoothstep(shore - 2, shore + 4, z))
      return c
    }
    m.grass = (x, z) => z < 18 + Math.sin(x * 0.04) * 6 - 26
    m.surface = (x, z) => z < 18 + Math.sin(x * 0.04) * 6 - 22 ? 'grass' : 'dirt'
    return m
  })(),

  (() => {
    const m = MapDef('Forest', 'Pines, oaks, mushrooms, a log cabin and a quiet pond')
    m.zenith = [0.25, 0.42, 0.7]; m.horizon = [0.75, 0.8, 0.8]; m.fog = [0.62, 0.7, 0.68]
    m.fogStart = 30; m.fogEnd = 300; m.sunIntensity = 2000
    m.grassLow = [0.07, 0.16, 0.04]; m.grassHigh = [0.2, 0.3, 0.08]; m.grassCount = 45000; m.hills = [0.1, 0.2, 0.07]
    m.waterLevel = -0.5
    m.natives = ['Deer', 'Moose', 'Bear', 'Fox', 'Wolf', 'Raccoon', 'Squirrel', 'Owl', 'Hedgehog', 'Beaver', 'Skunk', 'Rabbit']
    m.height = (x, z) => fbm(x, z, 0.018, 4, 81) * 5 + edgeRise(x, z) - 2 * smoothstep(13, 5, dist(x, z, -20, 22))
    m.color = (x, z) => {
      const n = fbm(x, z, 0.05, 4, 82), leaf = smoothstep(0.1, 0.5, fbm(x, z, 0.15, 3, 83))
      let c = mix3([0.14, 0.2, 0.06], [0.24, 0.26, 0.1], n * 0.5 + 0.5)
      c = mix3(c, [0.32, 0.2, 0.1], leaf * 0.4)
      return mix3(c, [0.22, 0.18, 0.12], smoothstep(14, 10, dist(x, z, -20, 22)))
    }
    m.grass = (x, z) => dist(x, z, -20, 22) > 13
    return m
  })(),

  (() => {
    const m = MapDef('Mountains', 'Alpine meadow ringed by snowy peaks, and a high lake')
    m.zenith = [0.12, 0.3, 0.75]; m.horizon = [0.75, 0.84, 0.92]; m.fog = [0.75, 0.82, 0.9]
    m.fogStart = 90; m.fogEnd = 700; m.sunIntensity = 2600
    m.grassLow = [0.1, 0.22, 0.05]; m.grassHigh = [0.3, 0.4, 0.12]; m.hills = [0.5, 0.5, 0.5]
    m.waterLevel = -0.8; m.waterCol = [0.03, 0.1, 0.16]
    m.natives = ['Goat', 'Eagle', 'Llama', 'Alpaca', 'Bear', 'Bison', 'Wolf', 'Deer']
    const peaks = (x, z) => ridged(x * 0.012, z * 0.012, 5, 91) * 55 * smoothstep(70, 210, dist(x, z, 0, 0))
    m.height = (x, z) => peaks(x, z) + fbm(x, z, 0.03, 4, 92) * 2 - 3 * smoothstep(16, 6, dist(x, z, -10, -30))
    m.color = (x, z) => {
      const h = peaks(x, z)
      const n = fbm(x, z, 0.06, 3, 93)
      let c = mix3([0.2, 0.3, 0.1], [0.3, 0.34, 0.14], n * 0.5 + 0.5)
      c = mix3(c, mul([0.4, 0.38, 0.35], 0.9 + n * 0.2), smoothstep(4, 14, h))
      c = mix3(c, [0.92, 0.94, 0.97], smoothstep(26, 34, h + n * 4))
      return mix3(c, [0.3, 0.28, 0.22], smoothstep(15, 11, dist(x, z, -10, -30)))
    }
    m.grass = (x, z) => {
      const r = dist(x, z, 0, 0)
      return r < 120 && dist(x, z, -10, -30) > 14 && peaks(x, z) < 5
    }
    m.surface = (x, z) => dist(x, z, 0, 0) < 110 ? 'grass' : 'concrete'
    return m
  })(),

  (() => {
    const m = MapDef('Swamp', 'Murky pools, dead trees, lily pads and a shack on stilts')
    m.zenith = [0.35, 0.42, 0.45]; m.horizon = [0.6, 0.64, 0.56]; m.fog = [0.45, 0.5, 0.42]
    m.fogStart = 10; m.fogEnd = 160; m.sunColor = [0.9, 0.9, 0.75]; m.sunIntensity = 1500; m.clouds = 2
    m.grassLow = [0.1, 0.14, 0.04]; m.grassHigh = [0.26, 0.28, 0.1]; m.grassCount = 50000; m.hills = [0.15, 0.18, 0.1]
    m.waterLevel = 0; m.waterCol = [0.08, 0.1, 0.05]
    m.natives = ['Crocodile', 'Frog', 'Turtle', 'Snake', 'Axolotl', 'Duck', 'Flamingo', 'Otter', 'Beaver']
    m.height = (x, z) => fbm(x, z, 0.03, 4, 101) * 1.4 + 0.15 + edgeRise(x, z) + 0.8 * smoothstep(12, 4, dist(x, z, 0, 0))
    m.color = (x, z) => {
      const n = fbm(x, z, 0.08, 3, 102)
      return mix3([0.18, 0.2, 0.08], [0.22, 0.18, 0.1], n * 0.5 + 0.5)
    }
    m.grass = () => true
    return m
  })(),

  (() => {
    const m = MapDef('City Park', 'Lawns, paths, a fountain and the city all around')
    m.fog = [0.75, 0.78, 0.82]; m.fogStart = 80; m.fogEnd = 600
    m.grassLow = [0.1, 0.24, 0.05]; m.grassHigh = [0.24, 0.4, 0.08]; m.grassCount = 30000; m.hills = [0.35, 0.35, 0.38]
    m.waterLevel = -0.4
    m.natives = ['Pigeon', 'Squirrel', 'Dog', 'Cat', 'Rat', 'Duck', 'Goose', 'Crow', 'Raccoon', 'Swan']
    const pathD = (x, z) => Math.min(Math.abs(x - Math.sin(z * 0.05) * 6), Math.abs(z + 20 + Math.sin(x * 0.04) * 5), Math.abs(dist(x, z, 0, 0) - 14))
    m.height = (x, z) => -1.4 * smoothstep(12, 4, dist(x, z, 20, 14)) + 0.3 * Math.sin(x * 0.05) * Math.cos(z * 0.04)
    m.color = (x, z) => {
      const n = fbm(x, z, 0.06, 3, 111)
      let c = mix3([0.14, 0.28, 0.06], [0.2, 0.33, 0.08], n * 0.5 + 0.5)
      const path = pathD(x, z)
      c = mix3(c, [0.55, 0.52, 0.47], smoothstep(1.8, 1.3, path))
      c = mix3(c, [0.35, 0.34, 0.33], smoothstep(184, 188, Math.max(Math.abs(x), Math.abs(z))))
      return mix3(c, [0.3, 0.26, 0.18], smoothstep(13, 10, dist(x, z, 20, 14)))
    }
    m.grass = (x, z) => pathD(x, z) > 2.2 && dist(x, z, 20, 14) > 12 && Math.max(Math.abs(x), Math.abs(z)) < 180
    m.surface = (x, z) => pathD(x, z) < 1.8 ? 'concrete' : 'grass'
    m.spawn = [0, 0, -6]
    return m
  })(),
]

export const Maps = { all, fbm, dist, edgeRise }
