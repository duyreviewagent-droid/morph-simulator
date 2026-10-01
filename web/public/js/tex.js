// Procedural PBR textures and material helpers. Ported from Texgen.swift.
import * as THREE from '../vendor/three.module.js'
import { clamp, QUALITY } from './util.js'

/// Generates albedo / normal / roughness (and optional metalness) DataTextures from a per-pixel
/// function f(x, y) -> { c: [r,g,b] (0..1, sRGB), h: height, r: roughness, m: metal }.
/// Sizes are scaled by QUALITY (tablets get half resolution). The height field wraps.
export function makePBR(w0, h0, bump, f, { metal = false, quality = QUALITY } = {}) {
  const w = Math.max(16, Math.round(w0 * quality)), h = Math.max(16, Math.round(h0 * quality))
  const sx = w0 / w, sy = h0 / h
  const n = w * h
  const H = new Float32Array(n), R = new Float32Array(n), M = metal ? new Float32Array(n) : null
  const dif = new Uint8Array(n * 4)
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x
      const t = f(Math.floor(x * sx), Math.floor(y * sy))
      const c = t.c || [0.5, 0.5, 0.5]
      dif[i * 4] = clamp(c[0], 0, 1) * 255; dif[i * 4 + 1] = clamp(c[1], 0, 1) * 255; dif[i * 4 + 2] = clamp(c[2], 0, 1) * 255; dif[i * 4 + 3] = 255
      H[i] = t.h || 0; R[i] = t.r === undefined ? 0.8 : t.r
      if (M) M[i] = t.m || 0
    }
  }
  const nor = new Uint8Array(n * 4), rou = new Uint8Array(n * 4)
  const b = bump * (1 / Math.max(sx, 1))
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x
      const xl = H[y * w + (x + w - 1) % w], xr = H[y * w + (x + 1) % w]
      const yu = H[((y + h - 1) % h) * w + x], yd = H[((y + 1) % h) * w + x]
      let nx = -(xr - xl) * b, ny = (yd - yu) * b, nz = 1
      const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l
      nor[i * 4] = (nx * 0.5 + 0.5) * 255; nor[i * 4 + 1] = (ny * 0.5 + 0.5) * 255; nor[i * 4 + 2] = (nz * 0.5 + 0.5) * 255; nor[i * 4 + 3] = 255
      const rv = clamp(R[i], 0.02, 1) * 255
      const mv = M ? clamp(M[i], 0, 1) * 255 : 0
      rou[i * 4] = 255; rou[i * 4 + 1] = rv; rou[i * 4 + 2] = mv; rou[i * 4 + 3] = 255   // three: G = roughness, B = metalness
    }
  }
  const mk = (data, srgb) => {
    const t = new THREE.DataTexture(data, w, h, THREE.RGBAFormat)
    t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace
    t.wrapS = t.wrapT = THREE.RepeatWrapping
    t.magFilter = THREE.LinearFilter
    t.minFilter = THREE.LinearMipmapLinearFilter
    t.generateMipmaps = true
    t.anisotropy = 4
    t.needsUpdate = true
    return t
  }
  return { diffuse: mk(dif, true), normal: mk(nor, false), rough: mk(rou, false), metal: !!M }
}

/// Same as makePBR but only an RGBA colour texture (with alpha), for cut-outs (grass, leaves).
export function makeRGBA(w0, h0, f, { quality = QUALITY } = {}) {
  const w = Math.max(16, Math.round(w0 * quality)), h = Math.max(16, Math.round(h0 * quality))
  const sx = w0 / w, sy = h0 / h
  const d = new Uint8Array(w * h * 4)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const p = f(Math.floor(x * sx), Math.floor(y * sy))   // [r,g,b,a]
    const i = (y * w + x) * 4
    d[i] = clamp(p[0], 0, 1) * 255; d[i + 1] = clamp(p[1], 0, 1) * 255; d[i + 2] = clamp(p[2], 0, 1) * 255; d[i + 3] = clamp(p[3], 0, 1) * 255
  }
  const t = new THREE.DataTexture(d, w, h, THREE.RGBAFormat)
  t.colorSpace = THREE.SRGBColorSpace
  t.wrapS = t.wrapT = THREE.RepeatWrapping
  t.minFilter = THREE.LinearMipmapLinearFilter; t.magFilter = THREE.LinearFilter
  t.generateMipmaps = true
  t.needsUpdate = true
  return t
}

