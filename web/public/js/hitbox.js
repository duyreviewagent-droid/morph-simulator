// Body-shaped collision circles, same rules as Body.hitCircles in Parts.swift.
import { CowLegs } from './parts.js'
import { GenLegs } from './genparts.js'

/// Trunk of the legs part: half-length along z, half-width, centre z.
function trunk(legs) {
  if (legs instanceof CowLegs) return { half: 0.8, width: 0.42, z: 0 }
  if (legs instanceof GenLegs) {
    const d = legs.d, s = legs.s, R = legs.R, L = legs.L
    switch (d.plan) {
      case 'quad': return { half: L + 0.05 * s, width: R * 1.05, z: 0 }
      case 'sprawl': return { half: L + 0.05 * s, width: R * 1.1 + 0.05 * s, z: 0 }
      case 'slither': { const half = 0.8 * s * d.bodyLen; return { half, width: Math.max(0.12, R * 1.6), z: 0.12 * s - half } }
      case 'fish': { const half = (0.5 + 0.5 * d.bodyLen) * s * 0.5; return { half, width: R * 1.05, z: 0.2 * s - half } }
      case 'insect': case 'spider': {
        const spider = d.plan === 'spider', crab = d.arms === 'pincer' && spider
        const half = (spider ? 0.25 : 0.32) * s * d.bodyLen
        return { half, width: Math.max(0.15, (crab ? 0.3 : 0.14) * s), z: 0.06 * s - half * 0.8 }
      }
    }
  }
  return { half: 0, width: legs.radius || 0.3, z: 0 }
}

/// [{z, r}] in body space along +z (forward).
export function hitCircles(body) {
  const t = trunk(body.legs)
  const w = Math.max(0.18, t.width)
  const out = []
  if (t.half > w * 0.9) {
    const span = t.half * 2 - w * 2
    const n = Math.max(2, Math.ceil(span / (w * 1.1)) + 1)
    for (let k = 0; k < n; k++) out.push({ z: t.z - t.half + w + span * k / (n - 1), r: w })
  } else out.push({ z: t.z, r: Math.max(w, Math.min(body.legs.radius, 0.45)) })
  // the head poking out past the trunk
  const nr = body.torso.neckRot - body.tiltFor(body.combo)
  const m = body.head.mouth
  const hz = body.legs.attach.z + body.torso.neck.z + m.z * Math.cos(nr) + m.y * Math.sin(nr)
  const last = out[out.length - 1]
  if (hz > last.z + last.r + 0.05) {
    const hr = Math.min(0.32, Math.max(0.1, body.head.height * 0.35))
    out.push({ z: hz - hr * 0.6, r: hr })
  }
  return out
}
