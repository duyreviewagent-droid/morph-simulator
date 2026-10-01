import simd

enum Plan { case biped, bird, quad, sprawl, slither, fish, insect, spider, tentacle, hopper }
enum Coat: String { case cells, fur, spots, rosettes, patches, stripes, feathers, scales, skin, slick, shell, chitin, wool, quills, holstein, bands }
enum Ears { case none, round, pointy, long, floppy, big, tufts }
enum Horns { case none, short, ram, long, antlers, palmate, rhino, ossicones, wide }
enum Mouth { case snout, pig, beak, bill, hooked, bigBeak, needle, pouch, trunk, flat, fish, mandibles, croc, hippo }
enum Arms { case hands, paw, hoof, wing, batWing, fin, pincer, tentacles, insect, none }
enum Tail { case none, thin, tuft, bushy, long, curly, stub, reptile, horse, flat, fan, stinger, fluffy, curl }
enum Foot { case paw, hoof, foot, pad, webbed, talon, none }
enum BugWings { case none, clear, big, elytra, long }
enum Voice { case talk, cluck, moo, neigh, oink, baa, bleat, bray, bark, meow, roar, howl, yip, growl, squeak, hiss, quack, honk, gobble, hoot, caw, squawk, tweet, coo, trumpet, grunt, bellow, hoo, screech, chatter, ribbit, buzz, click, whale, blub, chirp, snort }
enum Eat { case fruit, peck, graze, bite }
enum Special { case none, spray, puff, ink, shell }

/// Everything needed to build and play an animal's head, body and legs.
struct SpeciesDef {
    var name: String
    var plan: Plan
    var size: Float = 1
    var coat: Coat = .fur
    var a = V3(0.45, 0.33, 0.22)        // main colour
    var b = V3(0.15, 0.1, 0.07)         // pattern colour
    var limbCol: V3? = nil              // bare legs/feet (birds, pink tails)
    var beakCol = V3(0.85, 0.65, 0.25)
    var noseCol = V3(0.08, 0.06, 0.06)
    // head
    var snout: Float = 0.3
    var headW: Float = 1
    var neck: Float = 0.2
    var ears: Ears = .pointy
    var horns: Horns = .none
    var mouth: Mouth = .snout
    var eyeFront = false
    var eyeSize: Float = 1
    var eyeCol = V3(0.05, 0.03, 0.02)
    var mane = false
    var whiskers = false
    var antennae = false
    var comb = false
    var tusks = false
    var hood = false
    // body
    var arms: Arms = .paw
    var girth: Float = 1
    var hump = false
    var shell = false
    var dorsal = false
    var spikes = false
    var bugWings: BugWings = .none
    var wingCol: V3? = nil
    var special: Special = .none
    // legs
    var legLen: Float = 1
    var legThick: Float = 1
    var foot: Foot = .paw
    var tail: Tail = .thin
    var bodyLen: Float = 1
    // behaviour
    var voice: Voice = .grunt
    var eat: Eat = .fruit
    var speed: Float = 1
    var jump: Float = 1
    var custom = false                  // human, chicken, cow have hand-built parts

    init(_ n: String, _ p: Plan, _ s: Float, _ c: Coat, _ a: V3, _ b: V3, _ f: (inout SpeciesDef) -> Void = { _ in }) {
        name = n; plan = p; size = s; coat = c; self.a = a; self.b = b
        switch p {
        case .bird: arms = .wing; foot = .talon; ears = .none; mouth = .beak; voice = .tweet; eat = .peck; tail = .fan; limbCol = V3(0.8, 0.6, 0.25)
        case .quad: foot = .paw; tail = .thin
        case .sprawl: foot = .paw; tail = .reptile; ears = .none; voice = .hiss; eat = .bite; limbCol = nil
        case .slither: arms = .none; ears = .none; tail = .none; voice = .hiss; eat = .bite
        case .fish: arms = .fin; ears = .none; tail = .none; mouth = .fish; voice = .blub; eat = .bite
        case .insect, .spider: arms = .insect; ears = .none; mouth = .mandibles; tail = .none; voice = .chirp; antennae = p == .insect; eat = .fruit
        case .tentacle: arms = .tentacles; ears = .none; mouth = .fish; tail = .none; voice = .blub; eat = .bite
        case .biped: arms = .hands; foot = .foot; eyeFront = true; mouth = .flat
        case .hopper: foot = .foot; tail = .stub
        }
        f(&self)
    }
}

enum Zoo {
    static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { V3(r, g, b) }

