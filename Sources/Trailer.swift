import SceneKit
import AVFoundation
import simd

/// Renders a scripted ~33 s trailer to PNG frames plus a soundtrack WAV (encode with ffmpeg).
extension Game {
    func renderTrailer(to dir: String, renderer r: SCNRenderer, size: CGSize, fps: Double = 30) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var sfxLog: [(Double, String, Float, Float)] = []
        var clock = 0.0
        audio.onPlay = { name, vol, _, rate in sfxLog.append((clock, name, vol, rate)) }
        hud.setMode(.play)
        hud.playLayerHidden(true)
        enter(.play)
        hud.setMode(.play)
        hud.playLayerHidden(true)
        let total = 33.0
        var frame = 0
        var lineup: [SCNNode] = []
        var lastShot = -1
        let human = Combo(.human, .human, .human)
        func sp(_ n: String) -> Species { Species(id: Zoo.defs.firstIndex { $0.name == n } ?? 0) }
        let mapShots: [(Int, String)] = [(1, "Lion"), (2, "Polar Bear"), (3, "Gorilla"), (4, "Camel"), (5, "Dolphin"), (7, "Goat")]
        var rr = RNG(42)
        var nextRandom = 0.0
        var exploded = false

        func shotIndex(_ t: Double) -> Int {
            [4.0, 9.0, 13.0, 16.0, 22.0, 26.0, 29.5, 99].firstIndex { t < $0 }!
        }
        func cap(_ t: Double, _ t0: Double, _ t1: Double, _ big: String, _ small: String, title: Bool = false) {
            let a = min(1, max(0, (t - t0) / 0.4)) * min(1, max(0, (t1 - t) / 0.4))
            hud.caption(big, small, alpha: CGFloat(a), title: title)
        }
        while clock < total {
            let t = clock
            let shot = shotIndex(t)
            if shot != lastShot {
                // set up each shot
                for n in lineup { n.removeFromParentNode() }
                lineup.removeAll()
                body.root.isHidden = false
                devAct = nil
                switch shot {
                case 0, 1, 3, 5, 6, 7:
                    if mapIndex != 0 { loadMap(0) }
                    devPlace(V3(2, 0, 7), yaw: .pi)
                    body.setCombo(human); body.addOns = [0, 0, 0]; body.applyAddOns()
                    if shot == 5 { body.addOns = [2, 2, 9]; body.applyAddOns(); devAct = "run" }
                case 2:
                    body.root.isHidden = true
                    var x: Float = 0
                    for i in 3..<23 {
                        let s = Species(id: i)
                        let b = Body(Combo(s, s, s))
                        let w = max(0.9, b.radius * 2.2, s.def.size * 1.1)
                        x += w / 2
                        b.root.simdPosition = V3(x + 6, world.terrain(x + 6, 50), 50)
                        b.root.simdEulerAngles = V3(0, -.pi / 2, 0)
                        var p = Pose(); p.t = 1
                        b.update(p, dt: 1)
                        scene.rootNode.addChildNode(b.root)
                        lineup.append(b.root)
                        x += w / 2 + 0.3
                    }
                default: break
                }
                lastShot = shot
            }
            let u = Float(t)
            switch shot {
            case 0:
                cap(t, 0.3, 3.9, "MORPH SIMULATOR", "", title: true)
                let a = 0.6 + u * 0.12
                devCam = V3(2 + sinf(a) * 9, 3.5 - u * 0.25, 7 + cosf(a) * 9); devLook = V3(2, 1.2, 7)
            case 1:
                cap(t, 5.2, 8.9, "Be a human, a chicken and a cow", "at the same time")
                if t >= 5.0 && body.combo.legs == .human { morph(.legs, to: .cow) }
                if t >= 6.3 && body.combo.torso == .human { morph(.torso, to: .chicken) }
                let a = 2.2 + (u - 4) * 0.25
                devCam = V3(2 + sinf(a) * 4.2, 1.9, 7 + cosf(a) * 4.2); devLook = V3(2, 1.2, 7)
            case 2:
                cap(t, 9.2, 12.9, "100 animals", "farm, wild, birds, reptiles, sea life and bugs")
                let k = (u - 9) / 4
                devCam = V3(6 + k * 34, world.terrain(6 + k * 34, 42) + 2.2, 42.5); devLook = V3(9 + k * 34, world.terrain(9 + k * 34, 50) + 0.9, 50)
            case 3:
                cap(t, 13.1, 15.9, "Mix any head, body and legs", "1,000,000 possible creatures")
                if t >= nextRandom {
                    nextRandom = t + 0.5
                    // quick swaps without the full sparkle burst, so you can see each creature
                    for s in Slot.allCases { body.set(s, Species(id: 3 + rr.int(Species.count - 3))) }
                    audio.play("morph", volume: 0.5, rate: Float(rr.range(0.9, 1.2)))
                }
                let a = 0.4 + (u - 13) * 0.3
                devCam = V3(2 + sinf(a) * 5.5, 2.4, 7 + cosf(a) * 5.5); devLook = V3(2, 1.3, 7)
            case 4:
                let i = min(mapShots.count - 1, Int((u - 16) / 1.0))
                let (m, animal) = mapShots[i]
                if mapIndex != m {
                    loadMap(m)
                    let s = world.map.spawn
                    devPlace(V3(s.x, world.terrain(s.x, s.z), s.z), yaw: 0.6)
                    body.setCombo(Combo(sp(animal), sp(animal), sp(animal)))
                    devAct = "walk"
                }
                cap(t, 16.2, 21.9, "10 huge maps", world.map.name)
                let lt = u - 16 - Float(i)
                let s = world.map.spawn
                let a = 0.5 + lt * 0.35 + Float(i)
                devCam = V3(s.x + sinf(a) * 10, world.terrain(s.x, s.z) + 3.8 + lt, s.z + cosf(a) * 10)
                devLook = V3(s.x, world.terrain(s.x, s.z) + 1.2, s.z)
            case 5:
                cap(t, 22.2, 25.9, "12 add-ons for each part", "hats, capes, jetpacks, stilts… or Hurt mode")
                if t >= 24.0 && body.addOns[1] != 3 { body.setAddOn(.torso, 3); body.setAddOn(.legs, 4); devAct = "air" }
                if t >= 24.0 { pos.y = Float(t - 24) * 3; body.boosting = true; body.root.simdPosition = pos }
                let a = 1.0 + (u - 22) * 0.3
                devCam = V3(2 + sinf(a) * 6, 2.5 + max(0, u - 24) * 2.2, 7 + cosf(a) * 6); devLook = V3(2, 1.4 + max(0, u - 24) * 2.8, 7)
            case 6:
                cap(t, 26.8, 29.4, "Knock everything over", "crates, snowmen, bowling pins… and barrels that go boom")
                devPlace(V3(-4, 0, 1), yaw: -2.2)
                if t >= 27.0 && !exploded {
                    exploded = true
                    if let k = world.knockables.first(where: { $0.explosive && simd_length($0.pos - V3(-11, 0, -4)) < 4 }) { explode(k) }
                }
                devCam = V3(0, 4, 6 - (u - 26) * 0.4); devLook = V3(-10, 1, -4)
            default:
                cap(t, 29.8, 33.5, "MORPH SIMULATOR", "Free for Mac  ·  play in your browser too", title: true)
                pos.y = 0
                if body.combo != human { body.setCombo(human); body.addOns = [0, 0, 0]; body.applyAddOns() }
                devPlace(V3(2, 0, 7), yaw: .pi)
                let a = 3.6 + (u - 29.5) * 0.12
                devCam = V3(2 + sinf(a) * 11, 4.5, 7 + cosf(a) * 11); devLook = V3(2, 1.5, 7)
            }
            renderer(r, updateAtTime: t)
            if shot == 5 && t >= 24.0 { body.root.simdPosition = pos }
            let img = r.snapshot(atTime: t, with: size, antialiasingMode: .multisampling4X)
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: String(format: "%@/f%05d.png", dir, frame)))
            }
            frame += 1
            clock += 1 / fps
            if frame % 60 == 0 { print("frame \(frame)") }
        }
        writeSoundtrack(to: dir + "/audio.wav", seconds: total, events: sfxLog)
    }

    /// Music (play mood) with the trailer's sound effects mixed in, as 16-bit stereo WAV.
    private func writeSoundtrack(to path: String, seconds: Double, events: [(Double, String, Float, Float)]) {
        let sr = audio.sr
        let n = Int(seconds * sr)
        var L = [Float](repeating: 0, count: n), R = [Float](repeating: 0, count: n)
        let music = MusicSynth(sampleRate: Float(sr))
        music.mood = .play
        let block = 1024
        let bl = UnsafeMutablePointer<Float>.allocate(capacity: block), br = UnsafeMutablePointer<Float>.allocate(capacity: block)
        var i = 0
        while i < n {
            let c = min(block, n - i)
            music.render(frames: c, bl, br)
            for k in 0..<c { L[i + k] = bl[k] * 0.8; R[i + k] = br[k] * 0.8 }
            i += c
        }
        bl.deallocate(); br.deallocate()
        // fade the music in and out
        for k in 0..<n {
            let t = Double(k) / sr
            let g = Float(min(1, t / 1.5) * min(1, (seconds - t) / 2.0))
            L[k] *= g; R[k] *= g
        }
        var lastAt: [String: Double] = [:]
        for (t, name, vol, rate) in events {
            if let la = lastAt[name], t - la < 0.12 { continue }
            lastAt[name] = t
            guard let b = audio.buffer(name), vol > 0.05 else { continue }
            let bL = b.floatChannelData![0], bR = b.floatChannelData![1]
            let start = Int(t * sr)
            let len = Int(Double(b.frameLength) / Double(max(0.25, rate)))
            for k in 0..<len {
                let o = start + k
                guard o < n else { break }
                let src = Int(Double(k) * Double(rate))
                guard src < Int(b.frameLength) else { break }
                L[o] += bL[src] * vol * 0.7; R[o] += bR[src] * vol * 0.7
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4)); data.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr) * 4); u16(4); u16(16)
        data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
        var pcm = [Int16](repeating: 0, count: n * 2)
        for k in 0..<n {
            pcm[k * 2] = Int16(max(-1, min(1, softClip(L[k]))) * 32000)
            pcm[k * 2 + 1] = Int16(max(-1, min(1, softClip(R[k]))) * 32000)
        }
        pcm.withUnsafeBufferPointer { data.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: n * 4)) }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
