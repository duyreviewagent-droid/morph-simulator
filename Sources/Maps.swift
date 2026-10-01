import SceneKit
import simd

/// One playable place. The farm is hand-built; the other nine are generated from these numbers.
struct MapDef {
    let name: String
    let blurb: String
    var zenith = V3(0.2, 0.4, 0.78), horizon = V3(0.82, 0.86, 0.88), fog = V3(0.78, 0.83, 0.86)
    var fogStart: Float = 70, fogEnd: Float = 520
    var sunColor = V3(1, 0.93, 0.82), sunIntensity: Float = 2400
    var sunDir = simd_normalize(V3(0.5, 0.62, 0.45))
    var clouds: Float = 1
    var grassLow = V3(0.1, 0.2, 0.035), grassHigh = V3(0.26, 0.36, 0.08)
    var grassCount = 40000
    var hills = V3(0.18, 0.26, 0.09)
    var waterLevel: Float? = nil
    var waterCol = V3(0.05, 0.09, 0.08)
    var natives: [String] = []
    var spawn = V3(2, 0, 7)
    var groundRough: CGFloat = 0.95
    var height: (Float, Float) -> Float = { _, _ in 0 }
    var color: (Float, Float) -> V3 = { _, _ in V3(0.2, 0.3, 0.1) }
    var grass: (Float, Float) -> Bool = { _, _ in true }
    var surface: (Float, Float) -> Surface = { _, _ in .grass }
}

enum Maps {
    static func fbm(_ x: Float, _ z: Float, _ f: Float, _ o: Int, _ s: Int32) -> Float { Noise.fbm(x * f, z * f, octaves: o, seed: s) }
    static func dist(_ x: Float, _ z: Float, _ cx: Float, _ cz: Float) -> Float { simd_length(SIMD2(x - cx, z - cz)) }
    static func edgeRise(_ x: Float, _ z: Float) -> Float { smoothstep(Farm.half * 0.75, Farm.half, max(abs(x), abs(z))) * 10 }

