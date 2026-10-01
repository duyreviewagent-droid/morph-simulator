// Species definitions for all 100 animals, plus movement stats and ability helpers.
// Ported from Species.swift and the Species/LegStats parts of Abilities.swift.

const E = (...names) => Object.freeze(Object.fromEntries(names.map(n => [n, n])))

export const Plan = E('biped', 'bird', 'quad', 'sprawl', 'slither', 'fish', 'insect', 'spider', 'tentacle', 'hopper')
export const Coat = E('cells', 'fur', 'spots', 'rosettes', 'patches', 'stripes', 'feathers', 'scales', 'skin', 'slick', 'shell', 'chitin', 'wool', 'quills', 'holstein', 'bands')
export const Ears = E('none', 'round', 'pointy', 'long', 'floppy', 'big', 'tufts')
export const Horns = E('none', 'short', 'ram', 'long', 'antlers', 'palmate', 'rhino', 'ossicones', 'wide')
export const Mouth = E('snout', 'pig', 'beak', 'bill', 'hooked', 'bigBeak', 'needle', 'pouch', 'trunk', 'flat', 'fish', 'mandibles', 'croc', 'hippo')
export const Arms = E('hands', 'paw', 'hoof', 'wing', 'batWing', 'fin', 'pincer', 'tentacles', 'insect', 'none')
export const Tail = E('none', 'thin', 'tuft', 'bushy', 'long', 'curly', 'stub', 'reptile', 'horse', 'flat', 'fan', 'stinger', 'fluffy', 'curl')
export const Foot = E('paw', 'hoof', 'foot', 'pad', 'webbed', 'talon', 'none')
export const BugWings = E('none', 'clear', 'big', 'elytra', 'long')
export const Voice = E('talk', 'cluck', 'moo', 'neigh', 'oink', 'baa', 'bleat', 'bray', 'bark', 'meow', 'roar', 'howl', 'yip', 'growl', 'squeak', 'hiss', 'quack', 'honk', 'gobble', 'hoot', 'caw', 'squawk', 'tweet', 'coo', 'trumpet', 'grunt', 'bellow', 'hoo', 'screech', 'chatter', 'ribbit', 'buzz', 'click', 'whale', 'blub', 'chirp', 'snort')
export const Eat = E('fruit', 'peck', 'graze', 'bite')
export const Special = E('none', 'spray', 'puff', 'ink', 'shell')
export const TorsoAbility = E('grab', 'flap', 'shove', 'swipe', 'pinch', 'slap', 'ink', 'puff', 'spray', 'shell')
export const LegAbility = E('backflip', 'egg', 'buck', 'pounce', 'leap', 'dash')

/// A SpeciesDef as a plain object, with the same defaults and per-plan overrides as the Swift init.
export function def(name, plan, size, coat, a, b, f) {
  const d = {
    name, plan, size, coat, a, b,
    limbCol: null, beakCol: [0.85, 0.65, 0.25], noseCol: [0.08, 0.06, 0.06],
    // head
    snout: 0.3, headW: 1, neck: 0.2, ears: 'pointy', horns: 'none', mouth: 'snout', eyeFront: false, eyeSize: 1,
    eyeCol: [0.05, 0.03, 0.02], mane: false, whiskers: false, antennae: false, comb: false, tusks: false, hood: false,
    // body
    arms: 'paw', girth: 1, hump: false, shell: false, dorsal: false, spikes: false, bugWings: 'none', wingCol: null, special: 'none',
    // legs
    legLen: 1, legThick: 1, foot: 'paw', tail: 'thin', bodyLen: 1,
    // behaviour
    voice: 'grunt', eat: 'fruit', speed: 1, jump: 1, custom: false,
  }
  switch (plan) {
    case 'bird': d.arms = 'wing'; d.foot = 'talon'; d.ears = 'none'; d.mouth = 'beak'; d.voice = 'tweet'; d.eat = 'peck'; d.tail = 'fan'; d.limbCol = [0.8, 0.6, 0.25]; break
    case 'quad': d.foot = 'paw'; d.tail = 'thin'; break
    case 'sprawl': d.foot = 'paw'; d.tail = 'reptile'; d.ears = 'none'; d.voice = 'hiss'; d.eat = 'bite'; d.limbCol = null; break
    case 'slither': d.arms = 'none'; d.ears = 'none'; d.tail = 'none'; d.voice = 'hiss'; d.eat = 'bite'; break
    case 'fish': d.arms = 'fin'; d.ears = 'none'; d.tail = 'none'; d.mouth = 'fish'; d.voice = 'blub'; d.eat = 'bite'; break
    case 'insect': case 'spider': d.arms = 'insect'; d.ears = 'none'; d.mouth = 'mandibles'; d.tail = 'none'; d.voice = 'chirp'; d.antennae = plan === 'insect'; d.eat = 'fruit'; break
    case 'tentacle': d.arms = 'tentacles'; d.ears = 'none'; d.mouth = 'fish'; d.tail = 'none'; d.voice = 'blub'; d.eat = 'bite'; break
    case 'biped': d.arms = 'hands'; d.foot = 'foot'; d.eyeFront = true; d.mouth = 'flat'; break
    case 'hopper': d.foot = 'foot'; d.tail = 'stub'; break
  }
  if (f) f(d)
  return d
}

const c = (r, g, b) => [r, g, b]