/// A PBR material from generated maps. `rep` = [u, v] repeats across a 0..1 UV range.
export function pbrMaterial(p, { normalScale = 1, rep = [1, 1] } = {}) {
  const m = new THREE.MeshStandardMaterial({
    map: p.diffuse, normalMap: p.normal, roughnessMap: p.rough, roughness: 1,
    metalness: p.metal ? 1 : 0, metalnessMap: p.metal ? p.rough : null,
  })
  m.normalScale.set(normalScale, normalScale)
  if (rep[0] !== 1 || rep[1] !== 1) tiled(m, rep[0], rep[1])
  return m
}

/// Sets how many times every map repeats. Textures are cloned so shared images can repeat differently.
export function tiled(m, su, sv) {
  for (const k of ['map', 'normalMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'emissiveMap']) {
    if (m[k]) {
      if (m[k].userData.__tiledOwner !== m) { m[k] = m[k].clone(); m[k].userData.__tiledOwner = m; m[k].needsUpdate = true }
      m[k].repeat.set(su, sv); m[k].wrapS = m[k].wrapT = THREE.RepeatWrapping
    }
  }
  return m
}

/// A plain physically based material. Colour is sRGB 0..1.
export function pbr(c, { rough = 0.7, metal = 0, emissive = null, opacity = 1 } = {}) {
  const m = new THREE.MeshStandardMaterial({ roughness: rough, metalness: metal })
  m.color.setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace)
  if (emissive) { m.emissive.setRGB(emissive[0], emissive[1], emissive[2], THREE.SRGBColorSpace); m.emissiveIntensity = 1 }
  if (opacity < 1) { m.transparent = true; m.opacity = opacity; m.depthWrite = false }
  return m
}

export const copyMat = m => m.clone()

/// Adds GLSL into a standard material's fragment shader after the albedo is known.
/// `code` may use: vec4 diffuseColor, vec3 vWorldNormalMS (world normal), vec2 vUvMS, float uTime.
/// `vertex` may move `transformed` (object space) using `normal`, `uv`, uTime and uniforms in `uniforms`.
export function patchShader(m, { fragment = '', vertex = '', uniforms = {}, key = '' } = {}) {
  const prev = m.onBeforeCompile
  m.userData.uniforms = Object.assign(m.userData.uniforms || {}, uniforms)
  m.onBeforeCompile = (shader, r) => {
    if (prev) prev(shader, r)
    Object.assign(shader.uniforms, m.userData.uniforms)
    shader.uniforms.uTime = TIME
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;\nvarying vec3 vWorldNormalMS;\nvarying vec2 vUvMS;\nvarying vec3 vWorldPosMS;\n' + Object.keys(uniforms).map(k => `uniform float ${k};`).join('\n'))
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + vertex)
      .replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvWorldNormalMS = normalize(mat3(modelMatrix) * objectNormal);\nvUvMS = uv;\nvWorldPosMS = (modelMatrix * vec4(transformed, 1.0)).xyz;')
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;\nvarying vec3 vWorldNormalMS;\nvarying vec2 vUvMS;\nvarying vec3 vWorldPosMS;\n' + Object.keys(uniforms).map(k => `uniform float ${k};`).join('\n'))
      .replace('#include <map_fragment>', '#include <map_fragment>\n' + fragment)
  }
  m.customProgramCacheKey = () => 'mp|' + key + '|' + fragment.length + '|' + vertex.length
  // worldpos_vertex only runs when needed; make sure it always runs
  m.defines = Object.assign(m.defines || {}, { USE_UV: '' })
  return m
}
/// Shared time uniform for wind and other animated shaders.
export const TIME = { value: 0 }