    static let all: [MapDef] = [
        MapDef(name: "Farm", blurb: "Barn, silo, coop, pasture and a very nervous farmer"),

        { () -> MapDef in
            var m = MapDef(name: "Savanna", blurb: "Golden grass, acacia trees and a busy watering hole")
            m.zenith = V3(0.3, 0.48, 0.8); m.horizon = V3(0.95, 0.85, 0.66); m.fog = V3(0.9, 0.82, 0.66)
            m.sunColor = V3(1, 0.85, 0.62); m.sunIntensity = 2700; m.sunDir = simd_normalize(V3(0.6, 0.45, 0.4))
            m.grassLow = V3(0.36, 0.28, 0.1); m.grassHigh = V3(0.72, 0.58, 0.28); m.hills = V3(0.5, 0.4, 0.2)
            m.waterLevel = -0.45; m.waterCol = V3(0.12, 0.11, 0.06)
            m.natives = ["Lion", "Zebra", "Giraffe", "Elephant", "Rhino", "Cheetah", "Meerkat", "Hippo", "Ostrich"]
            m.height = { x, z in fbm(x, z, 0.012, 4, 31) * 3 + edgeRise(x, z) - 1.8 * smoothstep(12, 3, dist(x, z, 22, 18)) }
            m.color = { x, z in
                let n = fbm(x, z, 0.05, 4, 32), d = smoothstep(0.1, 0.5, fbm(x, z, 0.02, 3, 33))
                var c = mix3(V3(0.55, 0.45, 0.22), V3(0.42, 0.36, 0.16), n * 0.5 + 0.5)
                c = mix3(c, V3(0.58, 0.36, 0.2), d * 0.45)
                return mix3(c, V3(0.3, 0.22, 0.14), smoothstep(14, 9, dist(x, z, 22, 18)))
            }
            m.grass = { x, z in dist(x, z, 22, 18) > 13 }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Arctic", blurb: "Snowfields, ice floes and a freezing lake")
            m.zenith = V3(0.35, 0.5, 0.75); m.horizon = V3(0.88, 0.92, 0.96); m.fog = V3(0.86, 0.9, 0.95)
            m.fogStart = 40; m.fogEnd = 380
            m.sunColor = V3(1, 0.96, 0.9); m.sunIntensity = 2100; m.sunDir = simd_normalize(V3(0.5, 0.3, 0.5))
            m.grassCount = 0; m.hills = V3(0.88, 0.9, 0.95)
            m.waterLevel = -0.6; m.waterCol = V3(0.04, 0.1, 0.14)
            m.natives = ["Polar Bear", "Penguin", "Seal", "Walrus", "Reindeer", "Wolf", "Orca"]
            m.groundRough = 0.7
            m.height = { x, z in fbm(x, z, 0.015, 4, 41) * 4 + edgeRise(x, z) * 2 - 3 * smoothstep(24, 10, dist(x, z, -28, -22)) }
            m.color = { x, z in
                let n = fbm(x, z, 0.08, 3, 42)
                let c = V3(0.86, 0.9, 0.95) * (0.92 + n * 0.08)
                return mix3(c, V3(0.62, 0.72, 0.8), smoothstep(22, 14, dist(x, z, -28, -22)) * 0.6)
            }
            m.grass = { _, _ in false }
            m.surface = { _, _ in .concrete }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Jungle", blurb: "Towering trees, hanging vines and a muddy river")
            m.zenith = V3(0.3, 0.45, 0.62); m.horizon = V3(0.7, 0.78, 0.72); m.fog = V3(0.55, 0.65, 0.55)
            m.fogStart = 20; m.fogEnd = 220
            m.sunColor = V3(1, 0.95, 0.8); m.sunIntensity = 1900
            m.grassLow = V3(0.04, 0.14, 0.03); m.grassHigh = V3(0.14, 0.32, 0.06); m.grassCount = 60000; m.hills = V3(0.08, 0.2, 0.05)
            m.waterLevel = -0.7; m.waterCol = V3(0.14, 0.12, 0.06)
            m.natives = ["Monkey", "Gorilla", "Chimpanzee", "Orangutan", "Toucan", "Parrot", "Tiger", "Sloth", "Frog", "Snake", "Chameleon", "Leopard"]
            m.spawn = V3(2, 0, -14)
            m.height = { x, z in
                let river = abs(z - sinf(x * 0.035) * 18 - 8)
                return fbm(x, z, 0.02, 4, 51) * 4 + edgeRise(x, z) - 2.2 * smoothstep(9, 3, river)
            }
            m.color = { x, z in
                let n = fbm(x, z, 0.06, 4, 52)
                let river = abs(z - sinf(x * 0.035) * 18 - 8)
                let c = mix3(V3(0.1, 0.18, 0.05), V3(0.22, 0.2, 0.1), smoothstep(-0.2, 0.4, n))
                return mix3(c, V3(0.25, 0.2, 0.12), smoothstep(10, 6, river))
            }
            m.grass = { x, z in abs(z - sinf(x * 0.035) * 18 - 8) > 8 }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Desert", blurb: "Rolling dunes, cactus and a palm oasis by the pyramid")
            m.zenith = V3(0.25, 0.45, 0.82); m.horizon = V3(0.95, 0.86, 0.72); m.fog = V3(0.93, 0.84, 0.7)
            m.sunColor = V3(1, 0.9, 0.74); m.sunIntensity = 3000; m.sunDir = simd_normalize(V3(0.3, 0.8, 0.3)); m.clouds = 0.2
            m.grassCount = 0; m.hills = V3(0.8, 0.62, 0.4)
            m.waterLevel = -0.4; m.waterCol = V3(0.05, 0.15, 0.15)
            m.natives = ["Camel", "Lizard", "Snake", "Cobra", "Spider", "Ostrich", "Komodo Dragon", "Meerkat"]
            m.groundRough = 0.9
            m.height = { x, z in
                let dune = Noise.ridged(x * 0.02 + z * 0.006, z * 0.012, octaves: 3, seed: 61) * 9 * smoothstep(25, 70, dist(x, z, 0, 0))
                return dune + fbm(x, z, 0.03, 3, 62) * 0.8 + edgeRise(x, z) - 1.6 * smoothstep(10, 4, dist(x, z, 30, -20))
            }
            m.color = { x, z in
                let n = fbm(x, z, 0.1, 3, 63)
                let c = V3(0.82, 0.66, 0.44) * (0.92 + n * 0.1)
                return mix3(c, V3(0.35, 0.3, 0.18), smoothstep(11, 7, dist(x, z, 30, -20)))
            }
            m.grass = { x, z in dist(x, z, 30, -20) < 14 && dist(x, z, 30, -20) > 7 }
            m.grassLow = V3(0.1, 0.22, 0.05); m.grassHigh = V3(0.3, 0.4, 0.1)
            m.surface = { x, z in dist(x, z, 30, -20) < 14 ? .grass : .dirt }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Beach", blurb: "Sand, palms, a pier and a whole ocean to swim in")
            m.zenith = V3(0.15, 0.42, 0.85); m.horizon = V3(0.78, 0.88, 0.95); m.fog = V3(0.75, 0.86, 0.94)
            m.sunIntensity = 2700
            m.grassLow = V3(0.2, 0.3, 0.08); m.grassHigh = V3(0.4, 0.45, 0.15); m.grassCount = 12000; m.hills = V3(0.3, 0.45, 0.2)
            m.waterLevel = 0; m.waterCol = V3(0.03, 0.18, 0.24)
            m.natives = ["Crab", "Seal", "Turtle", "Pelican", "Dolphin", "Shark", "Octopus", "Jellyfish", "Goldfish", "Lobster", "Whale"]
            m.spawn = V3(0, 0, -8)
            m.height = { x, z in
                let land = 1.4 + fbm(x, z, 0.02, 4, 71) * 2.5 + smoothstep(-20, -160, z) * 10
                let shore = 18 + sinf(x * 0.04) * 6
                return mixf(land, -7, smoothstep(shore - 8, shore + 26, z)) + edgeRise(x, min(z, 0))
            }
            m.color = { x, z in
                let shore = 18 + sinf(x * 0.04) * 6
                let n = fbm(x, z, 0.08, 3, 72)
                let sand = V3(0.86, 0.78, 0.6) * (0.93 + n * 0.08)
                let wet = V3(0.6, 0.52, 0.38)
                var c = mix3(V3(0.25, 0.35, 0.12), sand, smoothstep(-30, -18, z - shore + 20))
                c = mix3(c, wet, smoothstep(shore - 2, shore + 4, z))
                return c
            }
            m.grass = { x, z in z < 18 + sinf(x * 0.04) * 6 - 26 }
            m.surface = { x, z in z < 18 + sinf(x * 0.04) * 6 - 22 ? .grass : .dirt }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Forest", blurb: "Pines, oaks, mushrooms, a log cabin and a quiet pond")
            m.zenith = V3(0.25, 0.42, 0.7); m.horizon = V3(0.75, 0.8, 0.8); m.fog = V3(0.62, 0.7, 0.68)
            m.fogStart = 30; m.fogEnd = 300; m.sunIntensity = 2000
            m.grassLow = V3(0.07, 0.16, 0.04); m.grassHigh = V3(0.2, 0.3, 0.08); m.grassCount = 45000; m.hills = V3(0.1, 0.2, 0.07)
            m.waterLevel = -0.5
            m.natives = ["Deer", "Moose", "Bear", "Fox", "Wolf", "Raccoon", "Squirrel", "Owl", "Hedgehog", "Beaver", "Skunk", "Rabbit"]
            m.height = { x, z in fbm(x, z, 0.018, 4, 81) * 5 + edgeRise(x, z) - 2 * smoothstep(13, 5, dist(x, z, -20, 22)) }
            m.color = { x, z in
                let n = fbm(x, z, 0.05, 4, 82), leaf = smoothstep(0.1, 0.5, fbm(x, z, 0.15, 3, 83))
                var c = mix3(V3(0.14, 0.2, 0.06), V3(0.24, 0.26, 0.1), n * 0.5 + 0.5)
                c = mix3(c, V3(0.32, 0.2, 0.1), leaf * 0.4)
                return mix3(c, V3(0.22, 0.18, 0.12), smoothstep(14, 10, dist(x, z, -20, 22)))
            }
            m.grass = { x, z in dist(x, z, -20, 22) > 13 }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Mountains", blurb: "Alpine meadow ringed by snowy peaks, and a high lake")
            m.zenith = V3(0.12, 0.3, 0.75); m.horizon = V3(0.75, 0.84, 0.92); m.fog = V3(0.75, 0.82, 0.9)
            m.fogStart = 90; m.fogEnd = 700; m.sunIntensity = 2600
            m.grassLow = V3(0.1, 0.22, 0.05); m.grassHigh = V3(0.3, 0.4, 0.12); m.hills = V3(0.5, 0.5, 0.5)
            m.waterLevel = -0.8; m.waterCol = V3(0.03, 0.1, 0.16)
            m.natives = ["Goat", "Eagle", "Llama", "Alpaca", "Bear", "Bison", "Wolf", "Deer"]
            m.height = { x, z in
                let r = dist(x, z, 0, 0)
                let peaks = Noise.ridged(x * 0.012, z * 0.012, octaves: 5, seed: 91) * 55 * smoothstep(70, 210, r)
                return peaks + fbm(x, z, 0.03, 4, 92) * 2 - 3 * smoothstep(16, 6, dist(x, z, -10, -30))
            }
            m.color = { x, z in
                let r = dist(x, z, 0, 0)
                let h = Noise.ridged(x * 0.012, z * 0.012, octaves: 5, seed: 91) * 55 * smoothstep(70, 210, r)
                let n = fbm(x, z, 0.06, 3, 93)
                var c = mix3(V3(0.2, 0.3, 0.1), V3(0.3, 0.34, 0.14), n * 0.5 + 0.5)
                c = mix3(c, V3(0.4, 0.38, 0.35) * (0.9 + n * 0.2), smoothstep(4, 14, h))
                c = mix3(c, V3(0.92, 0.94, 0.97), smoothstep(26, 34, h + n * 4))
                return mix3(c, V3(0.3, 0.28, 0.22), smoothstep(15, 11, dist(x, z, -10, -30)))
            }
            m.grass = { x, z in
                let r = dist(x, z, 0, 0)
                return r < 120 && dist(x, z, -10, -30) > 14 && Noise.ridged(x * 0.012, z * 0.012, octaves: 5, seed: 91) * 55 * smoothstep(70, 210, r) < 5
            }
            m.surface = { x, z in dist(x, z, 0, 0) < 110 ? .grass : .concrete }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "Swamp", blurb: "Murky pools, dead trees, lily pads and a shack on stilts")
            m.zenith = V3(0.35, 0.42, 0.45); m.horizon = V3(0.6, 0.64, 0.56); m.fog = V3(0.45, 0.5, 0.42)
            m.fogStart = 10; m.fogEnd = 160; m.sunColor = V3(0.9, 0.9, 0.75); m.sunIntensity = 1500; m.clouds = 2
            m.grassLow = V3(0.1, 0.14, 0.04); m.grassHigh = V3(0.26, 0.28, 0.1); m.grassCount = 50000; m.hills = V3(0.15, 0.18, 0.1)
            m.waterLevel = 0; m.waterCol = V3(0.08, 0.1, 0.05)
            m.natives = ["Crocodile", "Frog", "Turtle", "Snake", "Axolotl", "Duck", "Flamingo", "Otter", "Beaver"]
            m.height = { x, z in fbm(x, z, 0.03, 4, 101) * 1.4 + 0.15 + edgeRise(x, z) + 0.8 * smoothstep(12, 4, dist(x, z, 0, 0)) }
            m.color = { x, z in
                let n = fbm(x, z, 0.08, 3, 102)
                return mix3(V3(0.18, 0.2, 0.08), V3(0.22, 0.18, 0.1), n * 0.5 + 0.5)
            }
            m.grass = { _, _ in true }
            return m
        }(),