export const Zoo = {
  c,
  defs: [
        // the three originals
        def('Human', 'biped', 1, 'skin', c(0.7, 0.5, 0.42), c(0.1, 0.1, 0.1), d => { d.custom = true; d.voice = 'talk'; d.eat = 'fruit' }),
        def('Chicken', 'bird', 1, 'feathers', c(0.42, 0.16, 0.06), c(0.2, 0.06, 0.02), d => { d.custom = true; d.voice = 'cluck'; d.comb = true }),
        def('Cow', 'quad', 1, 'holstein', c(0.82, 0.79, 0.74), c(0.03, 0.03, 0.03), d => { d.custom = true; d.voice = 'moo'; d.eat = 'graze'; d.foot = 'hoof'; d.arms = 'hoof'; d.speed = 1.2 }),

        // farm and pets
        def('Pig', 'quad', 0.85, 'skin', c(0.88, 0.62, 0.58), c(0.7, 0.45, 0.42), d => { d.mouth = 'pig'; d.ears = 'floppy'; d.tail = 'curly'; d.foot = 'hoof'; d.arms = 'hoof'; d.voice = 'oink'; d.eat = 'graze'; d.snout = 0.28; d.girth = 1.2; d.legLen = 0.6; d.noseCol = c(0.8, 0.5, 0.5) }),
        def('Horse', 'quad', 1.1, 'fur', c(0.4, 0.24, 0.12), c(0.08, 0.05, 0.03), d => { d.snout = 0.55; d.neck = 0.55; d.mane = true; d.tail = 'horse'; d.foot = 'hoof'; d.arms = 'hoof'; d.voice = 'neigh'; d.eat = 'graze'; d.speed = 1.45; d.legLen = 1.25; d.jump = 1.3 }),
        def('Sheep', 'quad', 0.8, 'wool', c(0.88, 0.86, 0.8), c(0.1, 0.09, 0.08), d => { d.snout = 0.28; d.ears = 'floppy'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'baa'; d.eat = 'graze'; d.girth = 1.25; d.legLen = 0.75 }),
        def('Goat', 'quad', 0.8, 'fur', c(0.85, 0.82, 0.75), c(0.4, 0.3, 0.2), d => { d.snout = 0.32; d.horns = 'ram'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bleat'; d.eat = 'graze'; d.jump = 1.9 }),
        def('Donkey', 'quad', 0.95, 'fur', c(0.5, 0.47, 0.45), c(0.2, 0.18, 0.17), d => { d.snout = 0.45; d.ears = 'long'; d.mane = true; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'bray'; d.eat = 'graze' }),
        def('Duck', 'bird', 0.7, 'feathers', c(0.45, 0.35, 0.25), c(0.1, 0.35, 0.15), d => { d.mouth = 'bill'; d.beakCol = c(0.95, 0.65, 0.1); d.limbCol = c(0.95, 0.55, 0.1); d.foot = 'webbed'; d.voice = 'quack'; d.legLen = 0.55; d.tail = 'stub' }),
        def('Goose', 'bird', 0.85, 'feathers', c(0.9, 0.9, 0.88), c(0.75, 0.75, 0.72), d => { d.mouth = 'bill'; d.beakCol = c(0.95, 0.55, 0.1); d.limbCol = c(0.95, 0.55, 0.1); d.foot = 'webbed'; d.voice = 'honk'; d.neck = 0.55; d.legLen = 0.6; d.tail = 'stub' }),
        def('Turkey', 'bird', 1.0, 'feathers', c(0.25, 0.18, 0.12), c(0.05, 0.12, 0.08), d => { d.comb = true; d.voice = 'gobble'; d.tail = 'fan'; d.limbCol = c(0.7, 0.55, 0.5) }),
        def('Dog', 'quad', 0.75, 'fur', c(0.78, 0.55, 0.28), c(0.5, 0.3, 0.12), d => { d.snout = 0.34; d.ears = 'floppy'; d.tail = 'bushy'; d.voice = 'bark'; d.eat = 'bite'; d.speed = 1.3 }),
        def('Cat', 'quad', 0.6, 'stripes', c(0.85, 0.5, 0.2), c(0.5, 0.25, 0.08), d => { d.snout = 0.16; d.whiskers = true; d.tail = 'long'; d.voice = 'meow'; d.eat = 'bite'; d.jump = 1.7; d.eyeCol = c(0.5, 0.6, 0.1); d.noseCol = c(0.8, 0.45, 0.45) }),
        def('Rabbit', 'hopper', 0.6, 'fur', c(0.55, 0.47, 0.38), c(0.9, 0.88, 0.85), d => { d.snout = 0.14; d.ears = 'long'; d.tail = 'fluffy'; d.voice = 'squeak'; d.eat = 'graze'; d.jump = 1.5; d.whiskers = true; d.noseCol = c(0.8, 0.5, 0.5) }),
        def('Mouse', 'quad', 0.45, 'fur', c(0.55, 0.52, 0.5), c(0.8, 0.6, 0.6), d => { d.snout = 0.2; d.ears = 'round'; d.tail = 'long'; d.limbCol = c(0.85, 0.6, 0.6); d.voice = 'squeak'; d.whiskers = true; d.eyeSize = 1.3; d.noseCol = c(0.85, 0.5, 0.5) }),
        def('Rat', 'quad', 0.5, 'fur', c(0.32, 0.3, 0.28), c(0.6, 0.45, 0.45), d => { d.snout = 0.26; d.ears = 'round'; d.tail = 'long'; d.limbCol = c(0.8, 0.6, 0.58); d.voice = 'squeak'; d.whiskers = true }),
        def('Hamster', 'quad', 0.45, 'patches', c(0.85, 0.6, 0.3), c(0.95, 0.92, 0.88), d => { d.snout = 0.1; d.ears = 'round'; d.tail = 'stub'; d.voice = 'squeak'; d.girth = 1.4; d.legLen = 0.4; d.eyeSize = 1.3 }),
        def('Guinea Pig', 'quad', 0.5, 'patches', c(0.95, 0.92, 0.88), c(0.55, 0.3, 0.1), d => { d.snout = 0.14; d.ears = 'round'; d.tail = 'none'; d.voice = 'squeak'; d.girth = 1.3; d.legLen = 0.35; d.eat = 'graze' }),
        def('Llama', 'quad', 1.0, 'wool', c(0.88, 0.82, 0.7), c(0.5, 0.4, 0.3), d => { d.snout = 0.3; d.neck = 0.9; d.ears = 'long'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bleat'; d.eat = 'graze'; d.legLen = 1.1 }),
        def('Alpaca', 'quad', 0.85, 'wool', c(0.55, 0.4, 0.28), c(0.3, 0.2, 0.12), d => { d.snout = 0.24; d.neck = 0.65; d.ears = 'pointy'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bleat'; d.eat = 'graze' }),
        def('Water Buffalo', 'quad', 1.15, 'skin', c(0.18, 0.17, 0.17), c(0.1, 0.1, 0.1), d => { d.snout = 0.4; d.horns = 'wide'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'moo'; d.eat = 'graze'; d.girth = 1.2 }),
        def('Parrot', 'bird', 0.6, 'feathers', c(0.1, 0.6, 0.15), c(0.85, 0.1, 0.05), d => { d.mouth = 'hooked'; d.beakCol = c(0.2, 0.2, 0.2); d.limbCol = c(0.4, 0.4, 0.4); d.voice = 'squawk'; d.eat = 'fruit'; d.eyeCol = c(0.9, 0.9, 0.9); d.tail = 'long' }),
        def('Pigeon', 'bird', 0.55, 'feathers', c(0.5, 0.52, 0.56), c(0.25, 0.4, 0.35), d => { d.voice = 'coo'; d.limbCol = c(0.8, 0.35, 0.35); d.beakCol = c(0.3, 0.3, 0.3); d.tail = 'stub' }),

        // wild mammals
        def('Lion', 'quad', 1.05, 'fur', c(0.78, 0.6, 0.35), c(0.45, 0.28, 0.12), d => { d.snout = 0.28; d.mane = true; d.ears = 'round'; d.tail = 'tuft'; d.voice = 'roar'; d.eat = 'bite'; d.speed = 1.4; d.whiskers = true; d.eyeCol = c(0.6, 0.45, 0.1) }),
        def('Tiger', 'quad', 1.05, 'stripes', c(0.9, 0.5, 0.15), c(0.05, 0.03, 0.02), d => { d.snout = 0.28; d.ears = 'round'; d.tail = 'long'; d.voice = 'roar'; d.eat = 'bite'; d.speed = 1.4; d.whiskers = true; d.eyeCol = c(0.6, 0.5, 0.1) }),
        def('Leopard', 'quad', 0.85, 'rosettes', c(0.85, 0.65, 0.35), c(0.08, 0.06, 0.04), d => { d.snout = 0.24; d.ears = 'round'; d.tail = 'long'; d.voice = 'growl'; d.eat = 'bite'; d.speed = 1.5; d.jump = 1.6; d.whiskers = true }),
        def('Cheetah', 'quad', 0.85, 'spots', c(0.88, 0.72, 0.42), c(0.05, 0.04, 0.03), d => { d.snout = 0.22; d.ears = 'round'; d.tail = 'long'; d.voice = 'chirp'; d.eat = 'bite'; d.speed = 2.0; d.legLen = 1.2; d.girth = 0.8 }),
        def('Wolf', 'quad', 0.9, 'fur', c(0.5, 0.48, 0.45), c(0.85, 0.83, 0.8), d => { d.snout = 0.4; d.tail = 'bushy'; d.voice = 'howl'; d.eat = 'bite'; d.speed = 1.5; d.eyeCol = c(0.7, 0.6, 0.1) }),
        def('Fox', 'quad', 0.65, 'fur', c(0.85, 0.4, 0.12), c(0.95, 0.92, 0.88), d => { d.snout = 0.36; d.tail = 'bushy'; d.voice = 'yip'; d.eat = 'bite'; d.speed = 1.3; d.legLen = 0.8 }),
        def('Bear', 'quad', 1.3, 'fur', c(0.3, 0.18, 0.1), c(0.18, 0.1, 0.05), d => { d.snout = 0.32; d.ears = 'round'; d.tail = 'stub'; d.voice = 'roar'; d.eat = 'fruit'; d.girth = 1.3; d.speed = 1.1 }),
        def('Polar Bear', 'quad', 1.35, 'fur', c(0.92, 0.9, 0.84), c(0.8, 0.78, 0.7), d => { d.snout = 0.38; d.ears = 'round'; d.tail = 'stub'; d.voice = 'growl'; d.eat = 'bite'; d.girth = 1.25 }),
        def('Panda', 'quad', 1.1, 'patches', c(0.93, 0.92, 0.9), c(0.04, 0.04, 0.04), d => { d.snout = 0.2; d.ears = 'round'; d.tail = 'stub'; d.voice = 'grunt'; d.eat = 'graze'; d.girth = 1.35; d.speed = 0.8 }),
        def('Raccoon', 'quad', 0.6, 'fur', c(0.45, 0.43, 0.4), c(0.1, 0.1, 0.1), d => { d.snout = 0.2; d.arms = 'hands'; d.tail = 'bushy'; d.voice = 'chatter'; d.eat = 'fruit'; d.whiskers = true }),
        def('Deer', 'quad', 0.95, 'fur', c(0.6, 0.4, 0.22), c(0.9, 0.88, 0.82), d => { d.snout = 0.34; d.horns = 'antlers'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bleat'; d.eat = 'graze'; d.speed = 1.5; d.jump = 1.8; d.legLen = 1.2; d.girth = 0.85 }),
        def('Moose', 'quad', 1.4, 'fur', c(0.25, 0.17, 0.1), c(0.15, 0.1, 0.06), d => { d.snout = 0.5; d.horns = 'palmate'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bellow'; d.eat = 'graze'; d.legLen = 1.3 }),
        def('Reindeer', 'quad', 1.0, 'fur', c(0.5, 0.42, 0.35), c(0.9, 0.88, 0.85), d => { d.snout = 0.36; d.horns = 'antlers'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'grunt'; d.eat = 'graze'; d.noseCol = c(0.8, 0.1, 0.1) }),
        def('Camel', 'quad', 1.3, 'fur', c(0.78, 0.62, 0.4), c(0.6, 0.45, 0.28), d => { d.snout = 0.4; d.neck = 0.8; d.hump = true; d.ears = 'round'; d.foot = 'pad'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'grunt'; d.eat = 'graze'; d.legLen = 1.35 }),
        def('Giraffe', 'quad', 1.3, 'cells', c(0.95, 0.85, 0.6), c(0.6, 0.35, 0.12), d => { d.snout = 0.45; d.neck = 1.9; d.horns = 'ossicones'; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'snort'; d.eat = 'graze'; d.legLen = 1.6; d.girth = 0.9 }),
        def('Zebra', 'quad', 1.0, 'stripes', c(0.93, 0.92, 0.9), c(0.03, 0.03, 0.03), d => { d.snout = 0.5; d.neck = 0.45; d.mane = true; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'neigh'; d.eat = 'graze'; d.speed = 1.45 }),
        def('Elephant', 'quad', 1.6, 'skin', c(0.45, 0.43, 0.42), c(0.3, 0.29, 0.28), d => { d.mouth = 'trunk'; d.ears = 'big'; d.tusks = true; d.foot = 'pad'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'trumpet'; d.eat = 'graze'; d.girth = 1.3; d.speed = 0.85; d.snout = 0.25 }),
        def('Rhino', 'quad', 1.4, 'skin', c(0.5, 0.48, 0.45), c(0.35, 0.33, 0.3), d => { d.snout = 0.45; d.horns = 'rhino'; d.ears = 'pointy'; d.foot = 'pad'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'snort'; d.eat = 'graze'; d.girth = 1.35; d.legLen = 0.8 }),
        def('Hippo', 'quad', 1.45, 'skin', c(0.5, 0.4, 0.42), c(0.8, 0.5, 0.5), d => { d.mouth = 'hippo'; d.snout = 0.4; d.ears = 'round'; d.foot = 'pad'; d.arms = 'hoof'; d.tail = 'stub'; d.voice = 'bellow'; d.eat = 'graze'; d.girth = 1.6; d.legLen = 0.55 }),
        def('Gorilla', 'biped', 1.2, 'fur', c(0.1, 0.1, 0.1), c(0.3, 0.3, 0.3), d => { d.ears = 'round'; d.voice = 'hoo'; d.girth = 1.5; d.legThick = 1.3; d.limbCol = c(0.15, 0.13, 0.12) }),
        def('Chimpanzee', 'biped', 0.85, 'fur', c(0.12, 0.1, 0.09), c(0.4, 0.3, 0.25), d => { d.ears = 'round'; d.voice = 'hoo'; d.limbCol = c(0.5, 0.4, 0.35); d.jump = 1.3 }),
        def('Monkey', 'biped', 0.6, 'fur', c(0.45, 0.32, 0.2), c(0.8, 0.65, 0.5), d => { d.ears = 'round'; d.tail = 'long'; d.voice = 'screech'; d.jump = 1.5; d.limbCol = c(0.8, 0.6, 0.5) }),
        def('Orangutan', 'biped', 1.0, 'fur', c(0.7, 0.3, 0.1), c(0.4, 0.15, 0.05), d => { d.ears = 'none'; d.voice = 'hoo'; d.girth = 1.3; d.limbCol = c(0.35, 0.25, 0.2) }),
        def('Kangaroo', 'hopper', 1.0, 'fur', c(0.7, 0.45, 0.28), c(0.9, 0.8, 0.65), d => { d.snout = 0.3; d.ears = 'long'; d.tail = 'reptile'; d.arms = 'paw'; d.voice = 'grunt'; d.eat = 'graze'; d.jump = 1.7; d.speed = 1.4 }),
        def('Koala', 'biped', 0.6, 'fur', c(0.6, 0.6, 0.6), c(0.9, 0.9, 0.88), d => { d.ears = 'tufts'; d.mouth = 'snout'; d.snout = 0.1; d.noseCol = c(0.1, 0.1, 0.1); d.voice = 'grunt'; d.eat = 'graze'; d.girth = 1.3; d.speed = 0.6; d.eyeFront = true }),
        def('Sloth', 'biped', 0.75, 'fur', c(0.5, 0.45, 0.35), c(0.2, 0.15, 0.1), d => { d.ears = 'none'; d.voice = 'squeak'; d.speed = 0.3; d.jump = 0.5 }),
        def('Bat', 'biped', 0.5, 'fur', c(0.2, 0.15, 0.12), c(0.1, 0.08, 0.07), d => { d.arms = 'batWing'; d.ears = 'big'; d.mouth = 'snout'; d.snout = 0.1; d.voice = 'screech'; d.eat = 'fruit'; d.wingCol = c(0.12, 0.09, 0.08) }),
        def('Hedgehog', 'quad', 0.45, 'quills', c(0.35, 0.28, 0.2), c(0.85, 0.8, 0.7), d => { d.snout = 0.2; d.ears = 'round'; d.spikes = true; d.tail = 'none'; d.voice = 'squeak'; d.eat = 'bite'; d.legLen = 0.35; d.girth = 1.3 }),
        def('Skunk', 'quad', 0.55, 'patches', c(0.05, 0.05, 0.05), c(0.95, 0.95, 0.93), d => { d.snout = 0.2; d.ears = 'round'; d.tail = 'bushy'; d.voice = 'chatter'; d.special = 'spray'; d.legLen = 0.55 }),
        def('Squirrel', 'quad', 0.45, 'fur', c(0.6, 0.35, 0.18), c(0.9, 0.85, 0.75), d => { d.snout = 0.16; d.ears = 'tufts'; d.tail = 'bushy'; d.arms = 'hands'; d.voice = 'chatter'; d.jump = 1.6 }),
        def('Beaver', 'quad', 0.7, 'fur', c(0.35, 0.22, 0.12), c(0.2, 0.15, 0.1), d => { d.snout = 0.18; d.ears = 'round'; d.tail = 'flat'; d.voice = 'grunt'; d.girth = 1.3; d.legLen = 0.45 }),
        def('Otter', 'quad', 0.65, 'fur', c(0.35, 0.24, 0.15), c(0.7, 0.6, 0.5), d => { d.snout = 0.16; d.ears = 'round'; d.tail = 'reptile'; d.voice = 'chirp'; d.eat = 'bite'; d.whiskers = true; d.bodyLen = 1.3; d.legLen = 0.45 }),
        def('Bison', 'quad', 1.4, 'fur', c(0.28, 0.18, 0.1), c(0.15, 0.1, 0.05), d => { d.snout = 0.35; d.horns = 'short'; d.hump = true; d.mane = true; d.foot = 'hoof'; d.arms = 'hoof'; d.tail = 'tuft'; d.voice = 'bellow'; d.eat = 'graze' }),
        def('Meerkat', 'biped', 0.5, 'fur', c(0.72, 0.6, 0.45), c(0.3, 0.22, 0.15), d => { d.snout = 0.2; d.mouth = 'snout'; d.ears = 'round'; d.tail = 'long'; d.voice = 'chirp'; d.eyeFront = true }),
        def('Anteater', 'quad', 1.0, 'fur', c(0.35, 0.3, 0.25), c(0.9, 0.88, 0.8), d => { d.snout = 0.7; d.mouth = 'needle'; d.ears = 'round'; d.tail = 'bushy'; d.voice = 'snort'; d.eat = 'bite' }),
        def('Armadillo', 'quad', 0.55, 'shell', c(0.6, 0.52, 0.45), c(0.4, 0.34, 0.3), d => { d.snout = 0.25; d.ears = 'pointy'; d.shell = true; d.tail = 'reptile'; d.voice = 'squeak'; d.legLen = 0.4 }),
        def('Seal', 'fish', 0.95, 'slick', c(0.45, 0.45, 0.47), c(0.3, 0.3, 0.32), d => { d.mouth = 'snout'; d.snout = 0.16; d.whiskers = true; d.voice = 'bark'; d.eyeSize = 1.5 }),
        def('Walrus', 'fish', 1.3, 'skin', c(0.55, 0.38, 0.3), c(0.4, 0.28, 0.2), d => { d.mouth = 'snout'; d.snout = 0.2; d.whiskers = true; d.tusks = true; d.voice = 'bellow'; d.girth = 1.3 }),

        // birds
        def('Ostrich', 'bird', 1.2, 'feathers', c(0.1, 0.09, 0.08), c(0.9, 0.88, 0.85), d => { d.neck = 1.0; d.legLen = 2.1; d.limbCol = c(0.8, 0.6, 0.55); d.voice = 'grunt'; d.speed = 2.0; d.tail = 'fluffy'; d.mouth = 'beak' }),
        def('Penguin', 'bird', 0.85, 'slick', c(0.06, 0.06, 0.07), c(0.95, 0.95, 0.93), d => { d.arms = 'fin'; d.legLen = 0.25; d.limbCol = c(0.9, 0.5, 0.1); d.beakCol = c(0.15, 0.15, 0.15); d.voice = 'squawk'; d.foot = 'webbed'; d.tail = 'stub'; d.speed = 0.6 }),
        def('Owl', 'bird', 0.7, 'feathers', c(0.5, 0.38, 0.25), c(0.9, 0.85, 0.75), d => { d.eyeFront = true; d.eyeSize = 2.2; d.eyeCol = c(0.95, 0.7, 0.1); d.ears = 'tufts'; d.mouth = 'hooked'; d.beakCol = c(0.3, 0.3, 0.3); d.voice = 'hoot'; d.eat = 'bite'; d.tail = 'stub' }),
        def('Eagle', 'bird', 0.9, 'feathers', c(0.3, 0.2, 0.12), c(0.95, 0.95, 0.92), d => { d.mouth = 'hooked'; d.beakCol = c(0.95, 0.75, 0.1); d.limbCol = c(0.95, 0.75, 0.1); d.voice = 'screech'; d.eat = 'bite'; d.eyeCol = c(0.9, 0.7, 0.1) }),
        def('Flamingo', 'bird', 0.9, 'feathers', c(0.95, 0.5, 0.55), c(0.9, 0.35, 0.4), d => { d.neck = 0.9; d.legLen = 2.0; d.limbCol = c(0.9, 0.45, 0.5); d.mouth = 'hooked'; d.beakCol = c(0.15, 0.12, 0.12); d.voice = 'honk'; d.foot = 'webbed'; d.tail = 'stub' }),
        def('Peacock', 'bird', 0.9, 'feathers', c(0.05, 0.25, 0.6), c(0.1, 0.5, 0.35), d => { d.comb = false; d.voice = 'screech'; d.tail = 'fan'; d.limbCol = c(0.6, 0.55, 0.5) }),
        def('Crow', 'bird', 0.55, 'feathers', c(0.04, 0.04, 0.05), c(0.08, 0.08, 0.15), d => { d.beakCol = c(0.05, 0.05, 0.05); d.limbCol = c(0.08, 0.08, 0.08); d.voice = 'caw'; d.tail = 'stub' }),
        def('Swan', 'bird', 1.0, 'feathers', c(0.95, 0.95, 0.94), c(0.85, 0.85, 0.83), d => { d.mouth = 'bill'; d.beakCol = c(0.95, 0.4, 0.1); d.neck = 0.8; d.legLen = 0.5; d.limbCol = c(0.1, 0.1, 0.1); d.foot = 'webbed'; d.voice = 'honk'; d.tail = 'stub' }),
        def('Toucan', 'bird', 0.6, 'feathers', c(0.04, 0.04, 0.04), c(0.95, 0.9, 0.5), d => { d.mouth = 'bigBeak'; d.beakCol = c(0.98, 0.55, 0.05); d.limbCol = c(0.3, 0.4, 0.8); d.voice = 'squawk'; d.eat = 'fruit'; d.tail = 'stub' }),
        def('Hummingbird', 'bird', 0.4, 'feathers', c(0.1, 0.55, 0.3), c(0.8, 0.1, 0.3), d => { d.mouth = 'needle'; d.beakCol = c(0.1, 0.1, 0.1); d.limbCol = c(0.1, 0.1, 0.1); d.voice = 'tweet'; d.eat = 'fruit'; d.bugWings = 'clear'; d.tail = 'stub' }),
        def('Pelican', 'bird', 1.0, 'feathers', c(0.92, 0.92, 0.9), c(0.6, 0.6, 0.6), d => { d.mouth = 'pouch'; d.beakCol = c(0.95, 0.75, 0.3); d.neck = 0.6; d.legLen = 0.6; d.limbCol = c(0.4, 0.4, 0.4); d.foot = 'webbed'; d.voice = 'grunt'; d.eat = 'bite'; d.tail = 'stub' }),
        def('Emu', 'bird', 1.15, 'feathers', c(0.35, 0.28, 0.2), c(0.2, 0.15, 0.1), d => { d.neck = 0.9; d.legLen = 1.9; d.limbCol = c(0.4, 0.4, 0.4); d.voice = 'grunt'; d.speed = 1.7; d.tail = 'fluffy' }),

        // reptiles and amphibians
        def('Crocodile', 'sprawl', 1.25, 'scales', c(0.25, 0.3, 0.15), c(0.15, 0.18, 0.08), d => { d.mouth = 'croc'; d.snout = 0.7; d.voice = 'hiss'; d.bodyLen = 1.6; d.legLen = 0.8; d.eyeCol = c(0.7, 0.6, 0.1) }),
        def('Lizard', 'sprawl', 0.5, 'scales', c(0.35, 0.55, 0.2), c(0.2, 0.35, 0.1), d => { d.snout = 0.25; d.voice = 'hiss'; d.speed = 1.3 }),
        def('Iguana', 'sprawl', 0.75, 'scales', c(0.3, 0.55, 0.3), c(0.2, 0.35, 0.2), d => { d.snout = 0.25; d.dorsal = true; d.voice = 'hiss'; d.eat = 'graze' }),
        def('Chameleon', 'sprawl', 0.55, 'scales', c(0.4, 0.7, 0.25), c(0.9, 0.7, 0.2), d => { d.snout = 0.2; d.tail = 'curl'; d.eyeSize = 1.8; d.voice = 'hiss'; d.eat = 'bite'; d.speed = 0.5 }),
        def('Turtle', 'sprawl', 0.7, 'scales', c(0.35, 0.42, 0.22), c(0.25, 0.3, 0.15), d => { d.snout = 0.15; d.shell = true; d.tail = 'stub'; d.arms = 'fin'; d.foot = 'webbed'; d.voice = 'hiss'; d.eat = 'graze'; d.speed = 0.5; d.special = 'shell' }),
        def('Tortoise', 'sprawl', 0.85, 'scales', c(0.45, 0.4, 0.3), c(0.3, 0.25, 0.15), d => { d.snout = 0.15; d.shell = true; d.tail = 'stub'; d.foot = 'pad'; d.voice = 'hiss'; d.eat = 'graze'; d.speed = 0.3; d.special = 'shell' }),
        def('Snake', 'slither', 0.8, 'scales', c(0.3, 0.45, 0.15), c(0.1, 0.15, 0.05), d => { d.snout = 0.2; d.bodyLen = 2.0; d.eyeCol = c(0.8, 0.7, 0.1) }),
        def('Cobra', 'slither', 0.9, 'scales', c(0.55, 0.45, 0.25), c(0.2, 0.15, 0.08), d => { d.snout = 0.18; d.hood = true; d.bodyLen = 2.2 }),
        def('Frog', 'hopper', 0.5, 'slick', c(0.3, 0.6, 0.2), c(0.1, 0.3, 0.05), d => { d.mouth = 'fish'; d.snout = 0.1; d.ears = 'none'; d.eyeSize = 1.9; d.eyeCol = c(0.8, 0.7, 0.1); d.tail = 'none'; d.foot = 'webbed'; d.arms = 'paw'; d.voice = 'ribbit'; d.eat = 'bite'; d.jump = 1.9 }),
        def('Komodo Dragon', 'sprawl', 1.2, 'scales', c(0.4, 0.36, 0.3), c(0.3, 0.26, 0.2), d => { d.snout = 0.35; d.voice = 'hiss'; d.bodyLen = 1.4 }),
        def('Axolotl', 'sprawl', 0.5, 'slick', c(0.95, 0.65, 0.7), c(0.9, 0.3, 0.45), d => { d.snout = 0.1; d.mouth = 'fish'; d.mane = true; d.voice = 'squeak'; d.eat = 'bite' }),

        // sea life
        def('Goldfish', 'fish', 0.5, 'scales', c(0.98, 0.5, 0.1), c(0.95, 0.75, 0.3), d => { d.eyeSize = 1.6 }),
        def('Shark', 'fish', 1.3, 'slick', c(0.45, 0.5, 0.55), c(0.9, 0.9, 0.9), d => { d.dorsal = true; d.mouth = 'croc'; d.snout = 0.4; d.voice = 'blub'; d.eyeCol = c(0.02, 0.02, 0.02) }),
        def('Dolphin', 'fish', 1.1, 'slick', c(0.5, 0.55, 0.6), c(0.85, 0.87, 0.9), d => { d.dorsal = true; d.mouth = 'snout'; d.snout = 0.3; d.voice = 'click'; d.tail = 'flat' }),
        def('Orca', 'fish', 1.4, 'patches', c(0.04, 0.04, 0.05), c(0.95, 0.95, 0.95), d => { d.dorsal = true; d.mouth = 'snout'; d.snout = 0.15; d.voice = 'whale'; d.tail = 'flat' }),
        def('Whale', 'fish', 1.7, 'slick', c(0.25, 0.32, 0.42), c(0.6, 0.62, 0.65), d => { d.mouth = 'fish'; d.snout = 0.2; d.voice = 'whale'; d.tail = 'flat'; d.girth = 1.3; d.eyeSize = 0.7 }),
        def('Octopus', 'tentacle', 0.8, 'slick', c(0.8, 0.3, 0.2), c(0.6, 0.2, 0.15), d => { d.eyeSize = 1.5; d.special = 'ink'; d.eyeCol = c(0.9, 0.7, 0.1) }),
        def('Crab', 'spider', 0.6, 'chitin', c(0.8, 0.25, 0.12), c(0.95, 0.6, 0.4), d => { d.arms = 'pincer'; d.eyeSize = 1.2; d.voice = 'click'; d.antennae = false; d.eat = 'bite' }),
        def('Lobster', 'insect', 0.7, 'chitin', c(0.7, 0.12, 0.08), c(0.45, 0.08, 0.05), d => { d.arms = 'pincer'; d.voice = 'click'; d.bodyLen = 1.5; d.eat = 'bite' }),
        def('Pufferfish', 'fish', 0.55, 'spots', c(0.9, 0.82, 0.45), c(0.3, 0.25, 0.12), d => { d.spikes = true; d.eyeSize = 1.6; d.special = 'puff'; d.girth = 1.4 }),
        def('Jellyfish', 'tentacle', 0.7, 'slick', c(0.95, 0.6, 0.85), c(0.8, 0.4, 0.7), d => { d.eyeSize = 0; d.voice = 'blub' }),

        // bugs
        def('Bee', 'insect', 0.5, 'bands', c(0.95, 0.72, 0.1), c(0.05, 0.04, 0.03), d => { d.bugWings = 'clear'; d.voice = 'buzz'; d.eyeSize = 1.6; d.tail = 'stinger' }),
        def('Ant', 'insect', 0.45, 'chitin', c(0.35, 0.08, 0.05), c(0.15, 0.04, 0.03), d => { d.voice = 'chirp'; d.eat = 'bite' }),
        def('Butterfly', 'insect', 0.45, 'chitin', c(0.1, 0.08, 0.07), c(0.95, 0.5, 0.05), d => { d.bugWings = 'big'; d.wingCol = c(0.95, 0.5, 0.05); d.voice = 'buzz'; d.eyeSize = 1.3 }),
        def('Ladybug', 'insect', 0.45, 'spots', c(0.85, 0.08, 0.05), c(0.03, 0.03, 0.03), d => { d.bugWings = 'elytra'; d.voice = 'buzz'; d.girth = 1.4 }),
        def('Spider', 'spider', 0.55, 'fur', c(0.12, 0.1, 0.08), c(0.3, 0.2, 0.1), d => { d.eyeSize = 1.2; d.voice = 'hiss'; d.eat = 'bite'; d.antennae = false }),
        def('Snail', 'slither', 0.45, 'slick', c(0.6, 0.55, 0.45), c(0.55, 0.35, 0.18), d => { d.shell = true; d.antennae = true; d.snout = 0.08; d.voice = 'squeak'; d.eat = 'graze'; d.speed = 0.25; d.bodyLen = 0.8 }),
  ],
}

const cache = []

/// One animal. Instances are cached per id, so `Species.of(3) === Species.of(3)`.
export class Species {
  constructor(id) { this.id = id }
  static of(id) {
    let s = cache[id]
    if (!s) { s = new Species(id); cache[id] = s }
    return s
  }
  static get count() { return Zoo.defs.length }
  static get all() { return Zoo.defs.map((_, i) => Species.of(i)) }
  get def() { return Zoo.defs[this.id] }
  get name() { return this.def.name }
  get next() { return Species.of((this.id + 1) % Species.count) }
  get prev() { return Species.of((this.id + Species.count - 1) % Species.count) }
  get isBird() { return this.def.plan === 'bird' }
  get layEggs() {
    const d = this.def
    return ['bird', 'sprawl', 'slither', 'insect', 'spider', 'fish'].includes(d.plan) && !['Seal', 'Walrus', 'Dolphin', 'Orca', 'Whale'].includes(d.name)
  }
  toString() { return this.name }

  // ---- abilities (Abilities.swift) ----
  get torsoAbility() {
    const d = this.def
    switch (d.special) {
      case 'ink': return 'ink'
      case 'puff': return 'puff'
      case 'spray': return 'spray'
      case 'shell': return 'shell'
    }
    if (d.bugWings === 'clear' || d.bugWings === 'big' || d.bugWings === 'long') return 'flap'
    switch (d.arms) {
      case 'hands': return 'grab'
      case 'wing': case 'batWing': return 'flap'
      case 'pincer': return 'pinch'
      case 'fin': return 'slap'
      case 'tentacles': return 'ink'
      case 'insect': return 'pinch'
      case 'hoof': return 'shove'
      case 'paw': return d.size > 1.0 ? 'shove' : 'swipe'
      default: return d.size > 1.0 ? 'shove' : 'slap'
    }
  }
  get legAbility() {
    const d = this.def
    if (this.id === 0 || d.plan === 'biped') return 'backflip'
    if (this.id === 1 || this.layEggs) return 'egg'
    switch (d.plan) {
      case 'quad': return d.foot === 'hoof' || d.foot === 'pad' ? 'buck' : 'pounce'
      case 'hopper': return 'leap'
      default: return 'dash'
    }
  }
  get voiceSound() {
    switch (this.id) {
      case 0: return 'talk'
      case 1: return 'cluck'
      case 2: return 'moo'
      default: return `call_${this.id}`
    }
  }
  get loud() { return ['roar', 'howl', 'bark', 'growl', 'trumpet', 'screech', 'bellow', 'hiss', 'honk'].includes(this.def.voice) }
  /// [sound name, volume, rate]
  get stepSound() {
    const d = this.def
    switch (d.plan) {
      case 'slither': return ['slither', 0.4, 1]
      case 'fish': case 'tentacle': return ['flop', 0.45, 1]
      case 'insect': case 'spider': return ['step_claw', 0.2, 1.8]
    }
    switch (d.foot) {
      case 'hoof': return ['step_hoof', 0.6 * Math.min(1.3, d.size), 1.1 / Math.max(0.7, d.size)]
      case 'pad': return ['land', 0.35 * d.size, 0.7]
      case 'talon': case 'webbed': return ['step_claw', 0.35, 1.1 / Math.max(0.6, d.size)]
      default: return ['step_shoe', 0.35 * Math.min(1.2, d.size), 1.2 / Math.max(0.7, d.size)]
    }
  }
}
Species.HUMAN = Species.of(0)
Species.CHICKEN = Species.of(1)
Species.COW = Species.of(2)

/// Movement numbers for each kind of legs: { walk, sprint, jump, accel, turn, step }.
export const LegStats = {
  of(s) {
    switch (s.id) {
      case 0: return { walk: 2.3, sprint: 5.4, jump: 5.4, accel: 10, turn: 10, step: 0.45 }
      case 1: return { walk: 1.8, sprint: 4.3, jump: 6.9, accel: 14, turn: 12, step: 0.3 }
      case 2: return { walk: 1.9, sprint: 7.8, jump: 3.3, accel: 4.5, turn: 4, step: 0.35 }
    }
    const d = s.def
    const B = (walk, sprint, jump, accel, turn, step) => ({ walk, sprint, jump, accel, turn, step })
    let b
    switch (d.plan) {
      case 'biped': b = B(2.1, 5.0, 5.0, 10, 10, 0.45); break
      case 'bird': b = B(1.7, 4.0, 6.2, 13, 12, 0.3); break
      case 'quad': b = B(1.9, 6.4, 4.0, 6, 6, 0.35); break
      case 'sprawl': b = B(1.1, 3.2, 2.6, 7, 6, 0.25); break
      case 'slither': b = B(1.3, 3.2, 2.0, 6, 5, 0.25); break
      case 'fish': b = B(0.8, 1.8, 3.2, 5, 5, 0.2); break
      case 'insect': b = B(1.6, 4.2, 3.4, 14, 12, 0.3); break
      case 'spider': b = B(1.7, 4.8, 4.0, 14, 12, 0.3); break
      case 'tentacle': b = B(1.0, 2.4, 2.4, 6, 6, 0.25); break
      case 'hopper': b = B(1.9, 6.0, 6.4, 9, 9, 0.4); break
    }
    b.sprint *= d.speed
    b.walk *= Math.min(1.3, Math.sqrt(d.speed))
    b.jump = Math.min(10, b.jump * d.jump)
    b.step *= Math.min(Math.max(d.size, 0.6), 1.6)
    if (d.size > 1.2) { b.accel *= 0.7; b.turn *= 0.7 }
    return b
  },
}