    static let defs: [SpeciesDef] = [
        // the three originals
        SpeciesDef("Human", .biped, 1, .skin, c(0.7, 0.5, 0.42), c(0.1, 0.1, 0.1)) { $0.custom = true; $0.voice = .talk; $0.eat = .fruit },
        SpeciesDef("Chicken", .bird, 1, .feathers, c(0.42, 0.16, 0.06), c(0.2, 0.06, 0.02)) { $0.custom = true; $0.voice = .cluck; $0.comb = true },
        SpeciesDef("Cow", .quad, 1, .holstein, c(0.82, 0.79, 0.74), c(0.03, 0.03, 0.03)) { $0.custom = true; $0.voice = .moo; $0.eat = .graze; $0.foot = .hoof; $0.arms = .hoof; $0.speed = 1.2 },

        // farm and pets
        SpeciesDef("Pig", .quad, 0.85, .skin, c(0.88, 0.62, 0.58), c(0.7, 0.45, 0.42)) { $0.mouth = .pig; $0.ears = .floppy; $0.tail = .curly; $0.foot = .hoof; $0.arms = .hoof; $0.voice = .oink; $0.eat = .graze; $0.snout = 0.28; $0.girth = 1.2; $0.legLen = 0.6; $0.noseCol = c(0.8, 0.5, 0.5) },
        SpeciesDef("Horse", .quad, 1.1, .fur, c(0.4, 0.24, 0.12), c(0.08, 0.05, 0.03)) { $0.snout = 0.55; $0.neck = 0.55; $0.mane = true; $0.tail = .horse; $0.foot = .hoof; $0.arms = .hoof; $0.voice = .neigh; $0.eat = .graze; $0.speed = 1.45; $0.legLen = 1.25; $0.jump = 1.3 },
        SpeciesDef("Sheep", .quad, 0.8, .wool, c(0.88, 0.86, 0.8), c(0.1, 0.09, 0.08)) { $0.snout = 0.28; $0.ears = .floppy; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .baa; $0.eat = .graze; $0.girth = 1.25; $0.legLen = 0.75 },
        SpeciesDef("Goat", .quad, 0.8, .fur, c(0.85, 0.82, 0.75), c(0.4, 0.3, 0.2)) { $0.snout = 0.32; $0.horns = .ram; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bleat; $0.eat = .graze; $0.jump = 1.9 },
        SpeciesDef("Donkey", .quad, 0.95, .fur, c(0.5, 0.47, 0.45), c(0.2, 0.18, 0.17)) { $0.snout = 0.45; $0.ears = .long; $0.mane = true; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .bray; $0.eat = .graze },
        SpeciesDef("Duck", .bird, 0.7, .feathers, c(0.45, 0.35, 0.25), c(0.1, 0.35, 0.15)) { $0.mouth = .bill; $0.beakCol = c(0.95, 0.65, 0.1); $0.limbCol = c(0.95, 0.55, 0.1); $0.foot = .webbed; $0.voice = .quack; $0.legLen = 0.55; $0.tail = .stub },
        SpeciesDef("Goose", .bird, 0.85, .feathers, c(0.9, 0.9, 0.88), c(0.75, 0.75, 0.72)) { $0.mouth = .bill; $0.beakCol = c(0.95, 0.55, 0.1); $0.limbCol = c(0.95, 0.55, 0.1); $0.foot = .webbed; $0.voice = .honk; $0.neck = 0.55; $0.legLen = 0.6; $0.tail = .stub },
        SpeciesDef("Turkey", .bird, 1.0, .feathers, c(0.25, 0.18, 0.12), c(0.05, 0.12, 0.08)) { $0.comb = true; $0.voice = .gobble; $0.tail = .fan; $0.limbCol = c(0.7, 0.55, 0.5) },
        SpeciesDef("Dog", .quad, 0.75, .fur, c(0.78, 0.55, 0.28), c(0.5, 0.3, 0.12)) { $0.snout = 0.34; $0.ears = .floppy; $0.tail = .bushy; $0.voice = .bark; $0.eat = .bite; $0.speed = 1.3 },
        SpeciesDef("Cat", .quad, 0.6, .stripes, c(0.85, 0.5, 0.2), c(0.5, 0.25, 0.08)) { $0.snout = 0.16; $0.whiskers = true; $0.tail = .long; $0.voice = .meow; $0.eat = .bite; $0.jump = 1.7; $0.eyeCol = c(0.5, 0.6, 0.1); $0.noseCol = c(0.8, 0.45, 0.45) },
        SpeciesDef("Rabbit", .hopper, 0.6, .fur, c(0.55, 0.47, 0.38), c(0.9, 0.88, 0.85)) { $0.snout = 0.14; $0.ears = .long; $0.tail = .fluffy; $0.voice = .squeak; $0.eat = .graze; $0.jump = 1.5; $0.whiskers = true; $0.noseCol = c(0.8, 0.5, 0.5) },
        SpeciesDef("Mouse", .quad, 0.45, .fur, c(0.55, 0.52, 0.5), c(0.8, 0.6, 0.6)) { $0.snout = 0.2; $0.ears = .round; $0.tail = .long; $0.limbCol = c(0.85, 0.6, 0.6); $0.voice = .squeak; $0.whiskers = true; $0.eyeSize = 1.3; $0.noseCol = c(0.85, 0.5, 0.5) },
        SpeciesDef("Rat", .quad, 0.5, .fur, c(0.32, 0.3, 0.28), c(0.6, 0.45, 0.45)) { $0.snout = 0.26; $0.ears = .round; $0.tail = .long; $0.limbCol = c(0.8, 0.6, 0.58); $0.voice = .squeak; $0.whiskers = true },
        SpeciesDef("Hamster", .quad, 0.45, .patches, c(0.85, 0.6, 0.3), c(0.95, 0.92, 0.88)) { $0.snout = 0.1; $0.ears = .round; $0.tail = .stub; $0.voice = .squeak; $0.girth = 1.4; $0.legLen = 0.4; $0.eyeSize = 1.3 },
        SpeciesDef("Guinea Pig", .quad, 0.5, .patches, c(0.95, 0.92, 0.88), c(0.55, 0.3, 0.1)) { $0.snout = 0.14; $0.ears = .round; $0.tail = .none; $0.voice = .squeak; $0.girth = 1.3; $0.legLen = 0.35; $0.eat = .graze },
        SpeciesDef("Llama", .quad, 1.0, .wool, c(0.88, 0.82, 0.7), c(0.5, 0.4, 0.3)) { $0.snout = 0.3; $0.neck = 0.9; $0.ears = .long; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bleat; $0.eat = .graze; $0.legLen = 1.1 },
        SpeciesDef("Alpaca", .quad, 0.85, .wool, c(0.55, 0.4, 0.28), c(0.3, 0.2, 0.12)) { $0.snout = 0.24; $0.neck = 0.65; $0.ears = .pointy; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bleat; $0.eat = .graze },
        SpeciesDef("Water Buffalo", .quad, 1.15, .skin, c(0.18, 0.17, 0.17), c(0.1, 0.1, 0.1)) { $0.snout = 0.4; $0.horns = .wide; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .moo; $0.eat = .graze; $0.girth = 1.2 },
        SpeciesDef("Parrot", .bird, 0.6, .feathers, c(0.1, 0.6, 0.15), c(0.85, 0.1, 0.05)) { $0.mouth = .hooked; $0.beakCol = c(0.2, 0.2, 0.2); $0.limbCol = c(0.4, 0.4, 0.4); $0.voice = .squawk; $0.eat = .fruit; $0.eyeCol = c(0.9, 0.9, 0.9); $0.tail = .long },
        SpeciesDef("Pigeon", .bird, 0.55, .feathers, c(0.5, 0.52, 0.56), c(0.25, 0.4, 0.35)) { $0.voice = .coo; $0.limbCol = c(0.8, 0.35, 0.35); $0.beakCol = c(0.3, 0.3, 0.3); $0.tail = .stub },

        // wild mammals
        SpeciesDef("Lion", .quad, 1.05, .fur, c(0.78, 0.6, 0.35), c(0.45, 0.28, 0.12)) { $0.snout = 0.28; $0.mane = true; $0.ears = .round; $0.tail = .tuft; $0.voice = .roar; $0.eat = .bite; $0.speed = 1.4; $0.whiskers = true; $0.eyeCol = c(0.6, 0.45, 0.1) },
        SpeciesDef("Tiger", .quad, 1.05, .stripes, c(0.9, 0.5, 0.15), c(0.05, 0.03, 0.02)) { $0.snout = 0.28; $0.ears = .round; $0.tail = .long; $0.voice = .roar; $0.eat = .bite; $0.speed = 1.4; $0.whiskers = true; $0.eyeCol = c(0.6, 0.5, 0.1) },
        SpeciesDef("Leopard", .quad, 0.85, .rosettes, c(0.85, 0.65, 0.35), c(0.08, 0.06, 0.04)) { $0.snout = 0.24; $0.ears = .round; $0.tail = .long; $0.voice = .growl; $0.eat = .bite; $0.speed = 1.5; $0.jump = 1.6; $0.whiskers = true },
        SpeciesDef("Cheetah", .quad, 0.85, .spots, c(0.88, 0.72, 0.42), c(0.05, 0.04, 0.03)) { $0.snout = 0.22; $0.ears = .round; $0.tail = .long; $0.voice = .chirp; $0.eat = .bite; $0.speed = 2.0; $0.legLen = 1.2; $0.girth = 0.8 },
        SpeciesDef("Wolf", .quad, 0.9, .fur, c(0.5, 0.48, 0.45), c(0.85, 0.83, 0.8)) { $0.snout = 0.4; $0.tail = .bushy; $0.voice = .howl; $0.eat = .bite; $0.speed = 1.5; $0.eyeCol = c(0.7, 0.6, 0.1) },
        SpeciesDef("Fox", .quad, 0.65, .fur, c(0.85, 0.4, 0.12), c(0.95, 0.92, 0.88)) { $0.snout = 0.36; $0.tail = .bushy; $0.voice = .yip; $0.eat = .bite; $0.speed = 1.3; $0.legLen = 0.8 },
        SpeciesDef("Bear", .quad, 1.3, .fur, c(0.3, 0.18, 0.1), c(0.18, 0.1, 0.05)) { $0.snout = 0.32; $0.ears = .round; $0.tail = .stub; $0.voice = .roar; $0.eat = .fruit; $0.girth = 1.3; $0.speed = 1.1 },
        SpeciesDef("Polar Bear", .quad, 1.35, .fur, c(0.92, 0.9, 0.84), c(0.8, 0.78, 0.7)) { $0.snout = 0.38; $0.ears = .round; $0.tail = .stub; $0.voice = .growl; $0.eat = .bite; $0.girth = 1.25 },
        SpeciesDef("Panda", .quad, 1.1, .patches, c(0.93, 0.92, 0.9), c(0.04, 0.04, 0.04)) { $0.snout = 0.2; $0.ears = .round; $0.tail = .stub; $0.voice = .grunt; $0.eat = .graze; $0.girth = 1.35; $0.speed = 0.8 },
        SpeciesDef("Raccoon", .quad, 0.6, .fur, c(0.45, 0.43, 0.4), c(0.1, 0.1, 0.1)) { $0.snout = 0.2; $0.arms = .hands; $0.tail = .bushy; $0.voice = .chatter; $0.eat = .fruit; $0.whiskers = true },
        SpeciesDef("Deer", .quad, 0.95, .fur, c(0.6, 0.4, 0.22), c(0.9, 0.88, 0.82)) { $0.snout = 0.34; $0.horns = .antlers; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bleat; $0.eat = .graze; $0.speed = 1.5; $0.jump = 1.8; $0.legLen = 1.2; $0.girth = 0.85 },
        SpeciesDef("Moose", .quad, 1.4, .fur, c(0.25, 0.17, 0.1), c(0.15, 0.1, 0.06)) { $0.snout = 0.5; $0.horns = .palmate; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bellow; $0.eat = .graze; $0.legLen = 1.3 },
        SpeciesDef("Reindeer", .quad, 1.0, .fur, c(0.5, 0.42, 0.35), c(0.9, 0.88, 0.85)) { $0.snout = 0.36; $0.horns = .antlers; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .stub; $0.voice = .grunt; $0.eat = .graze; $0.noseCol = c(0.8, 0.1, 0.1) },
        SpeciesDef("Camel", .quad, 1.3, .fur, c(0.78, 0.62, 0.4), c(0.6, 0.45, 0.28)) { $0.snout = 0.4; $0.neck = 0.8; $0.hump = true; $0.ears = .round; $0.foot = .pad; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .grunt; $0.eat = .graze; $0.legLen = 1.35 },
        SpeciesDef("Giraffe", .quad, 1.3, .cells, c(0.95, 0.85, 0.6), c(0.6, 0.35, 0.12)) { $0.snout = 0.45; $0.neck = 1.9; $0.horns = .ossicones; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .snort; $0.eat = .graze; $0.legLen = 1.6; $0.girth = 0.9 },
        SpeciesDef("Zebra", .quad, 1.0, .stripes, c(0.93, 0.92, 0.9), c(0.03, 0.03, 0.03)) { $0.snout = 0.5; $0.neck = 0.45; $0.mane = true; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .neigh; $0.eat = .graze; $0.speed = 1.45 },
        SpeciesDef("Elephant", .quad, 1.6, .skin, c(0.45, 0.43, 0.42), c(0.3, 0.29, 0.28)) { $0.mouth = .trunk; $0.ears = .big; $0.tusks = true; $0.foot = .pad; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .trumpet; $0.eat = .graze; $0.girth = 1.3; $0.speed = 0.85; $0.snout = 0.25 },
        SpeciesDef("Rhino", .quad, 1.4, .skin, c(0.5, 0.48, 0.45), c(0.35, 0.33, 0.3)) { $0.snout = 0.45; $0.horns = .rhino; $0.ears = .pointy; $0.foot = .pad; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .snort; $0.eat = .graze; $0.girth = 1.35; $0.legLen = 0.8 },
        SpeciesDef("Hippo", .quad, 1.45, .skin, c(0.5, 0.4, 0.42), c(0.8, 0.5, 0.5)) { $0.mouth = .hippo; $0.snout = 0.4; $0.ears = .round; $0.foot = .pad; $0.arms = .hoof; $0.tail = .stub; $0.voice = .bellow; $0.eat = .graze; $0.girth = 1.6; $0.legLen = 0.55 },
        SpeciesDef("Gorilla", .biped, 1.2, .fur, c(0.1, 0.1, 0.1), c(0.3, 0.3, 0.3)) { $0.ears = .round; $0.voice = .hoo; $0.girth = 1.5; $0.legThick = 1.3; $0.limbCol = c(0.15, 0.13, 0.12) },
        SpeciesDef("Chimpanzee", .biped, 0.85, .fur, c(0.12, 0.1, 0.09), c(0.4, 0.3, 0.25)) { $0.ears = .round; $0.voice = .hoo; $0.limbCol = c(0.5, 0.4, 0.35); $0.jump = 1.3 },
        SpeciesDef("Monkey", .biped, 0.6, .fur, c(0.45, 0.32, 0.2), c(0.8, 0.65, 0.5)) { $0.ears = .round; $0.tail = .long; $0.voice = .screech; $0.jump = 1.5; $0.limbCol = c(0.8, 0.6, 0.5) },
        SpeciesDef("Orangutan", .biped, 1.0, .fur, c(0.7, 0.3, 0.1), c(0.4, 0.15, 0.05)) { $0.ears = .none; $0.voice = .hoo; $0.girth = 1.3; $0.limbCol = c(0.35, 0.25, 0.2) },
        SpeciesDef("Kangaroo", .hopper, 1.0, .fur, c(0.7, 0.45, 0.28), c(0.9, 0.8, 0.65)) { $0.snout = 0.3; $0.ears = .long; $0.tail = .reptile; $0.arms = .paw; $0.voice = .grunt; $0.eat = .graze; $0.jump = 1.7; $0.speed = 1.4 },
        SpeciesDef("Koala", .biped, 0.6, .fur, c(0.6, 0.6, 0.6), c(0.9, 0.9, 0.88)) { $0.ears = .tufts; $0.mouth = .snout; $0.snout = 0.1; $0.noseCol = c(0.1, 0.1, 0.1); $0.voice = .grunt; $0.eat = .graze; $0.girth = 1.3; $0.speed = 0.6; $0.eyeFront = true },
        SpeciesDef("Sloth", .biped, 0.75, .fur, c(0.5, 0.45, 0.35), c(0.2, 0.15, 0.1)) { $0.ears = .none; $0.voice = .squeak; $0.speed = 0.3; $0.jump = 0.5 },
        SpeciesDef("Bat", .biped, 0.5, .fur, c(0.2, 0.15, 0.12), c(0.1, 0.08, 0.07)) { $0.arms = .batWing; $0.ears = .big; $0.mouth = .snout; $0.snout = 0.1; $0.voice = .screech; $0.eat = .fruit; $0.wingCol = c(0.12, 0.09, 0.08) },
        SpeciesDef("Hedgehog", .quad, 0.45, .quills, c(0.35, 0.28, 0.2), c(0.85, 0.8, 0.7)) { $0.snout = 0.2; $0.ears = .round; $0.spikes = true; $0.tail = .none; $0.voice = .squeak; $0.eat = .bite; $0.legLen = 0.35; $0.girth = 1.3 },
        SpeciesDef("Skunk", .quad, 0.55, .patches, c(0.05, 0.05, 0.05), c(0.95, 0.95, 0.93)) { $0.snout = 0.2; $0.ears = .round; $0.tail = .bushy; $0.voice = .chatter; $0.special = .spray; $0.legLen = 0.55 },
        SpeciesDef("Squirrel", .quad, 0.45, .fur, c(0.6, 0.35, 0.18), c(0.9, 0.85, 0.75)) { $0.snout = 0.16; $0.ears = .tufts; $0.tail = .bushy; $0.arms = .hands; $0.voice = .chatter; $0.jump = 1.6 },
        SpeciesDef("Beaver", .quad, 0.7, .fur, c(0.35, 0.22, 0.12), c(0.2, 0.15, 0.1)) { $0.snout = 0.18; $0.ears = .round; $0.tail = .flat; $0.voice = .grunt; $0.girth = 1.3; $0.legLen = 0.45 },
        SpeciesDef("Otter", .quad, 0.65, .fur, c(0.35, 0.24, 0.15), c(0.7, 0.6, 0.5)) { $0.snout = 0.16; $0.ears = .round; $0.tail = .reptile; $0.voice = .chirp; $0.eat = .bite; $0.whiskers = true; $0.bodyLen = 1.3; $0.legLen = 0.45 },
        SpeciesDef("Bison", .quad, 1.4, .fur, c(0.28, 0.18, 0.1), c(0.15, 0.1, 0.05)) { $0.snout = 0.35; $0.horns = .short; $0.hump = true; $0.mane = true; $0.foot = .hoof; $0.arms = .hoof; $0.tail = .tuft; $0.voice = .bellow; $0.eat = .graze },
        SpeciesDef("Meerkat", .biped, 0.5, .fur, c(0.72, 0.6, 0.45), c(0.3, 0.22, 0.15)) { $0.snout = 0.2; $0.mouth = .snout; $0.ears = .round; $0.tail = .long; $0.voice = .chirp; $0.eyeFront = true },
        SpeciesDef("Anteater", .quad, 1.0, .fur, c(0.35, 0.3, 0.25), c(0.9, 0.88, 0.8)) { $0.snout = 0.7; $0.mouth = .needle; $0.ears = .round; $0.tail = .bushy; $0.voice = .snort; $0.eat = .bite },
        SpeciesDef("Armadillo", .quad, 0.55, .shell, c(0.6, 0.52, 0.45), c(0.4, 0.34, 0.3)) { $0.snout = 0.25; $0.ears = .pointy; $0.shell = true; $0.tail = .reptile; $0.voice = .squeak; $0.legLen = 0.4 },
        SpeciesDef("Seal", .fish, 0.95, .slick, c(0.45, 0.45, 0.47), c(0.3, 0.3, 0.32)) { $0.mouth = .snout; $0.snout = 0.16; $0.whiskers = true; $0.voice = .bark; $0.eyeSize = 1.5 },
        SpeciesDef("Walrus", .fish, 1.3, .skin, c(0.55, 0.38, 0.3), c(0.4, 0.28, 0.2)) { $0.mouth = .snout; $0.snout = 0.2; $0.whiskers = true; $0.tusks = true; $0.voice = .bellow; $0.girth = 1.3 },

        // birds
        SpeciesDef("Ostrich", .bird, 1.2, .feathers, c(0.1, 0.09, 0.08), c(0.9, 0.88, 0.85)) { $0.neck = 1.0; $0.legLen = 2.1; $0.limbCol = c(0.8, 0.6, 0.55); $0.voice = .grunt; $0.speed = 2.0; $0.tail = .fluffy; $0.mouth = .beak },
        SpeciesDef("Penguin", .bird, 0.85, .slick, c(0.06, 0.06, 0.07), c(0.95, 0.95, 0.93)) { $0.arms = .fin; $0.legLen = 0.25; $0.limbCol = c(0.9, 0.5, 0.1); $0.beakCol = c(0.15, 0.15, 0.15); $0.voice = .squawk; $0.foot = .webbed; $0.tail = .stub; $0.speed = 0.6 },
        SpeciesDef("Owl", .bird, 0.7, .feathers, c(0.5, 0.38, 0.25), c(0.9, 0.85, 0.75)) { $0.eyeFront = true; $0.eyeSize = 2.2; $0.eyeCol = c(0.95, 0.7, 0.1); $0.ears = .tufts; $0.mouth = .hooked; $0.beakCol = c(0.3, 0.3, 0.3); $0.voice = .hoot; $0.eat = .bite; $0.tail = .stub },
        SpeciesDef("Eagle", .bird, 0.9, .feathers, c(0.3, 0.2, 0.12), c(0.95, 0.95, 0.92)) { $0.mouth = .hooked; $0.beakCol = c(0.95, 0.75, 0.1); $0.limbCol = c(0.95, 0.75, 0.1); $0.voice = .screech; $0.eat = .bite; $0.eyeCol = c(0.9, 0.7, 0.1) },
        SpeciesDef("Flamingo", .bird, 0.9, .feathers, c(0.95, 0.5, 0.55), c(0.9, 0.35, 0.4)) { $0.neck = 0.9; $0.legLen = 2.0; $0.limbCol = c(0.9, 0.45, 0.5); $0.mouth = .hooked; $0.beakCol = c(0.15, 0.12, 0.12); $0.voice = .honk; $0.foot = .webbed; $0.tail = .stub },
        SpeciesDef("Peacock", .bird, 0.9, .feathers, c(0.05, 0.25, 0.6), c(0.1, 0.5, 0.35)) { $0.comb = false; $0.voice = .screech; $0.tail = .fan; $0.limbCol = c(0.6, 0.55, 0.5) },
        SpeciesDef("Crow", .bird, 0.55, .feathers, c(0.04, 0.04, 0.05), c(0.08, 0.08, 0.15)) { $0.beakCol = c(0.05, 0.05, 0.05); $0.limbCol = c(0.08, 0.08, 0.08); $0.voice = .caw; $0.tail = .stub },
        SpeciesDef("Swan", .bird, 1.0, .feathers, c(0.95, 0.95, 0.94), c(0.85, 0.85, 0.83)) { $0.mouth = .bill; $0.beakCol = c(0.95, 0.4, 0.1); $0.neck = 0.8; $0.legLen = 0.5; $0.limbCol = c(0.1, 0.1, 0.1); $0.foot = .webbed; $0.voice = .honk; $0.tail = .stub },
        SpeciesDef("Toucan", .bird, 0.6, .feathers, c(0.04, 0.04, 0.04), c(0.95, 0.9, 0.5)) { $0.mouth = .bigBeak; $0.beakCol = c(0.98, 0.55, 0.05); $0.limbCol = c(0.3, 0.4, 0.8); $0.voice = .squawk; $0.eat = .fruit; $0.tail = .stub },
        SpeciesDef("Hummingbird", .bird, 0.4, .feathers, c(0.1, 0.55, 0.3), c(0.8, 0.1, 0.3)) { $0.mouth = .needle; $0.beakCol = c(0.1, 0.1, 0.1); $0.limbCol = c(0.1, 0.1, 0.1); $0.voice = .tweet; $0.eat = .fruit; $0.bugWings = .clear; $0.tail = .stub },
        SpeciesDef("Pelican", .bird, 1.0, .feathers, c(0.92, 0.92, 0.9), c(0.6, 0.6, 0.6)) { $0.mouth = .pouch; $0.beakCol = c(0.95, 0.75, 0.3); $0.neck = 0.6; $0.legLen = 0.6; $0.limbCol = c(0.4, 0.4, 0.4); $0.foot = .webbed; $0.voice = .grunt; $0.eat = .bite; $0.tail = .stub },
        SpeciesDef("Emu", .bird, 1.15, .feathers, c(0.35, 0.28, 0.2), c(0.2, 0.15, 0.1)) { $0.neck = 0.9; $0.legLen = 1.9; $0.limbCol = c(0.4, 0.4, 0.4); $0.voice = .grunt; $0.speed = 1.7; $0.tail = .fluffy },

        // reptiles and amphibians
        SpeciesDef("Crocodile", .sprawl, 1.25, .scales, c(0.25, 0.3, 0.15), c(0.15, 0.18, 0.08)) { $0.mouth = .croc; $0.snout = 0.7; $0.voice = .hiss; $0.bodyLen = 1.6; $0.legLen = 0.8; $0.eyeCol = c(0.7, 0.6, 0.1) },
        SpeciesDef("Lizard", .sprawl, 0.5, .scales, c(0.35, 0.55, 0.2), c(0.2, 0.35, 0.1)) { $0.snout = 0.25; $0.voice = .hiss; $0.speed = 1.3 },
        SpeciesDef("Iguana", .sprawl, 0.75, .scales, c(0.3, 0.55, 0.3), c(0.2, 0.35, 0.2)) { $0.snout = 0.25; $0.dorsal = true; $0.voice = .hiss; $0.eat = .graze },
        SpeciesDef("Chameleon", .sprawl, 0.55, .scales, c(0.4, 0.7, 0.25), c(0.9, 0.7, 0.2)) { $0.snout = 0.2; $0.tail = .curl; $0.eyeSize = 1.8; $0.voice = .hiss; $0.eat = .bite; $0.speed = 0.5 },
        SpeciesDef("Turtle", .sprawl, 0.7, .scales, c(0.35, 0.42, 0.22), c(0.25, 0.3, 0.15)) { $0.snout = 0.15; $0.shell = true; $0.tail = .stub; $0.arms = .fin; $0.foot = .webbed; $0.voice = .hiss; $0.eat = .graze; $0.speed = 0.5; $0.special = .shell },
        SpeciesDef("Tortoise", .sprawl, 0.85, .scales, c(0.45, 0.4, 0.3), c(0.3, 0.25, 0.15)) { $0.snout = 0.15; $0.shell = true; $0.tail = .stub; $0.foot = .pad; $0.voice = .hiss; $0.eat = .graze; $0.speed = 0.3; $0.special = .shell },
        SpeciesDef("Snake", .slither, 0.8, .scales, c(0.3, 0.45, 0.15), c(0.1, 0.15, 0.05)) { $0.snout = 0.2; $0.bodyLen = 2.0; $0.eyeCol = c(0.8, 0.7, 0.1) },
        SpeciesDef("Cobra", .slither, 0.9, .scales, c(0.55, 0.45, 0.25), c(0.2, 0.15, 0.08)) { $0.snout = 0.18; $0.hood = true; $0.bodyLen = 2.2 },
        SpeciesDef("Frog", .hopper, 0.5, .slick, c(0.3, 0.6, 0.2), c(0.1, 0.3, 0.05)) { $0.mouth = .fish; $0.snout = 0.1; $0.ears = .none; $0.eyeSize = 1.9; $0.eyeCol = c(0.8, 0.7, 0.1); $0.tail = .none; $0.foot = .webbed; $0.arms = .paw; $0.voice = .ribbit; $0.eat = .bite; $0.jump = 1.9 },
        SpeciesDef("Komodo Dragon", .sprawl, 1.2, .scales, c(0.4, 0.36, 0.3), c(0.3, 0.26, 0.2)) { $0.snout = 0.35; $0.voice = .hiss; $0.bodyLen = 1.4 },
        SpeciesDef("Axolotl", .sprawl, 0.5, .slick, c(0.95, 0.65, 0.7), c(0.9, 0.3, 0.45)) { $0.snout = 0.1; $0.mouth = .fish; $0.mane = true; $0.voice = .squeak; $0.eat = .bite },

        // sea life
        SpeciesDef("Goldfish", .fish, 0.5, .scales, c(0.98, 0.5, 0.1), c(0.95, 0.75, 0.3)) { $0.eyeSize = 1.6 },
        SpeciesDef("Shark", .fish, 1.3, .slick, c(0.45, 0.5, 0.55), c(0.9, 0.9, 0.9)) { $0.dorsal = true; $0.mouth = .croc; $0.snout = 0.4; $0.voice = .blub; $0.eyeCol = c(0.02, 0.02, 0.02) },
        SpeciesDef("Dolphin", .fish, 1.1, .slick, c(0.5, 0.55, 0.6), c(0.85, 0.87, 0.9)) { $0.dorsal = true; $0.mouth = .snout; $0.snout = 0.3; $0.voice = .click; $0.tail = .flat },
        SpeciesDef("Orca", .fish, 1.4, .patches, c(0.04, 0.04, 0.05), c(0.95, 0.95, 0.95)) { $0.dorsal = true; $0.mouth = .snout; $0.snout = 0.15; $0.voice = .whale; $0.tail = .flat },
        SpeciesDef("Whale", .fish, 1.7, .slick, c(0.25, 0.32, 0.42), c(0.6, 0.62, 0.65)) { $0.mouth = .fish; $0.snout = 0.2; $0.voice = .whale; $0.tail = .flat; $0.girth = 1.3; $0.eyeSize = 0.7 },
        SpeciesDef("Octopus", .tentacle, 0.8, .slick, c(0.8, 0.3, 0.2), c(0.6, 0.2, 0.15)) { $0.eyeSize = 1.5; $0.special = .ink; $0.eyeCol = c(0.9, 0.7, 0.1) },
        SpeciesDef("Crab", .spider, 0.6, .chitin, c(0.8, 0.25, 0.12), c(0.95, 0.6, 0.4)) { $0.arms = .pincer; $0.eyeSize = 1.2; $0.voice = .click; $0.antennae = false; $0.eat = .bite },
        SpeciesDef("Lobster", .insect, 0.7, .chitin, c(0.7, 0.12, 0.08), c(0.45, 0.08, 0.05)) { $0.arms = .pincer; $0.voice = .click; $0.bodyLen = 1.5; $0.eat = .bite },
        SpeciesDef("Pufferfish", .fish, 0.55, .spots, c(0.9, 0.82, 0.45), c(0.3, 0.25, 0.12)) { $0.spikes = true; $0.eyeSize = 1.6; $0.special = .puff; $0.girth = 1.4 },
        SpeciesDef("Jellyfish", .tentacle, 0.7, .slick, c(0.95, 0.6, 0.85), c(0.8, 0.4, 0.7)) { $0.eyeSize = 0; $0.voice = .blub },

        // bugs
        SpeciesDef("Bee", .insect, 0.5, .bands, c(0.95, 0.72, 0.1), c(0.05, 0.04, 0.03)) { $0.bugWings = .clear; $0.voice = .buzz; $0.eyeSize = 1.6; $0.tail = .stinger },
        SpeciesDef("Ant", .insect, 0.45, .chitin, c(0.35, 0.08, 0.05), c(0.15, 0.04, 0.03)) { $0.voice = .chirp; $0.eat = .bite },
        SpeciesDef("Butterfly", .insect, 0.45, .chitin, c(0.1, 0.08, 0.07), c(0.95, 0.5, 0.05)) { $0.bugWings = .big; $0.wingCol = c(0.95, 0.5, 0.05); $0.voice = .buzz; $0.eyeSize = 1.3 },
        SpeciesDef("Ladybug", .insect, 0.45, .spots, c(0.85, 0.08, 0.05), c(0.03, 0.03, 0.03)) { $0.bugWings = .elytra; $0.voice = .buzz; $0.girth = 1.4 },
        SpeciesDef("Spider", .spider, 0.55, .fur, c(0.12, 0.1, 0.08), c(0.3, 0.2, 0.1)) { $0.eyeSize = 1.2; $0.voice = .hiss; $0.eat = .bite; $0.antennae = false },
        SpeciesDef("Snail", .slither, 0.45, .slick, c(0.6, 0.55, 0.45), c(0.55, 0.35, 0.18)) { $0.shell = true; $0.antennae = true; $0.snout = 0.08; $0.voice = .squeak; $0.eat = .graze; $0.speed = 0.25; $0.bodyLen = 0.8 },
    ]
}

struct Species: Hashable {
    let id: Int
    static let human = Species(id: 0), chicken = Species(id: 1), cow = Species(id: 2)
    static let count = Zoo.defs.count
    static var all: [Species] { (0..<count).map { Species(id: $0) } }
    var def: SpeciesDef { Zoo.defs[id] }
    var name: String { def.name }
    var next: Species { Species(id: (id + 1) % Species.count) }
    var prev: Species { Species(id: (id + Species.count - 1) % Species.count) }
    var isBird: Bool { def.plan == .bird }
    var layEggs: Bool { [.bird, .sprawl, .slither, .insect, .spider, .fish].contains(def.plan) && def.name != "Seal" && def.name != "Walrus" && def.name != "Dolphin" && def.name != "Orca" && def.name != "Whale" }
}