        { () -> MapDef in
            var m = MapDef(name: "City Park", blurb: "Lawns, paths, a fountain and the city all around")
            m.fog = V3(0.75, 0.78, 0.82); m.fogStart = 80; m.fogEnd = 600
            m.grassLow = V3(0.1, 0.24, 0.05); m.grassHigh = V3(0.24, 0.4, 0.08); m.grassCount = 30000; m.hills = V3(0.35, 0.35, 0.38)
            m.waterLevel = -0.4
            m.natives = ["Pigeon", "Squirrel", "Dog", "Cat", "Rat", "Duck", "Goose", "Crow", "Raccoon", "Swan"]
            m.height = { x, z in -1.4 * smoothstep(12, 4, dist(x, z, 20, 14)) + 0.3 * sinf(x * 0.05) * cosf(z * 0.04) }
            m.color = { x, z in
                let n = fbm(x, z, 0.06, 3, 111)
                var c = mix3(V3(0.14, 0.28, 0.06), V3(0.2, 0.33, 0.08), n * 0.5 + 0.5)
                let path = min(abs(x - sinf(z * 0.05) * 6), abs(z + 20 + sinf(x * 0.04) * 5), abs(dist(x, z, 0, 0) - 14))
                c = mix3(c, V3(0.55, 0.52, 0.47), smoothstep(1.8, 1.3, path))
                c = mix3(c, V3(0.35, 0.34, 0.33), smoothstep(184, 188, max(abs(x), abs(z))))
                return mix3(c, V3(0.3, 0.26, 0.18), smoothstep(13, 10, dist(x, z, 20, 14)))
            }
            m.grass = { x, z in
                let path = min(abs(x - sinf(z * 0.05) * 6), abs(z + 20 + sinf(x * 0.04) * 5), abs(dist(x, z, 0, 0) - 14))
                return path > 2.2 && dist(x, z, 20, 14) > 12 && max(abs(x), abs(z)) < 180
            }
            m.surface = { x, z in
                let path = min(abs(x - sinf(z * 0.05) * 6), abs(z + 20 + sinf(x * 0.04) * 5), abs(dist(x, z, 0, 0) - 14))
                return path < 1.8 ? .concrete : .grass
            }
            m.spawn = V3(0, 0, -6)
            return m
        }(),
    ]
}
